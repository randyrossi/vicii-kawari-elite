#!/usr/bin/env python3
"""Flight benchmark: launch, spawn a fixed set of rotating ships in front of
the player, then measure the frame rate and sample the 6510 program counter.

Uses the same VICE binary-monitor harness as smoke_kawari.py. Ships are added
through the game's own ZINF/NWSHP routines (simulated JSRs from MLOOP), so no
instructions are patched. The sampled profile is statistical: each sample
stops the emulator at an arbitrary point and records the routine containing
the program counter.
"""
import argparse
import bisect
import collections
import json
import os
from pathlib import Path
import random
import re
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from smoke_kawari import Test

# (type, x, y, z): sign-magnitude 16-bit coordinates, all in front of us.
SCENES = {
    "fleet": [(11, -0x180, 0x40, 0x600), (14, 0x200, -0x80, 0x900),
              (17, 0x60, 0xa0, 0x380), (20, -0x60, -0x90, 0x420),
              (31, 0x1c0, 0x100, 0x700), (16, -0x1e0, -0x100, 0x800)],
    "cobra": [(11, 0, 0, 0x300)],
    "none": [],
}


def call(test, m, routine, **registers):
    """Simulate JSR routine from MLOOP, then stop at MLOOP again."""
    sp = m.registers()["SP"]
    target = test.labels["MLOOP"] - 1
    m.write(0x100 + sp - 1, target.to_bytes(2, "little"))
    m.set_registers(PC=test.labels[routine], SP=sp - 2, **registers)
    return test.stop_at("MLOOP", m)


def spawn(test, scene):
    m = test.stop_at("MLOOP")
    m.write(test.labels["DELTA"], [0])          # stop our own ship
    for ship_type, x, y, z in SCENES[scene]:
        m = call(test, m, "ZINF")
        inwk = test.labels["INWK"]
        for offset, value in [(0, x), (3, y), (6, z)]:
            m.write(inwk + offset, [abs(value) & 255, abs(value) >> 8,
                                    0x80 if value < 0 else 0])
        m.write(inwk + 29, [127, 127])          # roll and pitch indefinitely
        m.write(inwk + 32, [0])                 # no AI: keep the scene fixed
        m = call(test, m, "NWSHP", A=ship_type)
        assert m.registers()["FL"] & 1, f"NWSHP failed for type {ship_type}"
    m.write(test.labels["DELTA"], [0])
    m.resume()


def explode(test):
    """Kill every ship in the local bubble, so they all explode at once."""
    m = test.stop_at("MLOOP")
    frin = m.memory(test.labels["FRIN"], 11)
    for slot, ship_type in enumerate(frin):
        if 0 < ship_type < 128:
            block = test.labels["K%"] + slot * 37
            flags = m.memory(block + 31, 1)[0]
            m.write(block + 31, [flags | 0x80])
    m.resume()


def jsr_targets(test):
    """Addresses of JSR instructions in the assembled host code."""
    game = Path(test.labels and __file__).resolve().parents[2] / "3-assembled-output"
    image = bytearray(65536)
    for name, address in [("LOCODE.unprot.bin", 0x1d00), ("HICODE.unprot.bin", 0x6a00)]:
        data = (game / name).read_bytes()
        image[address:address + len(data)] = data
    return image


def profile(test, samples):
    global jsr_sites
    image = jsr_targets(test)
    jsr_sites = {a for a in range(0x200, 0xd000) if image[a] == 0x20}
    # Attribute addresses to subroutines: the nearest preceding label that
    # is the target of some JSR (or JMP, for tail-called routines).
    sources = Path(__file__).resolve().parents[2] / "1-source-files/main-sources"
    text = "".join(f.read_text() for f in sources.glob("*.asm"))
    entries = set(re.findall(r"^ +JSR +([A-Za-z0-9_%]+)", text, re.M))
    names = sorted((address, name) for name, address in test.labels.items()
                   if name in entries and 0x0200 <= address < 0xd000)
    addresses = [a for a, _ in names]
    code = set(n for a, n in names)
    def routine(pc):
        i = bisect.bisect_right(addresses, pc) - 1
        return names[i][1] if i >= 0 else hex(pc)
    counts = collections.Counter()
    inclusive = collections.Counter()
    rng = random.Random(1)
    for _ in range(samples):
        time.sleep(rng.uniform(0.005, 0.03))
        m = test.monitor()
        regs = m.registers()
        stack = m.memory(0x100 + regs["SP"] + 1, 0xff - regs["SP"]) if regs["SP"] < 0xff else b""
        m.resume()
        counts[routine(regs["PC"])] += 1
        # Heuristic call stack: any stack byte pair that is a JSR return
        # address (the byte before it is part of a JSR) names a caller.
        seen = {routine(regs["PC"])}
        for n in range(len(stack) - 1):
            ret = (stack[n] | stack[n + 1] << 8) - 2
            if 0x0200 <= ret < 0xd000 and ret in jsr_sites:
                seen.add(routine(ret))
        for name in seen:
            inclusive[name] += 1
    return counts, inclusive


TOP_LEVEL = ["MVEIT", "LL9", "KW_PRESENT", "STARS", "DIALS", "TACTICS", "TIDY",
             "SCAN", "KW_MOVE"] + os.environ.get("BENCH_EXTRA", "").split()


def wait_stop(m):
    while True:
        kind, error, request, payload = m.receive()
        if kind == 0x61:
            raise RuntimeError("Emulated CPU jammed")
        if kind == 0x62:
            return m.registers()


def breakdown(test, frames=3):
    """Exact emulated cycles per top-level routine over whole frames.

    Breakpoints at each routine's entry; on a hit, a temporary breakpoint at
    its return address measures the inclusive time. Routines nested inside
    a measured one are measured as well (e.g. SCAN and KW_MOVE inside
    MVEIT), so the columns overlap.
    """
    m = test.stop_at("MLOOP")
    totals = collections.Counter()
    calls = collections.Counter()
    loop = test.labels["MLOOP"]
    entries = {test.labels[n]: n for n in TOP_LEVEL if n in test.labels}
    points = [m.checkpoint(a) for a in list(entries) + [loop]]
    start = test.clock(m, "clock")
    open_calls = {}      # return address -> list of (name, start clock)
    done = 0
    while True:
        m.resume(close=False)
        regs = wait_stop(m)
        pc = regs["PC"]
        now = test.clock(m, "clock")
        if pc == loop:
            done += 1
            if done == frames:
                break
            continue
        if pc in entries:
            sp = regs["SP"]
            ret = int.from_bytes(m.memory(0x101 + sp, 2), "little") + 1
            if ret not in open_calls:
                open_calls[ret] = [m.checkpoint(ret), []]
            open_calls[ret][1].append((entries[pc], now, sp))
        if pc in open_calls:
            point, stack = open_calls[pc]
            sp = regs["SP"]
            for item in [i for i in stack if i[2] + 2 == sp]:
                name, began, _ = item
                totals[name] += now - began
                calls[name] += 1
                stack.remove(item)
            if not stack:
                m.delete(point)
                del open_calls[pc]
    total = now - start
    for point in points:
        m.delete(point)
    for point, _ in open_calls.values():
        m.delete(point)
    m.resume()
    print(f"Exact breakdown over {frames} frames ({total / frames:.0f} cycles per frame):")
    for name, cycles in totals.most_common():
        print(f"  {name:12s} {100 * cycles / total:5.1f}%  {cycles / frames:7.0f} cycles/frame"
              f"  {calls[name] / frames:4.1f} calls/frame")
    return dict(cycles_per_frame=total / frames,
                routines={n: totals[n] / frames for n in totals},
                calls={n: calls[n] / frames for n in calls})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", choices=SCENES, default="fleet")
    parser.add_argument("--samples", type=int, default=300)
    parser.add_argument("--explode", action="store_true",
                        help="destroy the scene's ships, then measure the explosions")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--breakdown", type=int, default=3,
                        help="frames to measure exactly (0 to skip)")
    options = parser.parse_args()
    output = options.output or Path(tempfile.mkdtemp(prefix="elite-kawari-bench-"))
    output.mkdir(parents=True, exist_ok=True)
    test = Test(output.resolve(), False)
    try:
        test.monitor().resume()
        deadline = time.monotonic() + 300
        while True:
            time.sleep(1)
            m = test.monitor()
            ready = (m.memory(test.labels["STARS"], 1) == b"\x4c"
                     and m.memory(0xd2, 1) == b"\1")
            m.resume()
            if ready:
                break
            assert time.monotonic() < deadline, "title boot timed out"
        test.key(0x24)
        m = test.stop_at("TLL2"); m.resume()
        test.key(0x24)
        m = test.stop_at("MLOOP"); m.resume()
        test.function_key(0x3c)                 # launch
        time.sleep(1.5)
        spawn(test, options.scene)
        time.sleep(0.5)
        if options.explode:
            explode(test)
            # Explosions last about 60 frames: measure them at once, by
            # emulated cycles over whole frames rather than wall time.
            m = test.stop_at("MLOOP")
            m = test.stop_at("MLOOP", m)    # past the first explosion frame
            test.screenshot(m, "explosion-start")
            begin = test.clock(m, "explode-start")
            frames = 20
            for _ in range(frames):
                m = test.stop_at("MLOOP", m)
            end = test.clock(m, "explode-end")
            test.screenshot(m, "explosion")
            fps = frames * 985248 / (end - begin)
            test.report["explosion_fps"] = fps
            print(f"Explosions: {fps:.1f} FPS ({(end - begin) / frames:.0f} cycles per frame)")
            m.resume()
            if options.breakdown:
                test.report["breakdown"] = breakdown(test, options.breakdown)
            options.breakdown = 0
        m = test.stop_at("MLOOP")
        test.screenshot(m, "scene-" + options.scene)
        m.resume()
        test.benchmark("MLOOP")
        if options.breakdown:
            test.report["breakdown"] = breakdown(test, options.breakdown)
        counts, inclusive = profile(test, options.samples)
        total = sum(counts.values())
        print("Top routines (self time, share of sampled 6510 time):")
        for name, count in counts.most_common(25):
            print(f"  {name:20s} {100 * count / total:5.1f}%")
        print("Top routines (inclusive of callees):")
        for name, count in inclusive.most_common(40):
            print(f"  {name:20s} {100 * count / total:5.1f}%")
        test.report["profile"] = dict(counts.most_common())
        test.report["inclusive"] = dict(inclusive.most_common())
        test.report["scene"] = options.scene
    finally:
        test.close()
    print("Results:", output)


if __name__ == "__main__":
    main()

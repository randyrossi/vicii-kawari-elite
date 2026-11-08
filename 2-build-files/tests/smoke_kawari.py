#!/usr/bin/env python3
"""PAL integration test using the sibling Kawari VICE binary monitor.

Inputs are injected at the game's documented RDKEY/FRCE interfaces, since
VICE's keyboard-feed command writes the KERNAL buffer, not the CIA matrix.
No game instructions are patched. Screenshots require Pillow.
"""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import tempfile
import time

from PIL import Image

GAME = Path(__file__).resolve().parents[2]
VICE = GAME.parent / "vicii-kawari-vice/src/x64sc"


class Monitor:
    def __init__(self, port):
        deadline = time.monotonic() + 15
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), 1)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.1)
        self.sock.settimeout(45)
        self.request = 0

    def receive(self):
        def exact(n):
            data = b""
            while len(data) < n:
                part = self.sock.recv(n - len(data))
                if not part:
                    raise RuntimeError("VICE monitor disconnected")
                data += part
            return data
        header = exact(6)
        assert header[0] == 2
        size = struct.unpack_from("<I", header, 2)[0]
        message = exact(6 + size)
        return message[0], message[1], struct.unpack_from("<I", message, 2)[0], message[6:]

    def command(self, command, body=b""):
        self.request += 1
        self.sock.sendall(struct.pack("<BBIIB", 2, 2, len(body), self.request, command) + body)
        while True:
            kind, error, request, payload = self.receive()
            if request != self.request:
                if kind == 0x61:
                    raise RuntimeError("Emulated CPU jammed")
                continue
            assert error == 0, (hex(command), hex(error))
            return payload

    def memory(self, address, count, bank=0):
        body = struct.pack("<BHHBH", 0, address, address + count - 1, 0, bank)
        return self.command(1, body)[2:2 + count]

    def write(self, address, data, bank=0):
        body = struct.pack("<BHHBH", 0, address, address + len(data) - 1, 0, bank)
        self.command(2, body + bytes(data))

    def registers(self):
        payload = self.command(0x31, b"\0")
        names = {0: "A", 1: "X", 2: "Y", 3: "PC", 4: "SP", 5: "FL"}
        result = {}
        offset = 2
        for _ in range(struct.unpack_from("<H", payload)[0]):
            size, register, value = struct.unpack_from("<BBH", payload, offset)
            result[names.get(register, str(register))] = value
            offset += size + 1
        return result

    def set_registers(self, **values):
        ids = {"A": 0, "X": 1, "Y": 2, "PC": 3, "SP": 4, "FL": 5}
        self.command(0x32, struct.pack("<BH", 0, len(values)) + b"".join(
            struct.pack("<BBH", 3, ids[key], value) for key, value in values.items()))

    def checkpoint(self, address, stop=True):
        data = self.command(0x12, struct.pack("<HHBBBBB", address, address, stop, 1, 4, 0, 0))
        return struct.unpack_from("<I", data)[0]

    def delete(self, point):
        self.command(0x13, struct.pack("<I", point))

    def hits(self, point):
        return struct.unpack_from("<I", self.command(0x11, struct.pack("<I", point)), 13)[0]

    def resume(self, close=True):
        self.command(0xaa)
        if close:
            self.sock.close()


class Test:
    def __init__(self, output, true_drive):
        self.output = output
        self.labels = {key: int(value) for key, value in re.findall(
            r"'([^']+)':(\d+)L", (GAME / "3-assembled-output/labels.txt").read_text())}
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            self.port = reserve.getsockname()[1]
        self.report = {"true_drive": true_drive, "screens": [], "benchmarks": {}}
        self.log = (output / "vice.log").open("w")
        args = [str(VICE), "-default", "-pal", "+sound", "-warp", "-8",
                str(GAME / "5-compiled-game-disks/elite-kawari-pal.d64"),
                "-keybuf", 'lO"*",8,1\\x0d', "-keybuf-delay", "2000000",
                "-binarymonitor", "-binarymonitoraddress", f"ip4://127.0.0.1:{self.port}"]
        if not true_drive:
            args += ["-virtualdev8", "+drive8truedrive"]
        self.process = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT,
            env=dict(os.environ, SDL_RENDER_DRIVER="software", SDL_VIDEODRIVER="dummy"))

    def monitor(self):
        return Monitor(self.port)

    def stop_at(self, name, monitor=None):
        m = monitor or self.monitor()
        point = m.checkpoint(self.labels[name])
        m.resume(close=False)
        # Keeping the connection open is essential when a breakpoint stops VICE.
        while True:
            try:
                kind, error, request, payload = m.receive()
            except TimeoutError as error:
                regs = m.registers()
                self.screenshot(m, "timeout")
                self.clock(m, "timeout")
                raise RuntimeError(f"Timed out waiting for {name}: {regs}") from error
            if kind == 0x61:
                raise RuntimeError("Emulated CPU jammed")
            if kind == 0x62:
                break
        regs = m.registers()
        assert regs["PC"] == self.labels[name], (name, regs)
        m.delete(point)
        return m

    def key(self, code):
        m = self.stop_at("RDKEY")
        regs = m.registers()
        sp = regs["SP"]
        target = int.from_bytes(m.memory(0x101 + sp, 2), "little") + 1
        m.set_registers(PC=target, SP=sp + 2, A=code, X=code,
                        FL=(regs["FL"] & ~0x82) | 1)
        m.resume()

    def function_key(self, code):
        m = self.stop_at("MLOOP")
        m.set_registers(PC=self.labels["FRCE"], A=code, X=0, Y=0)
        m.resume()

    def screenshot(self, m, name):
        data = m.command(0x84, b"\0\0")
        header_size = struct.unpack_from("<I", data)[0]
        width, height = struct.unpack_from("<HH", data, 4)
        # This VICE build truncates the last four pixel bytes in its response.
        pixels = data[4 + header_size + 4:].ljust(width * height, b"\0")
        result = Image.frombytes("P", (width, height), pixels)
        palette = m.command(0x91, b"\0")
        colours, offset = [], 2
        for _ in range(struct.unpack_from("<H", palette)[0]):
            size = palette[offset]
            colours.extend(palette[offset + 1:offset + 4])
            offset += size + 1
        result.putpalette(colours)
        result.save(self.output / (name + ".png"))
        self.report["screens"].append(name)

    def clock(self, m, name):
        path = self.output / (name + ".vsf")
        filename = str(path).encode()
        assert len(filename) < 256
        m.command(0x41, bytes([0, 0, len(filename)]) + filename)
        data = path.read_bytes()
        return struct.unpack_from("<Q", data, data.index(b"MAINCPU\0") + 22)[0]

    def benchmark(self, name):
        m = self.stop_at(name)
        point = m.checkpoint(self.labels[name], stop=False)
        begin = self.clock(m, name + "-start")
        hits = m.hits(point)
        m.resume()
        time.sleep(2)
        m = self.monitor()
        end = self.clock(m, name + "-end")
        frames = m.hits(point) - hits
        m.delete(point)
        m.resume()
        result = dict(frames=frames, cycles=end - begin,
                      fps=frames * 985248 / (end - begin))
        self.report["benchmarks"][name] = result
        print(name, result, flush=True)

    def raster_copy(self):
        samples = []
        for _ in range(8):
            m = self.stop_at("KW_COPY_WAIT")
            start = m.memory(0xd012, 1, 3)[0] | ((m.memory(0xd011, 1, 3)[0] & 128) << 1)
            # The copy outruns the beam: any start after raster 148 is
            # tear-free, and it must finish before the first visible row.
            # (sampled just after the start, so it may have wrapped to 0..3)
            assert 148 <= start < 312 or start < 4, start
            m = self.stop_at("KW_FRAME_COUNTED", m)
            end = m.memory(0xd012, 1, 3)[0] | ((m.memory(0xd011, 1, 3)[0] & 128) << 1)
            assert 148 <= end < 312 or end < 50, end
            assert (end - start) % 312 <= 60, (start, end)
            samples.append([start, end])
            m.resume()
        self.report["copy_raster_intervals"] = samples
        print("PAL copy intervals:", samples, flush=True)

    def disk_error(self):
        # Exercise real KERNAL disk I/O without modifying the release image.
        # LOD's missing-file path restores both the game zero page and IRQs
        # before entering tapeerror. Return to the stopped main-loop context.
        m = self.stop_at("MLOOP")
        regs = m.registers()
        name = b"NO-KW-SAVE"
        m.write(self.labels["INWK"] + 5, name)
        m.write(self.labels["thislong"], [len(name)])
        m.write(self.labels["DISK"], [255])
        workspace = m.memory(0xd2, 16)
        m.set_registers(PC=self.labels["LOD"])
        m = self.stop_at("tapeerror", m)
        assert m.memory(0xd2, 16) == workspace, "disk I/O corrupted Kawari zero page"
        assert m.memory(1, 1)[0] & 7 == 4, "disk I/O left wrong memory banking"
        assert m.registers()["FL"] & 4 == 0, "disk I/O left IRQs disabled"
        m.set_registers(**{key: value for key, value in regs.items()
                           if key in ("A", "X", "Y", "PC", "SP", "FL")})
        m.resume()
        self.report["disk_load_error_restores_state"] = True
        print("Disk load error restores banking, IRQs and renderer workspace", flush=True)

    def flight_scene(self, entry, name):
        m = self.stop_at("MLOOP")
        sp = m.registers()["SP"]
        # Simulate a JSR from the main loop, without patching any instructions.
        target = self.labels["MLOOP"] - 1
        m.write(0x100 + sp - 1, target.to_bytes(2, "little"))
        m.set_registers(PC=self.labels[entry], SP=sp - 2)
        # Let the animation develop beyond the initial clear frame. The
        # monitor captures the last rasterised image, not the just-copied one.
        for _ in range(12 if entry == "ESCAPE" else 4):
            m = self.stop_at("KW_FRAME_COUNTED", m)
        self.screenshot(m, name)
        m = self.stop_at("MLOOP", m)
        m.set_registers(SP=sp)
        m.resume()
        print("Flight sequence:", name, flush=True)

    def run(self):
        self.monitor().resume()
        # The unchanged disk boot path must reach the title before any inputs.
        deadline = time.monotonic() + 300
        while True:
            time.sleep(1)
            m = self.monitor()
            loaded = m.memory(self.labels["STARS"], 1) == b"\x4c"
            active = m.memory(0xd2, 1) == b"\1"
            m.resume()
            if loaded and active:
                break
            assert time.monotonic() < deadline, "title boot timed out"
        m = self.stop_at("TLL2"); self.screenshot(m, "title"); m.resume()
        self.benchmark("TLL2")
        self.key(0x24)
        m = self.stop_at("TLL2"); self.screenshot(m, "adder"); m.resume()
        self.key(0x24)
        m = self.stop_at("MLOOP"); self.screenshot(m, "status"); m.resume()
        self.disk_error()
        self.function_key(0x3c)
        time.sleep(1)
        self.benchmark("MLOOP")
        self.raster_copy()
        for name, code, active in [("front", 0x3c, 1), ("rear", 0x3b, 1),
                ("left", 0x3a, 1), ("right", 0x3d, 1), ("long-chart", 0x35, 0),
                ("short-chart", 0x30, 0), ("system", 0x2d, 1), ("status-flight", 0x25, 0)]:
            self.function_key(code)
            time.sleep(0.25)
            m = self.stop_at("MLOOP")
            assert m.memory(0xd2, 1) == bytes([active]), name
            self.screenshot(m, name)
            m.resume()
            print("Screen:", name, flush=True)
        self.function_key(0x3c)
        self.flight_scene("MJP", "witchspace-tunnel")
        self.flight_scene("ESCAPE", "escape-pod")
        self.function_key(0x3c)
        m = self.stop_at("MLOOP")
        m.set_registers(PC=self.labels["DEATH"])
        m = self.stop_at("D2", m)
        assert m.memory(0xd2, 1) == b"\1", "death did not select VRAM"
        m.resume()
        time.sleep(0.3)
        m = self.monitor(); self.screenshot(m, "death"); m.resume()
        m = self.stop_at("TLL2"); m.resume()
        self.key(0x24)
        m = self.stop_at("TLL2"); m.resume()
        self.key(0x24)
        m = self.stop_at("MLOOP")
        m.set_registers(PC=self.labels["BRIEF"])
        m = self.stop_at("PAL1", m)
        assert m.memory(0xd2, 1) == b"\1", "mission did not select VRAM"
        m.resume()
        time.sleep(0.3)
        m = self.monitor(); self.screenshot(m, "mission"); m.resume()
        print("Death and mission ship verified", flush=True)

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=10)
        self.log.close()
        (self.output / "report.json").write_text(json.dumps(self.report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--true-drive", action="store_true")
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    output = options.output or Path(tempfile.mkdtemp(prefix="elite-kawari-smoke-"))
    output.mkdir(parents=True, exist_ok=True)
    print("Results:", output, flush=True)
    test = Test(output.resolve(), options.true_drive)
    try:
        test.run()
    finally:
        test.close()


if __name__ == "__main__":
    main()

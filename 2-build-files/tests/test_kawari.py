"""Execute the assembled VRAM program against the PAL reference binary.

Uses the CPU implementation in the sibling Kawari VICE repository, not a
Python reimplementation of the drawing algorithm. No display/server needed.
"""
import ctypes
from pathlib import Path
import random
import re
import subprocess
import tempfile
import unittest

GAME = Path(__file__).resolve().parents[2]
VICE = GAME.parent / "vicii-kawari-vice/src"
OUTPUT = GAME / "3-assembled-output"
REFERENCE = GAME / "4-reference-binaries/gma86-pal"


def labels(name):
    return {k: int(v) for k, v in re.findall(
        r"'([^']+)':(\d+)L", (OUTPUT / name).read_text())}


class Renderer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="elite-kawari-tests-")
        library = Path(cls.tmp.name) / "cpu.so"
        subprocess.run(["cc", "-shared", "-fPIC", "-O2", "-I" + str(VICE),
                        "-I" + str(VICE / "viciisc"),
                        str(Path(__file__).with_name("cpu_bridge.c")),
                        "-o", str(library)], check=True)
        cls.cpu = ctypes.CDLL(str(library))
        cls.mem = (ctypes.c_ubyte * 65536).in_dll(cls.cpu, "extraMem")
        cls.labels = labels("cpu-labels.txt")
        cls.host = labels("labels.txt")
        cls.code = (OUTPUT / "kawari-cpu.bin").read_bytes()
        cls.code_hi = (OUTPUT / "kawari-cpu-hi.bin").read_bytes()
        cls.reference = bytearray(65536)
        for address, file in [(0x1d00, "LOCODE.unprot.bin"),
                              (0x6a00, "HICODE.unprot.bin")]:
            data = (REFERENCE / file).read_bytes()
            cls.reference[address:address + len(data)] = data
        # Locate routines by their unique leading instructions, avoiding
        # dependence on addresses in the modified host's symbol table.
        cls.stock_line = cls.reference.index(bytes.fromhex("849ea98085bf0a8df406"))
        cls.stock_vector = cls.reference.index(bytes.fromhex("a200a000a56b859ab545"))
        cls.stock_stars = cls.reference.index(bytes.fromhex("ae8604f0"))
        cls.stock_ll9 = cls.reference.index(bytes.fromhex("a5a530f9a91f85ad"))
        # MVEIT part 2 starts just after MV30's JSR SCAN; part 8 is MV5.
        cls.stock_mv30 = cls.reference.index(bytes.fromhex("a5240a0a859a"))
        cls.stock_mv5 = cls.reference.index(bytes.fromhex("a52829a0d009a5280910"))
        cls.stock_circle2 = cls.reference.index(bytes.fromhex("a20086afa67e86b0a201867e"))
        cls.stock_erase = cls.reference.index(bytes.fromhex("a4afc4b0b006"))
        # The SNE table is in a data file: place it where stock FMLTU2 reads it.
        i = cls.reference.index(bytes.fromhex("291faabd"))
        sne = int.from_bytes(cls.reference[i + 4:i + 6], "little")
        import math
        cls.reference[sne:sne + 32] = bytes(
            255 if abs(math.sin(n / 64 * 2 * math.pi)) >= 1
            else int(256 * abs(math.sin(n / 64 * 2 * math.pi)) + 0.5) for n in range(32))
        cls.ships = (OUTPUT / "SHIPS.bin").read_bytes()
        cls.reference[0xd000:0xd000 + len(cls.ships)] = cls.ships
        # This build generates tables with BeebAsm's rounding rather than
        # copying the BBC assembler's old floating-point rounding artefacts.
        # Give the reference routine the same input tables as the new build.
        cls.reference[0x92e4:0x96e4] = cls.code[0xc00 - 0x200:0x1000 - 0x200]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def start(self):
        self.mem[:] = bytes(65536)
        self.mem[0x200:0x200 + len(self.code)] = self.code
        self.mem[0x7c00:0x8000] = self.code_hi
        # Canaries guard the displayed front image and the reserved area
        # below the mailbox. Blueprints follow the displayed rows; the ship
        # line heaps mirror the host heap addresses above them.
        self.mem[0x8000:0xda00] = bytes([0xa5]) * 0x5a00
        self.mem[0xdaa0:0xda00 + len(self.ships)] = self.ships[0xa0:]
        self.mem[0x7fec:0x7ff0] = bytes([0x69]) * 4
        self.assertGreaterEqual(self.cpu.run_to(0x200, self.labels["idle"],
                                               0, 0, 0, 0, 200000), 0)

    # Code shares the command pages: each buffer holds at most $161 bytes.
    CODE_RANGES = [(0x0200, 0x1c00), (0x1d62, 0x1e00), (0x1f62, 0x2000)]

    def submit(self, commands, page=0x1c):
        data = bytes(commands) + b"\0"
        self.assertLessEqual(len(data), 0x161)
        self.mem[page << 8:(page << 8) + len(data)] = data
        self.mem[0x7ff0] = page
        cycles = self.cpu.run_to(self.labels["idle"], self.labels["complete"],
                                 0, 0, 0, 0, 2000000)
        self.assertGreater(cycles, 0)
        self.assertEqual(self.mem[0x7ff1], 0)
        self.assertEqual(bytes(self.mem[0x8000:0xda00]), bytes([0xa5]) * 0x5a00)
        # Hires row 144 ($DA00-$DA9F) is shown on raster 195 before the
        # split turns hires off: it must stay black. Blueprints follow it.
        self.assertEqual(bytes(self.mem[0xda00:0xdaa0]), bytes(0xa0))
        self.assertEqual(bytes(self.mem[0xdaa0:0xda00 + len(self.ships)]), self.ships[0xa0:])
        self.assertEqual(bytes(self.mem[0x7fec:0x7ff0]), bytes([0x69]) * 4)
        self.assertEqual(bytes(self.mem[0x7c70:0x7fc0]), self.code_hi[0x70:0x3c0])
        for begin, end in self.CODE_RANGES:
            self.assertEqual(bytes(self.mem[begin:end]), self.code[begin - 0x200:end - 0x200])
        return cycles

    def pixels(self, colour=1):
        return {(x, y) for y in range(144) for x in range(256)
                if (self.mem[0x2010 + y * 160 + x // 2]
                    >> (4 if x % 2 == 0 else 0)) & 15 == colour}

    def test_lines_match_original(self):
        rng = random.Random(1)
        lines = [(0, 0, 255, 143), (128, 143, 128, 0), (128, 0, 128, 143),
                 (0, 0, 0, 0), (255, 143, 254, 142)]
        lines += [tuple(rng.randrange(256 if n % 2 == 0 else 144)
                        for n in range(4)) for _ in range(300)]
        for line in lines:
            with self.subTest(line=line):
                self.mem[:] = self.reference
                self.mem[0x6b:0x6f] = line
                self.assertGreater(self.cpu.reference_run_to(self.stock_line, 0x200,
                                                   0, 0, 0, 0, 200000), 0)
                expected = {(x, y) for y in range(144) for x in range(256)
                            if self.mem[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                        + (y & 7)] & (128 >> (x & 7))}
                self.start()
                self.submit([1, *line, 1])
                self.assertEqual(self.pixels(), expected)
                self.submit([1, *line, 1])
                self.assertEqual(self.pixels(), set(), "XOR erase must be exact")

    def test_reversed_right_edge_does_not_wrap(self):
        # Original LL30 wraps its exclusive endpoint 255+1 and draws nothing.
        self.start()
        self.submit([1, 255, 143, 0, 0, 1])
        self.assertEqual(len(self.pixels()), 255)

    def test_horizontal_colour_and_clip(self):
        self.start()
        self.submit([2, 224, 143, 255, 143, 3])
        self.assertEqual(self.pixels(3), {(x, 143) for x in range(224, 255)})
        self.submit([1, 128, 0, 128, 255, 1])
        self.assertTrue(all(y < 144 for x, y in self.pixels()))

    def test_packed_horizontal_endpoints(self):
        rng = random.Random(320)
        for _ in range(256):
            x1, x2 = rng.randrange(256), rng.randrange(256)
            y, colour = rng.randrange(144), rng.randrange(1, 16)
            self.start()
            self.submit([2, x1, y, x2, y, colour])
            self.assertEqual(self.pixels(colour),
                             {(x, y) for x in range(min(x1, x2), max(x1, x2))})

    def test_glyph_point_clear_and_page_crossing(self):
        self.start()
        self.submit([4, 248, 136, 2] + [255] * 8)
        self.assertEqual(self.pixels(2), {(x, y) for x in range(248, 256)
                                         for y in range(136, 144)})
        self.submit([5])
        self.assertEqual(self.pixels(), set())
        # Commands crossing the low-byte boundary, in both buffers.
        command = [3, 240, 140, 128, 1]
        self.submit(command * 70)
        self.assertEqual(self.pixels(), set())
        self.submit(command * 70, page=0x1e)
        self.assertEqual(self.pixels(), set())
        self.submit(command)
        self.assertEqual(self.pixels(), {(240, 140), (241, 140)})
        self.submit([5])
        self.assertEqual(self.pixels(), set())
        for y in range(144):
            self.assertEqual(self.mem[0x200f + y * 160], 0x11)
            self.assertEqual(self.mem[0x2090 + y * 160], 0x11)

    def test_vectors_match_original(self):
        rng = random.Random(6502)
        for _ in range(1000):
            # Retain low bits in sign bytes: Elite's packed sign values may
            # contain bits other than bit 7, and these must survive as well.
            data = bytes(rng.randrange(256) for _ in range(24))
            self.mem[:] = self.reference
            self.mem[0x6b:0x71] = data[:6]
            self.mem[0x45:0x57] = data[6:]
            self.assertGreater(self.cpu.reference_run_to(self.stock_vector, 0x200,
                                               0, 0, 0, 0, 10000), 0)
            expected = bytes(self.mem[0x71:0x77])
            self.start()
            # The ship job's LL51: XX15 at $20, XX16 at $26, XX12 at $A0.
            self.mem[0x20:0x38] = data
            self.assertGreater(self.cpu.run_to(self.labels["vector"], 0x200,
                                               0, 0, 0, 0, 10000), 0)
            self.assertEqual(bytes(self.mem[0xa0:0xa6]), expected)

    def test_text_clear_and_border_removal(self):
        self.start()
        self.submit([5, 4, 16, 24, 1] + [255] * 8
                    + [4, 24, 24, 1] + [255] * 8)
        self.submit([8, 8, 24, 4, 8])
        self.assertEqual(self.pixels(), {(x, y) for x in range(24, 32)
                                         for y in range(24, 32)})
        self.submit([8, 0, 8, 128, 136])
        self.assertEqual(self.pixels(), set())
        for y in range(144):
            self.assertEqual(self.mem[0x200f + y * 160], 0x11)
        self.submit([9])
        self.assertEqual(bytes(self.mem[0x2000:0x7a00]), bytes(23040))

    def test_stardust_all_views(self):
        rng = random.Random(16)
        addresses = [0x486, 0x50b, 0x96, 0x97, 0x98, 0xa6, 0x68, 0x69,
                     0x6a, 0x63, 0x64, 0x94, 0x95, 2, 3, 4, 5]
        for view in range(4):
            for case in range(40):
                speed, roll, pitch = rng.randrange(1, 41), rng.randrange(32), rng.randrange(9)
                rs, ps = rng.choice([0, 128]), rng.choice([0, 128])
                controls = bytes([view, 12, speed, speed * 64 & 255, speed >> 2,
                                  roll | rs, roll, rs, rs ^ 128,
                                  pitch | ps, pitch, ps, ps ^ 128]
                                 + [rng.randrange(256) for _ in range(4)])
                particles = bytearray(rng.randrange(256) for _ in range(78))
                for offset in [0, 26]:
                    for n in range(13):
                        particles[offset + n] = rng.randrange(120) | rng.choice([0, 128])
                for n in range(13):
                    particles[52 + n] = rng.randrange(16, 256)
                self.mem[:] = self.reference
                for address, value in zip(addresses, controls):
                    self.mem[address] = value
                self.mem[0x6a2:0x6f0] = particles
                self.assertGreater(self.cpu.reference_run_to(self.stock_stars, 0x200,
                                                   0, 0, 0, 0, 200000), 0)
                reference = bytearray(self.mem)
                expected = bytes(self.mem[2:6]) + bytes(self.mem[0x6a2:0x6f0])
                expected_pixels = {(x, y) for y in range(144) for x in range(256)
                                   if self.mem[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                               + (y & 7)] & (128 >> (x & 7))}
                self.start()
                self.submit(bytes([7]) + controls + particles)
                self.assertEqual(bytes(self.mem[0x7c1d:0x7c6f]), expected, (view, case))
                self.assertEqual(self.pixels(), expected_pixels, (view, case))
                if case % 4:
                    continue
                # Command 17: a second frame on the particles left in VRAM.
                vram = bytes(self.mem)
                controls = bytearray(controls)
                controls[2] = rng.randrange(1, 41)
                controls[13:17] = bytes(rng.randrange(256) for _ in range(4))
                self.mem[:] = reference
                for address, value in zip(addresses, controls):
                    self.mem[address] = value
                self.assertGreater(self.cpu.reference_run_to(self.stock_stars, 0x200,
                                                   0, 0, 0, 0, 200000), 0)
                expected = bytes(self.mem[0x6a2:0x6f0])
                expected_pixels = {(x, y) for y in range(144) for x in range(256)
                                   if self.mem[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                               + (y & 7)] & (128 >> (x & 7))}
                self.mem[:] = vram
                self.submit(bytes([17]) + controls)
                self.assertEqual(bytes(self.mem[0x7c21:0x7c6f]), expected, (view, case))
                self.assertEqual(self.pixels(), expected_pixels, (view, case))

    @staticmethod
    def ship_block(rng, ship_type, ships, laser):
        """A random visible ship: position, orthonormal orientation, flags."""
        import math
        def vector_bytes(v):
            m = min(int(round(abs(v) * 0x6000)), 0x7fff)
            return [m & 255, (m >> 8) | (0x80 if v < 0 else 0)]
        def coordinate(v):
            m = abs(v)
            return [m & 255, m >> 8, 0x80 if v < 0 else 0]
        header = ships[int.from_bytes(ships[2 * ship_type - 2:2 * ship_type], "little") - 0xd000:]
        visible = header[13]
        z = rng.randrange(0x60, min(visible, 0x30) * 256)
        x = rng.randrange(-z * 3 // 4, z * 3 // 4)
        y = rng.randrange(-z * 3 // 4, z * 3 // 4)
        # Random rotation from a random unit quaternion.
        q = [rng.gauss(0, 1) for _ in range(4)]
        n = math.sqrt(sum(c * c for c in q))
        a, b, c, d = (v / n for v in q)
        rot = [[a*a+b*b-c*c-d*d, 2*(b*c-a*d), 2*(b*d+a*c)],
               [2*(b*c+a*d), a*a-b*b+c*c-d*d, 2*(c*d-a*b)],
               [2*(b*d-a*c), 2*(c*d+a*b), a*a-b*b-c*c+d*d]]
        block = coordinate(x) + coordinate(y) + coordinate(z)
        for row in rot:
            for v in row:
                block += vector_bytes(v)
        block += [rng.randrange(40), 0, 0, 0]
        block += [(0x40 if laser else 0) | rng.randrange(8)]
        return block

    def test_ship_job_matches_original(self):
        """Command 10 reproduces stock LL9 lines and its line heap exactly."""
        rng = random.Random(9)
        heap = 0xff40
        for case in range(160):
            ship_type = 1 + case % 32
            colour = 2
            frames = [self.ship_block(rng, ship_type, self.ships, rng.random() < 0.5)
                      for _ in range(2)]
            blueprint = int.from_bytes(self.ships[2 * ship_type - 2:2 * ship_type], "little")
            reference = bytearray(self.reference)
            reference[0x4000:0x6000] = bytes(0x2000)
            self.start()
            vram = bytearray(self.mem)
            old_lines = []
            for frame, block in enumerate(frames):
                with self.subTest(case=case, frame=frame, ship=ship_type):
                    drawn = reference[0x09 + 31] & 8 if frame else 0
                    block = block[:31] + [(block[31] & ~8) | drawn]
                    self.mem[:] = reference
                    self.mem[0x09:0x09 + 32] = block
                    self.mem[0x09 + 33:0x09 + 35] = heap.to_bytes(2, "little")
                    self.mem[0x2d] = 0              # NEWB
                    self.mem[0xa5] = ship_type      # TYPE
                    self.mem[0x57:0x59] = blueprint.to_bytes(2, "little")
                    self.mem[0xb7] = 0              # dontclip
                    self.assertGreater(self.cpu.reference_run_to(
                        self.stock_ll9, 0x200, 0, 0, 0, 0, 2000000), 0)
                    reference = bytearray(self.mem)
                    self.assertTrue(reference[0x09 + 31] & 8, "stock drew no wireframe")
                    size = reference[heap]
                    expected = {(x, y) for y in range(144) for x in range(256)
                                if reference[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                             + (y & 7)] & (128 >> (x & 7))}
                    expected_heap = bytes(reference[heap:heap + size])
                    self.mem[:] = vram
                    command = [10, heap & 255, heap >> 8, drawn, colour,
                               reference[0xad], blueprint & 255, blueprint >> 8, 0]
                    preempt = case % 3 == 0
                    if preempt:
                        # Movement requested while this ship is drawn: it
                        # runs inside the job, which must be unaffected.
                        arguments, moved = self.random_move(random.Random(case))
                        self.urgent_move(arguments)
                    self.submit(command + block)
                    if preempt:
                        self.assertEqual(self.mem[0x7ff2], 0)
                        self.assertEqual(bytes(self.mem[0x50:0x50 + 31]), moved)
                    vram = bytearray(self.mem)
                    self.assertEqual(bytes(self.mem[heap:heap + size]), expected_heap)
                    lines = [expected_heap[n:n + 4] for n in range(1, size, 4)]
                    if any(255 in (line[0], line[2]) for line in lines + old_lines):
                        # The renderer deliberately fixes LL30's x=255 reversed
                        # endpoint wrap; compare with its own (tested) lines.
                        actual = self.pixels(colour)
                        self.start()
                        for line in lines:
                            self.submit([1, *line, colour])
                        expected = self.pixels(colour)
                        self.mem[:] = vram
                        self.assertEqual(actual, expected)
                    else:
                        self.assertEqual(self.pixels(colour), expected)
                    old_lines = lines
            # Erasing with an empty list (EE51) clears the image and heap.
            self.submit([11, heap & 255, heap >> 8, 8, colour, 0])
            self.assertEqual(self.pixels(colour), set())
            self.assertEqual(self.mem[heap], 1)

    def test_explosion_matches_original(self):
        """Command 13 reproduces stock LL9/DOEXP clouds, heap and sprite."""
        rng = random.Random(13)
        heap = 0xff00
        vic = [0xd002, 0xd003, 0xd010, 0xd015, 0xd017, 0xd01d]
        sprites = drawn = erased = particles = 0
        for case in range(64):
            ship_type = 1 + case % 32
            colour = 2
            blueprint = int.from_bytes(self.ships[2 * ship_type - 2:2 * ship_type], "little")
            block = self.ship_block(rng, ship_type, self.ships, False)
            block[31] = 0x20 | (block[31] & 7)          # exploding, nothing drawn
            if case % 2:                                # close: large clouds
                z = rng.randrange(0x80, 0x400)
                for offset, v in [(0, rng.randrange(-z // 2, z // 2)),
                                  (3, rng.randrange(-z // 2, z // 2)), (6, z)]:
                    block[offset:offset + 3] = [abs(v) & 255, abs(v) >> 8,
                                                0x80 if v < 0 else 0]
            counter = 18 if case % 3 == 0 else rng.randrange(19, 236)
            header = [0, counter, self.ships[blueprint - 0xd000 + 7]] + [
                rng.randrange(256) for _ in range(4)]
            reference = bytearray(self.reference)
            reference[0x4000:0x6000] = bytes(0x2000)
            reference[heap:heap + 7] = bytes(header)
            self.start()
            vram = bytearray(self.mem)
            for frame in range(3):
                with self.subTest(case=case, frame=frame, ship=ship_type):
                    self.mem[:] = reference
                    self.mem[0x09:0x09 + 32] = block
                    self.mem[0x09 + 33:0x09 + 35] = heap.to_bytes(2, "little")
                    self.mem[0x2d] = 0              # NEWB
                    self.mem[0xa5] = ship_type      # TYPE
                    self.mem[0x57:0x59] = blueprint.to_bytes(2, "little")
                    self.mem[0xb7] = 0              # dontclip
                    for a in vic:
                        self.mem[a] = 0
                    frump = self.mem[heap + 1]
                    self.assertGreater(self.cpu.reference_run_to(
                        self.stock_ll9, 0x200, 0, 0, 0, 0, 3000000), 0)
                    reference = bytearray(self.mem)
                    sprite_regs = [reference[a] for a in vic]
                    reference[0xd000:0xd000 + len(self.ships)] = self.ships
                    after = reference[0x09 + 31]
                    draw = after & 0x40
                    sprite = bool(draw) and frump == 18
                    flags = (block[31] & 0x40) | (8 if draw else 0) | (0x80 if sprite else 0)
                    sprx, spry = (44, 40) if block[7] >= 7 else (32, 30)
                    new_header = list(reference[heap:heap + 7])
                    self.mem[:] = vram
                    self.mem[0x7c00:0x7c04] = b"\x55\x55\x55\x55"
                    self.submit([13, heap & 255, heap >> 8, 0, colour, reference[0xad],
                                 blueprint & 255, blueprint >> 8, 0] + block
                                + [flags] + new_header + [sprx, spry])
                    vram = bytearray(self.mem)
                    expected = {(x, y) for y in range(144) for x in range(256)
                                if reference[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                             + (y & 7)] & (128 >> (x & 7))}
                    self.assertEqual(self.pixels(colour), expected)
                    particles += len(expected)
                    drawn += bool(draw)
                    erased += bool(block[31] & 0x40)
                    if draw:
                        end = new_header[2] + 1
                        self.assertEqual(bytes(self.mem[heap:heap + end]),
                                         bytes(reference[heap:heap + end]))
                    if sprite:
                        valid = sprite_regs[3] & 2
                        self.assertEqual(bool(self.mem[0x7c00]), bool(valid))
                        if valid:
                            sprites += 1
                            self.assertEqual(self.mem[0x7c01], sprite_regs[0])
                            self.assertEqual(self.mem[0x7c03], sprite_regs[1])
                            self.assertEqual(self.mem[0x7c02], sprite_regs[2] >> 1 & 1)
                    block = block[:31] + [after]
        self.assertGreater(sprites, 5)
        self.assertGreater(drawn, 150)
        self.assertGreater(erased, 100)
        self.assertGreater(particles, 3000)
        print(f"explosions: {drawn} drawn, {erased} erased, {sprites} sprites, {particles} pixels")

    def test_ship_dots_and_heap_moves(self):
        self.start()
        heap = 0xff00
        self.submit([11, 0, 0xff, 0, 5, 2, 10, 20, 13, 20, 10, 21, 13, 21])
        self.assertEqual(self.pixels(5), {(x, y) for x in range(10, 13) for y in (20, 21)})
        self.assertEqual(self.mem[heap], 9)
        # Replacing one dot with the same dot leaves the image unchanged.
        self.submit([11, 0, 0xff, 8, 5, 2, 10, 20, 13, 20, 10, 21, 13, 21])
        self.assertEqual(self.pixels(5), {(x, y) for x in range(10, 13) for y in (20, 21)})
        # KILLSHP shuffles a heap upwards; the VRAM copy must follow it.
        self.submit([12, 0, 0xff, 0x10, 0xff, 9])
        self.assertEqual(bytes(self.mem[0xff10:0xff19]), bytes(self.mem[0xff00:0xff09]))
        self.submit([11, 0x10, 0xff, 8, 5, 0])
        self.assertEqual(self.pixels(5), set())
        self.assertEqual(self.mem[0xff10], 1)

    def random_move(self, rng):
        """Random MVEIT inputs: (urgent-lane arguments, stock result)."""
        ship_type = rng.randrange(1, 33)
        blueprint = int.from_bytes(self.ships[2 * ship_type - 2:2 * ship_type], "little")
        block = self.ship_block(rng, ship_type, self.ships, False)[:31]
        block[0:9] = [rng.randrange(256) for _ in range(9)]  # any position
        block[2] &= 0x80
        block[5] &= 0x80
        block[8] &= 0x80
        block[27] = rng.randrange(48)
        block[28] = rng.choice([0, 1, 2, 3, 255, 254, 253])
        block[29] = rng.randrange(256)
        block[30] = rng.randrange(256)
        roll, pitch = rng.randrange(32), rng.randrange(9)
        rs, ps = rng.choice([0, 128]), rng.choice([0, 128])
        delta = rng.randrange(41)
        saved = bytes(self.mem)
        self.mem[:] = self.reference
        self.mem[0x09:0x09 + 31] = block
        self.mem[0xa5] = ship_type
        self.mem[0x57:0x59] = blueprint.to_bytes(2, "little")
        for address, value in [(0xa6, roll | rs), (0x68, roll), (0x69, rs),
                               (0x6a, rs ^ 128), (0x63, pitch | ps),
                               (0x64, pitch), (0x94, ps), (0x95, ps ^ 128),
                               (0x96, delta)]:
            self.mem[address] = value
        self.assertGreater(self.cpu.reference_run_to(
            self.stock_mv30, self.stock_mv5, 0, 0, 0, 0, 200000), 0)
        expected = bytes(self.mem[0x09:0x09 + 31])
        self.mem[:] = saved
        maximum = self.ships[blueprint - 0xd000 + 15]
        # A whole game tick: speed * 4 unscaled, the original rotation step
        # and the counters counting down, so the result must match exactly.
        arguments = block + [roll | rs, roll, rs, rs ^ 128, pitch | ps,
                             pitch, ps, ps ^ 128, delta, maximum,
                             block[27] * 4, 0xff, 0x7f]
        return arguments, expected

    def test_ship_movement_matches_original(self):
        """The urgent movement job reproduces stock MVEIT parts 2-7 exactly."""
        rng = random.Random(41)
        for case in range(600):
            with self.subTest(case=case):
                self.start()
                arguments, expected = self.random_move(rng)
                self.urgent_move(arguments)
                self.assertGreater(self.cpu.run_to(self.labels["idle"],
                                                  self.labels["idle_mailbox"],
                                                  0, 0, 0, 0, 200000), 0)
                self.assertEqual(self.mem[0x7ff2], 0)
                self.assertEqual(bytes(self.mem[0x50:0x50 + 31]), expected)

    @staticmethod
    def vectors(data):
        """The nine orientation vector components, as signed integers."""
        return [(data[i] | (data[i + 1] & 0x7f) << 8) * (-1 if data[i + 1] & 0x80 else 1)
                for i in range(9, 27, 2)]

    def test_fractional_tick_movement(self):
        """Between game ticks: scaled speed, a smaller rotation step, no countdown."""
        rng = random.Random(43)
        for case in range(200):
            with self.subTest(case=case):
                arguments, _ = self.random_move(rng)
                arguments[28] = 0                       # acceleration is applied as usual
                arguments[31:40] = [0, 0, 0, 128, 0, 0, 0, 128, 0]   # we are still
                # Reference: a whole tick, rotating by the original 1/16 radian.
                self.start()
                self.urgent_move(arguments)
                self.cpu.run_to(self.labels["idle"], self.labels["idle_mailbox"], 0, 0, 0, 0, 200000)
                whole = bytes(self.mem[0x50:0x50 + 31])
                # The same step as 1/256 radian steps: ROTQ = 16 is the same
                # angle, made of two shears, with the counters left alone.
                fraction = list(arguments)
                fraction[42], fraction[43] = 16, 0
                self.start()
                self.urgent_move(fraction)
                self.cpu.run_to(self.labels["idle"], self.labels["idle_mailbox"], 0, 0, 0, 0, 200000)
                self.assertEqual(self.mem[0x7ff2], 0)
                part = bytes(self.mem[0x50:0x50 + 31])
                self.assertEqual(part[0:9], whole[0:9])          # same speed: same move
                self.assertEqual(part[27], whole[27])
                self.assertEqual(part[29:31], bytes(arguments[29:31]))
                for a, b in zip(self.vectors(part), self.vectors(whole)):
                    self.assertLessEqual(abs(a - b), 160, (case, a, b))
                # No time at all: nothing moves or turns.
                fraction[41], fraction[42] = 0, 0
                self.start()
                self.urgent_move(fraction)
                self.cpu.run_to(self.labels["idle"], self.labels["idle_mailbox"], 0, 0, 0, 0, 200000)
                still = bytes(self.mem[0x50:0x50 + 31])
                # (Our roll and pitch of 0 can still nudge the position by one
                # unit through the stock rounding, as on a whole tick.)
                self.assertEqual(still[9:27], bytes(arguments[9:27]))
                self.assertEqual(still[29:31], bytes(arguments[29:31]))

    def test_movement_preempts_ship_job(self):
        """An urgent move raised mid-job runs inside it without disturbing it."""
        rng = random.Random(77)
        heap = 0xff40
        ran = 0
        for case in range(40):
            ship_type = rng.choice([2, 10, 11, 14, 17, 31])
            blueprint = int.from_bytes(self.ships[2 * ship_type - 2:2 * ship_type], "little")
            block = self.ship_block(rng, ship_type, self.ships, False)
            command = [10, heap & 255, heap >> 8, 0, 2, 31,
                       blueprint & 255, blueprint >> 8, 0] + block[:31] + [block[31] & ~8]
            # Reference: the same job without interruption.
            self.start()
            self.submit(command)
            image, lines = bytes(self.mem[0x2000:0x7a00]), bytes(self.mem[heap:heap + 256])
            arguments, moved = self.random_move(rng)
            stop = self.labels["sh_LL30_go" if case % 2 else "sh_LL48_go"]
            self.start()
            data = bytes(command) + b"\0"
            self.mem[0x1c00:0x1c00 + len(data)] = data
            self.mem[0x7ff0] = 0x1c
            if self.cpu.run_to(self.labels["idle"], stop, 0, 0, 0, 0, 2000000) < 0:
                continue                    # nothing visible: no line drawn
            self.urgent_move(arguments)
            self.assertGreater(self.cpu.continue_to(self.labels["complete"], 2000000), 0)
            ran += 1
            with self.subTest(case=case):
                self.assertEqual(self.mem[0x7ff2], 0)
                self.assertEqual(bytes(self.mem[0x50:0x50 + 31]), moved)
                self.assertEqual(bytes(self.mem[0x2000:0x7a00]), image)
                self.assertEqual(bytes(self.mem[heap:heap + 256]), lines)
        self.assertGreater(ran, 20)

    def segments(self, lsx2, lsy2, size):
        """Lines between consecutive points of a ball line heap."""
        lines = []
        for n in range(1, size - 1):
            if lsy2[n] != 0xff and lsy2[n + 1] != 0xff:
                lines.append((lsx2[n], lsy2[n], lsx2[n + 1], lsy2[n + 1]))
        return lines

    def test_planet_circle_matches_original(self):
        """Command 14 reproduces stock CIRCLE2 lines and its ball line heap."""
        rng = random.Random(14)
        colour = 5
        for case in range(120):
            reference = bytearray(self.reference)
            reference[0x4000:0x6000] = bytes(0x2000)
            reference[0x7e] = 0                       # WPSHPS: LSP = 0
            reference[0x26a4] = reference[0x27a4] = 0xff
            self.start()
            vram = bytearray(self.mem)
            old = []
            for frame in range(3):
                radius = rng.choice([rng.randrange(1, 60), rng.randrange(60, 249)])
                step = 8 if radius < 8 else 4 if radius < 60 else 2
                x = rng.randrange(-radius - 20, 256 + radius + 20)
                y = rng.randrange(-radius - 20, 144 + radius + 20)
                with self.subTest(case=case, frame=frame, x=x, y=y, k=radius):
                    self.mem[:] = reference
                    self.mem[0x35:0x37] = (x & 0xffff).to_bytes(2, "little")
                    self.mem[0x43:0x45] = (y & 0xffff).to_bytes(2, "little")
                    self.mem[0x77] = radius
                    self.mem[0xac] = step
                    self.mem[0xb7] = 0
                    self.mem[0x26a4] = 0                  # CIRCLE: LSX2 = 0
                    self.assertGreater(self.cpu.reference_run_to(
                        self.stock_circle2, 0x200, 0, 0, 0, 0, 3000000), 0)
                    # PL9 always erases what remains of the old heap after.
                    self.assertGreater(self.cpu.reference_run_to(
                        self.stock_erase, 0x200, 0, 0, 0, 0, 3000000), 0)
                    reference = bytearray(self.mem)
                    size = reference[0x7e]
                    lsx2 = bytes(reference[0x26a4:0x26a4 + size])
                    lsy2 = bytes(reference[0x27a4:0x27a4 + size])
                    self.assertLess(size, 112)
                    self.mem[:] = vram
                    self.submit([14, x & 255, (x >> 8) & 255, y & 255, (y >> 8) & 255,
                                 radius, step, colour, 5])
                    self.assertEqual(self.mem[0x74], size)
                    self.assertEqual(bytes(self.mem[0x7b90:0x7b90 + size]), lsy2)
                    # At a segment break (LSY2 = $FF) LSX2 is never written
                    # or read, so it holds stale bytes on both machines.
                    ours = bytes(self.mem[0x7b20:0x7b20 + size])
                    self.assertEqual([a for a, b in zip(ours, lsy2) if b != 0xff],
                                     [a for a, b in zip(lsx2, lsy2) if b != 0xff])
                    new = self.segments(lsx2, lsy2, size)
                    actual = self.pixels(colour)
                    vram = bytearray(self.mem)
                    if any(255 in (a[0], a[2]) for a in new + old):
                        # LL30's x=255 wrap is deliberately fixed: compare
                        # with the (tested) line routine instead.
                        self.start()
                        for line in new:
                            self.submit([1, *line, colour])
                        expected = self.pixels(colour)
                        self.mem[:] = vram
                    else:
                        expected = {(px, py) for py in range(144) for px in range(256)
                                    if reference[0x4020 + (py // 8) * 320 + (px // 8) * 8
                                                 + (py & 7)] & (128 >> (px & 7))}
                    self.assertEqual(actual, expected)
                    old = new
            # WPLS2 erases everything that is left.
            self.submit([16, colour, 1])
            self.assertEqual(self.pixels(colour), set(), f"case {case}")
            self.assertEqual(self.mem[0x74], 1)
            self.assertEqual(self.mem[0x7b20], 0xff)

    def urgent_move(self, arguments):
        self.mem[0x7fc0:0x7fc0 + len(arguments)] = bytes(arguments)
        self.mem[0x7ff2] = 1


if __name__ == "__main__":
    unittest.main()

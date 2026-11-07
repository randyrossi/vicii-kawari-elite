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
        # Canaries guard the front image and reserved area below the mailbox.
        self.mem[0x8000:] = bytes([0xa5]) * 32768
        self.mem[0x7d00:0x7ff0] = bytes([0x69]) * 0x2f0
        self.assertGreaterEqual(self.cpu.run_to(0x200, self.labels["idle"],
                                               0, 0, 0, 0, 200000), 0)

    def submit(self, commands):
        data = bytes(commands) + b"\0"
        self.assertLessEqual(len(data), 1024)
        self.mem[0x1c00:0x1c00 + len(data)] = data
        self.mem[0x7ff0] = 1
        cycles = self.cpu.run_to(self.labels["idle"], self.labels["complete"],
                                 0, 0, 0, 0, 2000000)
        self.assertGreater(cycles, 0)
        self.assertEqual(self.mem[0x7ff1], 0)
        self.assertEqual(bytes(self.mem[0x8000:]), bytes([0xa5]) * 32768)
        self.assertEqual(bytes(self.mem[0x7d00:0x7ff0]), bytes([0x69]) * 0x2f0)
        self.assertEqual(bytes(self.mem[0x200:0x200 + len(self.code)]), self.code)
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
        # Many commands cross both the low-byte boundary and $1e00.
        command = [3, 240, 140, 128, 1]
        self.submit(command * 200)
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
            self.submit(bytes([6]) + data)
            self.assertEqual(bytes(self.mem[0x7c00:0x7c06]), expected)

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
                expected = bytes(self.mem[2:6]) + bytes(self.mem[0x6a2:0x6f0])
                expected_pixels = {(x, y) for y in range(144) for x in range(256)
                                   if self.mem[0x4020 + (y // 8) * 320 + (x // 8) * 8
                                               + (y & 7)] & (128 >> (x & 7))}
                self.start()
                self.submit(bytes([7]) + controls + particles)
                self.assertEqual(bytes(self.mem[0x7c1d:0x7c6f]), expected, (view, case))
                self.assertEqual(self.pixels(), expected_pixels, (view, case))


if __name__ == "__main__":
    unittest.main()

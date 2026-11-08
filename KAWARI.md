# Elite for VIC-II Kawari (PAL)

This build replaces the upper space/ship display with Kawari's packed-pixel
320×200, 16-colour VRAM mode. The view is colour-coded: space ships are red
(palette 2), space stations light blue (14), planets green (5), and suns and
stardust stay white (1). The original 256-pixel-wide game view is centred in
that display; the dashboard stays in legacy C64 DRAM, with its existing colours
and raster split.

## Build and run

Run `make` in this directory. The only target disk is
`5-compiled-game-disks/elite-kawari-pal.d64`. Requirements are BeebAsm, Python 3,
and VICE's `c1541`. The Makefile prefers the sibling
`../tools/beebasm-new/build/beebasm`; override `BEEBASM`, `PYTHON`, or `C1541`
if needed. `make commander=max` builds the equipped test commander;
plain `make` restores the normal commander.

From the Kawari workspace root:

```sh
vicii-kawari-vice/src/x64sc -pal \
  -8 elite-source-code-commodore-64/5-compiled-game-disks/elite-kawari-pal.d64 \
  -keybuf 'lO"*",8,1\x0d'
```

Use `N` to decline loading a commander, then Space at the second title screen,
and F1 to launch. True-drive loading is slow: allow several minutes of emulated
time. Warp mode can speed it up. For headless use, prefix the command with
`SDL_RENDER_DRIVER=software SDL_VIDEODRIVER=dummy`.

No cartridge or original custom-sector fast loader is required. The disk has
standard CBM files: `ELITE` autostarts `KAWARI`, which uploads the co-processor
image and loads the game resources. Use the **vicii-kawari-vice** emulator, not
vicii-vice-3.4. NTSC and stock VIC-II hardware are not supported.

## Rendering and division of work

The native 6502 program is assembled for its VRAM addresses (a main block at
`$0200` and a second block at `$7c00`), uploaded by the boot loader while the
co-processor is held in reset, and started at `$0200` with `CPU_SPEED=0`. It
accesses only VRAM, never DRAM or C64 I/O. All instructions are legal NMOS
6502, and none is `BIT` (this emulator's co-processor `BIT` changes the carry).

The co-processor runs, as relocated copies of the original routines:

* **One job per ship** (command 10): all of LL9 from LL17 onwards for a ship
  that is not exploding: matrix scaling, face visibility, vertex
  transformation and projection, edge selection, LL145 clipping, line drawing
  and the flicker-free line heap (LSPUT/LL155). Lines identical to the
  previous frame's are left in place rather than XOR-erased and redrawn.
* **Exploding ships** (command 13): the same job with every face visible
  (LL17X/EE30), then DOEXP's particle cloud (EXL1, PTCLS, EXS1): erasing the
  previous cloud, copying the projected vertices into the cloud in VRAM and
  drawing the new one, with a private copy of the random number seeds. On an
  explosion's first frame it also finds the explosion sprite's position
  (PTCLS2), which the host reads back and applies.
* **Ship movement** (MVEIT parts 2–7: speed and acceleration, rotation by our
  pitch and roll, our speed, orientation and the ship's own roll and pitch),
  through an urgent lane that can interrupt drawing already in progress.
* **Planet outlines**: CIRCLE2, BLINE and the flicker-free ball line heap
  (DrawPlanetLine, DrawNewPlanetLine, EraseRestOfPlanet, WPLS2).
* The stardust for all four views, with the particles kept in VRAM.
* Lines, spans, points, glyphs and clearing.

The 6510 keeps all game logic and anything with side effects: input, sound,
the dashboard and scanner, TACTICS, TIDY, SCAN, collision and hit tests,
DOEXP's bookkeeping (cloud size and counter, flags, sprite registers), suns,
meridian/crater geometry, the legacy charts and command construction. Ship blueprints are copied to VRAM once at start-up, so a
ship job is just its position, orientation, flags and colour (41 bytes), and
nothing is read back. Each ship's line coordinates live in VRAM at the same
address as its host line heap; the host keeps only the "drawn" flag (bit 3 of
byte #31), and KILLSHP's heap shuffle is repeated in VRAM (command 12) in
order with the drawing commands.

Every co-processor job was checked against the stock GMA86 PAL binary running
in the emulator's 6502 core (see Verification). One deliberate drawing
correction remains: the original LL30's reversed-line endpoint wrap at x=255.

Drawing and XOR erasing touch a hidden 320×144 backbuffer. At a completed frame
boundary the host flushes commands and copies 23,040 bytes into the visible
image. The copy (8 bytes per 6510 cycle) moves 3.15 image rows per raster line,
so it outruns the beam: started once the beam has passed image row 98 (raster
148), it cannot catch the beam before row 143, so each row is shown wholly old
or wholly new for that frame, and wholly new from the next. Started as late as
raster 311 it still finishes by raster 45, before the first visible row (50).
The host therefore starts it anywhere in rasters 152–311. Thus the viewer sees
a completed frame, not the intermediate XOR erase/redraw. For the same
reason a beam or military laser, which the original draws and erases within
one loop of the main flight loop, is erased at the start of the next loop's
laser code instead (just before any new beams are drawn), so every published
frame shows it while firing; pulse lasers are unchanged. Title, mission,
flight, death, escape-pod and tunnel loops have explicit frame boundaries;
keyboard waits also publish pending text.

The top raster interrupt is at line 40, enabling the mode before the first
visible line (50). The existing lower split remains at 194, and its hires-off
write is timed: the interrupt reaches it between raster 194 cycle 59 and
raster 195 cycle 1, so it lands after hires row 143's last fetch (cycle 54)
and before raster 195's badline stalls the CPU (cycle 11; cycles counted from
0). Raster 195 therefore shows the dashboard's top frame line. Should the
write ever be late, raster 195 shows hires row 144 (VRAM `$da00`–`$da9f`),
which is kept zero, so it is black rather than data. Legacy badlines
remain enabled so the dashboard's row addressing progresses normally. The
dashboard in this source is actually multicolour **bitmap** graphics, not
character mode; its original rendering is preserved.

Every extended-register access maps I/O first. Host wrappers update both `$01`
and Elite's `L1M` banking shadow and restore the previous bank afterwards.
The line and span calls have a fast path for the usual all-RAM banking: `L1M`
is set before the port, so an interrupt in between still restores a port
that matches it. Only foreground code owns the VRAM ports; the raster IRQ
changes video mode without touching them. KERNAL disk operations swap zero
page with interrupts disabled and restore it before re-enabling raster
processing.

The host copies of the stardust routines, LL9's projection and edge drawing,
LL51, LSPUT/LL155, PTCLS/EXS1 and the ship part of MVEIT were removed; the
host ship-job code occupies the stardust routines' old space.

## VRAM layout

| Range | Purpose |
| --- | --- |
| `$0000–$00ff` | Co-processor zero page |
| `$0100–$0193` | Projected ship vertices (XX3, as on the host) |
| `$0194–$01ff` | Co-processor stack |
| `$0200–$0bff` | Renderer, vector, clipping, movement arithmetic, BLINE, explosions |
| `$0c00–$0fff` | Logarithm and antilogarithm tables |
| `$1000–$1bff` | Stardust and ship job code |
| `$1c00–$1d61` | Command buffer A |
| `$1d62–$1dff` | Planet commands |
| `$1e00–$1f61` | Command buffer B |
| `$1f62–$1fff` | CIRCLE2 |
| `$2000–$79ff` | Hidden 320×144 image, 160 bytes/row |
| `$7a00–$7b1f` | Row-address tables |
| `$7b20–$7b8f` | Ball line heap, x coordinates (LSX2), 112 entries |
| `$7b90–$7bff` | Ball line heap, y coordinates (LSY2), 112 entries |
| `$7c00–$7c6e` | Explosion sprite result, RNG and stardust results/particles (with gaps) |
| `$7c70–$7fbf` | Ship movement code, sine table |
| `$7fc0–$7fe8` | Urgent movement arguments |
| `$7ff0–$7ff2` | Mailbox, invalid-command diagnostic, urgent movement flag |
| `$8000–$d9ff` | Visible image: the 144 displayed rows |
| `$da00–$da9f` | Always zero: hires row 144 (see the raster split) |
| `$daa0–$f98c` | Ship blueprints: the host's SHIPS block (`$d000`) + `$0a00`, without its lookup tables |
| `$f990–$fa57` | Space station line heap (host LSO) |
| `$fa72–$ffbf` | Ship line heaps and explosion clouds, at their host addresses |

Even x uses the high nibble; odd x uses the low nibble. Game x=0 begins at
physical x=32, so its backbuffer address is `$2010 + y*160 + x/2`.
Only the upper 144 rows are presented: the raster split switches the hires
mode off below them, so the rest of the 32 KB display allocation holds the
blueprints and line heaps. Initialisation clears 32,000 bytes from `$8000`
(avoiding the emulator's wrapping 32,768-byte fill case) and then copies the
blueprints. A frame adds at most about 103 ball line heap entries (a circle
and two meridians, or a circle and a crater, at most 1.5 entries per BLINE
call). NWSHP never lowers the ship line heap below `$fa72` (the end of the
last ship data block), and the largest possible total is about 1,100 bytes.

## Mailbox protocol

Commands are double-buffered in two buffers at `$1c00` and `$1e00`. The 6510
fills one while the co-processor may run the other, terminates it with command
0 and writes the buffer's start page to `$7ff0`; the co-processor runs the list
and clears `$7ff0`. The host switches buffers only when the co-processor is
idle, so it never writes a buffer that is being read. A command only starts in
its buffer's first page, so each buffer needs at most `$161` bytes. Ship jobs,
planet outlines and the stardust start the co-processor straight away when it
is idle, so drawing overlaps the host's work; the host waits only to present a
frame, or for results. An unknown command sets `$7ff1` to `$ff` and
acknowledges without consuming further commands.

| Command | Payload after command byte |
| --- | --- |
| 0 | End of batch |
| 1 | x1, y1, x2, y2, colour: line |
| 2 | x1, y, x2, unused, colour: exclusive-end horizontal span |
| 3 | x, y, distance, colour: original Elite point/star shape |
| 4 | x, y, colour, eight glyph-row bytes |
| 5 | Clear hidden image and draw side borders |
| 7 | 17 control bytes, 78 particle bytes: stardust; particles kept at `$7c21` |
| 8 | byte-x, y, byte-width, height: clear text rectangle |
| 9 | XOR side borders (used by the death scene) |
| 10 | heap address, drawn flag, colour, XX4, blueprint, dontclip, ship bytes #0–#31: draw one ship |
| 11 | heap address, drawn flag, colour, n, n lines: replace a ship's lines (SHPPT dot, EE51 erase) |
| 12 | source, destination, count: KILLSHP heap move |
| 13 | as command 10, then flags (bit 6 erase, bit 3 project and draw, bit 7 sprite), cloud header #0–#6, sprx, spry: exploding ship; sprite position at `$7c00` |
| 14 | K3, K4, K, STP, colour, flags: planet circle (CIRCLE2) |
| 15 | K6 (4 bytes), FLAG, colour: one BLINE segment (meridians, craters) |
| 16 | colour, operation: EraseRestOfPlanet, WPLS2, or clearing the ball line heap |
| 17 | 17 control bytes: stardust on the particles already in VRAM |

Ship movement does not use the command lists. The host writes the 41
arguments (ship bytes #0–#30, our pitch, roll and speed, the maximum speed) to
`$7fc0` and sets `$7ff2`; the co-processor checks that flag in its idle loop,
between commands and at each vertex and line of a ship or planet job, runs
the movement there, and clears it. The host then reads the moved ship from
co-processor zero page (`$0050`). Movement therefore never waits for drawing
that was queued earlier.

The host uploads stardust particles only after nWq (new stardust) or FLIP
(view change) has changed them, and fetches them back only before FLIP. RAND
is sent with every stardust command but no longer read back, so respawning
stardust no longer advances the host's random sequence.
Likewise, drawing an explosion cloud no longer stirs the host's RAND and
RAND+2 (PTCLS reseeds them per vertex and leaves them changed); the host still
sets RAND+3 from the planet's z_lo as PTCLS did. Neither affects what the game
draws, but the game's random sequence differs from the original's.

Colours are per-command four-bit values. The host selects `KW_COLOUR` per
object before drawing: red for ships, light blue for the space station, green
for planets, and white for suns and stardust. Our own laser beams are red as
well. An object's colour is determined by its type, so the flicker-free XOR
erasure redraws the previous frame's lines in the same colour. Legacy menus,
charts and the dashboard retain their original colours.

## Verification

```sh
make check c64-disk
python3 2-build-files/tests/smoke_kawari.py --true-drive
python3 2-build-files/tests/bench_kawari.py
```

`make check` compiles a small test bridge around the sibling emulator's real
6502 core (requires a C compiler and its configured source tree). Its 14 test
groups run the assembled co-processor image against the stock GMA86 PAL
binary: 305 reference lines and their XOR erasure, right-edge wrapping, 256
random coloured spans, glyphs/points, both command buffers, clears, 1,000 LL51
vector products, 160 stardust cases across all four views (plus second frames on
resident particles), 160 random ships of every type over two frames (stock
LL9's pixels and line heap, including laser lines, XOR redraw and erasure),
dots and heap moves, 64 exploding ships of every type over three frames
(stock LL9/DOEXP: cloud pixels, erasure, the cloud heap and the PTCLS2 sprite
position), 600 random ship movements (stock MVEIT parts 2–7), urgent
movement raised in the middle of ship jobs, and 120 random planet circles over
three frames (stock CIRCLE2 and EraseRestOfPlanet: pixels and ball line heap).
Canary checks ensure commands cannot change code, blueprints or the visible
image.

Reference comparisons use the stock PAL binary with the same generated math
tables. One deliberate drawing correction avoids the original reversed-line
endpoint wrap at x=255; where it applies, the tests compare with the renderer's
own (tested) lines instead. The reference-only CPU adapter corrects this
emulator's BIT flags; the production co-processor code does not use BIT and is
tested against the unmodified execution core.

The integration test requires Pillow and local TCP access to VICE's binary
monitor. It boots the built D64, injects inputs at documented game routine
interfaces without patching instructions, saves screenshots, samples PAL copy
timing and reports emulated FPS. It also checks disk-load error recovery and
special flight/mission sequences. `--output DIRECTORY` selects the artifact
directory; without it a temporary directory is printed. Omit `--true-drive`
for faster KERNAL-trap disk loading.

`bench_kawari.py` launches, stops our ship and spawns a fixed fleet of six
rotating ships (Cobra Mk III, Anaconda, Sidewinder, Adder, Constrictor, Viper)
in front of the planet through the game's own ZINF/NWSHP routines. It reports
emulated FPS, an exact per-frame cycle breakdown of the top-level routines
(breakpoints and the emulated clock), and a sampled profile. `--scene cobra`
or `--scene none` select other scenes; `--explode` destroys the scene's ships
and measures the explosions (20 frames by emulated clock, plus the
breakdown); `BENCH_EXTRA="PLANET CIRCLE2"` adds routines to the breakdown.

## Measurements

Emulated PAL frame rates in the supplied Kawari VICE, original Kawari build
(commit `bad6aff`) versus this one, with the same scripts:

| Scene | Original | Now |
| --- | --- | --- |
| Title screen, rotating ship (`smoke_kawari.py`, TLL2) | 10.2 FPS | 47.4 FPS |
| Flight just after launch (`smoke_kawari.py`, MLOOP) | 12.3 FPS | 36.2 FPS |
| Six ships and the planet (`bench_kawari.py`) | 2.6 FPS | 16.7 FPS |
| The same six ships exploding (`bench_kawari.py --explode`) | 1.6 FPS* | 15.9 FPS |

\* Measured on the previous build of this branch, with host explosions; the
original Kawari build is slower still.

In the fleet scene a frame fell from about 410,000 to 59,000 6510 cycles. The
original spent 313,000 cycles per frame in LL9 (ships and planet) and 62,000 in
MVEIT; now LL9 takes 9,300 (the planet 3,900) and MVEIT 20,600, of which ship
movement is 10,100. Most of the remainder is host game logic: SCAN (5,200),
DIALS (3,200), TIDY, the main loop's ship bookkeeping, and presenting the frame
(11,200, including waiting for the co-processor to finish and for the raster
window). A ship job costs the co-processor roughly 45,000 of its cycles for a
Cobra Mk III (about 2,800 6510-cycle equivalents) and runs alongside the host.
With six explosions a frame fell from about 750,000 cycles (517,000 in DOEXP's
particles, most of the rest in projecting their vertices with a co-processor
round trip per vertex) to 62,000; presenting the frame (24,000) is then mostly
waiting for the co-processor to finish the clouds.
These are particular scenes, not a whole-game benchmark.

Validation is in the supplied Kawari VICE, not on a physical board. On real
hardware the co-processor is briefly stalled whenever the 6510 touches
`$d02f`–`$d03f`, which the emulator does not model, so polling loops may cost
it a little time. Long-play coverage of all missions, combat conditions and
commander save/load cases is still recommended. The normal game save menu
remains available; the automated disk test is read-only and checks the
missing-file recovery path.

The full-1541-emulation run passed on 2026-11-07 with these changes: title
47.5 FPS, flight 36.1 FPS, all eight copy samples within rasters 152–311 and
finished before raster 50. The disk image SHA-256 was
`7f297e21603364a63beef8308ffbf543564d67244f1c83e8b2c953b6ce183106`.

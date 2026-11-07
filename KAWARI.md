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

The native 6502 program is assembled for VRAM `$0200`, uploaded while held in
reset, and started there with `CPU_SPEED=0`. It handles line rasterisation,
horizontal spans, points, glyphs, clearing, the LL51 vector/matrix operation,
and the complete four-view stardust movement/rotation/drawing routines. It
accesses only VRAM, never DRAM or C64 I/O. All instructions are legal NMOS 6502.

The 6510 still runs game logic, input, sound, the dashboard, ship visibility,
projection/clipping and command construction. Unsigned host multiplication
uses Kawari's hardware multiplier; the legacy chart line fallback uses its
divider. Co-processor arithmetic uses private tables/software since that CPU
cannot access the math registers. Moving more of the complete ship pipeline
is a possible future optimisation, not part of this implementation.

Drawing and XOR erasing touch a hidden 320×144 backbuffer. At a completed frame
boundary the host flushes commands and copies 23,040 bytes into the visible
image. On PAL it starts only at raster 194–249. At eight bytes per 6510 cycle
the copy takes about 46 lines and finishes before the next visible upper
display. Thus the viewer sees a completed frame, not the intermediate XOR
erase/redraw. Title, mission, flight, death, escape-pod and tunnel loops have
explicit frame boundaries; keyboard waits also publish pending text.

The top raster interrupt is at line 40, enabling the mode before the first
visible line (50). The existing lower split remains at 194. Legacy badlines
remain enabled so the dashboard's row addressing progresses normally. The
dashboard in this source is actually multicolour **bitmap** graphics, not
character mode; its original rendering is preserved.

Every extended-register access maps I/O first. Host wrappers update both `$01`
and Elite's `L1M` banking shadow and restore the previous bank afterwards.
Only foreground code owns the VRAM ports; the raster IRQ changes video mode
without touching them. KERNAL disk operations swap zero page with interrupts
disabled and restore it before re-enabling raster processing.

## VRAM layout

| Range | Purpose |
| --- | --- |
| `$0000–$00ff` | Co-processor zero page |
| `$0100–$01ff` | Co-processor stack |
| `$0200–$0aff` | Renderer and vector code |
| `$0b00–$0fff` | Pixel-rounding and arithmetic tables |
| `$1000–$1bff` | Relocated stardust code |
| `$1c00–$1fff` | Host command buffer |
| `$2000–$79ff` | Hidden 320×144 image, 160 bytes/row |
| `$7a00–$7bff` | Row-address tables |
| `$7c00–$7c6e` | Vector, RNG and stardust results (with reserved gaps) |
| `$7c6f–$7fef` | Unused |
| `$7ff0–$7ff1` | Mailbox and invalid-command diagnostic |
| `$8000–$ffff` | Reserved 32 KB visible 320×200 image |

Even x uses the high nibble; odd x uses the low nibble. Game x=0 begins at
physical x=32, so its backbuffer address is `$2010 + y*160 + x/2`.
Only the upper 144 rows are presented. The full 32 KB display allocation is
reserved, although 320×200 pixels occupy 32,000 bytes. Initialisation clears
those 32,000 bytes, avoiding the emulator's wrapping 32,768-byte fill case.

## Mailbox protocol

The 6510 writes commands starting at `$1c00`, terminates them with command 0,
then writes 1 to `$7ff0`. The co-processor runs the entire list and clears
`$7ff0`. The host waits for acknowledgement before reusing the command buffer
or reading results. It flushes when the next command would start at or above
`$1f00`, reserving enough room for the largest command. An unknown command sets
`$7ff1` to `$ff` and acknowledges without consuming further commands.

| Command | Payload after command byte |
| --- | --- |
| 0 | End of batch |
| 1 | x1, y1, x2, y2, colour: line |
| 2 | x1, y, x2, unused, colour: exclusive-end horizontal span |
| 3 | x, y, distance, colour: original Elite point/star shape |
| 4 | x, y, colour, eight glyph-row bytes |
| 5 | Clear hidden image and draw side borders |
| 6 | Six vector bytes, 18 matrix bytes; result at `$7c00` |
| 7 | 17 control bytes, 78 particle bytes; results at `$7c1d` |
| 8 | byte-x, y, byte-width, height: clear text rectangle |
| 9 | XOR side borders (used by the death scene) |

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
```

`make check` compiles a small test bridge around the sibling emulator's real
6502 core (requires a C compiler and its configured source tree). Eight test
groups cover 305 reference lines and their XOR erasure, right-edge wrapping,
256 random coloured spans, glyphs/points, command-buffer boundaries, clears,
1,000 vector transforms and 160 stardust cases across all four views. Canary
checks ensure commands cannot change code or the visible image.

Reference comparisons use the stock PAL binary with the same generated math
tables. One deliberate drawing correction avoids the original reversed-line
endpoint wrap at x=255. The reference-only CPU adapter corrects this emulator's
BIT flags; the production co-processor code does not use BIT and is tested
against the unmodified execution core.

The integration test requires Pillow and local TCP access to VICE's binary
monitor. It boots the built D64, injects inputs at documented game routine
interfaces without patching instructions, saves screenshots, samples PAL copy
timing and reports emulated FPS. It also checks disk-load error recovery and
special flight/mission sequences. `--output DIRECTORY` selects the artifact
directory; without it a temporary directory is printed. Omit `--true-drive`
for faster KERNAL-trap disk loading.

Representative early measurements were approximately 9–10 FPS on the title
and 11–12 FPS in flight, versus approximately 7 and 9 FPS in the original PAL
build. Scene complexity and sampled animation phase matter; these are not a
whole-game benchmark or a claim of a 16× frame-rate improvement. Measured copy
intervals include PAL lines 199–245, entirely below the upper view.

Validation is in the supplied Kawari VICE, not on a physical board. Long-play
coverage of all missions, combat conditions and commander save/load cases is
still recommended. The normal game save menu remains available; the automated
disk test is read-only and checks the missing-file recovery path.

The full-1541-emulation run passed on 2026-11-07 after the per-object colour
change, with a sampled flight rate of 12.34 FPS and all eight copy samples at
raster 199–245. A second build produced the same disk SHA-256:
`98f443e07a6ae7fd9f11b3470558dcc0cb7594d6418d14f3e24e055251dd6237`.

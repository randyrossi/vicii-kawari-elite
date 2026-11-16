The game now runs at real-time pace. Flight, combat and timers move at the original game's speed while frames draw up to 25 FPS. The pace is a build parameter you can raise to speed the game up.

How to set it
make pace=10        # 10 game ticks/s, 25% faster than the original's 8
make pace=8 fps=50  # original pace, frame cap raised to 50 FPS
make                # defaults: pace=8 fps=25
- pace is game ticks per second, from 0.5 to 50. A tick is one step of game logic, so 8 matches the original's 7–8 FPS feel.
- fps is the frame cap, 25 or 50.
- Live tuning: the per-field increment is also stored in the KW_PACE_STEP word. You can change it from the VICE monitor while the game runs, without rebuilding.
- When it's missing: leaving an option out of a make resets it to its default. The settings from the previous build are not kept.

How it works
- Ticks: the raster interrupt counts screen refreshes (50 per second on PAL), and those counts decide when a game tick is due.
- Motion between ticks: each frame's motion is scaled by its share of a tick. That covers your speed, roll and pitch for stardust, planet and ships, plus each ship's own spin, which the co-processor now applies in fractional steps. On a full-tick frame the original code runs unchanged.
- Once per tick: everything else runs on ticks only: AI, energy, fuel and temperatures, spawning, laser firing, explosion growth, the hyperspace countdown, the docking computer, and key-driven speed and roll changes. The military laser beam is still redrawn every frame. The title ship, death screen, escape pod, mission briefing and hyperspace tunnel take as long as in the original.

Results (emulated, default build)

┌────────────────┬──────┬─────────┬──────────────────────────────────────────────┐
│     Scene      │ FPS  │ Ticks/s │            Speed (full throttle)             │
├────────────────┼──────┼─────────┼──────────────────────────────────────────────┤
│ One ship       │ 25.1 │ 8.04    │ 321 units/s (40 per tick, the original rate) │
├────────────────┼──────┼─────────┼──────────────────────────────────────────────┤
│ Six-ship fleet │ 17.3 │ 8.02    │ 321 units/s                                  │
└────────────────┴──────┴─────────┴──────────────────────────────────────────────┘

Flying speed stays the same even when the frame rate drops to 17 FPS. A pace=12 fps=50 build gave 12.0 ticks/s and 482 units/s in both scenes.

That build reached 31 FPS with no ships in view, so the 50 FPS cap does work. With even one ship it still renders at about 25, because drawing can't go faster there.

Tests: make check passes all 15 test groups, including a new one for fractional-tick ship movement. The full smoke test passes on the default build: title screen 25.0 FPS, flight 25.0 FPS, all special sequences verified. I haven't re-run the full disk-drive emulation test (--true-drive).

Caveats
- Paths: between ticks, rotation is approximated, so ships trace very slightly different paths than in the original.
- Random numbers: the game's random sequence differs from the original's.
- Heavy load: a frame never counts for more than one tick. If the frame rate falls below pace, the game slows down as the original did rather than skipping ahead.
- Short key taps: speed, jump and roll keys act only on ticks, so a very short tap that falls entirely between two ticks can be missed.

Memory: about 72 bytes remain free in the main code area. To make room, I moved the escape pod and briefing loops into the second code area, and the co-processor's sine table into its main code block.

KAWARI.md now has a "Game pacing" section and updated memory map, protocol, test and measurement notes. Nothing has been committed.

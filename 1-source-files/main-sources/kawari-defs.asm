; Private 6510 workspace; Elite's original zero page ends at $d1.
KW_ACTIVE = $D2
KW_WRITE = $D3
KW_DIRTY = $D5
KW_ARG = $D6
KW_DX = $D7
KW_DY = $D8
KW_ERR = $D9
KW_STEP = $DA
KW_COUNT = $DB
KW_X = $DC
KW_Y = $DD
KW_SLOPE = $DE
KW_BANK = $DF
KW_PTR = $E0
KW_EX_RESULT = $7C00     ; co-processor EX_RESULT (explosion sprite position)
; Real-time pacing (see KW_PACE in kawari-host.asm). The game logic advances
; in game ticks at the original game's rate, _KW_PACE per second (set with
; "make pace=..."), while frames are drawn as fast as possible, but no more
; often than every _KW_FIELDS PAL fields ("make fps=25" or "fps=50").
; A tick is 4096 units of time; KW_PACE_INC units pass every 50 Hz field.
KW_PACE_INC = INT(4096 * _KW_PACE / 50 + 0.5)
KW_MIN_FIELDS = _KW_FIELDS
; Sequences that the original ran one step per frame (see KW_SCENE) step at
; the stock PAL game's frame rate in that sequence, measured in the emulator
; on the GMA86 disk, scaled by the pace (_KW_PACE / 8) like everything else.
KW_RATE_TITLE1 = 24.5   ; first title (Cobra Mk III approaching): 96 -> 1 in 3.9 s
KW_RATE_TITLE2 = 44.0   ; second title (Adder approaching): 96 -> 1 in 2.2 s
KW_RATE_ESCAPE = 28.3   ; escape pod: our Cobra flies away (ESL1, 97 steps in 3.4 s)
KW_RATE_BRIEF1 = 8.7    ; mission briefing: the Constrictor turns (BRL1, 64 steps in 7.4 s)
KW_RATE_BRIEF2 = 47.4   ; mission briefing: the Constrictor flies away (BRL2, 127 steps in 2.7 s)
KW_RATE_TUNNEL = 12.2   ; launch and hyperspace tunnels (HFL5, 8 ring sets in 0.58 s; the
                        ; first ring set needs no wait, so this is below 8 / 0.58)
KW_RATE_DEATH = 5.5     ; death screen (D2, 64 passes of the flight loop in 11.7 s)
KW_SCENE_UNIT = 4096 * _KW_PACE / 8 / 50   ; tick units per field per step/s
KW_COLOUR = $E2         ; Current drawing colour, as a packed-pixel palette
                        ; index (see the KW_* colour values below)

; 320x200x16 command colours: one nibble per pixel, indexing the 16-colour
; palette (the same order as the C64's colour registers).
KW_WHITE = 1
KW_RED = 2
KW_GREEN = 5
KW_LIGHT_BLUE = 14

MACRO KW_SAVE
 PHP
 PHA
 TXA
 PHA
 TYA
 PHA
 LDA L1M
 PHA
 LDA #5
 JSR SETL1             ; update both the port and the IRQ's banking shadow
ENDMACRO
MACRO KW_RESTORE
 PLA
 JSR SETL1
 PLA
 TAY
 PLA
 TAX
 PLA
 PLP
 RTS
ENDMACRO

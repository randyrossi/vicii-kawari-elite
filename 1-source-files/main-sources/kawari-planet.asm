; Planet outlines for the co-processor: CIRCLE2, BLINE and the flicker-free
; ball line heap (DrawPlanetLine, DrawNewPlanetLine, EraseRestOfPlanet),
; relocated from elite-source.asm. Clipping uses the ship job's LL145 and
; drawing its LL30. The ball line heap (LSP, LSX2, LSY2) belongs to the
; co-processor; the host keeps its own copy only for the legacy charts.
;
; Command 14, circle (CIRCLE from CIRCLE2 onwards):
;   +1,+2 K3 (centre x), +3,+4 K4 (centre y), +5 K (radius), +6 STP,
;   +7 colour, +8 flags: bit 0 set LSX2 = 0 first (CIRCLE), bit 1 set LSP = 1
;   first (the hyperspace rings), bit 2 erase the rest of the old heap after
; Command 15, one BLINE segment (meridians and craters, from PLS22):
;   +1..+4 K6 (new point x, y, after BLINE's first addition), +5 FLAG,
;   +6 colour. The host itself updates FLAG and CNT as BLINE would.
; Command 16, heap operation: +1 colour, +2 operation:
;   0 = EraseRestOfPlanet, 1 = WPLS2, 2 = clear (RES2), 3 = clear and LSP = 0
;   (WPSHPS)

; Variables are defined in kawari-cpu.asm (its entry code initialises the
; heap).

.planet_circle_command
 LDY #1
 LDX #0
.planet_circle_input
 LDA (cmd),Y
 STA pl_K3,X            ; K3, K3+1
 INY
 INX
 CPX #2
 BNE planet_circle_input
 LDA (cmd),Y
 STA pl_K4
 INY
 LDA (cmd),Y
 STA pl_K4+1
 INY
 LDA (cmd),Y
 STA pl_K
 INY
 LDA (cmd),Y
 STA pl_STP
 INY
 JSR planet_colour
 INY
 LDA (cmd),Y
 PHA
 LSR A
 BCC planet_circle_heap
 LDA #0
 STA pl_LSX2            ; the heap is about to be filled
.planet_circle_heap
 PLA
 PHA
 AND #%00000010
 BEQ planet_circle_draw
 LDA #1
 STA pl_LSP
.planet_circle_draw
 JSR pl_CIRCLE2
 PLA
 AND #%00000100
 BEQ planet_done
 JMP pl_EraseRest

.planet_bline_command
 LDY #1
 LDX #0
.planet_bline_input
 LDA (cmd),Y
 STA pl_K6,X
 INY
 INX
 CPX #4
 BNE planet_bline_input
 LDA (cmd),Y
 STA pl_FLAG
 INY
 JSR planet_colour
 JMP pl_BLINE

.planet_op_command
 LDY #1
 JSR planet_colour
 INY
 LDA (cmd),Y
 BNE planet_op_heap
 JMP pl_EraseRest
.planet_op_heap
 LSR A
 BCS planet_odd_op
.planet_clear           ; 2: RES2 clears the heaps
 LDA #$FF
 STA pl_LSX2
 STA pl_LSY2
.planet_done
 RTS
.planet_odd_op
 BNE planet_clear_all
 LDY pl_LSX2            ; 1: WPLS2
 BNE planet_wipe_done
 STY pl_LSNUM
 LDA pl_LSP
 STA pl_LSNUM2
 JSR pl_EraseRest
.planet_wipe_done
 LDA #1
 STA pl_LSP
 LDA #$FF
 STA pl_LSX2
 RTS
.planet_clear_all       ; 3: WPSHPS also resets the heap pointer
 LDA #0
 STA pl_LSP
 BEQ planet_clear



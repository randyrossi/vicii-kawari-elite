; Complete wireframe ship job for the co-processor: the original LL9 code
; from LL17 (matrix scaling, face visibility, vertex transformation and
; projection, edge selection, clipping) through the flicker-free line heap
; (LSPUT/LL155), relocated from elite-source.asm. No host RAM or I/O access.
;
; Blueprints are a verbatim copy of the host's SHIPS block, placed at the
; host address + SH_BLUEPRINT_OFFSET. Each ship's line heap lives in VRAM at
; the same address as its host heap ($F98E-$FFBF), except the space station's
; LSO heap, which the host maps to SH_LSO. The co-processor owns the line
; coordinates; the host keeps only the "drawn" flag (bit 3 of byte #31).
;
; BIT is never used: the emulator's co-processor implementation of BIT is
; incorrect, so each original BIT test is replaced by an equivalent sequence.

; Constants and variables are defined in kawari-clip.asm, which is
; assembled first.

; ------------------------------------------------------------------------------
; Command 10: draw one ship.
;   +1,+2  line heap address (VRAM)
;   +3     bit 3 set if the heap holds the lines currently on screen
;   +4     colour
;   +5     XX4 (visibility distance cut)
;   +6,+7  host blueprint address (XX0)
;   +8     dontclip
;   +9..40 ship data block bytes #0-#31 (XX1)
; ------------------------------------------------------------------------------
.ship_command
 JSR sh_heap_header
 LDY #5
 LDA (cmd),Y
 STA sh_XX4
 INY
 LDA (cmd),Y
 STA sh_XX0
 INY
 LDA (cmd),Y
 CLC
 ADC #HI(SH_BLUEPRINT_OFFSET)
 STA sh_XX0+1
 INY
 LDA (cmd),Y
 STA sh_dontclip
 LDX #0
.ship_input
 INY
 LDA (cmd),Y
 STA sh_XX1,X
 INX
 CPX #32
 BNE ship_input
 LDY #6                 ; as in LL10: the laser vertex starts off invisible
 LDA (sh_XX0),Y
 TAX
 LDA #255
 STA SH_XX3,X
 STA SH_XX3+1,X
 JMP sh_LL17

; Common header: heap pointer, drawn flag and colour. Sets LSNUM = 1 and
; LSNUM2 to the old heap size (or 0 when nothing is on screen).
.sh_heap_header
 LDY #1
 LDA (cmd),Y
 STA sh_XX19
 INY
 LDA (cmd),Y
 STA sh_XX19+1
 INY
 LDA (cmd),Y
 AND #%00001000
 BEQ sh_heap_empty
 LDY #0
 LDA (sh_XX19),Y
.sh_heap_empty
 STA sh_LSNUM2
 LDY #4
 LDA (cmd),Y
 STA colour
 LDA #1
 STA sh_LSNUM
 RTS

; ------------------------------------------------------------------------------
; Command 11: replace a heap's lines with an explicit list (ship dots via
; SHPPT, or erasure via EE51 with no lines).
;   +1..+4 as command 10, +5 line count, then four bytes per line
; ------------------------------------------------------------------------------
.lines_command
 JSR sh_heap_header
 LDY #5
 LDA (cmd),Y
 STA sh_CNT2
 BEQ lines_done
.lines_next
 LDX #0
.lines_coords
 INY
 LDA (cmd),Y
 STA sh_XX15,X
 INX
 CPX #4
 BNE lines_coords
 STY sh_CNT
 JSR sh_LSPUT
 LDY sh_CNT
 DEC sh_CNT2
 BNE lines_next
.lines_done
 JMP sh_LL155

; ------------------------------------------------------------------------------
; Command 12: replicate KILLSHP's heap shuffle (KSL3) in VRAM.
;   +1,+2 source, +3,+4 destination, +5 count (copied from the top down)
; ------------------------------------------------------------------------------
.move_command
 LDY #1
 LDA (cmd),Y
 STA sh_V
 INY
 LDA (cmd),Y
 STA sh_V+1
 INY
 LDA (cmd),Y
 STA sh_XX19
 INY
 LDA (cmd),Y
 STA sh_XX19+1
 INY
 LDA (cmd),Y
 TAY
 BEQ move_done
.move_byte
 DEY
 LDA (sh_V),Y
 STA (sh_XX19),Y
 TYA
 BNE move_byte
.move_done
 RTS

; ------------------------------------------------------------------------------
; LL9 from LL17, for a ship that is not exploding.
; ------------------------------------------------------------------------------
.sh_LL17
 LDX #5
.sh_LL15
 LDA sh_XX1+21,X
 STA sh_XX16,X
 LDA sh_XX1+15,X
 STA sh_XX16+6,X
 LDA sh_XX1+9,X
 STA sh_XX16+12,X
 DEX
 BPL sh_LL15
 LDA #197
 STA sh_Q
 LDY #16
.sh_LL21
 LDA sh_XX16,Y
 ASL A
 LDA sh_XX16+1,Y
 ROL A
 JSR sh_LL28
 LDX sh_R
 STX sh_XX16,Y
 DEY
 DEY
 BPL sh_LL21
 LDX #8
.sh_ll91
 LDA sh_XX1,X
 STA sh_XX18,X
 DEX
 BPL sh_ll91
 LDA #255
 STA sh_XX2+15
 LDY #12
 LDA sh_XX1+31          ; exploding (command 13): all faces visible (EE30)
 AND #%00100000
 BEQ sh_LL17_faces
 JMP ex_EE30
.sh_LL17_faces
 LDA (sh_XX0),Y
 BNE sh_EE29
 JMP sh_LL42
.sh_EE29
 STA sh_XX20
 LDY #18
 LDA (sh_XX0),Y
 TAX
 LDA sh_XX18+7
.sh_LL90
 TAY
 BEQ sh_LL91
.sh_LL90b
 INX
 LSR sh_XX18+4
 ROR sh_XX18+3
 LSR sh_XX18+1
 ROR sh_XX18
 LSR A
 ROR sh_XX18+6
 TAY
 BNE sh_LL90b
.sh_LL91
 STX sh_XX17
 LDA sh_XX18+8
 STA sh_XX15+5
 LDA sh_XX18
 STA sh_XX15
 LDA sh_XX18+2
 STA sh_XX15+1
 LDA sh_XX18+3
 STA sh_XX15+2
 LDA sh_XX18+5
 STA sh_XX15+3
 LDA sh_XX18+6
 STA sh_XX15+4
 JSR sh_LL51
 LDA sh_XX12
 STA sh_XX18
 LDA sh_XX12+1
 STA sh_XX18+2
 LDA sh_XX12+2
 STA sh_XX18+3
 LDA sh_XX12+3
 STA sh_XX18+5
 LDA sh_XX12+4
 STA sh_XX18+6
 LDA sh_XX12+5
 STA sh_XX18+8
 LDY #4
 LDA (sh_XX0),Y
 CLC
 ADC sh_XX0
 STA sh_V
 LDY #17
 LDA (sh_XX0),Y
 ADC sh_XX0+1
 STA sh_V+1
 LDY #0
.sh_LL86
 LDA (sh_V),Y
 STA sh_XX12+1
 AND #%00011111
 CMP sh_XX4
 BCS sh_LL87
 TYA
 LSR A
 LSR A
 TAX
 LDA #255
 STA sh_XX2,X
 TYA
 ADC #4
 TAY
 JMP sh_LL88
.sh_LL87
 LDA sh_XX12+1
 ASL A
 STA sh_XX12+3
 ASL A
 STA sh_XX12+5
 INY
 LDA (sh_V),Y
 STA sh_XX12
 INY
 LDA (sh_V),Y
 STA sh_XX12+2
 INY
 LDA (sh_V),Y
 STA sh_XX12+4
 LDX sh_XX17
 CPX #4
 BCC sh_LL92
 LDA sh_XX18
 STA sh_XX15
 LDA sh_XX18+2
 STA sh_XX15+1
 LDA sh_XX18+3
 STA sh_XX15+2
 LDA sh_XX18+5
 STA sh_XX15+3
 LDA sh_XX18+6
 STA sh_XX15+4
 LDA sh_XX18+8
 STA sh_XX15+5
 JMP sh_LL89
.sh_ovflw
 LSR sh_XX18
 LSR sh_XX18+6
 LSR sh_XX18+3
 LDX #1
.sh_LL92
 LDA sh_XX12
 STA sh_XX15
 LDA sh_XX12+2
 STA sh_XX15+2
 LDA sh_XX12+4
.sh_LL93
 DEX
 BMI sh_LL94
.sh_LL93b
 LSR sh_XX15
 LSR sh_XX15+2
 LSR A
 DEX
 BPL sh_LL93b
.sh_LL94
 STA sh_R
 LDA sh_XX12+5
 STA sh_S
 LDA sh_XX18+6
 STA sh_Q
 LDA sh_XX18+8
 JSR sh_LL38
 BCS sh_ovflw
 STA sh_XX15+4
 LDA sh_S
 STA sh_XX15+5
 LDA sh_XX15
 STA sh_R
 LDA sh_XX12+1
 STA sh_S
 LDA sh_XX18
 STA sh_Q
 LDA sh_XX18+2
 JSR sh_LL38
 BCS sh_ovflw
 STA sh_XX15
 LDA sh_S
 STA sh_XX15+1
 LDA sh_XX15+2
 STA sh_R
 LDA sh_XX12+3
 STA sh_S
 LDA sh_XX18+3
 STA sh_Q
 LDA sh_XX18+5
 JSR sh_LL38
 BCS sh_ovflw
 STA sh_XX15+2
 LDA sh_S
 STA sh_XX15+3
.sh_LL89
 LDA sh_XX12
 STA sh_Q
 LDA sh_XX15
 JSR sh_FMLTU
 STA sh_T
 LDA sh_XX12+1
 EOR sh_XX15+1
 STA sh_S
 LDA sh_XX12+2
 STA sh_Q
 LDA sh_XX15+2
 JSR sh_FMLTU
 STA sh_Q
 LDA sh_T
 STA sh_R
 LDA sh_XX12+3
 EOR sh_XX15+3
 JSR sh_LL38
 STA sh_T
 LDA sh_XX12+4
 STA sh_Q
 LDA sh_XX15+4
 JSR sh_FMLTU
 STA sh_Q
 LDA sh_T
 STA sh_R
 LDA sh_XX15+5
 EOR sh_XX12+5
 JSR sh_LL38
 PHA
 TYA
 LSR A
 LSR A
 TAX
 LDA sh_S               ; replaces BIT S / BMI: keep A unless S is negative
 ASL A
 PLA
 BCS sh_face_store
 LDA #0
.sh_face_store
 STA sh_XX2,X
 INY
.sh_LL88
 CPY sh_XX20
 BCS sh_LL42
 JMP sh_LL86

.sh_LL42
 LDY sh_XX16+2
 LDX sh_XX16+3
 LDA sh_XX16+6
 STA sh_XX16+2
 LDA sh_XX16+7
 STA sh_XX16+3
 STY sh_XX16+6
 STX sh_XX16+7
 LDY sh_XX16+4
 LDX sh_XX16+5
 LDA sh_XX16+12
 STA sh_XX16+4
 LDA sh_XX16+13
 STA sh_XX16+5
 STY sh_XX16+12
 STX sh_XX16+13
 LDY sh_XX16+10
 LDX sh_XX16+11
 LDA sh_XX16+14
 STA sh_XX16+10
 LDA sh_XX16+15
 STA sh_XX16+11
 STY sh_XX16+14
 STX sh_XX16+15
 LDY #8
 LDA (sh_XX0),Y
 STA sh_XX20
 LDA sh_XX0
 CLC
 ADC #20
 STA sh_V
 LDA sh_XX0+1
 ADC #0
 STA sh_V+1
 LDY #0
 STY sh_CNT
.sh_LL48
 LDA MV_URGENT          ; let urgent movement run between vertices
 BEQ sh_LL48_go
 JSR urgent_run
.sh_LL48_go
 STY sh_XX17
 LDA (sh_V),Y
 STA sh_XX15
 INY
 LDA (sh_V),Y
 STA sh_XX15+2
 INY
 LDA (sh_V),Y
 STA sh_XX15+4
 INY
 LDA (sh_V),Y
 STA sh_T
 AND #%00011111
 CMP sh_XX4
 BCC sh_LL50j
 INY
 LDA (sh_V),Y
 STA sh_P
 AND #%00001111
 TAX
 LDA sh_XX2,X
 BNE sh_LL49
 LDA sh_P
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA sh_XX2,X
 BNE sh_LL49
 INY
 LDA (sh_V),Y
 STA sh_P
 AND #%00001111
 TAX
 LDA sh_XX2,X
 BNE sh_LL49
 LDA sh_P
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA sh_XX2,X
 BNE sh_LL49
.sh_LL50j
 JMP sh_LL50
.sh_LL49
 LDA sh_T
 STA sh_XX15+1
 ASL A
 STA sh_XX15+3
 ASL A
 STA sh_XX15+5
 JSR sh_LL51
 LDA sh_XX1+2
 STA sh_XX15+2
 EOR sh_XX12+1
 BMI sh_LL52
 CLC
 LDA sh_XX12
 ADC sh_XX1
 STA sh_XX15
 LDA sh_XX1+1
 ADC #0
 STA sh_XX15+1
 JMP sh_LL53
.sh_LL52
 LDA sh_XX1
 SEC
 SBC sh_XX12
 STA sh_XX15
 LDA sh_XX1+1
 SBC #0
 STA sh_XX15+1
 BCS sh_LL53
 EOR #%11111111
 STA sh_XX15+1
 LDA #1
 SBC sh_XX15
 STA sh_XX15
 BCC sh_LL52a
 INC sh_XX15+1
.sh_LL52a
 LDA sh_XX15+2
 EOR #%10000000
 STA sh_XX15+2
.sh_LL53
 LDA sh_XX1+5
 STA sh_XX15+5
 EOR sh_XX12+3
 BMI sh_LL54
 CLC
 LDA sh_XX12+2
 ADC sh_XX1+3
 STA sh_XX15+3
 LDA sh_XX1+4
 ADC #0
 STA sh_XX15+4
 JMP sh_LL55
.sh_LL54
 LDA sh_XX1+3
 SEC
 SBC sh_XX12+2
 STA sh_XX15+3
 LDA sh_XX1+4
 SBC #0
 STA sh_XX15+4
 BCS sh_LL55
 EOR #%11111111
 STA sh_XX15+4
 LDA sh_XX15+3
 EOR #%11111111
 ADC #1
 STA sh_XX15+3
 LDA sh_XX15+5
 EOR #%10000000
 STA sh_XX15+5
 BCC sh_LL55
 INC sh_XX15+4
.sh_LL55
 LDA sh_XX12+5
 BMI sh_LL56
 LDA sh_XX12+4
 CLC
 ADC sh_XX1+6
 STA sh_T
 LDA sh_XX1+7
 ADC #0
 STA sh_U
 JMP sh_LL57
.sh_LL61
 LDX sh_Q
 BEQ sh_LL84
 LDX #0
.sh_LL63
 LSR A
 INX
 CMP sh_Q
 BCS sh_LL63
 STX sh_S
 JSR sh_LL28
 LDX sh_S
 LDA sh_R
.sh_LL64
 ASL A
 ROL sh_U
 BMI sh_LL84
 DEX
 BNE sh_LL64
 STA sh_R
 RTS
.sh_LL84
 LDA #50
 STA sh_R
 STA sh_U
 RTS
.sh_LL62
 LDA #128
 SEC
 SBC sh_R
 STA SH_XX3,X
 INX
 LDA #0
 SBC sh_U
 STA SH_XX3,X
 JMP sh_LL66
.sh_LL56
 LDA sh_XX1+6
 SEC
 SBC sh_XX12+4
 STA sh_T
 LDA sh_XX1+7
 SBC #0
 STA sh_U
 BCC sh_LL140
 BNE sh_LL57
 LDA sh_T
 CMP #4
 BCS sh_LL57
.sh_LL140
 LDA #0
 STA sh_U
 LDA #4
 STA sh_T
.sh_LL57
 LDA sh_U
 ORA sh_XX15+1
 ORA sh_XX15+4
 BEQ sh_LL60
 LSR sh_XX15+1
 ROR sh_XX15
 LSR sh_XX15+4
 ROR sh_XX15+3
 LSR sh_U
 ROR sh_T
 JMP sh_LL57
.sh_LL60
 LDA sh_T
 STA sh_Q
 LDA sh_XX15
 CMP sh_Q
 BCC sh_LL69
 JSR sh_LL61
 JMP sh_LL69b
.sh_LL69
 JSR sh_LL28
.sh_LL69b
 LDX sh_CNT
 LDA sh_XX15+2
 BMI sh_LL62
 LDA sh_R
 CLC
 ADC #128
 STA SH_XX3,X
 INX
 LDA sh_U
 ADC #0
 STA SH_XX3,X
.sh_LL66
 TXA
 PHA
 LDA #0
 STA sh_U
 LDA sh_T
 STA sh_Q
 LDA sh_XX15+3
 CMP sh_Q
 BCC sh_LL67
 JSR sh_LL61
 JMP sh_LL68
.sh_LL70
 LDA #SH_Y
 CLC
 ADC sh_R
 STA SH_XX3,X
 INX
 LDA #0
 ADC sh_U
 STA SH_XX3,X
 JMP sh_LL50
.sh_LL67
 JSR sh_LL28
.sh_LL68
 PLA
 TAX
 INX
 LDA sh_XX15+5
 BMI sh_LL70
 LDA #SH_Y
 SEC
 SBC sh_R
 STA SH_XX3,X
 INX
 LDA #0
 SBC sh_U
 STA SH_XX3,X
.sh_LL50
 CLC
 LDA sh_CNT
 ADC #4
 STA sh_CNT
 LDA sh_XX17
 ADC #6
 TAY
 BCS sh_LL72
 CMP sh_XX20
 BCS sh_LL72
 JMP sh_LL48

; LL72/EE31/LL74: the host sets bit 3 and clears bit 6 of byte #31 itself.
; An exploding ship draws its particle cloud instead (DOEXP).
.sh_LL72
 LDA sh_XX1+31
 AND #%00100000
 BEQ sh_LL72_lines
 JMP ex_draw
.sh_LL72_lines
 LDY #9
 LDA (sh_XX0),Y
 STA sh_XX20
 LDY #0
 STY sh_XX17
 LDA sh_XX1+31          ; replaces BIT XX1+31 / BVC
 AND #%01000000
 BEQ sh_LL170
 LDY #6
 LDA (sh_XX0),Y
 TAY
 LDX SH_XX3,Y
 STX sh_XX15
 INX
 BEQ sh_LL170
 LDX SH_XX3+1,Y
 STX sh_XX15+1
 INX
 BEQ sh_LL170
 LDX SH_XX3+2,Y
 STX sh_XX15+2
 LDX SH_XX3+3,Y
 STX sh_XX15+3
 LDA #0
 STA sh_XX15+4
 STA sh_XX15+5
 STA sh_XX12+1
 LDA sh_XX1+6
 STA sh_XX12
 LDA sh_XX1+2
 BPL sh_LL74a
 DEC sh_XX15+4
.sh_LL74a
 JSR sh_LL145
 BCS sh_LL170
 JSR sh_LSPUT
.sh_LL170
 LDY #3
 CLC
 LDA (sh_XX0),Y
 ADC sh_XX0
 STA sh_V
 LDY #16
 LDA (sh_XX0),Y
 ADC sh_XX0+1
 STA sh_V+1
 LDY #5
 LDA (sh_XX0),Y
 STA sh_CNT
.sh_LL75
 LDY #0
 LDA (sh_V),Y
 CMP sh_XX4
 BCC sh_LL78
 INY
 LDA (sh_V),Y
 STA sh_P
 AND #%00001111
 TAX
 LDA sh_XX2,X
 BNE sh_LL79
 LDA sh_P
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA sh_XX2,X
 BEQ sh_LL78
.sh_LL79
 INY
 LDA (sh_V),Y
 TAX
 LDA SH_XX3+1,X
 STA sh_XX15+1
 LDA SH_XX3,X
 STA sh_XX15
 LDA SH_XX3+2,X
 STA sh_XX15+2
 LDA SH_XX3+3,X
 STA sh_XX15+3
 INY
 LDA (sh_V),Y
 TAX
 LDA SH_XX3,X
 STA sh_XX15+4
 LDA SH_XX3+3,X
 STA sh_XX12+1
 LDA SH_XX3+2,X
 STA sh_XX12
 LDA SH_XX3+1,X
 STA sh_XX15+5
 JSR sh_LL147
 BCS sh_LL78
 JSR sh_LSPUT
.sh_LL78
 LDA sh_LSNUM
 CMP sh_CNT
 BCS sh_LL155
 LDA sh_V
 CLC
 ADC #4
 STA sh_V
 BCC sh_ll81
 INC sh_V+1
.sh_ll81
 INC sh_XX17
 LDY sh_XX17
 CPY sh_XX20
 BCC sh_LL75
 ; fall through into LL155

; Erase the remaining old lines and store the new heap size.
.sh_LL155
 LDY sh_LSNUM
.sh_LL27
 CPY sh_LSNUM2
 BCS sh_LLEX
 LDA (sh_XX19),Y
 STA sh_XX15
 INY
 LDA (sh_XX19),Y
 STA sh_XX15+1
 INY
 LDA (sh_XX19),Y
 STA sh_XX15+2
 INY
 LDA (sh_XX19),Y
 STA sh_XX15+3
 JSR sh_LL30
 INY
 JMP sh_LL27
.sh_LLEX
 LDA sh_LSNUM
 LDY #0
 STA (sh_XX19),Y
 RTS

; Flicker-free line put. Draw the new line X1..Y2 and erase the old line in
; the same heap slot. An unchanged line is left on screen (two identical XOR
; draws cancel exactly), which is common for slowly moving objects.
.sh_LSPUT
 LDY sh_LSNUM
 CPY sh_LSNUM2
 BCS sh_LSPUT_new
 LDA (sh_XX19),Y
 CMP sh_X1
 BNE sh_LSPUT_swap
 INY
 LDA (sh_XX19),Y
 CMP sh_Y1
 BNE sh_LSPUT_swap1
 INY
 LDA (sh_XX19),Y
 CMP sh_X2
 BNE sh_LSPUT_swap2
 INY
 LDA (sh_XX19),Y
 CMP sh_Y2
 BNE sh_LSPUT_swap3
 INY
 STY sh_LSNUM
 RTS
.sh_LSPUT_swap3
 DEY
.sh_LSPUT_swap2
 DEY
.sh_LSPUT_swap1
 DEY
.sh_LSPUT_swap
 JSR sh_LL30            ; draw the new line (Y and X1..Y2 preserved)
 LDX #0
.sh_LSPUT_old
 LDA (sh_XX19),Y
 PHA
 LDA sh_XX15,X
 STA (sh_XX19),Y
 PLA
 STA sh_XX15,X
 INY
 INX
 CPX #4
 BNE sh_LSPUT_old
 STY sh_LSNUM
 JMP sh_LL30            ; erase the old line
.sh_LSPUT_new
 JSR sh_LL30
 LDX #0
.sh_LSPUT_store
 LDA sh_XX15,X
 STA (sh_XX19),Y
 INY
 INX
 CPX #4
 BNE sh_LSPUT_store
 STY sh_LSNUM
 RTS

; LL30 in the job's colour, preserving Y and X1..Y2.
.sh_LL30
 LDA MV_URGENT          ; and between lines
 BEQ sh_LL30_go
 JSR urgent_run
.sh_LL30_go
 STY sh_YSAV
 LDA sh_X1
 STA cx
 LDA sh_Y1
 STA cy
 LDA sh_X2
 STA ex
 LDA sh_Y2
 STA ey
 JSR line
 LDY sh_YSAV
 RTS

; LL51: XX12 = XX16 . XX15 (the shared vector routine writes XX12).
sh_LL51 = vector

.sh_LL28
 CMP sh_Q
 BCS sh_LL2
 STA sh_widget
 TAX
 BEQ sh_LLfix
 LDA loglo,X
 LDX sh_Q
 SEC
 SBC loglo,X
 BMI sh_noddlog
 LDX sh_widget
 LDA loghi,X
 LDX sh_Q
 SBC loghi,X
 BCS sh_LL2
 TAX
 LDA antilog,X
.sh_LLfix
 STA sh_R
 RTS
.sh_noddlog
 LDX sh_widget
 LDA loghi,X
 LDX sh_Q
 SBC loghi,X
 BCS sh_LL2
 TAX
 LDA antilog_odd,X
 STA sh_R
 RTS
.sh_LL2
 LDA #255
 STA sh_R
 RTS

.sh_LL38
 EOR sh_S
 BMI sh_LL39
 LDA sh_Q
 CLC
 ADC sh_R
 RTS
.sh_LL39
 LDA sh_R
 SEC
 SBC sh_Q
 BCC sh_LL40
 CLC
 RTS
.sh_LL40
 PHA
 LDA sh_S
 EOR #%10000000
 STA sh_S
 PLA
 EOR #%11111111
 ADC #1
 RTS

.sh_FMLTU
 STX sh_P
 STA sh_widget
 TAX
 BEQ sh_MU3
 LDA loglo,X
 LDX sh_Q
 BEQ sh_MU3again
 CLC
 ADC loglo,X
 BMI sh_oddlog
 LDA loghi,X
 LDX sh_widget
 ADC loghi,X
 BCC sh_MU3again
 TAX
 LDA antilog,X
 LDX sh_P
 RTS
.sh_oddlog
 LDA loghi,X
 LDX sh_widget
 ADC loghi,X
 BCC sh_MU3again
 TAX
 LDA antilog_odd,X
.sh_MU3
 LDX sh_P
 RTS
.sh_MU3again
 LDA #0
 LDX sh_P
 RTS


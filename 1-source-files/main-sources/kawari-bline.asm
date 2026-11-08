; Planet job, part 3: BLINE and the ball line heap routines (see
; kawari-planet.asm).

; BLINE from just after its first addition, without its CNT update.
.pl_BLINE
 LDA pl_FLAG
 BEQ pl_BL1
 INC pl_FLAG
.pl_BL5
 JSR pl_DrawPlanetLine
 LDY pl_LSP
 LDA #$FF
 CMP pl_LSY2-1,Y
 BEQ pl_BL7
 STA pl_LSY2,Y
 INC pl_LSP
 BNE pl_BL7
.pl_BL1
 LDX #3
.pl_BL1_copy
 LDA pl_K5,X
 STA sh_XX15,X
 DEX
 BPL pl_BL1_copy
 LDA pl_K6
 STA sh_XX15+4
 LDA pl_K6+1
 STA sh_XX15+5
 LDA pl_K6+2
 STA sh_XX12
 LDA pl_K6+3
 STA sh_XX12+1
 JSR sh_LL145
 BCS pl_BL5
 LDA sh_SWAP
 BEQ pl_BL9
 LDA sh_X1
 LDY sh_X2
 STA sh_X2
 STY sh_X1
 LDA sh_Y1
 LDY sh_Y2
 STA sh_Y2
 STY sh_Y1
.pl_BL9
 LDY pl_LSP
 LDA pl_LSY2-1,Y
 CMP #$FF
 BNE pl_BL8
 JSR pl_DrawPlanetLine
 LDA sh_X1
 STA pl_LSX2,Y
 LDA sh_Y1
 STA pl_LSY2,Y
 INY
.pl_BL8
 LDA #$FF
 STA pl_K3+8
 JSR pl_DrawPlanetLine4
 LDA sh_X2
 STA pl_LSX2,Y
 LDA sh_Y2
 STA pl_LSY2,Y
 INY
 STY pl_LSP
 JSR pl_DrawNewPlanetLine
 LDA sh_XX13
 BNE pl_BL5
.pl_BL7
 LDX #3
.pl_BL7_copy
 LDA pl_K6,X
 STA pl_K5,X
 DEX
 BPL pl_BL7_copy
 RTS

.pl_DrawPlanetLine
 LDA #0
 STA pl_K3+8
.pl_DrawPlanetLine4
 LDA #0
 STA pl_K3+9
 LDA pl_LSNUM
 CMP #2
 BCC pl_plin3
 LDA sh_X1
 PHA
 LDA sh_Y1
 PHA
 LDA sh_X2
 PHA
 LDA sh_Y2
 PHA
 TYA
 PHA
 LDY pl_LSNUM
 CPY pl_LSNUM2
 BCS pl_plin1
 LDA pl_K3+2
 STA sh_X1
 LDA pl_K3+3
 STA sh_Y1
 LDA pl_LSX2,Y
 STA sh_X2
 STA pl_K3+2
 LDA pl_LSY2,Y
 STA sh_Y2
 STA pl_K3+3
 INC pl_LSNUM
 LDA sh_Y1
 CMP #$FF
 BEQ pl_plin1
 LDA sh_Y2
 CMP #$FF
 BEQ pl_plin1
 DEC pl_K3+9
 LDA pl_K3+8            ; replaces BIT K3+8 / BMI
 BMI pl_plin2
 JSR sh_LL30
.pl_plin1
 PLA
 TAY
 PLA
 STA sh_Y2
 PLA
 STA sh_X2
 PLA
 STA sh_Y1
 PLA
 STA sh_X1
 RTS
.pl_plin2
 LDX #3
.pl_plin2_copy
 LDA sh_XX15,X
 STA pl_K3+4,X
 DEX
 BPL pl_plin2_copy
 JMP pl_plin1
.pl_plin3
 LDA pl_LSX2+1
 STA pl_K3+2
 LDA pl_LSY2+1
 STA pl_K3+3
 INC pl_LSNUM
 RTS

.pl_DrawNewPlanetLine
 LDA pl_K3+9            ; replaces BIT K3+9 / BPL
 BPL pl_nlin2
 LDX #3
.pl_nlin_compare
 LDA pl_K3+4,X
 CMP sh_XX15,X
 BNE pl_nlin1
 DEX
 BPL pl_nlin_compare
 RTS                    ; nlin3: the new line is the old one, so skip both
.pl_nlin1
 JSR sh_LL30
 LDX #3
.pl_nlin1_copy
 LDA pl_K3+4,X
 STA sh_XX15,X
 DEX
 BPL pl_nlin1_copy
.pl_nlin2
 JMP sh_LL30


.planet_colour
 LDA (cmd),Y
 STA colour
 LDA #0
 STA sh_dontclip        ; planets are only drawn in the space view
 RTS

.pl_EraseRest
 LDY pl_LSNUM
 CPY pl_LSNUM2
 BCS pl_EraseRest_done
 JSR pl_DrawPlanetLine
 JMP pl_EraseRest
.pl_EraseRest_done
 RTS

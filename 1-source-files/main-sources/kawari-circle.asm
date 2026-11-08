; Planet job, part 2: CIRCLE2 and its sine table (see kawari-planet.asm).

.pl_CIRCLE2
 LDX #0
 STX pl_LSNUM
 LDX pl_LSP
 STX pl_LSNUM2
 LDX #1
 STX pl_LSP
 LDX #$FF
 STX pl_FLAG
 INX
 STX pl_CNT
.pl_PLL3
 LDA pl_CNT
 JSR pl_FMLTU2
 LDX #0
 STX pl_T
 LDX pl_CNT
 CPX #33
 BCC pl_PL37
 EOR #%11111111
 ADC #0
 TAX
 LDA #$FF
 ADC #0
 STA pl_T
 TXA
 CLC
.pl_PL37
 ADC pl_K3
 STA pl_K6
 LDA pl_K3+1
 ADC pl_T
 STA pl_K6+1
 LDA pl_CNT
 CLC
 ADC #16
 JSR pl_FMLTU2
 TAX
 LDA #0
 STA pl_T
 LDA pl_CNT
 ADC #15
 AND #63
 CMP #33
 BCC pl_PL38
 TXA
 EOR #%11111111
 ADC #0
 TAX
 LDA #$FF
 ADC #0
 STA pl_T
 CLC
.pl_PL38
 TXA                    ; BLINE's first addition: K6(3 2) = (T X) + K4(1 0)
 ADC pl_K4
 STA pl_K6+2
 LDA pl_K4+1
 ADC pl_T
 STA pl_K6+3
 JSR pl_BLINE
 LDA pl_CNT             ; BLINE's last addition
 CLC
 ADC pl_STP
 STA pl_CNT
 CMP #65
 BCC pl_PLL3
 RTS

.pl_FMLTU2
 AND #%00011111
 TAX
 LDA pl_SNE,X
 STA sh_Q
 LDA pl_K
 JMP sh_FMLTU

; The sine table pl_SNE is in the high code block (kawari-sine.asm).

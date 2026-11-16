; Arithmetic helpers for the co-processor movement job (kawari-move.asm),
; relocated from elite-source.asm (MLTU2, MULT1/MAD and ADD), and the
; movement job's zero-page variables.

MV_ARGS = $7FC0                 ; urgent movement arguments (44 bytes)
MV_URGENT = $7FF2               ; urgent movement request flag
mv_INWK = $50                   ; $50-$6E, the same layout as the host
mv_P = $E0                      ; three bytes
mv_Q = $E3
mv_R = $E4
mv_S = $E5
mv_T = $E6
mv_T1 = $E7
mv_U = $E8
mv_K = $E9                      ; four bytes
mv_K2 = $ED                     ; four bytes
mv_RAT2 = $F1
mv_ALPHA = $F2
mv_ALP1 = $F3
mv_ALP2 = $F4                   ; two bytes
mv_BETA = $F6
mv_BET1 = $F7
mv_BET2 = $F8                   ; two bytes
mv_DELTA = $FA
mv_MAXSPD = $FB                 ; follows DELTA, as in MV_ARGS
mv_SPEEDQ = $FC                 ; this frame's speed * 4, scaled for real time
mv_ROTQ = $FD                   ; own-rotation step: $FF a whole tick, else /256 rad
mv_DECCMP = $FE                 ; $7F on a game tick, 0 between ticks

.mv_MLTU2m2
 STX mv_Q
.mv_MLTU2
 EOR #%11111111
 LSR A
 STA mv_P+1
 LDA #0
 LDX #16
 ROR mv_P
.mv_MUL7
 BCS mv_MU21
 ADC mv_Q
 ROR A
 ROR mv_P+1
 ROR mv_P
 DEX
 BNE mv_MUL7
 RTS
.mv_MU21
 LSR A
 ROR mv_P+1
 ROR mv_P
 DEX
 BNE mv_MUL7
 RTS

; MAD: (A X) = Q * A + (S R), via MULT1 and ADD, as in the original.
.mv_MAD
 TAX                    ; MULT1
 AND #%01111111
 LSR A
 STA mv_P
 TXA
 EOR mv_Q
 AND #%10000000
 STA mv_T
 LDA mv_Q
 AND #%01111111
 BEQ mv_mu10
 TAX
 DEX
 STX mv_T1
 LDA #0
 TAX
 LDX #7                 ; seven unrolled steps of the original, as a loop
.mv_MULT1_step
 BCC mv_MULT1_skip
 ADC mv_T1
.mv_MULT1_skip
 ROR A
 ROR mv_P
 DEX
 BNE mv_MULT1_step
 LSR A
 ROR mv_P
 ORA mv_T
 JMP mv_ADD
.mv_mu10
 STA mv_P
.mv_ADD
 STA mv_T1
 AND #%10000000
 STA mv_T
 EOR mv_S
 BMI mv_MU8
 LDA mv_R
 CLC
 ADC mv_P
 TAX
 LDA mv_S
 ADC mv_T1
 ORA mv_T
 RTS
.mv_MU8
 LDA mv_S
 AND #%01111111
 STA mv_U
 LDA mv_P
 SEC
 SBC mv_R
 TAX
 LDA mv_T1
 AND #%01111111
 SBC mv_U
 BCS mv_MU9
 STA mv_U
 TXA
 EOR #$FF
 ADC #1
 TAX
 LDA #0
 SBC mv_U
 ORA #%10000000
.mv_MU9
 EOR mv_T
 RTS

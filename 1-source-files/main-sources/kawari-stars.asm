; Stardust motion for all four views, with the original sign-magnitude
; arithmetic relocated from elite-source.asm. No host RAM or I/O accesses.
; Input controls: $50-$60. Particle arrays: $7c21-$7c6e.
st_VIEW = $0050
st_NOSTM = $0051
st_DELTA = $0052
st_DELT4 = $0053
st_ALPHA = $0055
st_ALP1 = $0056
st_ALP2 = $0057
st_BETA = $0059
st_BET1 = $005A
st_BET2 = $005B
st_RAND = $005D
st_XX = $0061
st_YY = $0063
st_T1 = $0065
st_P = $0066
st_Q = $0068
st_R = $0069
st_S = $006A
st_T = $006B
st_U = $006C
st_X1 = $006D
st_Y1 = $006E
st_ZZ = $006F
st_RAT = $0070
st_RAT2 = $0071
st_newzp = $0072
st_widget = $0073
st_SX = $7C21
st_SXL = $7C2E
st_SY = $7C3B
st_SYL = $7C48
st_SZ = $7C55
st_SZL = $7C62

.st_STARS
 LDX st_VIEW
 BEQ st_STARS1
 DEX
 BNE st_ST11
 JMP st_STARS6
.st_ST11
 JMP st_STARS2
.st_STARS1
 LDY st_NOSTM
.st_STL1
 JSR st_DV42
 LDA st_R
 LSR st_P
 ROR A
 LSR st_P
 ROR A
 ORA #1
 STA st_Q
 LDA st_SZL,Y
 SBC st_DELT4
 STA st_SZL,Y
 LDA st_SZ,Y
 STA st_ZZ
 SBC st_DELT4+1
 STA st_SZ,Y
 JSR st_MLU1
 STA st_YY+1
 LDA st_P
 ADC st_SYL,Y
 STA st_YY
 STA st_R
 LDA st_Y1
 ADC st_YY+1
 STA st_YY+1
 STA st_S
 LDA st_SX,Y
 STA st_X1
 JSR st_MLU2
 STA st_XX+1
 LDA st_P
 ADC st_SXL,Y
 STA st_XX
 LDA st_X1
 ADC st_XX+1
 STA st_XX+1
 EOR st_ALP2+1
 JSR st_MLS1
 JSR st_ADD
 STA st_YY+1
 STX st_YY
 EOR st_ALP2
 JSR st_MLS2
 JSR st_ADD
 STA st_XX+1
 STX st_XX
 LDX st_BET1
 LDA st_YY+1
 EOR st_BET2+1
 JSR st_MULTS-2
 STA st_Q
 JSR st_MUT2
 ASL st_P
 ROL A
 STA st_T
 LDA #0
 ROR A
 ORA st_T
 JSR st_ADD
 STA st_XX+1
 TXA
 STA st_SXL,Y
 LDA st_YY
 STA st_R
 LDA st_YY+1
 STA st_S
 LDA #0
 STA st_P
 LDA st_BETA
 EOR #%10000000
 JSR st_PIX1
 LDA st_XX+1
 STA st_X1
 STA st_SX,Y
 AND #%01111111
 CMP #120
 BCS st_KILL1
 LDA st_YY+1
 STA st_SY,Y
 STA st_Y1
 AND #%01111111
 CMP #120
 BCS st_KILL1
 LDA st_SZ,Y
 CMP #16
 BCC st_KILL1
 STA st_ZZ
.st_STC1
 JSR st_PIXEL2
 DEY
 BEQ P%+5
 JMP st_STL1
 RTS
.st_KILL1
 JSR st_DORND
 ORA #4
 STA st_Y1
 STA st_SY,Y
 JSR st_DORND
 ORA #8
 STA st_X1
 STA st_SX,Y
 JSR st_DORND
 ORA #144
 STA st_SZ,Y
 STA st_ZZ
 LDA st_Y1
 JMP st_STC1
.st_STARS6
 LDY st_NOSTM
.st_STL6
 JSR st_DV42
 LDA st_R
 LSR st_P
 ROR A
 LSR st_P
 ROR A
 ORA #1
 STA st_Q
 LDA st_SX,Y
 STA st_X1
 JSR st_MLU2
 STA st_XX+1
 LDA st_SXL,Y
 SBC st_P
 STA st_XX
 LDA st_X1
 SBC st_XX+1
 STA st_XX+1
 JSR st_MLU1
 STA st_YY+1
 LDA st_SYL,Y
 SBC st_P
 STA st_YY
 STA st_R
 LDA st_Y1
 SBC st_YY+1
 STA st_YY+1
 STA st_S
 LDA st_SZL,Y
 ADC st_DELT4
 STA st_SZL,Y
 LDA st_SZ,Y
 STA st_ZZ
 ADC st_DELT4+1
 STA st_SZ,Y
 LDA st_XX+1
 EOR st_ALP2
 JSR st_MLS1
 JSR st_ADD
 STA st_YY+1
 STX st_YY
 EOR st_ALP2+1
 JSR st_MLS2
 JSR st_ADD
 STA st_XX+1
 STX st_XX
 LDA st_YY+1
 EOR st_BET2+1
 LDX st_BET1
 JSR st_MULTS-2
 STA st_Q
 LDA st_XX+1
 STA st_S
 EOR #%10000000
 JSR st_MUT1
 ASL st_P
 ROL A
 STA st_T
 LDA #0
 ROR A
 ORA st_T
 JSR st_ADD
 STA st_XX+1
 TXA
 STA st_SXL,Y
 LDA st_YY
 STA st_R
 LDA st_YY+1
 STA st_S
 LDA #0
 STA st_P
 LDA st_BETA
 JSR st_PIX1
 LDA st_XX+1
 STA st_X1
 STA st_SX,Y
 LDA st_YY+1
 STA st_SY,Y
 STA st_Y1
 AND #%01111111
 CMP #110
 BCS st_KILL6
 LDA st_SZ,Y
 CMP #160
 BCS st_KILL6
 STA st_ZZ
.st_STC6
 JSR st_PIXEL2
 DEY
 BEQ st_ST3
 JMP st_STL6
.st_ST3
 RTS
.st_KILL6
 JSR st_DORND
 AND #%01111111
 ADC #10
 STA st_SZ,Y
 STA st_ZZ
 LSR A
 BCS st_ST4
 LSR A
 LDA #252
 ROR A
 STA st_X1
 STA st_SX,Y
 JSR st_DORND
 STA st_Y1
 STA st_SY,Y
 JMP st_STC6
.st_ST4
 JSR st_DORND
 STA st_X1
 STA st_SX,Y
 LSR A
 LDA #230
 ROR A
 STA st_Y1
 STA st_SY,Y
 BNE st_STC6
.st_STARS2
 LDA #0
 CPX #2
 ROR A
 STA st_RAT
 EOR #%10000000
 STA st_RAT2
 JSR st_ST2
 LDY st_NOSTM
.st_STL2
 LDA st_SZ,Y
 STA st_ZZ
 LSR A
 LSR A
 LSR A
 JSR st_DV41
 LDA st_P
 STA st_newzp
 EOR st_RAT2
 STA st_S
 LDA st_SXL,Y
 STA st_P
 LDA st_SX,Y
 STA st_X1
 JSR st_ADD
 STA st_S
 STX st_R
 LDA st_SY,Y
 STA st_Y1
 EOR st_BET2
 LDX st_BET1
 JSR st_MULTS-2
 JSR st_ADD
 STX st_XX
 STA st_XX+1
 LDX st_SYL,Y
 STX st_R
 LDX st_Y1
 STX st_S
 LDX st_BET1
 EOR st_BET2+1
 JSR st_MULTS-2
 JSR st_ADD
 STX st_YY
 STA st_YY+1
 LDX st_ALP1
 EOR st_ALP2
 JSR st_MULTS-2
 STA st_Q
 LDA st_XX
 STA st_R
 LDA st_XX+1
 STA st_S
 EOR #%10000000
 JSR st_MAD
 STA st_XX+1
 TXA
 STA st_SXL,Y
 LDA st_YY
 STA st_R
 LDA st_YY+1
 STA st_S
 JSR st_MAD
 STA st_S
 STX st_R
 LDA #0
 STA st_P
 LDA st_ALPHA
 JSR st_PIX1
 LDA st_XX+1
 STA st_SX,Y
 STA st_X1
 AND #%01111111
 EOR #%01111111
 CMP st_newzp
 BCC st_KILL2
 BEQ st_KILL2
 LDA st_YY+1
 STA st_SY,Y
 STA st_Y1
 AND #%01111111
 CMP #116
 BCS st_ST5
.st_STC2
 JSR st_PIXEL2
 DEY
 BEQ st_ST2
 JMP st_STL2
.st_ST2
 LDA st_ALPHA
 EOR st_RAT
 STA st_ALPHA
 LDA st_ALP2
 EOR st_RAT
 STA st_ALP2
 EOR #%10000000
 STA st_ALP2+1
 LDA st_BET2
 EOR st_RAT
 STA st_BET2
 EOR #%10000000
 STA st_BET2+1
 RTS
.st_KILL2
 JSR st_DORND
 STA st_Y1
 STA st_SY,Y
 LDA #115
 ORA st_RAT
 STA st_X1
 STA st_SX,Y
 BNE st_STF1
.st_ST5
 JSR st_DORND
 STA st_X1
 STA st_SX,Y
 LDA #110
 ORA st_ALP2+1
 STA st_Y1
 STA st_SY,Y
.st_STF1
 JSR st_DORND
 ORA #8
 STA st_ZZ
 STA st_SZ,Y
 BNE st_STC2
.st_DV42
 LDA st_SZ,Y
.st_DV41
 STA st_Q
 LDA st_DELTA
.st_DVID4
 ASL A
 STA st_P
 LDA #0
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 ROL A
 CMP st_Q
 BCC P%+4
 SBC st_Q
 ROL st_P
 LDX #0
 STA st_widget
 TAX
 BEQ st_LLfix22
 LDA loglo,X
 LDX st_Q
 SEC
 SBC loglo,X
 BMI st_noddlog22
 LDX st_widget
 LDA loghi,X
 LDX st_Q
 SBC loghi,X
 BCS st_LL222
 TAX
 LDA antilog,X
.st_LLfix22
 STA st_R
 RTS
.st_LL222
 LDA #255
 STA st_R
 RTS
.st_noddlog22
 LDX st_widget
 LDA loghi,X
 LDX st_Q
 SBC loghi,X
 BCS st_LL222
 TAX
 LDA antilog_odd,X
 STA st_R
 RTS
.st_MLU1
 LDA st_SY,Y
 STA st_Y1
.st_MLU2
 AND #%01111111
 STA st_P
.st_MULTU
 LDX st_Q
 BEQ st_MU1
.st_MU11
 DEX
 STX st_T
 LDA #0
 TAX
 LSR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T
 ROR A
 ROR st_P
 RTS
.st_MU1
 CLC
 STX st_P
 TXA
 RTS
.st_MUT2
 LDX st_XX+1
 STX st_S
.st_MUT1
 LDX st_XX
 STX st_R
.st_MULT1
 TAX
 AND #%01111111
 LSR A
 STA st_P
 TXA
 EOR st_Q
 AND #%10000000
 STA st_T
 LDA st_Q
 AND #%01111111
 BEQ st_mu10
 TAX
 DEX
 STX st_T1
 LDA #0
 TAX
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 LSR A
 ROR st_P
 ORA st_T
 RTS
.st_mu10
 STA st_P
 RTS
.st_MLS2
 LDX st_XX
 STX st_R
 LDX st_XX+1
 STX st_S
.st_MLS1
 LDX st_ALP1
 STX st_P
.st_MULTS
 TAX
 AND #%10000000
 STA st_T
 TXA
 AND #%01111111
 BEQ st_MU6
 TAX
 DEX
 STX st_T1
 LDA #0
 LSR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 BCC P%+4
 ADC st_T1
 ROR A
 ROR st_P
 LSR A
 ROR st_P
 LSR A
 ROR st_P
 LSR A
 ROR st_P
 ORA st_T
 RTS
.st_MU6
 STA st_P+1
 STA st_P
 RTS
.st_MAD
 JSR st_MULT1
.st_ADD
 STA st_T1
 AND #%10000000
 STA st_T
 EOR st_S
 BMI st_MU8
 LDA st_R
 CLC
 ADC st_P
 TAX
 LDA st_S
 ADC st_T1
 ORA st_T
 RTS
.st_MU8
 LDA st_S
 AND #%01111111
 STA st_U
 LDA st_P
 SEC
 SBC st_R
 TAX
 LDA st_T1
 AND #%01111111
 SBC st_U
 BCS st_MU9
 STA st_U
 TXA
 EOR #$FF
 ADC #1
 TAX
 LDA #0
 SBC st_U
 ORA #%10000000
.st_MU9
 EOR st_T
 RTS
.st_DORND
 LDA st_RAND
 ROL A
 TAX
 ADC st_RAND+2
 STA st_RAND
 STX st_RAND+2
 LDA st_RAND+1
 TAX
 ADC st_RAND+3
 STA st_RAND+1
 STX st_RAND+3
 RTS
.st_PIX1
 JSR st_ADD
 STA st_YY+1
 TXA
 STA st_SYL,Y
.st_PIXEL2
 LDA st_X1
 BPL st_PX1
 EOR #%01111111
 CLC
 ADC #1
.st_PX1
 EOR #%10000000
 TAX
 LDA st_Y1
 AND #%01111111
 CMP #72
 BCS st_PX4
 LDA st_Y1
 BPL st_PX2
 EOR #%01111111
 ADC #1
.st_PX2
 STA st_T
 LDA #72+1
 SBC st_T
; PIXEL2 falls through here. Keep the particle index in Y intact.
.st_pixel
 STA cy
 STX cx
 TXA
 AND #7
 BEQ st_pixel_x_ready
 DEC cx
.st_pixel_x_ready
 TYA
 PHA
 LDA st_ZZ
 STA temp
 LDA #1
 STA colour
 JSR point_render
 PLA
 TAY
.st_PX4
 RTS

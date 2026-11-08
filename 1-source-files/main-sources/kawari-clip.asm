; Ship-job line clipping (LL145/LL147, LL118-LL129), relocated from
; elite-source.asm for the co-processor, plus the ship job's constants and
; zero-page variables (this file is assembled before kawari-ship.asm).

SH_BLUEPRINT_OFFSET = $0A00     ; host $D000 -> VRAM $DA00
SH_XX3 = $0100                  ; projected vertex coordinates (148 bytes max),
                                ; below the stack, as on the host

; X1/Y1/X2/Y2 alias XX15 exactly as on the host. XX15 and XX16 coincide with
; the vector routine's input and matrix, so LL51 is a direct call.
sh_XX15 = v_input               ; $20-$25
sh_X1 = sh_XX15
sh_Y1 = sh_XX15+1
sh_X2 = sh_XX15+2
sh_Y2 = sh_XX15+3
sh_XX16 = v_matrix              ; $26-$37
sh_XX1 = $80                    ; 32 bytes, $80-$9F
sh_XX12 = $A0                   ; 6 bytes
sh_XX18 = $A6                   ; 9 bytes, $A6-$AE
sh_XX2 = $B0                    ; 16 bytes, $B0-$BF
sh_XX0 = $C0
sh_XX19 = $C2
sh_V = $C4
sh_XX4 = $C6
sh_XX17 = $C7
sh_XX20 = $C8
sh_CNT = $C9
sh_P = $CA
sh_Q = $CB
sh_R = $CC
sh_S = $CD
sh_T = $CE
sh_U = $CF
sh_widget = $D0
sh_LSNUM = $D1
sh_LSNUM2 = $D2
sh_XX13 = $D3
sh_SWAP = $D4
sh_dontclip = $D5
sh_YSAV = $D6
sh_CNT2 = $D7
SH_Y = 72                       ; centre y-coordinate of the 256x144 view

; ------------------------------------------------------------------------------
; LL145/LL147 line clipping and LL118-LL129, as in the original.
; ------------------------------------------------------------------------------
.sh_LL145
 LDA #0
 STA sh_SWAP
 LDA sh_XX15+5
.sh_LL147
 LDX sh_dontclip        ; replaces BIT dontclip / BMI (A is preserved)
 BMI sh_LL146
 LDX #SH_Y*2-1
 ORA sh_XX12+1
 BNE sh_LL107
 CPX sh_XX12
 BCC sh_LL107
 LDX #0
.sh_LL107
 STX sh_XX13
 LDA sh_XX15+1
 ORA sh_XX15+3
 BNE sh_LL83
 LDA #SH_Y*2-1
 CMP sh_XX15+2
 BCC sh_LL83
 LDA sh_XX13
 BNE sh_LL108
.sh_LL146
 LDA sh_XX15+2
 STA sh_XX15+1
 LDA sh_XX15+4
 STA sh_XX15+2
 LDA sh_XX12
 STA sh_XX15+3
 CLC
 RTS
.sh_LL109
 SEC
 RTS
.sh_LL108
 LSR sh_XX13
.sh_LL83
 LDA sh_XX13
 BPL sh_LL115
 LDA sh_XX15+1
 AND sh_XX15+5
 BMI sh_LL109
 LDA sh_XX15+3
 AND sh_XX12+1
 BMI sh_LL109
 LDX sh_XX15+1
 DEX
 TXA
 LDX sh_XX15+5
 DEX
 STX sh_XX12+2
 ORA sh_XX12+2
 BPL sh_LL109
 LDA sh_XX15+2
 CMP #SH_Y*2
 LDA sh_XX15+3
 SBC #0
 STA sh_XX12+2
 LDA sh_XX12
 CMP #SH_Y*2
 LDA sh_XX12+1
 SBC #0
 ORA sh_XX12+2
 BPL sh_LL109
.sh_LL115
 TYA
 PHA
 LDA sh_XX15+4
 SEC
 SBC sh_XX15
 STA sh_XX12+2
 LDA sh_XX15+5
 SBC sh_XX15+1
 STA sh_XX12+3
 LDA sh_XX12
 SEC
 SBC sh_XX15+2
 STA sh_XX12+4
 LDA sh_XX12+1
 SBC sh_XX15+3
 STA sh_XX12+5
 EOR sh_XX12+3
 STA sh_S
 LDA sh_XX12+5
 BPL sh_LL110
 LDA #0
 SEC
 SBC sh_XX12+4
 STA sh_XX12+4
 LDA #0
 SBC sh_XX12+5
 STA sh_XX12+5
.sh_LL110
 LDA sh_XX12+3
 BPL sh_LL111
 SEC
 LDA #0
 SBC sh_XX12+2
 STA sh_XX12+2
 LDA #0
 SBC sh_XX12+3
.sh_LL111
 TAX
 BNE sh_LL112
 LDX sh_XX12+5
 BEQ sh_LL113
.sh_LL112
 LSR A
 ROR sh_XX12+2
 LSR sh_XX12+5
 ROR sh_XX12+4
 JMP sh_LL111
.sh_LL113
 STX sh_T
 LDA sh_XX12+2
 CMP sh_XX12+4
 BCC sh_LL114
 STA sh_Q
 LDA sh_XX12+4
 JSR sh_LL28
 JMP sh_LL116
.sh_LL114
 LDA sh_XX12+4
 STA sh_Q
 LDA sh_XX12+2
 JSR sh_LL28
 DEC sh_T
.sh_LL116
 LDA sh_R
 STA sh_XX12+2
 LDA sh_S
 STA sh_XX12+3
 LDA sh_XX13
 BEQ sh_LL138
 BPL sh_LLX117
.sh_LL138
 JSR sh_LL118
 LDA sh_XX13
 BPL sh_LL124
 LDA sh_XX15+1
 ORA sh_XX15+3
 BNE sh_LL137
 LDA sh_XX15+2
 CMP #SH_Y*2
 BCS sh_LL137
.sh_LLX117
 LDX sh_XX15
 LDA sh_XX15+4
 STA sh_XX15
 STX sh_XX15+4
 LDA sh_XX15+5
 LDX sh_XX15+1
 STX sh_XX15+5
 STA sh_XX15+1
 LDX sh_XX15+2
 LDA sh_XX12
 STA sh_XX15+2
 STX sh_XX12
 LDA sh_XX12+1
 LDX sh_XX15+3
 STX sh_XX12+1
 STA sh_XX15+3
 JSR sh_LL118
 DEC sh_SWAP
.sh_LL124
 PLA
 TAY
 JMP sh_LL146
.sh_LL137
 PLA
 TAY
 SEC
 RTS

.sh_LL118
 LDA sh_XX15+1
 BPL sh_LL119
 STA sh_S
 JSR sh_LL120
 TXA
 CLC
 ADC sh_XX15+2
 STA sh_XX15+2
 TYA
 ADC sh_XX15+3
 STA sh_XX15+3
 LDA #0
 STA sh_XX15
 STA sh_XX15+1
 TAX
.sh_LL119
 BEQ sh_LL134
 STA sh_S
 DEC sh_S
 JSR sh_LL120
 TXA
 CLC
 ADC sh_XX15+2
 STA sh_XX15+2
 TYA
 ADC sh_XX15+3
 STA sh_XX15+3
 LDX #255
 STX sh_XX15
 INX
 STX sh_XX15+1
.sh_LL134
 LDA sh_XX15+3
 BPL sh_LL135
 STA sh_S
 LDA sh_XX15+2
 STA sh_R
 JSR sh_LL123
 TXA
 CLC
 ADC sh_XX15
 STA sh_XX15
 TYA
 ADC sh_XX15+1
 STA sh_XX15+1
 LDA #0
 STA sh_XX15+2
 STA sh_XX15+3
.sh_LL135
 LDA sh_XX15+2
 SEC
 SBC #SH_Y*2
 STA sh_R
 LDA sh_XX15+3
 SBC #0
 STA sh_S
 BCC sh_LL136
 JSR sh_LL123
 TXA
 CLC
 ADC sh_XX15
 STA sh_XX15
 TYA
 ADC sh_XX15+1
 STA sh_XX15+1
 LDA #SH_Y*2-1
 STA sh_XX15+2
 LDA #0
 STA sh_XX15+3
.sh_LL136
 RTS

.sh_LL120
 LDA sh_XX15
 STA sh_R
 JSR sh_LL129
 PHA
 LDX sh_T
 BNE sh_LL121
.sh_LL122
 LDA #0
 TAX
 TAY
 LSR sh_S
 ROR sh_R
 ASL sh_Q
 BCC sh_LL126
.sh_LL125
 TXA
 CLC
 ADC sh_R
 TAX
 TYA
 ADC sh_S
 TAY
.sh_LL126
 LSR sh_S
 ROR sh_R
 ASL sh_Q
 BCS sh_LL125
 BNE sh_LL126
 PLA
 BPL sh_LL133
 RTS
.sh_LL123
 JSR sh_LL129
 PHA
 LDX sh_T
 BNE sh_LL122
.sh_LL121
 LDA #%11111111
 TAY
 ASL A
 TAX
.sh_LL130
 ASL sh_R
 ROL sh_S
 LDA sh_S
 BCS sh_LL131
 CMP sh_Q
 BCC sh_LL132
.sh_LL131
 SBC sh_Q
 STA sh_S
 LDA sh_R
 SBC #0
 STA sh_R
 SEC
.sh_LL132
 TXA
 ROL A
 TAX
 TYA
 ROL A
 TAY
 BCS sh_LL130
 PLA
 BMI sh_LL128
.sh_LL133
 TXA
 EOR #%11111111
 ADC #1
 TAX
 TYA
 EOR #%11111111
 ADC #0
 TAY
.sh_LL128
 RTS
.sh_LL129
 LDX sh_XX12+2
 STX sh_Q
 LDA sh_S
 BPL sh_LL127
 LDA #0
 SEC
 SBC sh_R
 STA sh_R
 LDA sh_S
 PHA
 EOR #%11111111
 ADC #0
 STA sh_S
 PLA
.sh_LL127
 EOR sh_XX12+3
 RTS

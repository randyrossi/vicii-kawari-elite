; Ship movement for the co-processor: MVEIT parts 2-7 (move along the nose
; vector by speed, acceleration, rotation by our pitch and roll, our speed,
; orientation rotation, and the ship's own roll and pitch counters), relocated
; from elite-source.asm. The host keeps TIDY, TACTICS and SCAN (parts 1, 8).
;
; Urgent lane (not a command): the host writes the arguments to MV_ARGS and
; sets MV_URGENT. The co-processor checks the flag in its idle loop, between
; commands, and at each vertex and line inside a ship job, so movement does
; not wait for drawing that has already been queued. It then clears the flag.
;   MV_ARGS+0..30   ship data block bytes #0-#30 (INWK)
;   MV_ARGS+31..39  ALPHA, ALP1, ALP2, ALP2+1, BETA, BET1, BET2, BET2+1, DELTA
;   MV_ARGS+40      maximum speed (blueprint byte #15)
; Result: bytes #0-#30 in co-processor zero page at mv_INWK ($0050), which
; the host reads directly (with the register overlay disabled). mv_INWK
; shares zero page with the stardust job, which is never interrupted.

; Variables are defined in kawari-movemath.asm, assembled first.

.urgent_run
 PHA
 TXA
 PHA
 TYA
 PHA
 LDA sh_P               ; FMLTU's workspace, shared with an interrupted ship
 PHA
 LDA sh_Q
 PHA
 LDA sh_widget
 PHA
 LDX #30
.urgent_inwk
 LDA MV_ARGS,X
 STA mv_INWK,X
 DEX
 BPL urgent_inwk
 LDX #9
.urgent_globals
 LDA MV_ARGS+31,X
 STA mv_ALPHA,X
 DEX
 BPL urgent_globals
 JSR mv_MV30
 LDA #0
 STA MV_URGENT          ; the result is complete
 PLA
 STA sh_widget
 PLA
 STA sh_Q
 PLA
 STA sh_P
 PLA
 TAY
 PLA
 TAX
 PLA
 RTS

; MVEIT part 2 onwards, from just after MV30's JSR SCAN, for a ship (type
; >= 0, so the planet MV40 path and part 4's early return never apply).
.mv_MV30
 LDA mv_INWK+27
 ASL A
 ASL A
 STA sh_Q               ; FMLTU's Q
 LDA mv_INWK+10
 AND #%01111111
 JSR sh_FMLTU
 STA mv_R
 LDA mv_INWK+10
 LDX #0
 JSR mv_MVT1m2
 LDA mv_INWK+12
 AND #%01111111
 JSR sh_FMLTU
 STA mv_R
 LDA mv_INWK+12
 LDX #3
 JSR mv_MVT1m2
 LDA mv_INWK+14
 AND #%01111111
 JSR sh_FMLTU
 STA mv_R
 LDA mv_INWK+14
 LDX #6
 JSR mv_MVT1m2
 LDA mv_INWK+27
 CLC
 ADC mv_INWK+28
 BPL mv_speed_positive
 LDA #0
.mv_speed_positive
 CMP mv_MAXSPD
 BCC mv_speed_ok
 LDA mv_MAXSPD
.mv_speed_ok
 STA mv_INWK+27
 LDA #0
 STA mv_INWK+28
 LDX mv_ALP1
 LDA mv_INWK
 EOR #%11111111
 STA mv_P
 LDA mv_INWK+1
 JSR mv_MLTU2m2
 STA mv_P+2
 LDA mv_ALP2+1
 EOR mv_INWK+2
 LDX #3
 JSR mv_MVT6
 STA mv_K2+3
 LDA mv_P+1
 STA mv_K2+1
 EOR #%11111111
 STA mv_P
 LDA mv_P+2
 STA mv_K2+2
 LDX mv_BET1
 JSR mv_MLTU2m2
 STA mv_P+2
 LDA mv_K2+3
 EOR mv_BET2
 LDX #6
 JSR mv_MVT6
 STA mv_INWK+8
 LDA mv_P+1
 STA mv_INWK+6
 EOR #%11111111
 STA mv_P
 LDA mv_P+2
 STA mv_INWK+7
 JSR mv_MLTU2
 STA mv_P+2
 LDA mv_K2+3
 STA mv_INWK+5
 EOR mv_BET2
 EOR mv_INWK+8
 BPL mv_MV43
 LDA mv_P+1
 ADC mv_K2+1
 STA mv_INWK+3
 LDA mv_P+2
 ADC mv_K2+2
 STA mv_INWK+4
 JMP mv_MV44
.mv_MV43
 LDA mv_K2+1
 SBC mv_P+1
 STA mv_INWK+3
 LDA mv_K2+2
 SBC mv_P+2
 STA mv_INWK+4
 BCS mv_MV44
 LDA #1
 SBC mv_INWK+3
 STA mv_INWK+3
 LDA #0
 SBC mv_INWK+4
 STA mv_INWK+4
 LDA mv_INWK+5
 EOR #%10000000
 STA mv_INWK+5
.mv_MV44
 LDX mv_ALP1
 LDA mv_INWK+3
 EOR #$FF
 STA mv_P
 LDA mv_INWK+4
 JSR mv_MLTU2m2
 STA mv_P+2
 LDA mv_ALP2
 EOR mv_INWK+5
 LDX #0
 JSR mv_MVT6
 STA mv_INWK+2
 LDA mv_P+2
 STA mv_INWK+1
 LDA mv_P+1
 STA mv_INWK
 LDA mv_DELTA           ; MV45
 STA mv_R
 LDA #%10000000
 LDX #6
 JSR mv_MVT1
 LDY #9
 JSR mv_MVS4
 LDY #15
 JSR mv_MVS4
 LDY #21
 JSR mv_MVS4
 LDA mv_INWK+30
 AND #%10000000
 STA mv_RAT2
 LDA mv_INWK+30
 AND #%01111111
 BEQ mv_MV8
 CMP #%01111111
 SBC #0
 ORA mv_RAT2
 STA mv_INWK+30
 LDX #15
 LDY #9
 JSR mv_MVS5
 LDX #17
 LDY #11
 JSR mv_MVS5
 LDX #19
 LDY #13
 JSR mv_MVS5
.mv_MV8
 LDA mv_INWK+29
 AND #%10000000
 STA mv_RAT2
 LDA mv_INWK+29
 AND #%01111111
 BEQ mv_MV5
 CMP #%01111111
 SBC #0
 ORA mv_RAT2
 STA mv_INWK+29
 LDX #15
 LDY #21
 JSR mv_MVS5
 LDX #17
 LDY #23
 JSR mv_MVS5
 LDX #19
 LDY #25
 JSR mv_MVS5
.mv_MV5
 RTS

.mv_MVT1m2
 AND #%10000000
.mv_MVT1
 ASL A
 STA mv_S
 LDA #0
 ROR A
 STA mv_T
 LSR mv_S
 EOR mv_INWK+2,X
 BMI mv_MV10
 LDA mv_R
 ADC mv_INWK,X
 STA mv_INWK,X
 LDA mv_S
 ADC mv_INWK+1,X
 STA mv_INWK+1,X
 LDA mv_INWK+2,X
 ADC #0
 ORA mv_T
 STA mv_INWK+2,X
 RTS
.mv_MV10
 LDA mv_INWK,X
 SEC
 SBC mv_R
 STA mv_INWK,X
 LDA mv_INWK+1,X
 SBC mv_S
 STA mv_INWK+1,X
 LDA mv_INWK+2,X
 AND #%01111111
 SBC #0
 ORA #%10000000
 EOR mv_T
 STA mv_INWK+2,X
 BCS mv_MV11
 LDA #1
 SBC mv_INWK,X
 STA mv_INWK,X
 LDA #0
 SBC mv_INWK+1,X
 STA mv_INWK+1,X
 LDA #0
 SBC mv_INWK+2,X
 AND #%01111111
 ORA mv_T
 STA mv_INWK+2,X
.mv_MV11
 RTS

.mv_MVS4
 LDA mv_ALPHA
 STA mv_Q
 LDX mv_INWK+2,Y
 STX mv_R
 LDX mv_INWK+3,Y
 STX mv_S
 LDX mv_INWK,Y
 STX mv_P
 LDA mv_INWK+1,Y
 EOR #%10000000
 JSR mv_MAD
 STA mv_INWK+3,Y
 STX mv_INWK+2,Y
 STX mv_P
 LDX mv_INWK,Y
 STX mv_R
 LDX mv_INWK+1,Y
 STX mv_S
 LDA mv_INWK+3,Y
 JSR mv_MAD
 STA mv_INWK+1,Y
 STX mv_INWK,Y
 STX mv_P
 LDA mv_BETA
 STA mv_Q
 LDX mv_INWK+2,Y
 STX mv_R
 LDX mv_INWK+3,Y
 STX mv_S
 LDX mv_INWK+4,Y
 STX mv_P
 LDA mv_INWK+5,Y
 EOR #%10000000
 JSR mv_MAD
 STA mv_INWK+3,Y
 STX mv_INWK+2,Y
 STX mv_P
 LDX mv_INWK+4,Y
 STX mv_R
 LDX mv_INWK+5,Y
 STX mv_S
 LDA mv_INWK+3,Y
 JSR mv_MAD
 STA mv_INWK+5,Y
 STX mv_INWK+4,Y
 RTS

.mv_MVT6
 TAY
 EOR mv_INWK+2,X
 BMI mv_MV50
 LDA mv_P+1
 CLC
 ADC mv_INWK,X
 STA mv_P+1
 LDA mv_P+2
 ADC mv_INWK+1,X
 STA mv_P+2
 TYA
 RTS
.mv_MV50
 LDA mv_INWK,X
 SEC
 SBC mv_P+1
 STA mv_P+1
 LDA mv_INWK+1,X
 SBC mv_P+2
 STA mv_P+2
 BCC mv_MV51
 TYA
 EOR #%10000000
 RTS
.mv_MV51
 LDA #1
 SBC mv_P+1
 STA mv_P+1
 LDA #0
 SBC mv_P+2
 STA mv_P+2
 TYA
 RTS

.mv_MVS5
 LDA mv_INWK+1,X
 AND #%01111111
 LSR A
 STA mv_T
 LDA mv_INWK,X
 SEC
 SBC mv_T
 STA mv_R
 LDA mv_INWK+1,X
 SBC #0
 STA mv_S
 LDA mv_INWK,Y
 STA mv_P
 LDA mv_INWK+1,Y
 AND #%10000000
 STA mv_T
 LDA mv_INWK+1,Y
 AND #%01111111
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 ORA mv_T
 EOR mv_RAT2
 STX mv_Q
 JSR mv_ADD
 STA mv_K+1
 STX mv_K
 LDX mv_Q
 LDA mv_INWK+1,Y
 AND #%01111111
 LSR A
 STA mv_T
 LDA mv_INWK,Y
 SEC
 SBC mv_T
 STA mv_R
 LDA mv_INWK+1,Y
 SBC #0
 STA mv_S
 LDA mv_INWK,X
 STA mv_P
 LDA mv_INWK+1,X
 AND #%10000000
 STA mv_T
 LDA mv_INWK+1,X
 AND #%01111111
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 LSR A
 ROR mv_P
 ORA mv_T
 EOR #%10000000
 EOR mv_RAT2
 STX mv_Q
 JSR mv_ADD
 STA mv_INWK+1,Y
 STX mv_INWK,Y
 LDX mv_Q
 LDA mv_K
 STA mv_INWK,X
 LDA mv_K+1
 STA mv_INWK+1,X
 RTS


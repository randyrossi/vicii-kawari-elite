; LOAD"*",8,1 autostart, using the same BASIC-vector technique as Firebird.
CPU 0
ORG $02A5
 EQUW $02A7
.launch
 LDA #$37
 STA $01
 LDA #86
 STA $D03F
 LDA #73
 STA $D03F
 LDA #67
 STA $D03F
 LDA #50
 STA $D03F
 LDA #0
 JSR $FF90
 LDA #1
 LDX #8
 LDY #1
 JSR $FFBA
 LDA #6
 LDX #LO(name)
 LDY #HI(name)
 JSR $FFBD
 LDA #0
 JSR $FFD5
 BCS failed
 JMP $080D
.failed
 INC $D020
 JMP failed
.name
 EQUS "KAWARI"
 ASSERT P% <= $0300
 SKIP $0300-P%
 FOR vector,0,5
 EQUW launch
 NEXT
 SAVE "3-assembled-output/launch.prg", $02A5, P%

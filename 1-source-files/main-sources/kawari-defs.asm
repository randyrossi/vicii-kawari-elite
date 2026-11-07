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

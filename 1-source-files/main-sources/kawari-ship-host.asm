; Host side of the co-processor ship renderer: blueprint upload and the
; commands that replace LL9's drawing, SHPPT's dot, EE51 and KILLSHP's heap
; shuffle. Assembled in the main code block (CODE1), as CODE2 is full.

; Copy the ship blueprints (the SHIPS block, host $D0A0-$EFFF) to VRAM
; $DAA0-$F9FF, below the displayed rows' end and the line-heap mirror. The
; co-processor adds KW_BLUEPRINT_OFFSET to each XX0 pointer. RAM under I/O
; is read with I/O switched out, one byte at a time, interrupts disabled.
; The block's first $A0 bytes (lookup tables, not needed by the co-processor)
; are skipped: VRAM $DA00-$DA9F is hires row 144, shown on raster 195 just
; before the raster split turns hires off, so it must stay zero (black).
KW_BLUEPRINT_OFFSET = $0A00
.KW_BLUEPRINTS
 LDY #$A0
 STY $D039
 LDA #1
 STA $D03F
 LDA #0
 STA $D035
 STA KW_PTR
 LDA #HI($D000 + KW_BLUEPRINT_OFFSET)
 STA $D03A
 LDA #$D0
 STA KW_PTR+1
 SEI
 LDA $01
 AND #$F8
 STA KW_ARG
 ORA #4                ; all RAM
 STA KW_DX
 LDA KW_ARG
 ORA #5                ; RAM with I/O
 STA KW_DY
.KW_BLUEPRINT_BYTE
 LDA KW_DX
 STA $01
 LDA (KW_PTR),Y
 LDX KW_DY
 STX $01
 STA $D03B
 INY
 BNE KW_BLUEPRINT_BYTE
 INC KW_PTR+1
 LDA KW_PTR+1
 CMP #$F0
 BNE KW_BLUEPRINT_BYTE
 CLI                   ; KW_INIT runs with L1M = 5, as now restored
 RTS

; Send a host ship line heap address, mapped to its VRAM copy: ship heaps
; ($FA72-$FFBF) are mirrored at the same address; the space station's heap
; at LSO is mirrored at KW_LSO, just below any possible ship heap (NWSHP
; never lowers the heap below the last ship data block, $FA72).
; A = low byte, X = high byte.
KW_LSO = $F990
.KW_PUT_HEAP
 CPX #$F9
 BCS KW_PUT_HEAP_SAME
 SEC
 SBC #LO(LSO + $10000 - KW_LSO)
 PHA
 TXA
 SBC #HI(LSO + $10000 - KW_LSO)
 TAX
 PLA
.KW_PUT_HEAP_SAME
 STA $D03B
 STX $D03B
 RTS
.KW_HEAP_HEADER        ; heap address, drawn flag (bit 3) and colour
 LDA XX19
 LDX XX19+1
 JSR KW_PUT_HEAP
 LDA XX1+31
 AND #%00001000
.KW_HEAP_FLAGS
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 RTS

; LL9 from LL17 as one co-processor job (command 10), for a ship that is not
; exploding. Nothing is read back. As LL9 would, record that the ship is on
; screen (bit 3) and that any laser shot has been drawn (bit 6 clear).
.KW_SHIP
 KW_SAVE
 LDA #10
 JSR KW_SHIP_BODY
 JSR KW_CLOSE
 JSR KW_KICK           ; start drawing while the host carries on
 LDA XX1+31
 ORA #%00001000
 AND #%10111111
 STA XX1+31
 KW_RESTORE

; Open command A (10, or 13 for an exploding ship) and send the ship job:
; heap header, XX4, XX0, dontclip and the ship data block. I/O is mapped.
.KW_SHIP_BODY
 PHA
 JSR KW_OPEN
 PLA
 STA $D03B
 JSR KW_HEAP_HEADER
 LDA XX4
 STA $D03B
 LDA XX0
 STA $D03B
 LDA XX0+1
 STA $D03B
 LDA dontclip
 STA $D03B
 FOR n, 0, 31           ; unrolled: this runs for every ship on every frame
  LDA XX1+n
  STA $D03B
 NEXT
 RTS

; SHPPT's two-row dot (KW_DOT) or nothing (KW_NODOT), replacing the ship's
; old lines (command 11). The caller updates bit 3 afterwards.
.KW_DOT
 LDA #2
 EQUB $2C              ; skip the next instruction
.KW_NODOT
 LDA #0
 STA KW_ARG
 KW_SAVE
 JSR KW_OPEN
 LDA #11
 STA $D03B
 JSR KW_HEAP_HEADER
 LDA KW_ARG
 STA $D03B
 BEQ KW_DOT_DONE
 LDA K4
 JSR KW_DASH
 LDA K4
 CLC
 ADC #1
 JSR KW_DASH
.KW_DOT_DONE
 JSR KW_CLOSE
 KW_RESTORE
.KW_DASH               ; x1 = K3, y1 = y2 = A, x2 = min(K3 + 3, 255)
 TAX
 LDA K3
 STA $D03B
 STX $D03B
 CLC
 ADC #3
 BCC KW_DASH_X2
 LDA #255
.KW_DASH_X2
 STA $D03B
 STX $D03B
 RTS

; EE51: erase everything in the ship's line heap. The caller has already
; cleared bit 3, so the heap is explicitly marked as on screen here.
.KW_ERASE
 KW_SAVE
 JSR KW_OPEN
 LDA #11
 STA $D03B
 LDA XX19
 LDX XX19+1
 JSR KW_PUT_HEAP
 LDA #%00001000
 JSR KW_HEAP_FLAGS
 LDA #0
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE

; KILLSHP (KSL3) moves T bytes of line heap from K(1 0) to P(1 0); repeat the
; move in VRAM (command 12), ordered with the queued drawing commands.
.KW_HEAP_MOVE
 KW_SAVE
 JSR KW_OPEN
 LDA #12
 STA $D03B
 LDA K
 LDX K+1
 JSR KW_PUT_HEAP
 LDA P
 LDX P+1
 JSR KW_PUT_HEAP
 LDA T
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE

; Planet outlines on the co-processor (VRAM views only; see kawari-planet.asm).
; CIRCLE from CIRCLE2 onwards as one command (14). A = flags: bit 0 sets
; LSX2 = 0 first (CIRCLE), bit 1 sets LSP = 1 first (the other callers).
.KW_CIRCLE
 STA KW_ARG
 KW_SAVE
 JSR KW_OPEN
 LDA #14
 STA $D03B
 LDA K3
 STA $D03B
 LDA K3+1
 STA $D03B
 LDA K4
 STA $D03B
 LDA K4+1
 STA $D03B
 LDA K
 STA $D03B
 LDA STP
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 LDA KW_ARG
 STA $D03B
 JSR KW_CLOSE
 JSR KW_KICK
 KW_RESTORE

; BLINE: the first addition uses the caller's C flag, so do it here, then
; send the segment (command 15) and update FLAG and CNT as BLINE would,
; returning A = CNT.
.KW_BLINE
 TXA
 ADC K4
 STA K6+2
 LDA K4+1
 ADC T
 STA K6+3
 JSR KW_BLINE_SEND
 LDA FLAG
 BEQ KW_BLINE_CNT
 INC FLAG
.KW_BLINE_CNT
 LDA CNT
 CLC
 ADC STP
 STA CNT
 RTS
.KW_BLINE_SEND
 KW_SAVE
 JSR KW_OPEN
 LDA #15
 STA $D03B
 LDA K6
 STA $D03B
 LDA K6+1
 STA $D03B
 LDA K6+2
 STA $D03B
 LDA K6+3
 STA $D03B
 LDA FLAG
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE

; Ball line heap operation (command 16), A = 0 EraseRestOfPlanet, 1 WPLS2,
; 2 clear (RES2), 3 clear and reset LSP (WPSHPS). Registers are preserved.
.KW_PLANET_OP
 STA KW_ARG
 KW_SAVE
 JSR KW_OPEN
 LDA #16
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 LDA KW_ARG
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE

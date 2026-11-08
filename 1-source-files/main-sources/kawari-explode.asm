; Exploding ships for the co-processor: LL9's vertex projection with every
; face visible (EE30) and DOEXP's particle cloud (PTCLS, EXS1), relocated
; from elite-source.asm. The host keeps DOEXP's bookkeeping (the cloud's
; size and counter in its copy of the heap, the flags and the explosion
; sprite) and sends the results.
;
; The cloud lives in VRAM at the ship's line heap mirror, as on the host:
;   #0 cloud size, #1 counter, #2 end of the vertex data, #3-#6 random seeds,
;   #7 onwards the projected vertices (four bytes each, copied from XX3).
;
; Command 13, one exploding ship:
;   +1..+40  as command 10 (byte #31 of XX1 has bit 5 set)
;   +41      flags: bit 6 erase the cloud on screen first, bit 3 project the
;            ship and draw its new cloud, bit 7 also find the explosion
;            sprite's position (PTCLS2) for EX_RESULT
;   +42..+48 the host's new cloud header, bytes #0-#6
;   +49,+50  sprx, spry (PTCLS2's sprite offsets)
;
; The particles use a private copy of RAND, seeded per vertex as in PTCLS, so
; each cloud is drawn and erased with identical pixels.

.explode_command
 JSR sh_heap_header     ; sh_XX19 and colour
 LDY #41
 LDA (cmd),Y
 STA ex_flags
 LDY #49
 LDA (cmd),Y
 STA ex_SPRX
 INY
 LDA (cmd),Y
 STA ex_SPRY
 LDA #0
 STA ex_sprite
 STA EX_RESULT
 LDA ex_flags
 AND #%01000000
 BEQ ex_noerase
 JSR ex_PTCLS           ; erase the cloud drawn last time (its header is
.ex_noerase             ; still in VRAM)
 LDA ex_flags
 AND #%00001000
 BEQ ex_done
 LDA ex_flags
 AND #%10000000
 STA ex_sprite
 LDA sh_XX19            ; copy the new header to the heap: ex_ptr + Y
 SEC                    ; addresses heap byte Y - 42
 SBC #42
 STA ex_ptr
 LDA sh_XX19+1
 SBC #0
 STA ex_ptr+1
 LDY #48
.ex_header
 LDA (cmd),Y
 STA (ex_ptr),Y
 DEY
 CPY #41
 BNE ex_header
 JMP ship_command       ; projects the vertices, then ex_draw
.ex_done
 RTS

; LL17X's EE30, entered from sh_LL17 with Y = 12: every face is visible and
; so is every vertex (XX4 = 0).
.ex_EE30
 LDA (sh_XX0),Y
 LSR A
 LSR A
 TAX
 LDA #255
.ex_EE30_loop
 STA sh_XX2,X
 DEX
 BPL ex_EE30_loop
 INX
 STX sh_XX4
 JMP sh_LL42

; DOEXP from EXL1, entered from sh_LL72 once the vertices are projected:
; copy them into the cloud, then draw it.
.ex_draw
 LDY #2
 LDA (sh_XX19),Y
 TAY
.ex_EXL1
 LDA SH_XX3-7,Y
 STA (sh_XX19),Y
 DEY
 CPY #6
 BNE ex_EXL1

; PTCLS: draw (or, by XOR, erase) the cloud described by the heap.
.ex_PTCLS
 LDY #0
 LDA (sh_XX19),Y
 STA sh_Q               ; the cloud size, for EXS1's FMLTU
 INY
 LDA (sh_XX19),Y
 BPL ex_counter
 EOR #$FF
.ex_counter
 LSR A
 LSR A
 LSR A
 LSR A
 ORA #1
 STA ex_U               ; particles per vertex, less one
 INY
 LDA (sh_XX19),Y
 STA ex_TGT
 LDY #6
.ex_EXL5
 LDA MV_URGENT          ; movement need not wait for a whole cloud
 BEQ ex_EXL5_vertex
 JSR urgent_run
.ex_EXL5_vertex
 LDX #3
.ex_EXL3
 INY
 LDA (sh_XX19),Y
 STA ex_K3,X            ; K3+3/K3+2 = x, K3+1/K3 = y
 DEX
 BPL ex_EXL3
 STY ex_CNT
 LDA ex_sprite
 BEQ ex_seed
 LDA ex_K3+3            ; PTCLS2: the sprite goes on each vertex in turn
 CLC                    ; that is on screen, so record the last one
 ADC ex_SPRX
 STA ex_SC
 LDA ex_K3+2
 ADC #0
 BMI ex_seed
 CMP #2
 BCS ex_seed
 TAX
 LDA ex_K3+1
 CLC
 ADC ex_SPRY
 TAY
 LDA ex_K3
 ADC #0
 BNE ex_seed
 CPY #2*SH_Y+50
 BCS ex_seed
 STY EX_RESULT+3
 STX EX_RESULT+2
 LDA ex_SC
 STA EX_RESULT+1
 LDA #1
 STA EX_RESULT
.ex_seed
 LDY #2
.ex_EXL2
 INY
 LDA (sh_XX19),Y
 EOR ex_CNT
 STA ex_RAND-3,Y
 CPY #6
 BNE ex_EXL2
 LDY ex_U
.ex_EXL4
 JSR ex_DORND
 STA ex_ZZ
 LDA ex_K3+1
 STA sh_R
 LDA ex_K3
 JSR ex_EXS1
 BNE ex_EX11
 CPX #2*SH_Y-1
 BCS ex_EX11
 STX ex_Y1
 LDA ex_K3+3
 STA sh_R
 LDA ex_K3+2
 JSR ex_EXS1
 BNE ex_EX4
 STY ex_YSAV            ; PIXEL preserves Y; point does not
 LDA ex_ZZ
 STA temp
 LDA ex_Y1
 STA cy
 TXA
 JSR point_at
 LDY ex_YSAV
.ex_EX4
 DEY
 BPL ex_EXL4
 LDY ex_CNT
 CPY ex_TGT
 BCS ex_PTCLS_done
 JMP ex_EXL5
.ex_PTCLS_done
 RTS
.ex_EX11
 JSR ex_DORND
 JMP ex_EX4

; EXS1: (A R) +/- random * cloud size, returned as (A X).
.ex_EXS1
 STA sh_S
 JSR ex_DORND
 ROL A
 BCS ex_EX5
 JSR sh_FMLTU
 ADC sh_R
 TAX
 LDA sh_S
 ADC #0
 RTS
.ex_EX5
 JSR sh_FMLTU
 STA sh_T
 LDA sh_R
 SBC sh_T
 TAX
 LDA sh_S
 SBC #0
 RTS

; PTCLS's inline random number step (DORND2), on the private RAND.
.ex_DORND
 CLC
 LDA ex_RAND
 ROL A
 TAX
 ADC ex_RAND+2
 STA ex_RAND
 STX ex_RAND+2
 LDA ex_RAND+1
 TAX
 ADC ex_RAND+3
 STA ex_RAND+1
 STX ex_RAND+3
 RTS

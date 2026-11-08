; Native NMOS 6502 code, assembled at its execution address in VRAM.
; $0000-$01ff private zero page/stack, $0200-$0fff code/tables,
; $1000-$1bff stardust and ship code, $1c00-$1d61 and $1e00-$1f61 command
; buffers, $1d62-$1dff and $1f62-$1fff planet code,
; $2000-$79ff working image (320 x 144),
; $7a00-$7b1f row tables, $7b20-$7bff ball line heap (x, y), $7c00-$7c6e results, $7c70-$7fef movement code,
; $7ff0 mailbox, $8000-$d9ff displayed rows, $da00-$da9f always zero (hires
; row 144, shown on raster 195 before the split takes effect), $daa0-$f98c ship blueprints,
; $f990-$fa57 space station line heap, $fa72-$ffbf ship line heaps.
CPU 0
cmd = $00
dst = $02
cx = $04
cy = $05
ex = $06
ey = $07
dx = $08
dy = $09
step = $0A
error = $0B
count = $0C
colour = $0D
mask = $0E
temp = $0F
swapped = $10
slope = $11
row = $12
bits = $13
linecarry = $14
stars_resident = $15
v_input = $20
v_matrix = $26
v_p = $40
v_q = $41
v_r = $42
v_s = $43
v_t = $44
v_widget = $45
v_result = $7C00
rowlo = $7A00
rowhi = $7A90
mailbox = $7FF0
; Planet job (kawari-planet.asm) heap and workspace
pl_LSX2 = $7B20                 ; 112 bytes each. A frame makes at most ~68
pl_LSY2 = $7B90                 ; BLINE calls (circle plus two meridians, or
                                ; a crater), each adding one point, or two
                                ; after a break, which itself adds one $FF:
                                ; at most ~1.5 per call, about 103 in all
pl_LSP = $74                    ; persistent heap pointer
pl_K3 = $80                     ; K3(1 0) centre x, K3+2..K3+9 BLINE workspace
pl_K4 = $8A                     ; two bytes
pl_K5 = $8C                     ; four bytes
pl_K6 = $90                     ; four bytes
pl_K = $94
pl_STP = $95
pl_CNT = $96
pl_T = $97
pl_FLAG = $98
pl_LSNUM = $99
pl_LSNUM2 = $9A

ORG $0200
.entry
 SEI
 CLD
 LDX #$FF
 TXS
 LDA #$10
 STA dst
 LDA #$20
 STA dst+1
 LDX #0
.build_rows
 LDA dst
 STA rowlo,X
 LDA dst+1
 STA rowhi,X
 CLC
 LDA dst
 ADC #160
 STA dst
 BCC row_no_carry
 INC dst+1
.row_no_carry
 INX
 CPX #144
 BNE build_rows
 LDA #0
 STA mailbox
 STA MV_URGENT
 STA pl_LSP             ; the ball line heap starts empty
 LDA #$FF
 STA pl_LSX2
 STA pl_LSY2
.idle
 LDA MV_URGENT
 BEQ idle_mailbox
 JSR urgent_run
.idle_mailbox
 LDA mailbox
 BEQ idle
 STA cmd+1             ; the mailbox holds the command list's start page
 LDA #0
 STA cmd
.dispatch
 LDA MV_URGENT
 BEQ dispatch_command
 JSR urgent_run
.dispatch_command
 LDY #0
 LDA (cmd),Y
 BEQ complete
 CMP #1
 BEQ line_command
 CMP #2
 BEQ horizontal_command
 CMP #3
 BEQ point_command
 CMP #4
 BEQ glyph_command
 CMP #5
 BEQ clear_command
 CMP #6
 BEQ vector_command
 CMP #7
 BNE check_clear_box
 JSR stars_command
 LDA #96
 JMP advance
.check_clear_box
 CMP #8
 BNE check_borders
 JSR clear_box
 LDA #5
 JMP advance
.check_borders
 CMP #9
 BEQ borders_command
 JMP check_ship
.borders_command
 JSR borders
 LDA #1
 JMP advance
.invalid_command
 ; Invalid command: leave a diagnostic and stop consuming the buffer.
 LDA #$FF
 STA mailbox+1
.complete
 LDA #0
 STA mailbox
 JMP idle
.line_command
 JSR read_line
 JSR line
 LDA #6
 BNE advance
.horizontal_command
 JSR read_line
 JSR horizontal
 LDA #6
 BNE advance
.point_command
 JSR point
 LDA #5
 BNE advance
.glyph_command
 JSR glyph
 LDA #12
 BNE advance
.clear_command
 JSR clear
 LDA #1
 BNE advance
.vector_command
 LDY #1
 LDX #0
.vector_input
 LDA (cmd),Y
 STA v_input,X
 INY
 INX
 CPX #24
 BNE vector_input
 JSR vector
 LDA #25
 BNE advance
.advance
 CLC
 ADC cmd
 STA cmd
 BCC advance_ready
 INC cmd+1
.advance_ready
 JMP dispatch
.check_ship
 CMP #10
 BNE check_lines
 JSR ship_command
 LDA #41
 JMP advance
.check_lines
 CMP #11
 BNE check_move
 JSR lines_command
 LDY #5
 LDA (cmd),Y
 ASL A
 ASL A
 CLC
 ADC #6
 JMP advance
.check_move
 CMP #12
 BNE check_planet
 JSR move_command
 LDA #6
 JMP advance
.check_planet
 CMP #14
 BNE check_bline
 JSR planet_circle_command
 LDA #9
 JMP advance
.check_bline
 CMP #15
 BNE check_planet_op
 JSR planet_bline_command
 LDA #7
 JMP advance
.check_planet_op
 CMP #16
 BNE check_stars_resident
 JSR planet_op_command
 LDA #3
 JMP advance
.check_stars_resident
 CMP #17
 BEQ stars_resident_dispatch
 JMP invalid_command
.stars_resident_dispatch
 JSR stars_resident_command
 LDA #18
 JMP advance
.read_line
 LDY #1
 LDA (cmd),Y
 STA cx
 INY
 LDA (cmd),Y
 STA cy
 INY
 LDA (cmd),Y
 STA ex
 INY
 LDA (cmd),Y
 STA ey
 INY
 LDA (cmd),Y
 STA colour
 RTS

; Plot the game's x=0..255 at screen x=32..287. Add the margin to
; the byte address, so x=224..255 cannot wrap at an 8-bit addition.
.plot
 LDX cy
 CPX #144
 BCS plot_return
 LDA rowlo,X
 STA dst
 LDA rowhi,X
 STA dst+1
 LDA cx
 LSR A
 TAY
 LDA colour
 BCS odd_pixel
 ASL A
 ASL A
 ASL A
 ASL A
.odd_pixel
 EOR (dst),Y
 STA (dst),Y
.plot_return
 RTS

; Elite's fixed-point DDA and its logarithmic slope tables. Keeping the
; original quantisation and endpoint rules preserves XOR shared vertices.
.line
 LDA #0
 STA swapped
 LDA #128
 STA error
 SEC
 LDA ex
 SBC cx
 BCS dx_positive
 EOR #$FF
 ADC #1
.dx_positive
 STA dx
 SEC
 LDA ey
 SBC cy
 BCS dy_positive
 EOR #$FF
 ADC #1
.dy_positive
 STA dy
 CMP dx
 BCC shallow
 JMP steep
.shallow
 LDA cx
 CMP ex
 BCC shallow_ordered
 JSR swap_ends
.shallow_ordered
 LDX dy
 LDY dx
 JSR ratio
 LDA #1
 STA step
 LDA cy
 CMP ey
 BCC shallow_down
 LDA #$FF
 STA step
.shallow_down
 LDA #0
 STA linecarry
 LDA step
 BMI shallow_initialised
 LDX cy
 LDA cx
 AND #$F8
 CLC
 ADC tilelo,X
 CMP #248
 ROL linecarry
.shallow_initialised
 LDA dx
 STA count
 LDA swapped
 BEQ shallow_plot
 JSR shallow_step
.shallow_plot
 JSR plot
 DEC count
 BEQ line_return
 JSR shallow_step
 JMP shallow_plot
.shallow_step
 INC cx
 LSR linecarry
 LDA error
 ADC slope
 STA error
 BCC shallow_carry
 CLC
 LDA cy
 ADC step
 STA cy
.shallow_carry
 ; Preserve the original DDA's carry at an eight-pixel column crossing.
 ; It depends on the old VIC bitmap pointer even though pixels now go
 ; directly to packed VRAM. This keeps existing shared vertices identical.
 LDA #0
 STA linecarry
 LDA cx
 AND #7
 BNE line_return
 LDA cx
 AND #$F8
 LDX cy
 CLC
 ADC tilelo,X
 LDX step
 BMI shallow_carry_test
 CLC
 ADC #8
.shallow_carry_test
 CMP #8
 BCS line_return
 INC linecarry
.line_return
 RTS
.steep
 LDA dy
 BEQ line_return
 LDA cy
 CMP ey
 BCS steep_ordered
 JSR swap_ends
.steep_ordered
 LDX dx
 LDY dy
 JSR ratio
 LDA #1
 STA step
 LDA ex
 CMP cx
 BCS steep_right
 LDA #$FF
 STA step
.steep_right
 LDA dy
 STA count
 LDA swapped
 BNE steep_plot
 JSR steep_step
.steep_plot
 JSR plot
 DEC count
 BEQ line_return
 JSR steep_step
 JMP steep_plot
.steep_step
 DEC cy
 LDA cy
 AND #7
 CMP #7               ; carry at the original bitmap's row boundary
 LDA error
 ADC slope
 STA error
 BCC line_return
 CLC
 LDA cx
 ADC step
 STA cx
 RTS
.swap_ends
 LDX cx
 LDA ex
 STA cx
 STX ex
 LDX cy
 LDA ey
 STA cy
 STX ey
 INC swapped
 RTS
.ratio
 TXA
 BEQ ratio_store
 SEC
 LDA loglo,X
 SBC loglo,Y
 BMI ratio_odd
 LDA loghi,X
 SBC loghi,Y
 BCS ratio_max
 TAX
 LDA antilog,X
 JMP ratio_store
.ratio_odd
 LDA loghi,X
 SBC loghi,Y
 BCS ratio_max
 TAX
 LDA antilog_odd,X
 JMP ratio_store
.ratio_max
 LDA #255
.ratio_store
 STA slope
 RTS

.horizontal
 LDA cx
 CMP ex
 BNE h_nonempty
 RTS
.h_nonempty
 BCC h_ordered
 LDX ex
 STX cx
 STA ex
.h_ordered
 LDX cy
 CPX #144
 BCS h_return
 LDA rowlo,X
 STA dst
 LDA rowhi,X
 STA dst+1
 LDA cx
 LSR A
 TAY
 BCC h_even
 LDA colour
 EOR (dst),Y
 STA (dst),Y
 INY
.h_even
 LDA ex
 LSR A
 STA temp
 LDA colour
 ASL A
 ASL A
 ASL A
 ASL A
 STA mask
 ORA colour
 STA bits
.h_bytes
 CPY temp
 BEQ h_last
 LDA bits
 EOR (dst),Y
 STA (dst),Y
 INY
 BNE h_bytes
.h_last
 LDA ex
 AND #1
 BEQ h_return
 LDA mask
 EOR (dst),Y
 STA (dst),Y
.h_return
 RTS

; Preserve PIXEL's actual two-bit masks (including its x=0 special case)
; and the original double-height rule at character-row boundaries.
.point
 LDY #1
 LDA (cmd),Y
 STA cx
 AND #7
 BEQ point_x_ready
 DEC cx
.point_x_ready
 INY
 LDA (cmd),Y
 STA cy
 INY
 LDA (cmd),Y
 STA temp
 INY
 LDA (cmd),Y
 STA colour
.point_render
 JSR point_row
 LDA temp
 CMP #80
 BCS point_return
 LDA cy
 AND #7
 BNE point_up
 INC cy
 BNE point_second
.point_up
 DEC cy
.point_second
 JSR point_row
.point_return
 RTS
.point_row
 JSR plot
 INC cx
 JSR plot
 DEC cx
 RTS

; CHAR: x, y, colour, eight bitmap rows. White is a command parameter,
; so later object colours do not require a new framebuffer format.
.glyph
 LDY #1
 LDA (cmd),Y
 STA ex
 INY
 LDA (cmd),Y
 STA cy
 INY
 LDA (cmd),Y
 STA colour
 LDA #0
 STA row
.glyph_row
 LDA row
 CLC
 ADC #4
 TAY
 LDA (cmd),Y
 STA bits
 LDA ex
 STA cx
 LDA #8
 STA count
.glyph_bit
 ASL bits
 BCC glyph_skip
 JSR plot
.glyph_skip
 INC cx
 DEC count
 BNE glyph_bit
 INC cy
 INC row
 LDA row
 CMP #8
 BNE glyph_row
 RTS

.clear
 LDA #0
 STA dst
 LDA #$20
 STA dst+1
 LDY #0
 LDX #90
 LDA #0
.clear_page
 STA (dst),Y
 INY
 BNE clear_page
 INC dst+1
 DEX
 BNE clear_page
 ; White side borders at physical x=30,31 and x=288,289.
.borders
 LDX #0
.clear_border
 LDA rowlo,X
 SEC
 SBC #16
 STA dst
 LDA rowhi,X
 SBC #0
 STA dst+1
 LDY #15
 LDA #$11
 EOR (dst),Y
 STA (dst),Y
 LDY #144
 LDA #$11
 EOR (dst),Y
 STA (dst),Y
 INX
 CPX #144
 BNE clear_border
 RTS

; CLEAR_BOX: byte-x within the 256-pixel game area, y, byte-width, height.
; Text cells are byte-aligned in the packed-nibble framebuffer.
.clear_box
 LDY #1
 LDA (cmd),Y
 STA cx
 INY
 LDA (cmd),Y
 STA cy
 INY
 LDA (cmd),Y
 STA dx
 INY
 LDA (cmd),Y
 STA dy
 BEQ clear_box_done
.clear_box_row
 LDX cy
 CPX #144
 BCS clear_box_done
 LDA rowlo,X
 STA dst
 LDA rowhi,X
 STA dst+1
 LDY cx
 LDX dx
 BEQ clear_box_done
 LDA #0
.clear_box_byte
 CPY #128
 BCS clear_box_next
 STA (dst),Y
 INY
 DEX
 BNE clear_box_byte
.clear_box_next
 INC cy
 DEC dy
 BNE clear_box_row
.clear_box_done
 RTS

.vector
 LDX #0
 LDY #0
.vector_loop
 LDA v_input
 STA v_q
 LDA v_matrix,X
 JSR v_multiply
 STA v_t
 LDA v_input+1
 EOR v_matrix+1,X
 STA v_s
 LDA v_input+2
 STA v_q
 LDA v_matrix+2,X
 JSR v_multiply
 STA v_q
 LDA v_t
 STA v_r
 LDA v_input+3
 EOR v_matrix+3,X
 JSR v_add
 STA v_t
 LDA v_input+4
 STA v_q
 LDA v_matrix+4,X
 JSR v_multiply
 STA v_q
 LDA v_t
 STA v_r
 LDA v_input+5
 EOR v_matrix+5,X
 JSR v_add
 STA v_result,Y
 LDA v_s
 STA v_result+1,Y
 INY
 INY
 TXA
 CLC
 ADC #6
 TAX
 CMP #17
 BCC vector_loop
 RTS
.v_multiply
 STX v_p
 STA v_widget
 TAX
 BEQ v_return
 LDA loglo,X
 LDX v_q
 BEQ v_zero
 CLC
 ADC loglo,X
 BMI v_odd
 LDA loghi,X
 LDX v_widget
 ADC loghi,X
 BCC v_zero
 TAX
 LDA antilog,X
 LDX v_p
 RTS
.v_odd
 LDA loghi,X
 LDX v_widget
 ADC loghi,X
 BCC v_zero
 TAX
 LDA antilog_odd,X
.v_return
 LDX v_p
 RTS
.v_zero
 LDA #0
 LDX v_p
 RTS
.v_add
 EOR v_s
 BMI v_subtract
 LDA v_q
 CLC
 ADC v_r
 RTS
.v_subtract
 LDA v_r
 SEC
 SBC v_q
 BCC P%+4
 CLC
 RTS
.v_negate
 PHA
 LDA v_s
 EOR #%10000000
 STA v_s
 PLA
 EOR #%11111111
 ADC #1
 RTS
 INCLUDE "1-source-files/main-sources/kawari-clip.asm"
 INCLUDE "1-source-files/main-sources/kawari-movemath.asm"
 INCLUDE "1-source-files/main-sources/kawari-bline.asm"
 PRINT "Main co-processor code ends at ", ~P%
 ASSERT P% <= $0B00
ORG $0B00
.tilelo
 FOR n,0,255
 EQUB LO($20+(n AND $F8)*40)
 NEXT
ORG $0C00
.loghi
 EQUB 0
 FOR n,1,255
 EQUB HI(INT($2000 * LOG(n) / LOG(2) + 0.5))
 NEXT
.loglo
 EQUB 0
 FOR n,1,255
 EQUB LO(INT($2000 * LOG(n) / LOG(2) + 0.5))
 NEXT
.antilog
 FOR n,0,255
 EQUB HI(INT(2^((n / 2 + 128) / 16) + 0.5))
 NEXT
.antilog_odd
 FOR n,0,255
 EQUB HI(INT(2^((n / 2 + 128.25) / 16) + 0.5))
 NEXT
ORG $1000
.stars_resident_command ; command 17: the particles are already in VRAM
 LDA #$FF
 BNE stars_common       ; (never BIT: the emulator's BIT changes C)
.stars_command
 LDA #0
.stars_common
 STA stars_resident
 LDY #1
 LDX #0
.stars_controls
 LDA (cmd),Y
 STA $50,X
 INY
 INX
 CPX #17
 BNE stars_controls
 LDA stars_resident
 BNE stars_run
 LDX #0
.stars_particles
 LDA (cmd),Y
 STA $7C21,X
 INY
 INX
 CPX #78
 BNE stars_particles
.stars_run
 JSR st_STARS
 LDX #3
.stars_random
 LDA $5D,X             ; st_RAND (defined with the relocated routines below)
 STA $7C1D,X
 DEX
 BPL stars_random
 RTS
 INCLUDE "1-source-files/main-sources/kawari-stars.asm"
 INCLUDE "1-source-files/main-sources/kawari-ship.asm"
 PRINT "Stardust and ship code ends at ", ~P%
 ASSERT P% <= $1C00

; Each command buffer ($1C00, $1E00) holds at most $161 bytes, as the host
; never starts a command beyond the buffer's first page and the largest is
; 97 bytes plus END. Code fills the rest of each pair of pages.
ORG $1D62
 INCLUDE "1-source-files/main-sources/kawari-planet.asm"
 PRINT "Planet commands end at ", ~P%
 ASSERT P% <= $1E00
ORG $1F62
 INCLUDE "1-source-files/main-sources/kawari-circle.asm"
 PRINT "Planet circle ends at ", ~P%
 ASSERT P% <= $2000
 SAVE "3-assembled-output/kawari-cpu.bin", $0200, $2000

; Second code block, between the result area and the mailbox. It is uploaded
; separately by the boot loader (the whole $7C00-$7FFF page range).
ORG $7C70
 INCLUDE "1-source-files/main-sources/kawari-move.asm"
 INCLUDE "1-source-files/main-sources/kawari-sine.asm"
 PRINT "High co-processor code ends at ", ~P%
 ASSERT P% <= MV_ARGS
 SAVE "3-assembled-output/kawari-cpu-hi.bin", $7C00, $8000

; PAL Kawari disk bootstrap. Standard CBM files avoid the original PAL
; loader's fixed sector map, so the game and co-processor may change size.
CPU 0
ORG $07FF
 EQUW $0801
.boot_start
 EQUW $080B, 1
 EQUB $9E
 EQUS "2061"
 EQUB 0
 EQUW 0
.boot
 SEI
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
 STA $D037
 LDA #$20
 STA $D03F
 LDA #0
 STA $D03A
 LDA #$22
 STA $D039
 LDA #1
 STA $D03B             ; hold the co-processor in reset during upload
 ; The engine is assembled for VRAM $0200, independent of its disk address.
 LDA #1
 STA $D03F
 LDA #0
 STA $D035
 STA $D039
 LDA #2
 STA $D03A
 LDA #LO(engine_image)
 STA $FB
 LDA #HI(engine_image)
 STA $FC
 LDY #0
 LDX #(engine_end-engine_image)/256
.upload
 LDA ($FB),Y
 STA $D03B
 INY
 BNE upload
 INC $FC
 DEX
 BNE upload
 ; This page survives the loader's data relocations and both game loads.
.relocate
 LDA $0900,X
 STA $CF00,X
 INX
 BNE relocate
 CLI
 JMP disk_loader
 ASSERT P% <= $0900

ORG $CF00
.disk_loader
 LDA #'4'
 JSR load_file
 SEI
 LDA #$35
 STA $01
 JSR $7596             ; COMLOD entry; the Kawari build returns with RTS
 LDA #$36
 STA $01
 JSR $FF8A             ; Restore KERNAL vectors (including LOAD)
 CLI
 LDA #'5'
 JSR load_file
 LDA #'6'
 JSR load_file
 JSR $FFE7
 JMP $1D22
.load_file
 STA filename+3
 LDA #4
 LDX #LO(filename)
 LDY #HI(filename)
 JSR $FFBD
 LDA #1
 LDX #8
 LDY #1
 JSR $FFBA
 LDA #0
 JSR $FFD5
 BCS load_error
 RTS
.load_error
 INC $D020             ; A failed disk load is visible; never run partial code
 JMP load_error
.filename
 EQUS "GMA4"
 ASSERT P% <= $D000
 COPYBLOCK $CF00, P%, $0900

ORG $0A00
.engine_image
 INCBIN "3-assembled-output/kawari-cpu.bin"
 ALIGN 256
.engine_end
 SAVE "3-assembled-output/elite-kawari.prg", $07FF, engine_end

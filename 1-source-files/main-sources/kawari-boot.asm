; PAL Kawari disk bootstrap. Standard CBM files avoid the original PAL
; loader's fixed sector map, so the game and co-processor may change size.
CPU 0
FIRMWARE_MAJOR = 1     ; oldest Kawari firmware with the 6502 co-processor
FIRMWARE_MINOR = 20
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
 ; The co-processor needs firmware 1.20 or later. The major and minor version
 ; are extra registers $83 and $84 (read through the overlay). A C64 without a
 ; Kawari reads $FF for both, which is refused as well.
 LDA #$20
 STA $D03F             ; extra register overlay on, no auto-increment
 LDA #0
 STA $D03A
 LDA #$84
 STA $D039
 LDX $D03B             ; X = minor
 LDA #$83
 STA $D039
 LDA $D03B             ; A = major
 CMP #$FF
 BEQ old_firmware
 CMP #FIRMWARE_MAJOR
 BCC old_firmware
 BNE firmware_ok
 CPX #FIRMWARE_MINOR
 BCS firmware_ok
.old_firmware
 LDA #0
 STA $D03F             ; overlay off
 CLI
 LDY #0
.message_char
 LDA firmware_message,Y
 BEQ message_done
 JSR $FFD2             ; CHROUT
 INY
 BNE message_char
.message_done
 JSR $E453             ; restore BASIC's vectors (launch.prg replaced them)
 JMP ($A002)           ; BASIC warm start: READY.
.firmware_message
 EQUB 147, 14          ; clear screen, upper/lower case character set
 MAPCHAR 'a', 'z', $41 ; PETSCII in that set: $41-$5A lower, $C1-$DA upper
 MAPCHAR 'A', 'Z', $C1
 EQUS "Kawari firmware v1.20 or higher is", 13   ; 44 characters: break the
 EQUS "required."                                ; line between words
 MAPCHAR 'a', 'z', 'a'
 MAPCHAR 'A', 'Z', 'A'
 EQUB 13, 0
.firmware_ok
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
 LDA #HI(engine_image)
 LDX #(engine_hi-engine_image)/256
 JSR upload
 LDA #0                ; second block (movement code) at VRAM $7C00
 STA $D039
 LDA #$7C
 STA $D03A
 LDA #HI(engine_hi)
 LDX #(engine_end-engine_hi)/256
 JSR upload
 ; This page survives the loader's data relocations and both game loads.
.relocate
 LDA $0900,X
 STA $CF00,X
 INX
 BNE relocate
 CLI
 JMP disk_loader
.upload                ; copy X pages from page A to the VRAM port
 STA $FC
 LDA #0
 STA $FB
 TAY
.upload_byte
 LDA ($FB),Y
 STA $D03B
 INY
 BNE upload_byte
 INC $FC
 DEX
 BNE upload_byte
 RTS
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
.engine_hi
 INCBIN "3-assembled-output/kawari-cpu-hi.bin"
.engine_end
 SAVE "3-assembled-output/elite-kawari.prg", $07FF, engine_end

; The IRQ only changes VIDEO_MODE1, never the VRAM ports. All command/DMA
; traffic belongs to the foreground, with I/O and L1M mapped together.
.KW_INIT
 KW_SAVE
 LDA #0
 STA KW_ACTIVE
 STA KW_DIRTY
 STA KW_WRITE
 STA $D037
 STA $D035
 STA $D039
 STA $D03C
 LDA #KW_WHITE
 STA KW_COLOUR
 LDA #$1C
 STA KW_WRITE+1
 STA KW_BUF
 LDA #$80
 STA $D03A
 LDA #$7D
 STA $D036
 LDA #15
 STA $D03F
 LDA #4
 STA $D03B             ; blank 32000 displayed bytes, ending below $10000
                       ; (the emulator's fill completion doesn't wrap)
.KW_INIT_WAIT
 LDA $D036
 BNE KW_INIT_WAIT
 JSR KW_BLUEPRINTS     ; after the clear, which also covers this area
 LDA #1
 STA $D038             ; display base $8000
 LDA #0
 STA $D03F
 STA $D035
 LDA #$7F
 STA $D03A
 LDA #$F0
 STA $D039
 LDA #$FF
 STA $D03B             ; startup handshake
 LDA #$20
 STA $D03F
 LDA #0
 STA $D03A
 LDA #$20
 STA $D039
 LDA #0
 STA $D03B             ; CPU_START_LO
 INC $D039
 LDA #2
 STA $D03B             ; CPU_START_HI
 LDA #$2B
 STA $D039
 LDA #0
 STA $D03B             ; CPU_SPEED = full speed
 LDA #$22
 STA $D039
 LDA #0
 STA $D03B             ; release CPU reset
 STA $D03F
 LDA #$7F
 STA $D03A
 LDA #$F0
 STA $D039
.KW_READY
 LDA $D03B
 BNE KW_READY
 KW_RESTORE

; One mailbox round-trip moves, rotates and plots all 12 dust particles.
; Host state remains authoritative so view changes and hyperspace can reset
; it normally. Only the private copy is touched by the co-processor.
.KW_STARS
 KW_SAVE
 JSR KW_OPEN
 LDA KW_STARS_DIRTY    ; command 7 uploads the particles as well, command 17
 BEQ KW_STARS_RESIDENT ; uses those already in VRAM
 LDA #7
 EQUB $2C              ; skip the next instruction
.KW_STARS_RESIDENT
 LDA #17
 STA $D03B
 LDX #0
 LDY #0
.KW_STARS_CONTROLS
 LDA KW_STARS_ADDR,X
 STA KW_PTR
 INX
 LDA KW_STARS_ADDR,X
 STA KW_PTR+1
 INX
 LDA (KW_PTR),Y
 STA $D03B
 CPX #34
 BNE KW_STARS_CONTROLS
 LDA KW_STARS_DIRTY
 BEQ KW_STARS_QUEUED
 LDX #0
.KW_STARS_PARTICLES
 LDA SX,X
 STA $D03B
 INX
 CPX #78
 BNE KW_STARS_PARTICLES
 STY KW_STARS_DIRTY    ; Y = 0: VRAM now holds the particles
.KW_STARS_QUEUED
 JSR KW_CLOSE
 JSR KW_KICK           ; the stardust is drawn while the host carries on
 KW_RESTORE
; The co-processor owns the stardust particles between frames (it moves
; them; the host only needs them when FLIP swaps their coordinates, and nWq
; replaces them all). RAND is sent each frame but not read back, so stardust
; respawning no longer advances the host's random sequence.
.KW_STARS_FETCH        ; FLIP: wait for the stardust, read it, then modify it
 KW_SAVE
 JSR KW_FLUSH
 LDA #1
 STA $D03F
 STA KW_STARS_DIRTY
 LDA #$21
 STA $D039
 LDA #$7C
 STA $D03A
 LDX #0
.KW_STARS_RESULT
 LDA $D03B
 STA SX,X
 INX
 CPX #78
 BNE KW_STARS_RESULT
 KW_RESTORE
.KW_STARS_DIRTY
 EQUB 1                ; nonzero when the host has changed the particles
.KW_STARS_ADDR
 EQUW VIEW,NOSTM,KW_SDELTA,KW_SDELT4,KW_SDELT4+1,KW_SALPHA,KW_SALP1,ALP2,ALP2+1
 EQUW KW_SBETA,KW_SBET1,BET2,BET2+1,RAND,RAND+1,RAND+2,RAND+3

; Command lists are double-buffered: two buffers at $1C00 and $1E00, each
; at most $161 bytes, as co-processor code follows each one. A command only
; starts in its buffer's first page, so even the largest (96 bytes) and the
; END byte end by $160. The host fills the current buffer (KW_BUF) while the
; co-processor may run the other one. Submitting writes the END byte, then
; the buffer's start page to the mailbox; the co-processor clears the mailbox
; when it has finished. The host only switches buffers while the
; co-processor is idle, so it never writes a buffer that is still being read.
.KW_OPEN
 LDA KW_WRITE+1
 CMP KW_BUF
 BEQ KW_SPACE          ; still in the first page: always room
 JSR KW_WAIT           ; otherwise wait for the other buffer to finish and
 JSR KW_SUBMIT         ; switch to it
.KW_SPACE
 LDA #1
 STA KW_DIRTY
 STA $D03F
 LDA #0
 STA $D035
 LDA KW_WRITE
 STA $D039
 LDA KW_WRITE+1
 STA $D03A
 RTS
.KW_CLOSE
 LDA $D039
 STA KW_WRITE
 LDA $D03A
 STA KW_WRITE+1
 RTS
; Start the queued commands without waiting, if the co-processor is idle.
.KW_KICK
 LDA KW_WRITE
 BNE KW_KICK_QUEUED
 LDA KW_WRITE+1
 CMP KW_BUF
 BEQ KW_KICK_DONE
.KW_KICK_QUEUED
 JSR KW_IDLE
 BNE KW_KICK_DONE
 JMP KW_SUBMIT
.KW_KICK_DONE
 RTS
; Z set when the co-processor is idle (mailbox clear).
.KW_IDLE
 LDA #0
 STA $D03F
 LDA #$F0
 STA $D039
 LDA #$7F
 STA $D03A
 LDA $D03B
 RTS
.KW_WAIT
 JSR KW_IDLE
 BNE KW_WAIT
 RTS
; Submit the current buffer (the co-processor must be idle) and switch.
.KW_SUBMIT
 LDA #1
 STA $D03F
 LDA KW_WRITE
 STA $D039
 LDA KW_WRITE+1
 STA $D03A
 LDA #0
 STA $D03B             ; END, committed before the mailbox
 STA $D03F
 LDA #$F0
 STA $D039
 LDA #$7F
 STA $D03A
 LDA KW_BUF
 STA $D03B             ; mailbox = start page
 EOR #2
 STA KW_BUF
 STA KW_WRITE+1
 LDA #0
 STA KW_WRITE
 RTS
; Run everything queued and wait until the co-processor has finished.
.KW_FLUSH
 LDA KW_WRITE
 BNE KW_FLUSH_QUEUED
 LDA KW_WRITE+1
 CMP KW_BUF
 BEQ KW_BUSY
.KW_FLUSH_QUEUED
 JSR KW_WAIT
 JSR KW_SUBMIT
.KW_BUSY
 JSR KW_IDLE
 BNE KW_BUSY
 RTS
.KW_BUF
 EQUB $1C              ; page of the buffer the host is filling

.KW_LINE
 LDA KW_ACTIVE
 BNE KW_VRAM_LINE
 JMP KW_DRAM_LINE
.KW_VRAM_LINE
 LDA #1
.KW_FAST_SEGMENT
 ; Fast path for the common case: all-RAM banking (L1M = 4) and room in the
 ; buffer's first page. L1M is changed before the port, so an interrupt in
 ; between still returns with the port matching L1M. Like the original LOIN
 ; and HLOIN, this preserves X and Y but not A or the flags.
 STA KW_ARG
 LDA L1M
 CMP #4
 BNE KW_SLOW_SEGMENT
 LDA KW_WRITE+1
 CMP KW_BUF
 BNE KW_SLOW_SEGMENT
 LDA #5
 STA L1M
 LDA l1                ; %100 -> %101: I/O visible. ORA is idempotent, so an
 ORA #1                ; interrupt that has already applied L1M is harmless
 STA l1
 LDA #1
 STA KW_DIRTY
 STA $D03F
 LDA #0
 STA $D035
 LDA KW_WRITE
 STA $D039
 LDA KW_WRITE+1
 STA $D03A
 LDA KW_ARG
 STA $D03B
 LDA X1
 STA $D03B
 LDA Y1
 STA $D03B
 LDA X2
 STA $D03B
 LDA Y2
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 LDA $D039
 STA KW_WRITE
 LDA $D03A
 STA KW_WRITE+1
 LDA #4
 STA L1M
 LDA l1                ; back to all RAM (idempotent, as above)
 AND #%11111110
 STA l1
 RTS
.KW_SLOW_SEGMENT
 KW_SAVE
 JSR KW_OPEN
 LDA KW_ARG
.KW_SEGMENT
 STA $D03B
 LDA X1
 STA $D03B
 LDA Y1
 STA $D03B
 LDA X2
 STA $D03B
 LDA Y2
 STA $D03B
 LDA KW_COLOUR        ; per-command colour
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE
.KW_HLINE
 LDA KW_ACTIVE
 BEQ KW_HLINE_LEGACY
 LDA Y1
 CMP #144
 BCS KW_HLINE_LEGACY
 LDA #2
 JMP KW_FAST_SEGMENT
.KW_HLINE_LEGACY
 JMP KW_OLD_HLOIN
.KW_PIXEL
 PHA
 LDA KW_ACTIVE
 BEQ KW_PIXEL_LEGACY
 PLA
 KW_SAVE
 TSX
 LDA $0104,X          ; saved A (bank, Y, X, A above the caller's return)
 STA KW_ARG
 JSR KW_OPEN
 LDA #3
 STA $D03B
 TSX
 LDA $0103,X          ; saved X
 STA $D03B
 LDA KW_ARG
 STA $D03B
 LDA ZZ
 STA $D03B
 LDA KW_COLOUR
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE
.KW_PIXEL_LEGACY
 PLA
 JMP KW_OLD_PIXEL

; Select the colour for the current ship in TYPE. The space station is light
; blue; all other ships, including the player's Cobra, cargo and escape pods,
; are red.
.KW_SHIP_COLOUR
 LDA TYPE
 CMP #SST
 BEQ KW_SHIP_COLOUR_STATION
 LDA #KW_RED
 BNE KW_SHIP_COLOUR_STORE  ; always taken, as KW_RED is non-zero
.KW_SHIP_COLOUR_STATION
 LDA #KW_LIGHT_BLUE
.KW_SHIP_COLOUR_STORE
 STA KW_COLOUR
 RTS

; Planets are green, while suns are stars and stay white.
.KW_PLANET_COLOUR
 LDA TYPE
 AND #1
 BNE KW_PLANET_COLOUR_SUN
 LDA #KW_GREEN
 BNE KW_PLANET_COLOUR_STORE ; always taken, as KW_GREEN is non-zero
.KW_PLANET_COLOUR_SUN
 LDA #KW_WHITE
.KW_PLANET_COLOUR_STORE
 STA KW_COLOUR
 RTS

.KW_CHAR
 LDA L1M              ; KERNAL messages use its swapped zero page, not ours
 CMP #6
 BEQ KW_CHAR_DONE
 LDA KW_ACTIVE
 BEQ KW_CHAR_DONE
 LDA YC
 CMP #18
 BCS KW_CHAR_DONE
 KW_SAVE
 JSR KW_OPEN
 LDA #4
 STA $D03B
 LDA XC
 ASL A
 ASL A
 ASL A
 STA $D03B
 LDA YC
 ASL A
 ASL A
 ASL A
 STA $D03B
 LDA #1
 STA $D03B
 LDY #0
.KW_CHAR_ROW
 LDA (P+1),Y
 STA $D03B
 INY
 CPY #8
 BNE KW_CHAR_ROW
 JSR KW_CLOSE
 KW_RESTORE
.KW_CHAR_DONE
 RTS

.KW_DELETE
 KW_SAVE
 LDA XC
 ASL A
 ASL A
 STA KW_X
 LDA YC
 ASL A
 ASL A
 ASL A
 STA KW_Y
 LDA #4
 STA KW_DX
 LDA #8
 STA KW_DY
 JMP KW_CLEAR_BOX
.KW_TEXT_PAGE
 PHP
 PHA
 LDA L1M
 CMP #6
 BNE KW_TEXT_GAME
 PLA
 PLP
 RTS
.KW_TEXT_GAME
 PLA
 PLP
 KW_SAVE
 LDA #0
 STA KW_X
 LDA #8
 STA KW_Y
 LDA #128
 STA KW_DX
 LDA #136
 STA KW_DY
.KW_CLEAR_BOX
 LDA KW_ACTIVE
 BEQ KW_CLEAR_BOX_DONE
 JSR KW_OPEN
 LDA #8
 STA $D03B
 LDA KW_X
 STA $D03B
 LDA KW_Y
 STA $D03B
 LDA KW_DX
 STA $D03B
 LDA KW_DY
 STA $D03B
 JSR KW_CLOSE
.KW_CLEAR_BOX_DONE
 KW_RESTORE
.KW_UNBORDER
 KW_SAVE
 JSR KW_OPEN
 LDA #9
 STA $D03B
 JSR KW_CLOSE
 KW_RESTORE
.KW_CLEAR
 KW_SAVE
 LDA #KW_WHITE
 STA KW_COLOUR
 JSR KW_FLUSH
 LDA #0
 STA KW_ACTIVE
 LDA QQ11
 BEQ KW_CLEAR_SPACE
 CMP #1              ; mission briefings also contain rotating ships
 BEQ KW_CLEAR_SPACE
 CMP #3              ; the second hyperspace tunnel in a mis-jump
 BEQ KW_CLEAR_SPACE
 CMP #6              ; death/explosion scene
 BEQ KW_CLEAR_SPACE
 CMP #13
 BNE KW_CLEAR_DONE
.KW_CLEAR_SPACE
 INC KW_ACTIVE
 JSR KW_OPEN
 LDA #5
 STA $D03B
 JSR KW_CLOSE
.KW_CLEAR_DONE
 KW_RESTORE

.KW_PRESENT
 PHP
 PHA
 LDA KW_ACTIVE
 BEQ KW_PRESENT_DONE
 LDA KW_DIRTY
 BEQ KW_PRESENT_DONE
 PLA
 PLP
 KW_SAVE
 JSR KW_FLUSH
 PHP                   ; frame cap: wait until KW_MIN_FIELDS fields have passed
 PLA                   ; since the last frame (unless interrupts are off, when
 AND #%00000100        ; no fields are counted)
 BNE KW_CAP_DONE
.KW_CAP
 LDA KW_FIELDS
 SEC
 SBC KW_PRESENTED
 CMP #KW_MIN_FIELDS
 BCC KW_CAP
.KW_CAP_DONE
 ; At PAL 8 bytes/cycle the 23040-byte copy needs 2880 cycles (46 raster
 ; lines) and moves 3.15 image rows per line, so it outruns the beam. If
 ; the beam has passed image row 98 (raster 148) when the copy starts, the
 ; copy cannot catch it before the beam leaves row 143: every row is shown
 ; wholly old or wholly new this frame, and wholly new from the next. A
 ; start as late as raster 311 still finishes by raster 45, before the
 ; first visible row (raster 50). So start anywhere in rasters 152..311.
.KW_SAFE_RASTER
 BIT $D011
 BMI KW_RASTER_OK      ; rasters 256..311
 LDA $D012
 CMP #152
 BCC KW_SAFE_RASTER
.KW_RASTER_OK
 LDA KW_FIELDS
 STA KW_PRESENTED
 LDA #15
 STA $D03F
 LDA #0
 STA $D039
 STA $D03C
 STA $D035
 LDA #$80
 STA $D03A
 LDA #$20
 STA $D03D
 LDA #$5A
 STA $D036
 LDA #1
 STA $D03B
.KW_COPY_WAIT
 LDA $D036
 BNE KW_COPY_WAIT
 STA KW_DIRTY
 STA $D03F
 INC KW_FRAMES
 BNE KW_FRAME_COUNTED
 INC KW_FRAMES+1
.KW_FRAME_COUNTED
 KW_RESTORE
.KW_PRESENT_DONE
 PLA
 PLP
 RTS
.KW_FRAMES
 EQUW 0
.KW_BANK_NOIRQ
 ; Disk setup/teardown already has SEI set. Unlike SETL1, do not enable
 ; interrupts before the zero-page swap and IRQ configuration are complete.
 STA L1M
 LDA l1
 AND #$F8
 ORA L1M
 STA l1
 RTS
; DOEXP's cloud on the co-processor (command 13). A = flags: bit 3 project
; the ship and draw its new cloud, bit 7 also place the explosion sprite
; (PTCLS2). KW_EXFLAGS (bit 6) says whether the old cloud is on screen and
; must be erased first. The heap header (#0-#6) is the host's, as updated.
.KW_EXPLODE
 ORA KW_EXFLAGS
 BNE KW_EXPLODE_SEND
 RTS                   ; nothing on screen and nothing to draw
.KW_EXPLODE_SEND
 STA KW_EXFLAGS
 LDA K%+6              ; as PTCLS leaves it (it also stirs RAND and RAND+2,
 STA RAND+3            ; which now stay as they are)
 KW_SAVE
 LDA #13
 JSR KW_SHIP_BODY
 LDA KW_EXFLAGS
 STA $D03B
 LDY #0
.KW_EXPLODE_HEADER
 LDA (XX19),Y
 STA $D03B
 INY
 CPY #7
 BNE KW_EXPLODE_HEADER
 LDA sprx
 STA $D03B
 LDA spry
 STA $D03B
 JSR KW_CLOSE
 LDA KW_EXFLAGS
 BMI KW_EXPLODE_SPRITE
 JSR KW_KICK           ; start drawing while the host carries on
 JMP KW_EXPLODE_DONE
.KW_EXPLODE_SPRITE     ; once per explosion: wait for the sprite position
 JSR KW_FLUSH
 LDA #1
 STA $D03F
 LDA #0
 STA $D035
 STA $D039
 LDA #HI(KW_EX_RESULT)
 STA $D03A
 LDA $D03B             ; valid
 BEQ KW_EXPLODE_DONE
 LDY $D03B             ; x
 LDX $D03B             ; x high bit (0 or 1)
 LDA VIC+$10
 AND #%11111101
 ORA exlook,X
 STA VIC+$10
 LDA $D03B             ; y
 STA VIC+$3
 STY VIC+$2
 LDA VIC+$15
 ORA #%00000010
 STA VIC+$15
.KW_EXPLODE_DONE
 KW_RESTORE
.KW_EXFLAGS
 EQUB 0

.KW_LASPEND             ; a beam or military laser is on screen (MA23)
 EQUB 0

.KW_IRQ               ; COMIRQ1 has just turned hires off ($48, timing
 CPX #0                ; critical at the lower split); at the upper split
 BNE KW_IRQ_DONE       ; (raster 40, in the border) turn it on for the
 INC KW_FIELDS         ; VRAM views, and count the field for KW_PACE
 LDA KW_ACTIVE
 BEQ KW_IRQ_DONE
 LDA #$58
 STA $D037
.KW_IRQ_DONE
 RTS

; Exact unsigned multiply, performed by the host because the co-processor
; cannot access the math registers. MU11 remains for its separate callers.
.KW_MULT
 STY KW_ARG
 LDA L1M
 STA KW_BANK
 LDA #5
 JSR SETL1
 LDA #0
 STA $D02F
 STA $D031
 LDA P
 STA $D030
 LDA Q
 STA $D032
 LDA #0
 STA $D033
 LDA $D032
 STA P
 LDA $D031
 PHA
 LDA KW_BANK
 JSR SETL1
 PLA
 LDX #0
 LDY KW_ARG
 CLC
 RTS

; Compact legacy chart line path. Space/ship lines always use the 16MHz CPU.
; Eight-bit major-axis DDA with a hardware slope divide; one-bit plotting.
.KW_DRAM_LINE
 STY YSAV
 LDA X1
 STA KW_X
 LDA Y1
 STA KW_Y
 SEC
 LDA X2
 SBC X1
 BCS KW_DX_POS
 EOR #$FF
 ADC #1
.KW_DX_POS
 STA KW_DX
 SEC
 LDA Y2
 SBC Y1
 BCS KW_DY_POS
 EOR #$FF
 ADC #1
.KW_DY_POS
 STA KW_DY
 CMP KW_DX
 BCC KW_MAJOR_X
 LDA KW_DY
 LDX KW_DX
 LDY #1
 BNE KW_SLOPE_SETUP
.KW_MAJOR_X
 LDA KW_DX
 LDX KW_DY
 LDY #0
.KW_SLOPE_SETUP
 STA KW_COUNT
 STY KW_STEP
 LDA KW_COUNT
 BNE KW_HAVE_LINE
 LDY YSAV
 RTS
.KW_HAVE_LINE
 PHA
 LDA L1M
 STA KW_BANK
 LDA #5
 JSR SETL1
 PLA
 STA $D032
 STX $D02F
 LDA #0
 STA $D030
 STA $D031
 LDA #1
 STA $D033
 LDA $D032
 STA KW_SLOPE
 LDA $D031
 BEQ KW_SLOPE_OK
 LDA #255
 STA KW_SLOPE
.KW_SLOPE_OK
 LDA KW_BANK
 JSR SETL1
 LDA #128
 STA KW_ERR
.KW_DRAM_PLOT
 LDY KW_Y
 LDA KW_X
 AND #$F8
 CLC
 ADC ylookupl,Y
 STA SC
 LDA ylookuph,Y
 ADC #0
 STA SC+1
 TYA
 AND #7
 TAY
 LDA KW_X
 AND #7
 TAX
 LDA TWOS,X
 EOR (SC),Y
 STA (SC),Y
 DEC KW_COUNT
 BEQ KW_DRAM_RETURN
 LDA KW_ERR
 CLC
 ADC KW_SLOPE
 STA KW_ERR
 BCC KW_MAJOR_STEP
 LDA KW_STEP
 BEQ KW_MINOR_Y
 JSR KW_STEP_X
 JMP KW_MAJOR_STEP
.KW_MINOR_Y
 JSR KW_STEP_Y
.KW_MAJOR_STEP
 LDA KW_STEP
 BEQ KW_MAJOR_STEP_X
 JSR KW_STEP_Y
 JMP KW_DRAM_PLOT
.KW_MAJOR_STEP_X
 JSR KW_STEP_X
 JMP KW_DRAM_PLOT
.KW_DRAM_RETURN
 LDY YSAV
 RTS
.KW_STEP_X
 LDA X1
 CMP X2
 BCS KW_STEP_LEFT
 INC KW_X
 RTS
.KW_STEP_LEFT
 DEC KW_X
 RTS
.KW_STEP_Y
 LDA Y1
 CMP Y2
 BCS KW_STEP_UP
 INC KW_Y
 RTS
.KW_STEP_UP
 DEC KW_Y
 RTS


; MVEIT parts 2-7 for a ship, on the co-processor's urgent lane: write the
; arguments to MV_ARGS ($7FC0), set MV_URGENT ($7FF2), wait for it to clear
; and read the moved ship back from co-processor zero page ($0050). Queued
; drawing is not flushed, so it carries on around the movement job. The
; transfers are unrolled, as this runs for every ship on every frame.
.KW_MOVE
 LDY #15               ; maximum speed, read before KW_SAVE maps I/O over
 LDA (XX0),Y           ; the blueprints at $D000-$DFFF
 STA KW_ARG
 KW_SAVE
 JSR KW_KICK           ; start any queued drawing first
 LDA #1                ; auto-increment, register overlay off
 STA $D03F
 LDA #0
 STA $D035
 LDA #$C0
 STA $D039
 LDA #$7F
 STA $D03A
 FOR n, 0, 30
  LDA INWK+n
  STA $D03B
 NEXT
 LDA KW_SALPHA         ; our roll, pitch and speed, scaled to this frame
 STA $D03B
 LDA KW_SALP1
 STA $D03B
 LDA ALP2
 STA $D03B
 LDA ALP2+1
 STA $D03B
 LDA KW_SBETA
 STA $D03B
 LDA KW_SBET1
 STA $D03B
 LDA BET2
 STA $D03B
 LDA BET2+1
 STA $D03B
 LDA KW_SDELTA
 STA $D03B
 LDA KW_ARG            ; maximum speed
 STA $D03B
 LDA INWK+27           ; the ship's speed * 4, scaled to this frame (rounded)
 ASL A
 ASL A
 LDX KW_SFULL
 BNE KW_MOVE_SPEED
 JSR KW_MULS
 PHA
 LDA KW_PM
 ASL A
 PLA
 ADC #0
.KW_MOVE_SPEED
 STA $D03B
 LDA KW_ROTQ           ; its own rotation step
 STA $D03B
 LDA KW_DECCMP         ; whether its roll and pitch counters count down
 STA $D03B
 LDA #$F2
 STA $D039
 LDA #1
 STA $D03B             ; MV_URGENT = 1
 LDA #0                ; no auto-increment while polling
 STA $D03F
 LDA #$F2
 STA $D039
.KW_MOVE_WAIT
 LDA $D03B
 BNE KW_MOVE_WAIT
 LDA #1
 STA $D03F
 LDA #$50              ; the co-processor's mv_INWK
 STA $D039
 LDA #0
 STA $D03A
 LDX #0
.KW_MOVE_READ
 LDA $D03B             ; two bytes per iteration (31 = 15 * 2 + 1)
 STA INWK,X
 LDA $D03B
 STA INWK+1,X
 INX
 INX
 CPX #30
 BNE KW_MOVE_READ
 LDA $D03B
 STA INWK+30
 KW_RESTORE

; ******************************************************************************
;
; Real-time pacing
;
; The original game advances everything once per pass of the main loop, so
; with faster drawing it would simply play faster. Instead the game logic
; runs in game ticks at a fixed rate (KW_PACE_STEP, from "make pace=..."):
; on a tick frame (KW_TICK = $FF) the main loop does everything it did
; before, and between ticks (KW_TICK = 0) it only draws, scanning the keys
; and moving things by the fraction of a tick that the frame took. Motion
; therefore stays smooth at the higher frame rate while speeds, turning
; rates, timers, AI, energy, lasers and spawning keep the original's pace.
;
; KW_S is that fraction in 1/256 ticks, unless KW_SFULL is $80 (a whole tick,
; when every movement is done exactly as in the original). A frame never
; counts for more than one tick, so the game slows down as the original did
; if a frame takes longer than that.
;
; ******************************************************************************

.KW_FIELDS
 EQUB 0                ; PAL fields, counted by the raster interrupt
.KW_PACE_LAST
 EQUB 0                ; KW_FIELDS when KW_PACE last ran
.KW_PACE_STEP
 EQUW KW_PACE_INC      ; tick units per field (4096 = one tick); may be changed
.KW_ACC
 EQUW 0                ; tick units accumulated towards the next tick
.KW_AMT
 EQUW 0                ; tick units in this frame
.KW_TICK
 EQUB $FF              ; $FF when this frame is a game tick, 0 otherwise
.KW_S
 EQUB 0                ; this frame's share of a tick, in 1/256 ticks...
.KW_SFULL
 EQUB $80              ; ...unless this is $80 (a whole tick)
.KW_SREM
 EQUB 0                ; sixteenths of 1/256 tick carried into the next frame
.KW_PACED
 EQUB 0                ; nonzero when MLOOP has paced the frame for M%
.KW_PM
 EQUB 0                ; KW_MULS: product low byte
.KW_RES
 EQUB 0, 0, 0, 0       ; KW_SCALED: carried fractions (speed, roll, pitch, turn)
.KW_SDELTA
 EQUB 0                ; DELTA, scaled to this frame
.KW_SDELT4
 EQUW 0                ; DELT4, scaled to this frame
.KW_SALPHA
 EQUB 0                ; ALPHA and ALP1, scaled to this frame
.KW_SALP1
 EQUB 0
.KW_SBETA
 EQUB 0                ; BETA and BET1, scaled to this frame
.KW_SBET1
 EQUB 0
.KW_ROTQ
 EQUB $FF              ; ships' own rotation step ($FF: the original 1/16 rad)
.KW_DECCMP
 EQUB $7F              ; $7F on a tick (roll and pitch counters count down)
.KW_LASWAS
 EQUB 0                ; a beam or military laser was on screen last frame
.KW_PRESENTED
 EQUB 0                ; KW_FIELDS when the last frame was presented

; Measure the time since the last frame and decide whether it is a tick.
.KW_PACE
 LDA KW_FIELDS
 TAY
 SEC
 SBC KW_PACE_LAST
 STY KW_PACE_LAST
 TAX                   ; X = fields since the last frame
 LDA #0
 STA KW_AMT
 STA KW_AMT+1
 CPX #0
 BEQ KW_PACE_SPLIT
.KW_PACE_ADD
 CLC
 LDA KW_AMT
 ADC KW_PACE_STEP
 STA KW_AMT
 LDA KW_AMT+1
 ADC KW_PACE_STEP+1
 STA KW_AMT+1
 CMP #$10
 BCS KW_PACE_WHOLE     ; a whole tick or more: count it as one tick
 DEX
 BNE KW_PACE_ADD
 BEQ KW_PACE_SPLIT
.KW_PACE_WHOLE
 LDA #0
 STA KW_AMT
 LDA #$10
 STA KW_AMT+1
.KW_PACE_SPLIT
 LDA KW_AMT+1
 CMP #$10
 ROR A
 AND #%10000000
 STA KW_SFULL          ; $80 for a whole tick
 LDA KW_AMT            ; KW_S = (AMT + carried remainder) / 16, keeping the
 AND #%00001111        ; remainder in KW_SREM so that motion keeps exact time
 CLC                   ; with the ticks (a whole tick has none: AMT = 4096)
 ADC KW_SREM
 TAX
 AND #%00001111
 STA KW_SREM
 TXA
 LSR A
 LSR A
 LSR A
 LSR A                 ; 0 or 1, carried into the next 1/256 tick
 STA KW_S
 LDA KW_AMT+1
 ASL A
 ASL A
 ASL A
 ASL A
 ORA KW_S
 STA KW_S
 LDA KW_AMT
 LSR A
 LSR A
 LSR A
 LSR A
 CLC
 ADC KW_S
 BCC P%+4
 LDA #255              ; (just short of a whole tick)
 STA KW_S
 CLC                   ; KW_ACC += AMT, and a tick each time it reaches 4096
 LDA KW_ACC
 ADC KW_AMT
 STA KW_ACC
 LDA KW_ACC+1
 ADC KW_AMT+1
 LDX #0
 CMP #$10
 BCC KW_PACE_NOTICK
 SBC #$10
 DEX
.KW_PACE_NOTICK
 STA KW_ACC+1
 STX KW_TICK
 LDA #1
 STA KW_PACED
 RTS

; (A KW_PM) = A * KW_S, unsigned.
.KW_MULS
 STA KW_PM
 LDA #0
 LDX #8
 LSR KW_PM
.KW_MULS_LOOP
 BCC KW_MULS_SKIP
 CLC
 ADC KW_S
.KW_MULS_SKIP
 ROR A
 ROR KW_PM
 DEX
 BNE KW_MULS_LOOP
 RTS

; A = A scaled to this frame, carrying the fraction in KW_RES+Y so that the
; average over many frames is exact. Unchanged on a whole tick.
.KW_SCALED
 LDX KW_SFULL
 BNE KW_SCALED_DONE
 JSR KW_MULS
 PHA
 LDA KW_PM
 CLC
 ADC KW_RES,Y
 STA KW_RES,Y
 PLA
 ADC #0
.KW_SCALED_DONE
 RTS

; Our speed, roll and pitch for this frame, for the ship movement job, the
; stardust and the planet and sun (MVEIT's MV40 and MV45 paths).
.KW_MOTION
 LDA DELTA
 LDY #0
 JSR KW_SCALED
 STA KW_SDELTA
 LDA ALP1
 LDY #1
 JSR KW_SCALED
 STA KW_SALP1
 ORA ALP2
 STA KW_SALPHA
 LDA BET1
 LDY #2
 JSR KW_SCALED
 STA KW_SBET1
 ORA BET2
 STA KW_SBETA
 LDA KW_SFULL
 BEQ KW_MOTION_PART
 LDA DELT4
 STA KW_SDELT4
 LDA DELT4+1
 STA KW_SDELT4+1
 LDA #$FF              ; the original rotation step
 BNE KW_MOTION_ROT
.KW_MOTION_PART
 LDA DELT4+1
 JSR KW_MULS
 STA KW_SDELT4+1
 LDA KW_PM
 STA KW_SDELT4
 LDA DELT4
 JSR KW_MULS
 CLC
 ADC KW_SDELT4
 STA KW_SDELT4
 BCC P%+5
 INC KW_SDELT4+1
 LDA #16               ; 1/16 rad per tick, in 1/256 rad
 LDY #3
 JSR KW_SCALED
.KW_MOTION_ROT
 STA KW_ROTQ
 LDA KW_TICK
 AND #%01111111
 STA KW_DECCMP
 RTS

; ******************************************************************************
;
; Scene pacing
;
; The title screens, escape pod, mission briefing, launch and hyperspace
; tunnels and death screen each ran one step per frame in the original, at
; whatever frame rate the stock game managed for that scene (much faster
; than in flight for a single ship). So each of these steps at its own rate,
; the stock frame rate measured for the scene (KW_RATE_* in kawari-defs.asm,
; scaled by the pace), rather than at the flight tick rate. A frame takes
; as many steps as are due, so the frame cap does not slow them down, and
; each step is a whole original step (KW_WHOLE).
;
; ******************************************************************************

KW_SC_TITLE1 = 0
KW_SC_TITLE2 = 2
KW_SC_ESCAPE = 4
KW_SC_BRIEF1 = 6
KW_SC_BRIEF2 = 8
KW_SC_TUNNEL = 10
KW_SC_DEATH = 12

MACRO KW_SCENE_RATE rate
 ASSERT rate * KW_SCENE_UNIT < 61440   ; a field's worth must fit in 16 bits
 EQUW INT(rate * KW_SCENE_UNIT + 0.5)
ENDMACRO

.KW_SCENE_INC
 KW_SCENE_RATE KW_RATE_TITLE1
 KW_SCENE_RATE KW_RATE_TITLE2
 KW_SCENE_RATE KW_RATE_ESCAPE
 KW_SCENE_RATE KW_RATE_BRIEF1
 KW_SCENE_RATE KW_RATE_BRIEF2
 KW_SCENE_RATE KW_RATE_TUNNEL
 KW_SCENE_RATE KW_RATE_DEATH
.KW_SCENE_ACC
 EQUW 0                ; tick units towards the next step
.KW_SCENE_LAST
 EQUB 0                ; KW_FIELDS when KW_SCENE last ran
.KW_SCENE_N
 EQUB 0                ; steps due in this frame

; X = scene (KW_SC_*). Returns A = KW_SCENE_N = the number of steps due since
; the last call, with Z set if there are none. At most three fields count,
; so a scene does not jump ahead after a long pause or a slow frame.
.KW_SCENE
 LDA KW_FIELDS
 TAY
 SEC
 SBC KW_SCENE_LAST
 STY KW_SCENE_LAST
 CMP #4
 BCC P%+4
 LDA #3
 TAY
 LDA #0
 STA KW_SCENE_N
 CPY #0
 BEQ KW_SCENE_DONE
.KW_SCENE_ADD
 CLC                   ; add a field's worth...
 LDA KW_SCENE_ACC
 ADC KW_SCENE_INC,X
 STA KW_SCENE_ACC
 LDA KW_SCENE_ACC+1
 ADC KW_SCENE_INC+1,X
 PHA                   ; ...and move whole steps (4096 units) into KW_SCENE_N
 AND #%00001111
 STA KW_SCENE_ACC+1
 PLA
 LSR A
 LSR A
 LSR A
 LSR A
 CLC
 ADC KW_SCENE_N
 STA KW_SCENE_N
 DEY
 BNE KW_SCENE_ADD
.KW_SCENE_DONE
 LDA KW_SCENE_N
 RTS

; Make the following MVEIT calls whole original steps.
.KW_WHOLE
 LDA #$80
 STA KW_SFULL
 LDA #$FF
 STA KW_TICK
 JMP KW_MOTION

; TLL2 (the title screens): the ship approaches and turns one step at a time
; at the stock rate for the title's ship (the Cobra Mk III on the first
; title, the Adder on the second).
.KW_TITLE_MOVE
 LDX #KW_SC_TITLE1
 LDA TYPE
 CMP #CYL
 BEQ P%+4
 LDX #KW_SC_TITLE2
 JSR KW_SCENE
 BEQ KW_TITLE_DONE
 JSR KW_WHOLE
.KW_TITLE_STEP
 LDA INWK+7            ; bring the ship a step closer, down to z_hi = 1
 CMP #1
 BEQ P%+4
 DEC INWK+7
 JSR MVEIT
 DEC KW_SCENE_N
 BNE KW_TITLE_STEP
.KW_TITLE_DONE
 RTS

; HFL5 (the launch and hyperspace tunnels): wait for the next ring step.
.KW_TUNNELWAIT
 LDA KW_SCENE_N
 BNE KW_TUNNEL_DUE
 LDX #KW_SC_TUNNEL
 JSR KW_SCENE
 BEQ KW_TUNNELWAIT
.KW_TUNNEL_DUE
 DEC KW_SCENE_N
 RTS

; D2 (the death screen): count down LASCT one step at a time. Returns Z set
; when the sequence is over.
.KW_DEATH_COUNT
 LDX #KW_SC_DEATH
 JSR KW_SCENE
 BEQ KW_DEATH_MORE
.KW_DEATH_STEP
 DEC LASCT
 BEQ KW_DEATH_DONE
 DEC KW_SCENE_N
 BNE KW_DEATH_STEP
.KW_DEATH_MORE
 LDA #1
 RTS
.KW_DEATH_DONE
 STA KW_SCENE_N        ; (A = 0, Z set)
 RTS

; M% part 2, roll damping: pace this frame (unless MLOOP already has), then
; damp JSTX twice as the original did, but only on a game tick. Between
; ticks, the speed and in-system jump keys wait for the next tick.
.KW_CNTR2
 STX KW_ARG
 LDA KW_PACED
 BNE P%+5
 JSR KW_PACE
 LDA #0
 STA KW_PACED
 LDX KW_ARG
 LDA KW_TICK
 BNE KW_CNTR2_TICK
 STA KY1
 STA KY2
 STA KY18
 RTS
.KW_CNTR2_TICK
 JSR cntr
 JMP cntr

; M% part 2, pitch damping, on game ticks only.
.KW_CNTR
 LDA KW_TICK
 BEQ P%+5
 JMP cntr
 RTS

; M% part 3, before the laser logic: this frame's motion, then the laser.
; Beam and military lasers are erased here, a frame after they were drawn
; (MA23 defers it), so they are visible in every frame. Returns Z set to skip
; the original firing logic between game ticks: firing (heat, energy and
; hits) happens on ticks, but a beam that is still firing is redrawn in a new
; place every frame, as it was in every pass of the original's loop.
.KW_LASFR
 JSR KW_MOTION
 LDA KW_LASPEND
 STA KW_LASWAS
 BEQ KW_LASFR_TICK
 LDA #0
 STA KW_LASPEND
 JSR LASLI2
.KW_LASFR_TICK
 LDA KW_TICK
 BNE KW_LASFR_DONE     ; a tick: carry on with the original logic
 LDA KW_LASWAS
 BEQ KW_LASFR_SKIP
 LDA KY7
 BEQ KW_LASFR_SKIP
 LDA GNTMP
 CMP #242
 BCS KW_LASFR_SKIP
 LDX VIEW
 LDA LASER,X
 BEQ KW_LASFR_SKIP
 AND #%01111111        ; LAS2 makes MA23 defer the erase again; LAS stays 0,
 STA LAS2              ; so this does not hit anything
 JSR KW_LASDRAW
.KW_LASFR_SKIP
 LDA #0
.KW_LASFR_DONE
 RTS

; LASLI without heating the laser or draining energy.
.KW_LASDRAW
 JSR DORND
 AND #7
 ADC #Y-4
 STA LASY
 JSR DORND
 AND #7
 ADC #X-4
 STA LASX
 JMP LASLI2

; ESCAPE's loop (ESL1): our Cobra flies away for 97 steps.
.KW_ESCAPE_FLIGHT
 JSR KW_PRESENT
 LDX #KW_SC_ESCAPE
 JSR KW_SCENE
 BEQ KW_ESCAPE_DRAW
 JSR KW_WHOLE
.KW_ESCAPE_STEP
 JSR MVEIT
 DEC INWK+32
 BEQ KW_ESCAPE_END
 DEC KW_SCENE_N
 BNE KW_ESCAPE_STEP
.KW_ESCAPE_DRAW
 JSR LL9
 JMP KW_ESCAPE_FLIGHT
.KW_ESCAPE_END
 STA KW_SCENE_N        ; (A = 0)
 JMP LL9

; BRIEF's loops (BRL1, BRL2): the Constrictor turns for 64 steps, then
; moves away and up a step at a time until it is out of range.
.KW_BRIEF_SHIP
 JSR KW_PRESENT
 JSR LL9
 LDX #KW_SC_BRIEF1
 JSR KW_SCENE
 BEQ KW_BRIEF_SHIP
 JSR KW_WHOLE
.KW_BRIEF_TURN
 LDX #%01111111
 STX INWK+29
 STX INWK+30
 JSR MVEIT
 DEC MCNT
 BEQ KW_BRIEF_AWAY
 DEC KW_SCENE_N
 BNE KW_BRIEF_TURN
 BEQ KW_BRIEF_SHIP
.KW_BRIEF_AWAY
 JSR KW_PRESENT
 JSR LL9
 LDX #KW_SC_BRIEF2
 JSR KW_SCENE
 BEQ KW_BRIEF_AWAY
 JSR KW_WHOLE
.KW_BRIEF_STEP
 LSR INWK
 INC INWK+6
 BEQ KW_BRIEF_DONE
 INC INWK+6
 BEQ KW_BRIEF_DONE
 LDX INWK+3
 INX
 CPX #conhieght
 BCC P%+4
 LDX #conhieght
 STX INWK+3
 JSR MVEIT
 DEC MCNT
 DEC KW_SCENE_N
 BNE KW_BRIEF_STEP
 BEQ KW_BRIEF_AWAY
.KW_BRIEF_DONE
 LDA #0
 STA KW_SCENE_N
 RTS


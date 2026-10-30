; =============================================================================
; Lantern Moth
; NROM-256 (mapper 0, 32KB PRG + 8KB CHR), no extra chips. ca65 syntax.
;
;   lantern.s  reset, NMI, main loop, input, screen loading
;   player.s   moth movement, spirits, revives, moth sprites
;   trail.s    glowing trails and the loop (capture) pipeline
;   light.s    attribute lighting, palettes, flare
;   enemies.s  dust bunnies, cocoons, fireflies
;   game.s     stages, timer, score, lives, power-ups, HUD, banners
;   title.s    title screen with the attract-mode moth
;   sound.s    sound effects and jingles
; =============================================================================

.include "defs.inc"

.segment "HEADER"
    .byte "NES", $1A
    .byte 2             ; 2 x 16KB PRG
    .byte 1             ; 1 x 8KB CHR
    .byte $01           ; mapper 0, vertical mirroring
    .byte $00
    .res 8, 0

.include "vars.inc"

.segment "CODE"

; =============================================================================
reset:
    sei
    cld
    ldx #$40
    stx APUFRAME
    ldx #$FF
    txs
    inx                     ; X = 0
    stx PPUCTRL
    stx PPUMASK
    stx DMCFREQ
    bit PPUSTATUS
@vb1:
    bit PPUSTATUS
    bpl @vb1

    txa
@clr:
    sta $0000,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clr
    jsr hide_all_sprites

    jsr detect_region       ; also waits for the PPU to warm up
    jsr clear_nt1           ; (seen at the screen edge while it shakes)

    lda #$0F
    sta APUSTATUS           ; pulse 1, pulse 2, triangle, noise
    lda #$5A
    sta seed
    sta seed+1
    lda #CTRL_VAL
    sta PPUCTRL             ; NMI on from here

    jsr title_start
main_loop:
    jsr read_joy
    lda game_mode
    bne :+
    jsr title_frame
    jmp @sync
:   jsr play_frame
@sync:
    jsr wait_frame
    jmp main_loop

; wait_frame: hand this frame's shadows to the NMI and wait for it
wait_frame:
    lda #1
    sta nmi_ready
@w:
    lda nmi_ready
    bne @w
    rts

; detect_region: count loop passes between two vblanks. NTSC frames are
; 29780 cycles, PAL 33247. Each pass is 12 cycles, so the pass count's high
; byte is 9 on NTSC and 10 on PAL. Sets fps for the stage timer.
detect_region:
    bit PPUSTATUS
@sync:
    bit PPUSTATUS
    bpl @sync
    ldx #0
    ldy #0
@count:
    inx                     ; 2
    bne :+                  ; 3 (2 when wrapping)
    iny
:   bit PPUSTATUS           ; 4
    bpl @count              ; 3
    cpy #16                 ; missed a vblank (read race): try again
    bcs detect_region
    lda #60
    cpy #10
    bcc :+
    lda #50
:   sta fps
    rts

; =============================================================================
; NMI: must fit in vblank (~2270 cycles NTSC).
; OAM DMA 513 + queue 12*26 + HUD row ~270 + attributes ~520 + palette ~265
; + overhead ~80 => about 1960 worst case.
nmi:
    pha
    txa
    pha
    tya
    pha

    lda nmi_ready
    bne @upload
    lda loading
    bne :+
    inc lag_frames          ; main loop didn't finish in time (watch in Mesen)
:   jmp nmi_skip
@upload:
    lda #0
    sta OAMADDR
    lda #>oam
    sta OAMDMA

    bit PPUSTATUS
    ldx #0
@q:
    cpx vq_len
    beq @qdone
    lda vq_hi,x
    sta PPUADDR
    lda vq_lo,x
    sta PPUADDR
    lda vq_tile,x
    sta PPUDATA
    inx
    jmp @q
@qdone:

    lda hud_send
    bne :+
    jmp @no_hud
:   lda #$20
    sta PPUADDR
    lda #$20
    sta PPUADDR
    .repeat 32, I
        lda hud_buf+I
        sta PPUDATA
    .endrep
    lda #0
    sta hud_send
@no_hud:

    lda #$23
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    .repeat 64, I
        lda attr_shadow+I
        sta PPUDATA
    .endrep

    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    .repeat 32, I
        lda pal_shadow+I
        sta PPUDATA
    .endrep

    lda mask_val
    sta PPUMASK
    lda #CTRL_VAL               ; (+ nametable 1 when shaking left)
    ora scroll_nt
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda #0
    sta PPUSCROLL
nmi_ppu_end:                    ; all PPU writes done (must be inside vblank)
    lda #0
    sta vq_len
    sta nmi_ready
nmi_skip:
    lda paused                  ; sound runs here so lag frames and screen
    bne :+                      ; loads don't stretch the jingles
    jsr sound_update
:   inc frame
    pla
    tay
    pla
    tax
    pla
irq:
    rti

; =============================================================================
read_joy:
    lda #1
    sta JOY1
    lda #0
    sta JOY1
    ldx #0
@pl:
    lda joy,x
    sta joy_prev,x
    ldy #8
@bit:
    lda JOY1,x
    and #$03                ; standard pad on bit 0, Famicom expansion on bit 1
    cmp #1
    rol joy,x
    dey
    bne @bit
    lda joy_prev,x
    eor #$FF
    and joy,x
    sta joy_new,x
    inx
    cpx #MAX_PLAYERS
    bne @pl
    rts

; rand: 16-bit Galois LFSR (polynomial $0039), clocked 8 times at once -> A.
; Preserves X and Y. (Overlapped form from the NESdev wiki, ~70 cycles.)
rand:
    lda seed+1
    sta rand_t                  ; the original high byte
    lsr a
    lsr a
    lsr a
    sta seed+1
    lsr a
    eor seed+1
    lsr a
    eor seed+1
    eor seed
    sta seed+1
    lda rand_t
    sta seed
    asl a
    eor seed
    asl a
    eor seed
    asl a
    asl a
    asl a
    eor seed
    sta seed
    rts

; seed_rand: mix the frame counter in when a game starts, so each game plays
; out differently. The LFSR must never be all zeros.
seed_rand:
    lda frame
    eor seed
    sta seed
    ora seed+1
    bne :+
    lda #$5A
    sta seed
:   rts

hide_all_sprites:
    ldx #0
    lda #$FF
@h:
    sta oam,x
    inx
    inx
    inx
    inx
    bne @h
    rts

; =============================================================================
; Screen loading. The screen is switched off for a frame or two while a whole
; nametable is copied (960 bytes don't fit in a vblank).

screen_off:
    lda #0
    sta mask_val
    jsr wait_frame          ; next NMI turns rendering off
    lda #1
    sta loading
    rts

screen_on:
    lda #MASK_VAL
    sta mask_val
    lda #0
    sta loading
    rts                     ; the next wait_frame's NMI switches it back on

clear_nt1:
    bit PPUSTATUS
    lda #$24
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #4
    ldy #0
    lda #TILE_SPACE
@l:
    sta PPUDATA
    iny
    bne @l
    dex
    bne @l
    rts

; load_nametable: unpack the level at cur_map / cur_level into nametable 0,
; one tile at a time through level_tile_at. Rows 0-1 become the (blank) HUD
; rows; attributes start dark. Screen must be off (takes ~2 frames).
load_nametable:
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldy #64                 ; HUD rows: blank
    lda #TILE_SPACE
@blank:
    sta PPUDATA
    dey
    bne @blank
    lda #2
    sta tmp_cy
@row:
    lda #0
    sta tmp_cx
@cell:
    jsr level_tile_at
    sta PPUDATA
    inc tmp_cx
    lda tmp_cx
    cmp #32
    bne @cell
    inc tmp_cy
    lda tmp_cy
    cmp #30
    bne @row
    lda #0                  ; attribute table: all dark
    ldy #64
@attr:
    sta PPUDATA
    dey
    bne @attr
    rts

; =============================================================================
.include "player.s"
.include "trail.s"
.include "light.s"
.include "enemies.s"
.include "boss.s"
.include "game.s"
.include "title.s"
.include "sound.s"

.segment "RODATA"
.include "../gen/tables.inc"
.include "../gen/levels.inc"
.include "../gen/sound.inc"

set_bit:
    .byte $80, $40, $20, $10, $08, $04, $02, $01
clear_bit:
    .byte $7F, $BF, $DF, $EF, $F7, $FB, $FD, $FE

; =============================================================================
.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .incbin "../gen/lantern.chr"

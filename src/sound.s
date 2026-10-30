; =============================================================================
; Lantern Moth - sound
;   pulse 1: sound effects     pulse 2: jingles (gen/sound.inc)     noise: deaths
; =============================================================================

.segment "CODE"

; play_jingle: A = JG_* id
play_jingle:
    tax
    lda #0                      ; the NMI steps jingles: switch this one off
    sta jg_ptr+1                ; while its pointer is half written
    lda jingle_lo,x
    sta jg_ptr
    lda #1
    sta jg_timer
    lda jingle_hi,x
    sta jg_ptr+1                ; (high byte last: this turns it on)
    rts

; sound_update: once per frame (from the NMI), steps the jingle
sound_update:
    lda jg_ptr+1
    beq @done
    dec jg_timer
    bne @done
    ldy #0
    lda (jg_ptr),y
    cmp #$FF
    beq @stop
    tax
    iny
    lda (jg_ptr),y
    sta jg_timer
    lda jg_ptr
    clc
    adc #2
    sta jg_ptr
    bcc :+
    inc jg_ptr+1
:   txa
    beq @rest
    lda #$84                    ; 50% duty, decaying: a plucky note
    sta SQ2_VOL
    lda #$08                    ; no sweep
    sta SQ2_SWEEP
    lda note_lo,x
    sta SQ2_LO
    lda note_hi,x
    ora #$08
    sta SQ2_HI
    rts
@rest:
    lda #$30                    ; constant volume 0
    sta SQ2_VOL
    rts
@stop:
    lda #0
    sta jg_ptr+1
    lda #$30
    sta SQ2_VOL
@done:
    rts

; silence: all channels quiet (pause)
silence:
    lda #$30
    sta SQ1_VOL
    sta SQ2_VOL
    sta NOISE_VOL
    rts

; Pulse 1 one-shots. All preserve X and Y.
SFX_CAPTURE = 0
SFX_COLLECT = 1
SFX_REVIVE  = 2
SFX_TICK    = 3
SFX_APPEAR  = 4
SFX_DEATH   = 5
SFX_STEAL   = 6
SFX_BOSS    = 7
.segment "ZEROPAGE"
sfx_sx:     .res 1
.segment "CODE"

sfx_play:                       ; A = effect
    stx sfx_sx
    tax
    lda sfx_vol,x
    sta SQ1_VOL
    lda sfx_sweep,x
    sta SQ1_SWEEP
    lda sfx_lo,x
    sta SQ1_LO
    lda sfx_hi,x
    sta SQ1_HI
    ldx sfx_sx
    rts

sfx_capture:                    ; rising chime
    lda #SFX_CAPTURE
    beq sfx_play
sfx_collect:                    ; bright 'pling'
    lda #SFX_COLLECT
    bne sfx_play
sfx_revive:                     ; long rise
    lda #SFX_REVIVE
    bne sfx_play
sfx_tick:                       ; short blip
    lda #SFX_TICK
    bne sfx_play
sfx_appear:                     ; soft rise
    lda #SFX_APPEAR
    bne sfx_play
sfx_steal:                      ; the wisp drinks your light
    lda #SFX_STEAL
    bne sfx_play
sfx_boss_hit:                   ; big hit: rumble + fall
    lda #$0F
    sta NOISE_VOL
    lda #$0E
    sta NOISE_LO
    lda #$38
    sta NOISE_HI
    lda #SFX_BOSS
    bne sfx_play
sfx_chomp:                      ; beetle bites the trail (noise click)
    lda #$02
    sta NOISE_VOL
    lda #$04
    sta NOISE_LO
    lda #$08
    sta NOISE_HI
    rts
sfx_spit:                       ; web / tongue (noise hiss)
    lda #$03
    sta NOISE_VOL
    lda #$02
    sta NOISE_LO
    lda #$10
    sta NOISE_HI
    rts
sfx_death:                      ; falling tone + rumble
    lda #$06
    sta NOISE_VOL
    lda #$0C
    sta NOISE_LO
    lda #$18
    sta NOISE_HI
    lda #SFX_DEATH
    bne sfx_play

.segment "RODATA"
;              capture collect revive tick  appear death  steal  boss
sfx_vol:   .byte $84,   $82,    $86,   $81,  $83,   $86,   $85,   $8F
sfx_sweep: .byte $9A,   $8A,    $9B,   $08,  $8B,   $93,   $94,   $92
sfx_lo:    .byte $FD,   $A9,    $52,   $6A,  $1C,   $D5,   $70,   $FD
sfx_hi:    .byte $09,   $08,    $09,   $08,  $09,   $08,   $08,   $09
.segment "CODE"

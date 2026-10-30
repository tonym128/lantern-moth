; =============================================================================
; Lantern Moth - light
;
; Every 16x16 block gets one of four background palettes:
;   0 dark, 1 lit, 2 dim (edge of a light), 3 flare (a capture)
; Layers, bottom to top:
;   attr_keep    light that stays: the title logo, the stage-clear sweep
;   attr_base    attr_keep plus the current flare
;   moth light   each living moth lights blocks by distance (1 lit, 2 dim)
;   fireflies    each lights its own block
; Only the blocks near a moth are recalculated, and only when a moth moves to
; another block (or something sets light_dirty).
; =============================================================================

.segment "ZEROPAGE"
light_stage: .res 1             ; 1 = second half of a two-moth rebuild pending
light_rebuilt: .res 1           ; set on frames where the light was rebuilt
two_lights:  .res 1
.segment "CODE"

build_attrs:
    ; this frame's light sources: block of each living moth ($FF = none)
    ldx #0
@src:
    lda p_state,x
    cmp #PS_ALIVE
    bne @none
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_POSX,y
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    sta tmp
    lda plr+P_POSY,y
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    jmp @have
@none:
    lda #$FF
    sta tmp
    tay
@have:
    txa
    asl a
    stx tmp2
    tax                         ; X = 2p
    lda tmp
    cmp last_m,x
    beq :+
    sta last_m,x
    inc class_dirty
:   tya
    cmp last_m+1,x
    beq :+
    sta last_m+1,x
    inc class_dirty
:   ldx tmp2
    inx
    cpx #MAX_PLAYERS
    bne @src
    lda bloom
    cmp last_bloom
    beq :+
    sta last_bloom
    inc class_dirty
:   lda light_dirty
    ora class_dirty
    ora light_stage
    bne :+
    rts
:   lda search_done             ; a loop search already ran this frame:
    beq @rebuild                ; rebuild next frame instead (and the next
    lda #1                      ; search waits a frame for us)
    sta light_owed
    rts
@rebuild:
    lda #0
    sta light_owed
    lda light_stage             ; second half of a two-moth rebuild?
    bne @stage2
    lda #1
    sta light_rebuilt
    lda last_m                  ; bit 7 of two_lights = both moths shine
    and last_m+2
    eor #$FF
    sta two_lights
    lda #0
    sta light_dirty
    lda class_dirty
    beq @classes_done
    lda #0
    sta class_dirty
    jsr compute_classes
@classes_done:
    ldx #63
@copy:
    lda attr_base,x
    sta attr_work,x
    dex
    bpl @copy
    lda last_m                  ; moth 1's window
    cmp #$FF
    beq @m2
    sta mmx
    lda last_m+1
    sta mmy
    jsr light_window
    bit two_lights              ; both moths: finish next frame
    bpl @m2
    lda #1
    sta light_stage
    rts
@m2:
    lda last_m+2
    cmp #$FF
    beq @finish
    sta mmx
    lda last_m+3
    sta mmy
    jsr light_window
    jmp @finish
@stage2:
    lda #0
    sta light_stage
    lda #1
    sta light_rebuilt
    lda last_m+2
    cmp #$FF
    beq @finish
    sta mmx
    lda last_m+3
    sta mmy
    jsr light_window
@finish:
    jsr firefly_glow
    ldx #63
@out:
    lda attr_work,x
    sta attr_shadow,x
    dex
    bpl @out
    rts

; compute_classes: per moth, distance class of every block column / row:
; min(3, |block - moth block| + bloom). Only 5 entries near a moth are < 3.
compute_classes:
    ldx #31
    lda #3
@fill:
    sta cclass,x
    sta rclass,x
    dex
    bpl @fill
    ldy #0                      ; Y = 2 * moth
@moth:
    lda last_m,y
    cmp #$FF
    beq @next
    sty tmp2
    tya
    asl a
    asl a
    asl a
    sta tmp_b                   ; moth * 16
    lda last_m,y
    sta tmp_c
    lda last_m+1,y
    sta tmp_r
    tya                         ; dimmed?
    lsr a
    tax
    lda p_dim,x
    beq :+
    lda #1
:   sta tmp_age
    ldx #4                      ; offsets -2..+2
@d:
    lda dist_abs,x
    clc
    adc bloom
    adc tmp_age                 ; +1 while a wisp has stolen this moth's light
    cmp #3
    bcs @nd
    sta tmp_f
    txa                         ; column = moth column + offset
    clc
    adc tmp_c
    sec
    sbc #2
    cmp #16
    bcs :+
    adc tmp_b
    tay
    lda tmp_f
    sta cclass,y
:   txa                         ; row
    clc
    adc tmp_r
    sec
    sbc #2
    cmp #16
    bcs @nd
    adc tmp_b
    tay
    lda tmp_f
    sta rclass,y
@nd:
    dex
    bpl @d
    ldy tmp2
@next:
    iny
    iny
    cpy #2*MAX_PLAYERS
    bne @moth
    rts

; light_window: recalculate the attribute bytes within 2 blocks of (mmx, mmy)
light_window:
    lda mmx
    sec
    sbc #2
    bcs :+
    lda #0
:   lsr a
    sta ac_lo
    lda mmx
    clc
    adc #2
    cmp #16
    bcc :+
    lda #15
:   lsr a
    sta ac_hi
    lda mmy
    sec
    sbc #2
    bcs :+
    lda #0
:   lsr a
    sta ar
    lda mmy
    clc
    adc #2
    cmp #15
    bcc :+
    lda #14
:   lsr a
    sta ar_hi
@arow:
    lda ar
    asl a
    sta r0
    ora #1
    sta r1
    lda ac_lo
    sta ac
@acol:
    lda ar
    asl a
    asl a
    asl a
    ora ac
    tax                         ; attribute byte
    lda ac
    asl a
    sta c0
    ora #1
    sta c1
    lda attr_base,x
    sta tmp_b
    lda #0
    sta acc
    lda r0                      ; quadrants in bit order: TL, TR, BL, BR
    sta tmp_r
    ldy c0
    jsr quad
    ldy c1
    jsr quad
    lda r1
    sta tmp_r
    ldy c0
    jsr quad
    ldy c1
    jsr quad
    lda acc
    sta attr_work,x
    lda ac
    cmp ac_hi
    beq @row_done
    inc ac
    jmp @acol
@row_done:
    lda ar
    cmp ar_hi
    beq @done
    inc ar
    jmp @arow
@done:
    rts

; quad: Y = block column, tmp_r = block row. Merges the moths' light with the
; base layer for one quadrant and shifts it into acc. Preserves X.
quad:
    sty tmp_c
    lda cclass,y                ; moth 1: max(column class, row class)
    ldy tmp_r
    cmp rclass,y
    bcs :+
    lda rclass,y
:   bit two_lights
    bmi :+
    ldy last_m                  ; only one light: which one?
    cpy #$FF
    bne @one
    ldy tmp_c                   ; it's moth 2
    lda cclass+16,y
    ldy tmp_r
    cmp rclass+16,y
    bcs @one
    lda rclass+16,y
    jmp @one
:   sta tmp_f
    ldy tmp_c
    lda cclass+16,y             ; moth 2
    ldy tmp_r
    cmp rclass+16,y
    bcs :+
    lda rclass+16,y
:   cmp tmp_f                   ; nearest moth wins
    bcc :+
    lda tmp_f
:
@one:
    tay
    lda light_table,y           ; moth light: 0 dark, 1 lit, 2 dim
    sta tmp_f
    lda tmp_b                   ; base quadrant
    and #3
    asl a
    asl a
    ora tmp_f
    tay
    lda combine,y
    tay
    lsr tmp_b
    lsr tmp_b
    lsr acc
    lsr acc
    lda acc
    ora shl6,y
    sta acc
    rts

; firefly_glow: a dark block holding a firefly becomes lit
firefly_glow:
    ldx #3
@loop:
    jsr carries_light
    bcc @next
    lda en_y,x
    clc
    adc #4
    lsr a
    lsr a
    lsr a
    lsr a
    cmp #15
    bcs @next
    sta tmp
    and #1
    asl a
    sta tmp_c                   ; quadrant = (row & 1) * 2 + (col & 1)
    lda tmp
    lsr a
    asl a
    asl a
    asl a
    sta tmp
    lda en_x,x
    clc
    adc #4
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    and #1
    ora tmp_c
    sta tmp_c
    tya
    lsr a
    ora tmp
    tay
    stx edx
    ldx tmp_c
    lda attr_work,y
    and quad_mask,x
    bne :+
    lda attr_work,y
    ora quad_lit,x
    sta attr_work,y
:   ldx edx
@next:
    dex
    bpl @loop
    rts

; set_block_kept: A = block column, Y = block row. Makes it lit in the keep
; layer (and the base layer unless that block is flaring). C=1 if it changed.
set_block_kept:
    sta tmp_c
    tya
    and #1
    asl a
    sta tmp                     ; quadrant row part
    tya
    lsr a
    asl a
    asl a
    asl a
    sta tmp_r                   ; attribute row * 8
    lda tmp_c
    and #1
    ora tmp
    sta tmp                     ; quadrant
    lda tmp_c
    lsr a
    ora tmp_r
    tay                         ; attribute byte
    stx tmp2
    ldx tmp
    lda attr_keep,y
    and quad_mask,x
    bne @same
    lda attr_keep,y
    ora quad_lit,x
    sta attr_keep,y
    lda attr_base,y
    and quad_mask,x
    cmp quad_mask,x             ; flaring there? leave it
    beq :+
    lda attr_base,y
    and quad_clear,x
    ora quad_lit,x
    sta attr_base,y
:   lda #1
    sta light_dirty
    ldx tmp2
    sec
    rts
@same:
    ldx tmp2
    clc
    rts

; clear_light_layers: everything dark
clear_light_layers:
    ldx #63
    lda #0
@l:
    sta attr_keep,x
    sta attr_base,x
    sta attr_shadow,x
    dex
    bpl @l
    lda #1
    sta light_dirty
    sta class_dirty
    lda #0
    sta light_stage
    rts

; build_flare_base: attr_base = keep layer with palette 3 on every block of
; flare_meta (1 bit per block).
build_flare_base:
    lda #0
    sta fm_i
    ldx #0
@row:
    ldy fm_i
    lda flare_meta,y
    sta tmp_f
    lda flare_meta+2,y
    sta tmp_c
    jsr @four
    ldy fm_i
    lda flare_meta+1,y
    sta tmp_f
    lda flare_meta+3,y
    sta tmp_c
    jsr @four
    lda fm_i
    clc
    adc #4
    sta fm_i
    cpx #64
    bne @row
    rts
@four:
    lda #4
    sta tmp
@q:
    lda tmp_c                   ; bottom two blocks
    rol a
    rol a
    rol a
    and #3
    tay
    lda bottom_quads,y
    sta acc
    lda tmp_f                   ; top two blocks
    rol a
    rol a
    rol a
    and #3
    tay
    lda top_quads,y
    ora acc
    ora attr_keep,x
    sta attr_base,x
    inx
    asl tmp_f
    asl tmp_f
    asl tmp_c
    asl tmp_c
    dec tmp
    bne @q
    rts

; -----------------------------------------------------------------------------
; update_bloom: the light grows out of darkness at the start of a stage
update_bloom:
    lda bloom
    beq @done
    dec bloom_timer
    bne @done
    dec bloom
    lda #8
    sta bloom_timer
@done:
    rts

start_bloom:
    lda #3
    sta bloom
    lda #20
    sta bloom_timer
    rts

; -----------------------------------------------------------------------------
build_palette:
    ldx #31
@l:
    lda palette_rom,x
    sta pal_shadow,x
    dex
    bpl @l
    lda frame                   ; candle flicker on the glow colour
    lsr a
    lsr a
    and #7
    tax
    lda flicker_lit,x
    sta pal_shadow+7
    lda flicker_dim,x
    sta pal_shadow+11
    lda flare_timer             ; palette 3 = flare, bright then fading
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda flare_c1,x
    sta pal_shadow+13
    lda flare_c2,x
    sta pal_shadow+14
    lda flare_c3,x
    sta pal_shadow+15
    lda frame                   ; eyes in the dark and fireflies twinkle
    lsr a
    lsr a
    lsr a
    and #3
    tax
    lda twinkle,x
    sta pal_shadow+31
    rts

.segment "RODATA"

light_table:                    ; distance class -> palette
    .byte 1, 1, 2, 0
combine:                        ; [base quadrant * 4 + moth light] -> palette
    .byte 0, 1, 2, 0            ; base dark:  the moth's light shows
    .byte 1, 1, 1, 1            ; base lit:   stays lit
    .byte 2, 1, 2, 2            ; base dim:   a moth can brighten it
    .byte 3, 3, 3, 3            ; flare:      wins
shl6:
    .byte $00, $40, $80, $C0
dist_abs:
    .byte 2, 1, 0, 1, 2
quad_mask:
    .byte $03, $0C, $30, $C0
quad_clear:
    .byte $FC, $F3, $CF, $3F
quad_lit:                       ; palette 1 in each quadrant
    .byte $01, $04, $10, $40
top_quads:                      ; 2 block bits (left, right) -> TL/TR palette 3
    .byte $00, $0C, $03, $0F
bottom_quads:
    .byte $00, $C0, $30, $F0

palette_rom:
    ; background: colour 1 = back wall/rock base, 2 = rock detail, 3 = glow
    .byte $0F, $0F, $01, $27    ; 0 dark: back wall gone, rock is a faint hint
    .byte $0F, $07, $17, $38    ; 1 lit: back wall revealed
    .byte $0F, $0F, $07, $27    ; 2 dim: the soft edge of the light
    .byte $0F, $0F, $01, $27    ; 3 flare (set every frame)
    ; sprites
    .byte $0F, $16, $37, $30    ; 0 moth 1 (red/cream) / text / power-ups
    .byte $0F, $01, $10, $30    ; 1 moth 2 (blue/silver) / bunny lit / cocoon
    .byte $0F, $01, $00, $10    ; 2 dim enemies / spirits / sleeping mimic / threads
    .byte $0F, $0F, $0F, $28    ; 3 dark: eyes only / glow (twinkles)
flicker_lit:
    .byte $38, $38, $37, $38, $28, $38, $37, $38
flicker_dim:
    .byte $27, $27, $27, $17, $27, $27, $17, $27
twinkle:
    .byte $28, $38, $28, $27
flare_c1:
    .byte $0F, $07, $17, $27
flare_c2:
    .byte $07, $17, $27, $37
flare_c3:
    .byte $17, $28, $38, $30

.segment "CODE"

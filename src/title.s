; =============================================================================
; Lantern Moth - title screen
;
; The logo is built from level blocks. An attract-mode moth glides a fixed
; route around it; every logo block its light reaches
; stays lit, so the logo slowly lights up. Its route closes a loop around
; "MOTH", which flares gold. Bunnies wander the floor (harmless here).
; Once the whole logo is lit it stays a few seconds, then goes dark again.
;
; Up/Down/Select picks 1 or 2 players; Start begins.
; =============================================================================

.segment "ZEROPAGE"
logo_mx:    .res 1
logo_my:    .res 1

LOGO_HOLD  = 360            ; frames the fully lit logo stays lit

.segment "CODE"

title_start:
    lda #GM_TITLE
    sta game_mode
    lda #1
    sta num_players
    jsr screen_off
    jsr hide_all_sprites
    lda #TITLE_LEVEL
    sta cur_level
    tax
    lda lv_map_lo,x
    sta cur_map
    lda lv_map_hi,x
    sta cur_map+1
    jsr load_nametable
    jsr clear_light_layers
    jsr reset_trails
    lda #PS_ALIVE
    sta p_state
    lda #PS_OUT
    sta p_state+1
    lda #PW_SPEED|PW_CONTROL|PW_TAIL
    sta p_power
    jsr place_players
    lda #0
    sta p_invuln
    sta pw_state
    sta banner_on
    sta ai_wp
    sta logo_lit
    sta title_timer
    sta title_timer+1
    sta flare_timer
    jsr init_enemies
    jsr boss_init
    jsr start_bloom
    jsr draw_cursor_now
    lda #1
    sta hud_dirty
    jsr build_hud
    jsr build_attrs
    jsr build_palette
    jmp screen_on

title_frame:
    lda joy_new                 ; menu: player 1's pad
    and #BTN_START
    beq @no_start
    lda menu_sel
    clc
    adc #1
    sta num_players
    jsr seed_rand
    lda #JG_START
    jsr play_jingle
    jmp start_game
@no_start:
    lda joy_new
    and #BTN_UP|BTN_DOWN|BTN_SELECT
    beq @no_move
    lda menu_sel
    eor #1
    sta menu_sel
    jsr sfx_tick
    jsr queue_cursor
@no_move:
    jsr attract_ai
    lda #0
    sta controls_on
    lda #1
    sta enemies_on
    jsr world_update
    jsr light_logo
    jsr blink_start
    lda frame                   ; repaint the cursor now and then (a trail
    and #15                     ; dot may have been drawn over it)
    bne :+
    jsr queue_cursor
:   rts

; -----------------------------------------------------------------------------
; attract_ai: glide player 1 along the route at 2 px/frame (no physics: a
; smooth, even path keeps the loop around "MOTH" short enough to close).
attract_ai:
    ldx ai_wp
    lda wp_x,x
    sec
    sbc plr+P_POSX
    beq @x_done
    bcc @x_left
    cmp #2
    bcc :+
    lda #2
:   clc
    adc plr+P_POSX
    sta plr+P_POSX
    jmp @x_done
@x_left:
    cmp #$FE                    ; -1 or -2: go all the way
    bcs :+
    lda #$FE
:   clc
    adc plr+P_POSX
    sta plr+P_POSX
@x_done:
    lda wp_y,x
    sec
    sbc plr+P_POSY
    beq @y_done
    bcc @y_up
    cmp #2
    bcc :+
    lda #2
:   clc
    adc plr+P_POSY
    sta plr+P_POSY
    jmp @y_done
@y_up:
    cmp #$FE
    bcs :+
    lda #$FE
:   clc
    adc plr+P_POSY
    sta plr+P_POSY
@y_done:
    lda plr+P_POSX              ; arrived?
    cmp wp_x,x
    bne @flap
    lda plr+P_POSY
    cmp wp_y,x
    bne @flap
    inx
    cpx #WP_COUNT
    bcc :+
    ldx #WP_LOOP
:   stx ai_wp
@flap:
    lda frame                   ; flap the wings now and then
    and #15
    bne :+
    lda #FLAP_ANIM
    sta plr+P_FLAPA
:   rts

; light_logo: logo blocks within 2 blocks of the moth stay lit
light_logo:
    lda light_rebuilt           ; spread the work: not on a light-rebuild frame
    ora busy_frame
    beq :+
    rts
:   lda plr+P_POSX
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    sta mmx
    lda plr+P_POSY
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    sta mmy
    cmp logo_my                 ; only when the moth reaches a new block
    bne :+
    lda mmx
    cmp logo_mx
    bne :+
    jmp @check_done
:   lda mmx
    sta logo_mx
    lda mmy
    sta logo_my
    lda #4
    sta tmp_d                   ; dy + 2
@row:
    lda mmy
    clc
    adc tmp_d
    sec
    sbc #2
    cmp #15
    bcs @next_row
    sta r0
    lda #4
    sta tmp_b                   ; dx + 2
@col:
    lda mmx
    clc
    adc tmp_b
    sec
    sbc #2
    cmp #16
    bcs @next_col
    sta c0
    ; logo block? mask byte = row*2 + col/8
    lda r0
    asl a
    sta tmp
    lda c0
    lsr a
    lsr a
    lsr a
    ora tmp
    tax
    lda c0
    and #7
    tay
    lda logo_mask,x
    and set_bit,y
    beq @next_col
    lda c0
    ldy r0
    jsr set_block_kept
    bcc @next_col
    inc logo_lit
@next_col:
    dec tmp_b
    bpl @col
@next_row:
    dec tmp_d
    bpl @row
@check_done:
    ; fully lit: hold it, then start over in the dark
    lda logo_lit
    cmp #LOGO_BLOCKS
    bcc @done
    inc title_timer
    bne :+
    inc title_timer+1
:   lda title_timer
    cmp #<LOGO_HOLD
    lda title_timer+1
    sbc #>LOGO_HOLD
    bcc @done
    lda #$FF
    sta logo_mx                 ; re-check around the moth
    lda #0
    sta logo_lit
    sta title_timer
    sta title_timer+1
    ldx #63
@dark:
    sta attr_keep,x
    dex
    bpl @dark
    lda flare_timer
    bne :+
    ldx #63
@dark2:
    sta attr_base,x
    dex
    bpl @dark2
:   lda #1
    sta light_dirty
@done:
    rts

; blink_start: "PUSH START" on for 64 frames, off for 64 (5 tiles a frame)
blink_start:
    lda frame
    and #63
    cmp #2
    bcs @done
    sta tmp_d                   ; 0: first half, 1: second half
    lda frame
    and #64
    sta tmp_b
    lda tmp_d
    asl a
    sta tmp
    asl a
    asl a
    adc tmp                     ; *5... (0 or 10) / 2 below
    lsr a
    sta tmp                     ; 0 or 5
    lda #5
    sta tmp_f
@ch:
    ldx tmp
    lda str_push,x
    ldy tmp_b
    beq :+
    lda #TILE_SPACE
:   pha
    txa
    clc
    adc #11
    tax
    ldy #21
    pla
    jsr queue_tile_at
    inc tmp
    dec tmp_f
    bne @ch
@done:
    rts

queue_cursor:
    lda menu_sel
    eor #1                      ; the unselected line gets a blank
    clc
    adc #23
    tay
    ldx #10
    lda #TILE_SPACE
    jsr queue_tile_at
    lda menu_sel
    clc
    adc #23
    tay
    ldx #10
    lda #'>'
    jmp queue_tile_at

; draw_cursor_now: while the screen is off
draw_cursor_now:
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$EA                    ; row 23, column 10
    sta PPUADDR
    lda menu_sel
    beq :+
    lda #TILE_SPACE
    bne :++
:   lda #'>'
:   sta PPUDATA
    lda #$23
    sta PPUADDR
    lda #$0A                    ; row 24, column 10
    sta PPUADDR
    lda menu_sel
    bne :+
    lda #TILE_SPACE
    bne :++
:   lda #'>'
:   sta PPUDATA
    rts

.segment "RODATA"
str_push:
    .byte "PUSH START"
; attract route (moth top-left). After the last waypoint it goes back to WP_LOOP.
; Waypoints 4-8 fly a loop around "MOTH" of ~62 cells, so it closes before the
; 64-dot trail starts overwriting its own beginning. The only way between the
; top band and the rest is the gap right of "LANTERN" (x ~230).
wp_x:
    .byte 230, 230,  12, 230, 230,  28,  28, 206, 206, 110
wp_y:
    .byte  80,  26,  26,  26,  80,  80, 134, 134,  80,  80
WP_COUNT = 10
WP_LOOP  = 0
.segment "CODE"

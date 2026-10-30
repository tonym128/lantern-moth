; =============================================================================
; Lantern Moth - game flow
;
;   INTRO   "STAGE n / READY", light blooms in, nothing moves         (2s)
;   PLAY    the stage; timer counts down
;     all enemies collected -> CLEAR
;     no moth alive         -> DEAD
;     timer hits 0          -> TIMEUP
;   CLEAR   the whole cave lights up row by row, remaining time is paid out as
;           a bonus to every player still in, then the next stage starts with
;           the remaining time + 60s (max 99)
;   DEAD    (both moths down) a pause, then the stage restarts with the time it
;           started with - or GAME OVER if nobody has lives left
;   TIMEUP  everyone still in loses a life; the stage restarts with 60s
;   OVER    "GAME OVER", back to the title
;   (PLAY can be paused with Start: nothing moves, the picture goes grey)
;   END     after the last stage
; =============================================================================

TIME_BONUS = 5               ; tens of points per remaining second (50 pts)

.segment "ZEROPAGE"
controls_on: .res 1
enemies_on:  .res 1
clear_step:  .res 1

.segment "CODE"

; -----------------------------------------------------------------------------
; start_game: from the title. num_players is already set.
start_game:
    ldx #MAX_PLAYERS-1
@pl:
    lda #START_LIVES
    sta p_lives,x
    lda #0
    sta p_power,x
    sta p_invuln,x
    lda #PS_ALIVE
    cpx num_players
    bcc :+
    lda #PS_OUT
:   sta p_state,x
    dex
    bpl @pl
    ldx #11
    lda #0
@sc:
    sta p_score,x
    dex
    bpl @sc
    lda #GM_PLAY
    sta game_mode
    lda #0
    sta stage
    lda #STAGE_TIME
    sta time_sec
    sta stage_time
    jmp load_stage

; load_stage: (re)start `stage` with time_sec on the clock
load_stage:
    jsr screen_off
    jsr hide_all_sprites
    lda stage
    sta cur_level
    tax
    lda lv_map_lo,x
    sta cur_map
    lda lv_map_hi,x
    sta cur_map+1
    jsr load_nametable
    jsr clear_light_layers
    jsr reset_trails
    jsr init_enemies
    jsr boss_init
    jsr place_players
    jsr setup_power
    jsr start_bloom
    lda #0
    sta time_frac
    sta flare_timer
    sta paused
    lda #$FF
    sta last_m
    lda #PH_INTRO
    ldy #INTRO_TIME
    jsr set_phase
    jsr banner_stage
    lda #1
    sta hud_dirty
    jsr build_hud
    jsr build_attrs
    jsr build_palette
    jsr screen_on
    lda #JG_READY
    jmp play_jingle

; set_phase: A = phase, Y = frames
set_phase:
    sta phase
    sty phase_timer
    lda #0
    sta phase_timer+1
    sta clear_step
    rts

; -----------------------------------------------------------------------------
play_frame:
    ldx #MAX_PLAYERS-1          ; moths obey the pads
@pads:
    lda joy,x
    sta pads,x
    lda joy_new,x
    sta pads_new,x
    dex
    bpl @pads

    lda phase
    cmp #PH_PLAY
    bne @run
    lda joy_new                 ; Start (either pad) pauses and resumes
    ora joy_new+1
    and #BTN_START
    beq :+
    jsr toggle_pause
:   lda paused
    beq @run
    rts
@run:
    lda phase
    asl a
    tax
    lda phase_jump+1,x
    pha
    lda phase_jump,x
    pha
    rts

; toggle_pause: grey picture + PAUSE banner + silence, or back to play
toggle_pause:
    lda paused
    eor #1
    sta paused
    beq @resume
    jsr silence
    lda #MASK_VAL|$01           ; greyscale
    sta mask_val
    lda #<str_pause
    ldy #>str_pause
    jsr banner_line1
    jsr banner_no_line2
    jmp draw_banner
@resume:
    lda #MASK_VAL
    sta mask_val
    lda #0
    sta banner_on
    jmp draw_banner

phase_intro:
    lda #0
    sta controls_on
    sta enemies_on
    jsr world_update
    jsr count_down
    bne :+
    lda #0
    sta banner_on
    lda #PH_PLAY
    ldy #0
    jmp set_phase
:   rts

phase_play:
    lda #1
    sta controls_on
    sta enemies_on
    jsr world_update
    jsr update_power
    lda boss_type               ; cleared? (boss stages: when it's beaten)
    beq :+
    lda boss_dead
    beq @not_clear
    jmp enter_clear
:   lda en_left
    bne @not_clear
    jmp enter_clear
@not_clear:
    ldx #MAX_PLAYERS-1          ; anyone alive?
@alive:
    lda p_state,x
    cmp #PS_ALIVE
    beq @someone
    dex
    bpl @alive
    lda #PH_DEAD
    ldy #DEAD_TIME
    jmp set_phase
@someone:
    jmp tick_timer

phase_dead:
    lda #1
    sta controls_on
    sta enemies_on
    jsr world_update
    jsr count_down
    bne @wait
    jsr anyone_left
    bcc @over
    lda stage_time
    sta time_sec
    jmp load_stage
@over:
    jmp enter_over
@wait:
    rts

phase_timeup:
    lda #0
    sta controls_on
    sta enemies_on
    jsr world_update
    jsr count_down
    bne @wait
    jsr anyone_left
    bcc @over
    lda #STAGE_TIME
    sta time_sec
    sta stage_time
    jmp load_stage
@over:
    jmp enter_over
@wait:
    rts

phase_clear:
    lda #1
    sta controls_on
    lda #0
    sta enemies_on
    jsr world_update
    lda clear_step
    bne @tally
    ; step 0: the cave lights up one block row every 2 frames
    lda frame
    and #1
    bne @done
    lda sweep_row
    cmp #15
    bcs @sweep_done
    jsr light_row
    inc sweep_row
    rts
@sweep_done:
    inc clear_step
    lda time_sec
    sta tally
    rts
@tally:
    cmp #1
    bne @wait
    ; step 1: pay out the remaining seconds, one every 3 frames
    lda phase_timer
    beq :+
    dec phase_timer
    rts
:   lda #3
    sta phase_timer
    lda tally
    beq @tally_done
    dec tally
    ldx #MAX_PLAYERS-1
@pay:
    lda p_state,x
    beq @np
    lda #TIME_BONUS
    ldy #4                      ; tens
    jsr add_score
@np:
    dex
    bpl @pay
    jmp sfx_tick
@tally_done:
    inc clear_step
    lda #90
    sta phase_timer
    rts
@wait:
    jsr count_down              ; step 2: a moment to enjoy it
    bne @done
    inc stage
    lda stage
    cmp #STAGE_COUNT
    bcc :+
    jmp enter_end
:   lda time_sec                ; leftover time carries over, plus a fresh 60s
    clc
    adc #STAGE_TIME
    cmp #MAX_TIME+1
    bcc :+
    lda #MAX_TIME
:   sta time_sec
    sta stage_time
    jmp load_stage
@done:
    rts

phase_over:
    lda #0
    sta controls_on
    sta enemies_on
    jsr hide_all_sprites
    jsr draw_banner
    jsr count_down
    bne :+
    jsr update_hi_score
    jmp title_start
:   rts

phase_end:
    lda #1
    sta controls_on
    lda #0
    sta enemies_on
    jsr world_update
    jsr count_down
    bne :+
    jsr update_hi_score
    jmp title_start
:   rts

phase_jump:
    .word phase_intro-1, phase_play-1, phase_dead-1, phase_timeup-1
    .word phase_clear-1, phase_over-1, phase_end-1

; count_down: phase_timer--; Z=1 when it reaches 0
count_down:
    lda phase_timer
    ora phase_timer+1
    beq @zero
    lda phase_timer
    bne :+
    dec phase_timer+1
:   dec phase_timer
    lda phase_timer
    ora phase_timer+1
@zero:
    rts

; anyone_left: C=1 if any player still has lives (state not OUT)
anyone_left:
    ldx #MAX_PLAYERS-1
@l:
    lda p_state,x
    bne @yes
    dex
    bpl @l
    clc
    rts
@yes:
    sec
    rts

enter_clear:
    lda #0
    sta scroll_x
    sta scroll_nt
    sta web_t
    lda #PH_CLEAR
    ldy #0
    jsr set_phase
    lda #1
    sta sweep_row               ; row 0 is the HUD
    lda #0
    sta pw_state
    lda #<str_clear
    ldy #>str_clear
    jsr banner_line1
    jsr banner_no_line2
    lda #JG_CLEAR
    jmp play_jingle

enter_over:
    lda #PH_OVER
    ldy #OVER_TIME
    jsr set_phase
    lda #<str_game
    ldy #>str_game
    jsr banner_line1
    lda #<str_over
    ldy #>str_over
    jsr banner_line2
    lda #JG_GAMEOVER
    jmp play_jingle

enter_end:
    lda #PH_END
    ldy #<END_TIME
    jsr set_phase
    lda #>END_TIME
    sta phase_timer+1
    lda #<str_theend
    ldy #>str_theend
    jsr banner_line1
    lda #<str_welldone
    ldy #>str_welldone
    jsr banner_line2
    lda #JG_END
    jmp play_jingle

; tick_timer: one second every `fps` frames
tick_timer:
    inc time_frac
    lda time_sec                ; low on time: the HUD digits blink
    cmp #LOW_TIME+1
    bcs :+
    lda fps
    lsr a
    cmp time_frac
    bne :+
    lda #1
    sta hud_dirty
:   lda time_frac
    cmp fps
    bcc @done
    lda #0
    sta time_frac
    lda time_sec
    beq @done
    dec time_sec
    lda #1
    sta hud_dirty
    lda time_sec
    beq @timeup
    cmp #LOW_TIME+1
    bcs @done
    jmp sfx_tick
@timeup:
    ldx #MAX_PLAYERS-1          ; one life each for running out of time
@lose:
    lda p_state,x
    beq @nl
    lda #0
    sta p_power,x
    dec p_lives,x
    bne @nl
    lda #PS_OUT
    sta p_state,x
@nl:
    dex
    bpl @lose
    lda #PH_TIMEUP
    ldy #TIMEUP_TIME
    jsr set_phase
    lda #<str_time
    ldy #>str_time
    jsr banner_line1
    lda #<str_up
    ldy #>str_up
    jsr banner_line2
    lda #JG_TIMEUP
    jmp play_jingle
@done:
    rts

; light_row: stage clear sweep - every block of row sweep_row becomes lit
light_row:
    lda #15
    sta tmp_d
@b:
    lda tmp_d
    ldy sweep_row
    jsr set_block_kept
    dec tmp_d
    bpl @b
    rts

; -----------------------------------------------------------------------------
; world_update: everything that moves, then everything that's drawn.
world_update:
    lda #0
    sta light_rebuilt
    sta busy_frame
    sta search_done
    jsr update_loops
    jsr update_flare
    ldx #0
@pl:
    lda p_state,x
    cmp #PS_ALIVE
    bne @spirit
    jsr load_player
    lda controls_on
    beq :+
    jsr update_moth
:   jsr add_trail
    jsr save_player
    jmp @next
@spirit:
    cmp #PS_SPIRIT
    bne @next
    jsr load_player
    jsr update_spirit
    jsr save_player
@next:
    inx
    cpx #MAX_PLAYERS
    bne @pl
    jsr check_revive
    lda enemies_on
    beq :+
    jsr update_enemies
    jsr boss_update
:   jsr update_trail
    jsr update_bloom
    jsr tick_invuln
    lda busy_frame
    bne :+
    jsr build_attrs
:
    jsr build_palette
    jsr build_moth_oam
    jsr build_enemy_oam
    jsr draw_power
    jsr draw_banner
    lda hud_dirty
    beq :+
    jsr build_hud
:   rts

; -----------------------------------------------------------------------------
; add_score: X = player, A = amount (0-99), Y = digit (0 = 100000s .. 5 = 1s).
; Preserves X. Caps at 999999.
add_score:
    sta tmp_f
    stx tmp2
    sty tmp
    txa
    asl a
    sta tmp_b
    asl a
    adc tmp_b                   ; player * 6
    adc tmp
    tax
    lda tmp_f
@add:
    clc
    adc p_score,x
    ldy #0
@norm:
    cmp #10
    bcc @store
    sbc #10
    iny
    bne @norm
@store:
    sta p_score,x
    tya
    beq @done
    dec tmp                     ; carry into the next digit up
    bmi @cap
    dex
    jmp @add
@cap:
    ldy #5
    lda #9
:   sta p_score,x
    inx
    dey
    bpl :-
@done:
    lda #1
    sta hud_dirty
    ldx tmp2
    rts

update_hi_score:
    ldx #0
@pl:
    stx tmp2
    txa
    asl a
    sta tmp
    asl a
    adc tmp
    sta tmp                     ; player * 6
    tay
    ldx #0
@cmp:
    lda p_score,y
    cmp hi_score,x
    bcc @next                   ; lower: not a new hi score
    bne @copy                   ; higher: it is
    iny
    inx
    cpx #6
    bne @cmp
    beq @next
@copy:
    ldy tmp
    ldx #0
:   lda p_score,y
    sta hi_score,x
    iny
    inx
    cpx #6
    bne :-
@next:
    ldx tmp2
    inx
    cpx #MAX_PLAYERS
    bne @pl
    rts

; -----------------------------------------------------------------------------
; HUD (nametable row 1). Column 0 is left blank: TVs (and many emulators) crop it.
;    1P000000&3SCT 60 2P000000&3SCT
build_hud:
    lda #0
    sta hud_dirty
    ldx #31
    lda #TILE_SPACE
@clr:
    sta hud_buf,x
    dex
    bpl @clr
    lda game_mode
    bne @play
    ldx #0                      ; title: hi score
@hi:
    lda str_hi,x
    sta hud_buf+11,x
    inx
    cpx #3
    bne @hi
    ldx #0
:   lda hi_score,x
    ora #'0'
    sta hud_buf+14,x
    inx
    cpx #6
    bne :-
    jmp @send
@play:
    ldx #0
    jsr @player
    lda num_players
    cmp #2
    bcc :+
    ldx #1
    jsr @player
:   lda time_sec                ; time in the middle
    ldx #0
@tens:
    cmp #10
    bcc :+
    sbc #10
    inx
    bne @tens
:   ora #'0'
    sta hud_buf+16
    txa
    ora #'0'
    sta hud_buf+15
    lda time_sec                ; low on time: blank for the second half
    cmp #LOW_TIME+1             ; of every second
    bcs @send
    lda phase
    cmp #PH_PLAY
    bne @send
    lda fps
    lsr a
    sta tmp
    lda time_frac
    cmp tmp
    bcc @send
    lda #TILE_SPACE
    sta hud_buf+15
    sta hud_buf+16
@send:
    lda #1
    sta hud_send
    rts
@player:                        ; X = player
    lda hud_col,x
    tay
    txa
    clc
    adc #'1'
    sta hud_buf,y
    lda #'P'
    sta hud_buf+1,y
    stx tmp2
    txa
    asl a
    sta tmp
    asl a
    adc tmp
    tax
    lda #6
    sta tmp
:   lda p_score,x
    ora #'0'
    sta hud_buf+2,y
    inx
    iny
    dec tmp
    bne :-
    ldx tmp2                    ; Y = col + 6
    lda #'&'
    sta hud_buf+2,y
    lda p_lives,x
    ora #'0'
    sta hud_buf+3,y
    lda p_power,x
    lsr a
    bcc :+
    pha
    lda #'S'
    sta hud_buf+4,y
    pla
:   lsr a
    bcc :+
    pha
    lda #'C'
    sta hud_buf+5,y
    pla
:   lsr a
    bcc :+
    lda #'T'
    sta hud_buf+6,y
:   rts

; -----------------------------------------------------------------------------
; Banners: two centred lines of sprite text (up to 10 chars each).
banner_stage:
    ldx #0
:   lda str_stage,x
    sta banner_buf,x
    inx
    cpx #6
    bne :-
    lda stage                   ; stage number, 1 or 2 digits (up to 99)
    clc
    adc #1
    ldx #6
    ldy #0                      ; tens
@tens:
    cmp #10
    bcc @ones
    sbc #10
    iny
    bne @tens
@ones:
    pha
    tya
    beq :+
    ora #'0'
    sta banner_buf,x
    inx
:   pla
    ora #'0'
    sta banner_buf,x
    lda #0
    sta banner_buf+1,x
    ldx cur_level
    lda lv_boss,x
    beq :+
    lda #<str_boss
    ldy #>str_boss
    bne @line2
:   lda #<str_ready
    ldy #>str_ready
    cpx #0                      ; the first stage says what to do
    bne @line2
    lda #<str_hint
    ldy #>str_hint
@line2:
    jsr banner_line2
    lda #1
    sta banner_on
    rts

; banner_line1/2: A/Y = pointer to a 0-terminated string
banner_line1:
    ldx #0
    beq banner_copy
banner_line2:
    ldx #10
banner_copy:
    sta ptr2
    sty ptr2+1
    ldy #0
@c:
    lda (ptr2),y
    sta banner_buf,x
    beq @done
    inx
    iny
    cpy #10
    bne @c
@done:
    lda #1
    sta banner_on
    rts

banner_no_line2:
    lda #0
    sta banner_buf+10
    rts

draw_banner:
    ldy #OAM_BANNER
    lda banner_on
    beq @hide
    lda #0
    sta tmp_d                   ; line
@line:
    lda tmp_d                   ; length
    beq :+
    lda #10
:   sta tmp_b                   ; start index
    tax
    lda #0
    sta tmp
@len:
    lda banner_buf,x
    beq @have
    inc tmp
    inx
    lda tmp
    cmp #10
    bne @len
@have:
    lda tmp                     ; x = 128 - len*4
    asl a
    asl a
    sta tmp_c
    lda #128
    sec
    sbc tmp_c
    sta tmp_c
    ldx tmp_b
@ch:
    lda tmp
    beq @next_line
    dec tmp
    lda banner_buf,x
    cmp #' '
    beq @skip
    sta oam+1,y
    lda tmp_d
    asl a
    asl a
    asl a
    asl a
    adc #99
    sta oam,y
    lda #0
    sta oam+2,y
    lda tmp_c
    sta oam+3,y
    iny
    iny
    iny
    iny
@skip:
    lda tmp_c
    clc
    adc #8
    sta tmp_c
    inx
    jmp @ch
@next_line:
    inc tmp_d
    lda tmp_d
    cmp #2
    bne @line
@hide:
    lda #$FF
:   cpy #OAM_BANNER+64
    bcs @done
    sta oam,y
    iny
    iny
    iny
    iny
    bne :-
@done:
    rts

; -----------------------------------------------------------------------------
; Power-ups: one appears a while into each stage at one of the level's 'p'
; spots; team loops drop one too. Whoever grabs it keeps it until they lose a
; life (extra lives are instant).
setup_power:
    lda #0
    sta pw_state
    ldx cur_level
    lda lv_npw,x
    beq @none
    sta tmp
    jsr rand
    and #3
:   cmp tmp
    bcc :+
    sbc tmp
    jmp :-
:   sta tmp
    txa
    asl a
    asl a
    ora tmp
    tay
    lda lv_pw_x,y
    sta pw_x
    lda lv_pw_y,y
    sta pw_y
    lda #1
    sta pw_state
    lda #POWER_DELAY
    sta pw_timer
    lda #0
    sta pw_sub
@none:
    rts

update_power:
    lda pw_state
    bne :+
    rts
:   inc pw_sub
    lda pw_sub
    cmp #15
    bcc @check
    lda #0
    sta pw_sub
    dec pw_timer
    bne @check
    lda pw_state
    cmp #1
    bne @expire
    jsr appear_power            ; it's time
    jmp @check
@expire:
    lda #0
    sta pw_state
    rts
@check:
    lda pw_state
    cmp #2
    bne @done
    lda pw_x
    sta ex0
    clc
    adc #8
    sta ex1
    lda pw_y
    sta ey0
    clc
    adc #8
    sta ey1
    ldx #0
@moth:
    lda p_state,x
    cmp #PS_ALIVE
    bne @nm
    jsr moth_box_x
    jsr box_overlap
    bcs @got
@nm:
    inx
    cpx #MAX_PLAYERS
    bne @moth
@done:
    rts
@got:
    lda #0
    sta pw_state
    ldy pw_type
    cpy #3
    beq @life
    lda p_power,x
    ora power_bit,y
    sta p_power,x
    jmp @score
@life:
    lda p_lives,x
    cmp #MAX_LIVES
    bcs @score
    inc p_lives,x
@score:
    lda #5                      ; 500 points
    ldy #3
    jsr add_score
    lda #JG_POWER
    jmp play_jingle

appear_power:
    jsr rand
    and #7
    tay
    lda power_types,y
    sta pw_type
    lda #2
    sta pw_state
    lda #POWER_LIFE
    sta pw_timer
    lda #0
    sta pw_sub
    jmp sfx_appear

; team_power_drop: a power-up in the middle of a team loop
team_power_drop:
    lda game_mode
    cmp #GM_PLAY
    bne @no
    lda pw_state
    cmp #2
    beq @no                     ; one already out there
    lda ls_minx
    clc
    adc ls_maxx
    lsr a
    sta tmp_cx
    lda ls_miny
    clc
    adc ls_maxy
    lsr a
    sta tmp_cy
    lda #4                      ; inside rock? move up until it isn't
    sta tmp_d
@air:
    jsr level_tile_at
    tay
    lda solid_tab,y
    beq @ok
    dec tmp_cy
    dec tmp_d
    bne @air
@ok:
    lda tmp_cx
    asl a
    asl a
    asl a
    sta pw_x
    lda tmp_cy
    asl a
    asl a
    asl a
    sta pw_y
    jmp appear_power
@no:
    rts

draw_power:
    ldy #OAM_POWER
    lda pw_state
    cmp #2
    bne @hide
    lda pw_timer                ; blink before it goes
    cmp #POWER_WARN
    bcs :+
    lda frame
    and #8
    bne @hide
:   lda frame                   ; bob
    lsr a
    lsr a
    lsr a
    and #3
    tax
    lda pw_y
    clc
    adc bob_table,x
    sec
    sbc #1
    sta oam,y
    lda pw_type
    ora #$10
    sta oam+1,y
    lda #0
    sta oam+2,y
    lda pw_x
    sta oam+3,y
    lda frame                   ; sparkle circling it
    lsr a
    lsr a
    and #7
    tax
    lda pw_y
    clc
    adc orbit_y,x
    sta oam+4,y
    lda #$14
    sta oam+5,y
    lda #3
    sta oam+6,y
    lda pw_x
    clc
    adc orbit_x,x
    sta oam+7,y
    rts
@hide:
    lda #$FF
    sta oam,y
    sta oam+4,y
    rts

.segment "RODATA"
hud_col:
    .byte 1, 18
power_types:                    ; speed, control, tail, life (life is rarer)
    .byte 0, 1, 2, 0, 1, 2, 3, 2
power_bit:
    .byte PW_SPEED, PW_CONTROL, PW_TAIL
orbit_x:
    .byte 0, 6, 9, 6, 0, $FA, $F7, $FA
orbit_y:
    .byte $F6, $F9, $FF, 5, 7, 5, $FF, $F9
str_hi:      .byte "HI "
str_stage:   .byte "STAGE "
str_ready:   .byte "READY", 0
str_hint:    .byte "LOOP ALL!", 0           ; (8 sprites: the NES shows 8 per line)
str_pause:   .byte "PAUSE", 0
str_boss:    .byte "BOSS!", 0
str_clear:   .byte "CLEAR!", 0
str_time:    .byte "TIME", 0
str_up:      .byte "UP!", 0
str_game:    .byte "GAME", 0
str_over:    .byte "OVER", 0
str_theend:  .byte "THE END", 0
str_welldone:.byte "WELL DONE", 0
.segment "CODE"

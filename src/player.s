; =============================================================================
; Lantern Moth - players
;
; Each moth's movement state lives in plr[p*16]. Before a moth is updated its
; block is copied into the zero-page `pblock` (load_player) and afterwards
; copied back (save_player), so the movement and trail code only ever deals
; with "the current moth".
; =============================================================================

P_POSX   = pos_x - pblock       ; offsets inside a saved block
P_POSY   = pos_y - pblock
P_VXLO   = vx_lo - pblock
P_VXHI   = vx_hi - pblock
P_VYLO   = vy_lo - pblock
P_VYHI   = vy_hi - pblock
P_LASTCX = last_cx - pblock
P_LASTCY = last_cy - pblock
P_HEAD   = trail_head - pblock
P_FLAPA  = flap_anim - pblock

.segment "CODE"

; load_player: X = player. Copies its block in and sets up its physics.
load_player:
    stx cur_p
    txa
    asl a
    asl a
    asl a
    asl a
    tay                         ; Y = p*16
    ldx #0
@cp:
    lda plr,y
    sta pblock,x
    iny
    inx
    cpx #PB_SIZE
    bne @cp
    ldx cur_p
    lda trail_off,x
    sta toff
    lda pads,x
    sta pad
    lda pads_new,x
    sta pad_new
    ; physics from power-ups
    lda p_power,x
    sta tmp
    and #PW_CONTROL
    beq @no_ctrl
    lda #ACC_C
    sta c_acc
    lda #FRIC_C
    sta c_fric
    lda #<FLAP_C
    sta c_flap_lo
    lda #>FLAP_C
    sta c_flap_hi
    lda #FLAPT_C
    sta c_flapt
    jmp @speed
@no_ctrl:
    lda tmp
    and #PW_SPEED
    beq :+
    lda #ACC_S
    bne :++
:   lda #ACC_N
:   sta c_acc
    lda #FRIC_N
    sta c_fric
    lda #<FLAP_N
    sta c_flap_lo
    lda #>FLAP_N
    sta c_flap_hi
    lda #FLAPT_N
    sta c_flapt
@speed:
    lda tmp
    and #PW_SPEED
    beq @slow
    lda #<MAX_S
    sta c_max_lo
    lda #>MAX_S
    sta c_max_hi
    lda #<(-MAX_S)
    sta c_nmax_lo
    lda #>(-MAX_S)
    sta c_nmax_hi
    jmp webbed
@slow:
    lda #<MAX_N
    sta c_max_lo
    lda #>MAX_N
    sta c_max_hi
    lda #<(-MAX_N)
    sta c_nmax_lo
    lda #>(-MAX_N)
    sta c_nmax_hi
    ; fall through
; webbed: half speed, half steering
webbed:
    ldx cur_p
    lda p_slow,x
    beq @free
    lsr c_max_hi
    ror c_max_lo
    sec                         ; -max / 2 (stays negative)
    ror c_nmax_hi
    ror c_nmax_lo
    lsr c_acc
@free:
    rts

save_player:
    lda cur_p
    asl a
    asl a
    asl a
    asl a
    tay
    ldx #0
@cp:
    lda pblock,x
    sta plr,y
    iny
    inx
    cpx #PB_SIZE
    bne @cp
    ldx cur_p
    rts

; -----------------------------------------------------------------------------
; update_moth: steer, flap, fall, move. Works on the loaded player.
update_moth:
    lda pad
    and #BTN_LEFT
    beq @not_left
    sec
    lda vx_lo
    sbc c_acc
    sta vx_lo
    lda vx_hi
    sbc #0
    sta vx_hi
    lda vx_lo                   ; clamp: if vx < -max then vx = -max
    cmp c_nmax_lo
    lda vx_hi
    sbc c_nmax_hi
    bvc :+
    eor #$80
:   bpl @h_done
    lda c_nmax_lo
    sta vx_lo
    lda c_nmax_hi
    sta vx_hi
    jmp @h_done
@not_left:
    lda pad
    and #BTN_RIGHT
    beq @friction
    clc
    lda vx_lo
    adc c_acc
    sta vx_lo
    lda vx_hi
    adc #0
    sta vx_hi
    lda c_max_lo                ; clamp: if max < vx then vx = max
    cmp vx_lo
    lda c_max_hi
    sbc vx_hi
    bvc :+
    eor #$80
:   bpl @h_done
    lda c_max_lo
    sta vx_lo
    lda c_max_hi
    sta vx_hi
    jmp @h_done
@friction:
    jsr friction
@h_done:

    lda flap_timer
    beq :+
    dec flap_timer
:   lda pad_new
    and #BTN_A|BTN_B           ; either button flaps
    bne @flap
    lda pad
    and #BTN_A|BTN_B
    beq @gravity
    lda flap_timer
    bne @gravity
@flap:
    lda c_flap_lo
    sta vy_lo
    lda c_flap_hi
    sta vy_hi
    lda c_flapt
    sta flap_timer
    lda #FLAP_ANIM
    sta flap_anim
    jmp move_body
@gravity:
    clc
    lda vy_lo
    adc #<GRAVITY
    sta vy_lo
    lda vy_hi
    adc #>GRAVITY
    sta vy_hi
    lda #<MAX_FALL              ; clamp: if MAX_FALL < vy then vy = MAX_FALL
    cmp vy_lo
    lda #>MAX_FALL
    sbc vy_hi
    bvc :+
    eor #$80
:   bpl move_body
    lda #<MAX_FALL
    sta vy_lo
    lda #>MAX_FALL
    sta vy_hi
    ; fall through

; move_body: apply vx, vy with collision (each axis separately).
move_body:
    clc
    lda pos_xf
    adc vx_lo
    sta new_f
    lda pos_x
    adc vx_hi
    sta cand_x
    lda pos_y
    sta cand_y
    jsr check_box
    bcs @x_block
    lda new_f
    sta pos_xf
    lda cand_x
    sta pos_x
    jmp @try_y
@x_block:
    lda #0
    sta vx_lo
    sta vx_hi
@try_y:
    clc
    lda pos_yf
    adc vy_lo
    sta new_f
    lda pos_y
    adc vy_hi
    sta cand_y
    lda pos_x
    sta cand_x
    jsr check_box
    bcs @y_block
    lda new_f
    sta pos_yf
    lda cand_y
    sta pos_y
    rts
@y_block:
    lda #0
    sta vy_lo
    sta vy_hi
    rts

; friction: ease vx toward zero by c_fric
friction:
    lda vx_hi
    bmi @neg
    ora vx_lo
    beq @done
    sec
    lda vx_lo
    sbc c_fric
    sta vx_lo
    lda vx_hi
    sbc #0
    sta vx_hi
    bpl @done
    bmi @zero
@neg:
    clc
    lda vx_lo
    adc c_fric
    sta vx_lo
    lda vx_hi
    adc #0
    sta vx_hi
    bmi @done
@zero:
    lda #0
    sta vx_lo
    sta vx_hi
@done:
    rts

; check_box: C=1 if the hitbox at (cand_x, cand_y) touches rock
check_box:
    lda cand_y
    clc
    adc #HB_TOP
    sta box_y0
    adc #HB_SIZE
    sta box_y1
    lda cand_x
    clc
    adc #HB_LEFT
    sta box_x0
    adc #HB_SIZE
    sta box_x1
    lda box_x0
    ldy box_y0
    jsr is_solid
    bcs @hit
    lda box_x1
    ldy box_y0
    jsr is_solid
    bcs @hit
    lda box_x0
    ldy box_y1
    jsr is_solid
    bcs @hit
    lda box_x1
    ldy box_y1
    jsr is_solid
@hit:
    rts

; is_solid: A = pixel x, Y = pixel y. C=1 if that tile is rock (tiles $01-$04)
; or part of a boss (solid_tab, from make_assets.py). Preserves X.
is_solid:
    lsr a
    lsr a
    lsr a
    sta tmp_cx
    tya
    lsr a
    lsr a
    lsr a
    sta tmp_cy
    jsr level_tile_at
    tay
    lda solid_tab,y
    lsr a                       ; C = solid
    rts

; level_tile_at: (tmp_cx, tmp_cy) -> A = the level's tile there. Maps are
; packed 4 bits a cell (make_assets.py pack_map); $0F means the tile is in the
; level's overlay (boss art, title text). Preserves X; changes Y and ptr.
level_tile_at:
    ldy tmp_cy
    lda lv_row_lo,y
    clc
    adc cur_map
    sta ptr
    lda lv_row_hi,y
    adc cur_map+1
    sta ptr+1
    lda tmp_cx
    lsr a                       ; C = odd column (low nibble)
    tay
    lda (ptr),y
    bcs @odd
    lsr a
    lsr a
    lsr a
    lsr a
    cmp #$0F
    beq @overlay
    rts
@odd:
    and #$0F
    cmp #$0F
    beq @overlay
    rts
@overlay:                       ; overlay rows are 16 bytes
    ldy cur_level
    lda lv_ov_lo,y
    sta ptr
    lda lv_ov_hi,y
    sta ptr+1
    lda tmp_cy
    sec
    sbc lv_ov_y,y
    asl a
    asl a
    asl a
    asl a
    sta lt_t
    lda tmp_cx
    sec
    sbc lv_ov_x,y
    clc
    adc lt_t
    tay
    lda (ptr),y
    rts

; -----------------------------------------------------------------------------
; Spirits drift away from whatever killed them, then hover until revived.
update_spirit:
    ldx cur_p
    lda p_stimer,x
    beq @hover
    dec p_stimer,x
    lda #$06
    sta c_fric
    jsr friction
    jmp move_body
@hover:
    rts

; check_revive: an alive moth touching its partner's spirit brings it back.
check_revive:
    lda num_players
    cmp #2
    bne @done
    ldx #0
@each:
    lda p_state,x
    cmp #PS_SPIRIT
    bne @next
    txa
    eor #1
    tay                         ; Y = partner
    lda p_state,y
    cmp #PS_ALIVE
    bne @next
    stx mp
    jsr moth_box_x              ; spirit's box -> mbx..
    lda mbx0
    sec
    sbc #4                      ; generous: 8px extra all round
    sta ex0
    lda mbx1
    clc
    adc #4
    sta ex1
    lda mby0
    sec
    sbc #4
    sta ey0
    lda mby1
    clc
    adc #4
    sta ey1
    ldx mp
    txa
    eor #1
    tax
    jsr moth_box_x              ; partner's box
    jsr box_overlap
    ldx mp
    bcc @next
    lda #PS_ALIVE               ; revived!
    sta p_state,x
    lda #REVIVE_SAFE
    sta p_invuln,x
    jsr reset_moth_motion
    jsr sfx_revive
    lda #1
    sta hud_dirty
@next:
    inx
    cpx #MAX_PLAYERS
    bne @each
@done:
    rts

; reset_moth_motion: X = player. Stop it and restart its trail tracking.
reset_moth_motion:
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda #0
    sta plr+P_VXLO,y
    sta plr+P_VXHI,y
    sta plr+P_VYLO,y
    sta plr+P_VYHI,y
    lda #$FF
    sta plr+P_LASTCX,y          ; next dot is a fresh start
    rts

; moth_box_x: X = player -> mbx0..mby1 (its hitbox). Preserves X.
moth_box_x:
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_POSX,y
    clc
    adc #HB_LEFT
    sta mbx0
    adc #HB_SIZE-1
    sta mbx1
    lda plr+P_POSY,y
    clc
    adc #HB_TOP
    sta mby0
    adc #HB_SIZE-1
    sta mby1
    rts

; box_overlap: C=1 if mbx0..mby1 overlaps ex0..ey1
box_overlap:
    lda mbx1
    cmp ex0
    bcc @no
    lda ex1
    cmp mbx0
    bcc @no
    lda mby1
    cmp ey0
    bcc @no
    lda ey1
    cmp mby0
    bcc @no
    sec
    rts
@no:
    clc
    rts

; kill_player: X = player, A = x of what killed it.
kill_player:
    sta tmp
    inc deaths
    lda #0
    sta p_power,x               ; power-ups last until you lose a life
    sta p_slow,x
    sta p_dim,x
    dec p_lives,x
    bne @spirit
    lda #PS_OUT
    sta p_state,x
    jmp @after
@spirit:
    lda #PS_SPIRIT
    sta p_state,x
    lda #SPIRIT_DRIFT
    sta p_stimer,x
    txa                         ; drift away from the killer and upward
    asl a
    asl a
    asl a
    asl a
    tay
    lda tmp
    cmp plr+P_POSX,y
    bcc @right
    lda #$80
    sta plr+P_VXLO,y
    lda #$FE                    ; -1.5 px/frame, easing off: ~45 px away
    sta plr+P_VXHI,y
    jmp @up
@right:
    lda #$80
    sta plr+P_VXLO,y
    lda #$01
    sta plr+P_VXHI,y
@up:
    lda #$80                    ; -0.5 px/frame: ~24 px up
    sta plr+P_VYLO,y
    lda #$FF
    sta plr+P_VYHI,y
@after:
    stx mp
    jsr dissolve_player_trail
    ldx mp
    jsr sfx_death
    lda #1
    sta hud_dirty
    ldx mp
    rts

; place_players: stage start. Every player still in the game starts alive.
place_players:
    ldx #0
@each:
    lda p_state,x
    beq @next                   ; out
    lda #PS_ALIVE
    sta p_state,x
    lda #SPAWN_SAFE
    sta p_invuln,x
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    stx tmp
    ldx cur_level
    lda #0
    sta plr+0,y                 ; subpixels
    sta plr+2,y
    sta plr+P_VXLO,y
    sta plr+P_VXHI,y
    sta plr+P_VYLO,y
    sta plr+P_VYHI,y
    sta plr+(flap_timer - pblock),y
    sta plr+P_FLAPA,y
    lda tmp
    bne @p2
    lda lv_p1x,x
    sta plr+P_POSX,y
    lda lv_p1y,x
    sta plr+P_POSY,y
    jmp @placed
@p2:
    lda lv_p2x,x
    sta plr+P_POSX,y
    lda lv_p2y,x
    sta plr+P_POSY,y
@placed:
    lda #$FF
    sta plr+P_LASTCX,y
    ldx tmp
    lda trail_off,x
    sta plr+P_HEAD,y
@next:
    inx
    cpx #MAX_PLAYERS
    bne @each
    rts

; tick_invuln: count down every player's invulnerability
tick_invuln:
    ldx #MAX_PLAYERS-1
@l:
    lda p_invuln,x
    beq :+
    dec p_invuln,x
:   lda p_slow,x
    beq :+
    dec p_slow,x
:   lda p_dim,x
    beq :+
    dec p_dim,x
    bne :+
    lda #1                      ; light back to full
    sta class_dirty
:   dex
    bpl @l
    rts

; -----------------------------------------------------------------------------
; build_moth_oam: 4 sprites per moth; the right half is the left half flipped.
; Player 1 uses sprite palette 0, player 2 palette 1, spirits palette 2.
; The two moths swap OAM slots every frame so neither always loses when a
; scanline has too many sprites.
build_moth_oam:
    ldx #0
@each:
    stx mp
    txa
    eor frame
    and #1
    asl a
    asl a
    asl a
    asl a
    sta eo                      ; OAM offset 0 or 16
    lda p_state,x
    beq @to_hide
    cmp #PS_SPIRIT
    beq @spirit
    lda p_invuln,x              ; alive: flicker while invulnerable
    beq @draw
    lda frame
    and #4
    beq @draw
@to_hide:
    jmp @hide
@draw:
    txa
    sta epal                    ; palette = player number
    jsr @tile
    jmp @put
@spirit:
    lda frame                   ; pale and slowly blinking
    and #$18
    beq @to_hide
    lda #2
    sta epal
    lda frame
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #1
    asl a
    sta etile
@put:
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_POSY,y
    sta tmp
    lda p_state,x
    cmp #PS_SPIRIT
    bne :+
    lda frame                   ; spirits bob
    lsr a
    lsr a
    lsr a
    and #3
    tax
    lda bob_table,x
    clc
    adc tmp
    sta tmp
    ldx mp
:   lda plr+P_POSX,y
    sta tmp2
    ldy eo
    lda tmp
    sec
    sbc #1
    sta oam+0,y
    sta oam+4,y
    clc
    adc #8
    sta oam+8,y
    sta oam+12,y
    lda etile
    sta oam+1,y
    sta oam+5,y
    ora #1
    sta oam+9,y
    sta oam+13,y
    lda epal
    sta oam+2,y
    sta oam+10,y
    ora #$40
    sta oam+6,y
    sta oam+14,y
    lda tmp2
    sta oam+3,y
    sta oam+11,y
    clc
    adc #8
    sta oam+7,y
    sta oam+15,y
    jmp @next
@hide:
    ldy eo
    lda #$FF
    sta oam+0,y
    sta oam+4,y
    sta oam+8,y
    sta oam+12,y
@next:
    ldx mp
    inx
    cpx #MAX_PLAYERS
    beq :+
    jmp @each
:   rts
; @tile: X = player -> etile (wing frame)
@tile:
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_FLAPA,y
    beq @idle
    sec
    sbc #1
    sta plr+P_FLAPA,y
    lsr a
    lsr a
    and #1
    jmp @have
@idle:
    lda frame
    lsr a
    lsr a
    lsr a
    lsr a
    and #1
@have:
    asl a
    sta etile
    rts

.segment "RODATA"
trail_off:
    .byte 0, TRAIL_LEN
bob_table:
    .byte 0, 1, 2, 1
.segment "CODE"

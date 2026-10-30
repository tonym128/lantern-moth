; =============================================================================
; Lantern Moth - bosses (every 5th stage)
;
; Bosses are drawn in the background (gen/level*.bin has them stamped in with
; their eyes closed) and are solid. Only their eyes are rewritten at run time
; (a few tiles a frame). The parts that move are sprites in the enemy slots.
;
; GREAT OWL (stage 5), 4 hits
;   sleeps -> opens its eyes -> sends out its MOON ORB for 10s. The orb drifts
;   from spot to spot, hovering at each: loop it while it hovers to hit the
;   owl. Meanwhile feathers rain from its wings. Each hit makes it quicker.
;
; CAVE TOAD (stage 10), 6 hits
;   squats on the floor, blowing glowing BUBBLES that rise, hover a while and
;   float off: loop a hovering bubble to hit the toad. When a moth flies over
;   it, its tongue lashes straight up.
;
; SNUFFER QUEEN (stage 15), 8 hits
;   the snuffer beetles' mother. Sleeps; awake, an EMBER drifts out of one of
;   the glowing sacs on her shell and hovers like the owl's orb (loop it to hit
;   her), and she lays larvae on the ledges: snuffer beetles that eat trails.
;   At half health two embers come out at once.
;
; Hits shake the screen (horizontal scroll) and score 1000 for whoever closed
; the loop; beating a boss gives every player still in 5000.
; =============================================================================

BOSS_OWL  = 1
BOSS_TOAD = 2
BOSS_QUEEN = 3

BS_SLEEP  = 0           ; owl
BS_OPEN   = 1
BS_ACTIVE = 2
BS_HURT   = 3
BS_IDLE   = 4           ; toad
BS_TONGUE = 5
BS_DEAD   = 6

OWL_HP       = 4
TOAD_HP      = 6
QUEEN_HP     = 8
LARVA_SAFE   = 40       ; no larva hatches this close to a moth (|dx|+|dy|)
ORB_TIME     = 600      ; frames the orb stays out
TONGUE_MAX   = 96
TONGUE_SPEED = 6
TONGUE_HOLD  = 16

.segment "ZEROPAGE"
boss_type:   .res 1
boss_hp:     .res 1
boss_state:  .res 1
boss_timer:  .res 2
boss_eye:    .res 1     ; eyes as drawn: 0 closed, 1 open
boss_eye_want: .res 1
boss_eye_i:  .res 1     ; progress of a swap (6 tiles a frame)
boss_dead:   .res 1
boss_bx:     .res 1     ; top-left cell of the boss art
boss_by:     .res 1
shake_t:     .res 1
feather_t:   .res 1
bub_t:       .res 1
tongue_len:  .res 1
tongue_t:    .res 1
tongue_cd:   .res 1
blink_t:     .res 1
mouth_x:     .res 1
mouth_y:     .res 1

.segment "CODE"

; boss_init: set up the boss of cur_level (if it has one)
boss_init:
    lda #0
    sta shake_t
    sta scroll_x
    sta scroll_nt
    sta boss_dead
    sta boss_eye
    sta boss_eye_want
    sta boss_eye_i
    sta tongue_len
    ldx cur_level
    lda lv_boss,x
    sta boss_type
    bne :+
    rts
:   lda lv_bossx,x
    sta boss_bx
    lda lv_bossy,x
    sta boss_by
    lda #1
    sta en_left                 ; (the clear comes from beating the boss)
    lda boss_type
    cmp #BOSS_TOAD
    beq @toad
    lda #OWL_HP
    ldy boss_type
    cpy #BOSS_QUEEN
    bne :+
    lda #150                    ; first larva after 2.5s awake
    sta bub_t
    lda #QUEEN_HP
:   sta boss_hp
    lda #BS_SLEEP
    ldy #90
    jmp boss_set
@toad:
    lda #TOAD_HP
    sta boss_hp
    lda boss_bx                 ; mouth position in pixels
    asl a
    asl a
    asl a
    clc
    adc #TOAD_MOUTH_X
    sta mouth_x
    lda boss_by
    asl a
    asl a
    asl a
    clc
    adc #TOAD_MOUTH_Y
    sta mouth_y
    lda #1
    sta boss_eye_want
    lda #60
    sta bub_t
    lda #150
    sta tongue_cd
    lda #100
    sta blink_t
    lda #BS_IDLE
    ldy #0
    ; fall through
; boss_set: A = state, Y = timer (frames)
boss_set:
    sta boss_state
    sty boss_timer
    lda #0
    sta boss_timer+1
    rts

; boss_tick: count boss_timer down; Z=1 when it hits 0
boss_tick:
    lda boss_timer
    ora boss_timer+1
    beq @z
    lda boss_timer
    bne :+
    dec boss_timer+1
:   dec boss_timer
    lda boss_timer
    ora boss_timer+1
@z:
    rts

; -----------------------------------------------------------------------------
boss_update:
    lda shake_t                 ; screen shake
    beq @still
    dec shake_t
    lda shake_t
    and #7
    tax
    lda shake_tab,x
    bpl :+
    sta scroll_x                ; negative: show nametable 1's edge on the left
    lda #1
    sta scroll_nt
    jmp @shook
:   sta scroll_x
    lda #0
    sta scroll_nt
    jmp @shook
@still:
    lda #0
    sta scroll_x
    sta scroll_nt
@shook:
    lda boss_type
    bne :+
    rts
:   jsr eye_swap
    lda boss_state
    cmp #BS_DEAD
    bne @alive
    jsr boss_tick
    bne :+
    lda #1
    sta boss_dead
:   rts
@alive:
    lda boss_type
    cmp #BOSS_OWL
    beq owl_update
    cmp #BOSS_TOAD
    bne :+
    jmp toad_update
:   jmp queen_update

owl_update:
    lda boss_state
    cmp #BS_SLEEP
    bne @open
    jsr boss_tick
    bne @done
    lda #1                      ; wake up
    sta boss_eye_want
    lda #BS_OPEN
    ldy #40
    jmp boss_set
@open:
    cmp #BS_OPEN
    bne @active
    jsr boss_tick
    bne @done
    ldx #0                      ; send out the orb, from the owl's chest
    lda #T_ORB
    sta en_type,x
    lda #ES_WALK
    sta en_state,x
    lda #0
    sta en_hop,x
    sta en_timer,x
    lda boss_bx
    asl a
    asl a
    asl a
    clc
    adc #OWL_CHEST_X-8
    sta en_x,x
    lda boss_by
    asl a
    asl a
    asl a
    clc
    adc #OWL_CHEST_Y-8
    sta en_y,x
    jsr upd_orb_pick
    jsr sfx_appear
    lda #40
    sta feather_t
    lda #BS_ACTIVE
    ldy #<ORB_TIME
    jsr boss_set
    lda #>ORB_TIME
    sta boss_timer+1
@done:
    rts
@active:
    cmp #BS_ACTIVE
    bne @hurt
    dec feather_t               ; feathers fall
    bne :+
    jsr drop_feather
    lda boss_hp                 ; faster as it weakens (1.4s down to 1s)
    asl a
    asl a
    asl a
    clc
    adc #50
    sta feather_t
:   jsr boss_tick
    bne @done
    lda #ES_NONE                ; the orb goes home
    sta en_state
    lda #0
    sta boss_eye_want
    lda #BS_SLEEP
    ldy #120
    jmp boss_set
@hurt:
    lda frame                   ; blinking with pain
    lsr a
    lsr a
    lsr a
    and #1
    sta boss_eye_want
    jsr boss_tick
    bne @done
    lda #0
    sta boss_eye_want
    lda boss_hp
    asl a
    asl a
    asl a
    asl a
    adc #40
    tay
    lda #BS_SLEEP
    jmp boss_set

; drop_feather: in a free slot (1-3), from somewhere under the owl's wings
drop_feather:
    ldx #1
@find:
    lda en_state,x
    beq @got
    inx
    cpx #MAX_EN
    bne @find
    rts
@got:
    lda #T_FEATHER
    sta en_type,x
    lda #ES_WALK
    sta en_state,x
    lda boss_bx
    asl a
    asl a
    asl a
    clc
    adc #8
    sta tmp
    jsr rand
    and #63
    clc
    adc tmp
    sta en_by,x                 ; base x
    sta en_x,x
    lda boss_by
    clc
    adc #OWL_H
    asl a
    asl a
    asl a
    sta en_y,x
    lda #0
    sta en_yf,x
    lda #OWL_HP+1               ; fall speed (1/16 px): faster when hurt
    sec
    sbc boss_hp
    asl a
    asl a
    clc
    adc #14
    sta en_vy,x
    jsr rand
    sta en_hop,x
    rts

toad_update:
    lda boss_state
    cmp #BS_IDLE
    beq @idle
    cmp #BS_TONGUE
    bne :+
    jmp @tongue
:   jsr boss_tick               ; hurt: eyes shut a moment
    bne @done
    lda #1
    sta boss_eye_want
    lda #BS_IDLE
    ldy #0
    jmp boss_set
@done:
    rts
@idle:
    dec blink_t                 ; blink now and then
    lda blink_t
    cmp #10
    bcs :+
    lda #0
    sta boss_eye_want
    lda blink_t
    bne :+
    jsr rand
    ora #$80
    sta blink_t
    lda #1
    sta boss_eye_want
:   dec bub_t                   ; blow a bubble
    bne @no_bub
    jsr blow_bubble
    lda boss_hp
    asl a
    asl a
    asl a
    asl a
    clc
    adc #30
    sta bub_t
@no_bub:
    dec tongue_cd               ; anyone overhead? tongue!
    bne @done
    lda #20
    sta tongue_cd
    ldy #0
@m:
    lda p_state,y
    cmp #PS_ALIVE
    bne @nm
    sty tmp2
    tya
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_POSX,y
    clc
    adc #8
    sec
    sbc mouth_x
    clc
    adc #40
    cmp #80
    ldy tmp2
    bcc @lash
@nm:
    iny
    cpy #MAX_PLAYERS
    bne @m
    rts
@lash:
    lda #0
    sta tongue_len
    sta tongue_t
    jsr sfx_spit
    lda boss_hp
    asl a
    asl a
    asl a
    asl a
    clc
    adc #50
    sta tongue_cd
    lda #BS_TONGUE
    ldy #0
    jmp boss_set
@tongue:
    lda tongue_t                ; 0 = shooting up, 1.. = holding, $80 = pulling back
    bmi @back
    bne @hold
    lda tongue_len
    clc
    adc #TONGUE_SPEED
    cmp #TONGUE_MAX
    bcc :+
    lda #TONGUE_MAX
    inc tongue_t
:   sta tongue_len
    jmp tongue_hit
@hold:
    inc tongue_t
    lda tongue_t
    cmp #TONGUE_HOLD
    bcc :+
    lda #$80
    sta tongue_t
:   jmp tongue_hit
@back:
    lda tongue_len
    sec
    sbc #TONGUE_SPEED
    bcs :+
    lda #0
:   sta tongue_len
    bne tongue_hit
    lda #BS_IDLE
    ldy #0
    jmp boss_set

; tongue_hit: the tongue is deadly along its whole length
tongue_hit:
    lda mouth_x
    sta kill_x
    sec
    sbc #3
    sta ex0
    clc
    adc #6
    sta ex1
    lda mouth_y
    sta ey1
    sec
    sbc tongue_len
    sta ey0
    jmp box_kill_x

blow_bubble:
    ldx #0
@find:
    lda en_state,x
    beq @got
    inx
    cpx #2                      ; at most two bubbles
    bne @find
    rts
@got:
    lda #T_BUBBLE
    sta en_type,x
    lda #ES_WALK
    sta en_state,x
    lda mouth_x
    sec
    sbc #8
    sta en_by,x                 ; base x
    sta en_x,x
    lda mouth_y
    sec
    sbc #22
    sta en_y,x
    jsr rand                    ; hover somewhere 60..123 px up
    and #63
    clc
    adc #60
    sta en_vy,x
    lda #240                    ; for 4 seconds
    sta en_timer,x
    jsr rand
    sta en_hop,x
    jmp sfx_appear

queen_update:
    lda boss_state
    cmp #BS_SLEEP
    bne @open
    jsr boss_tick
    bne @done
    lda #1                      ; wake up
    sta boss_eye_want
    lda #BS_OPEN
    ldy #40
    jmp boss_set
@open:
    cmp #BS_OPEN
    bne @active
    jsr boss_tick
    bne @done
    ldx #0                      ; an ember from one of her sacs...
    jsr queen_ember
    lda boss_hp                 ; ...two at half health
    cmp #QUEEN_HP/2+1
    bcs :+
    ldx #3
    jsr queen_ember
:   lda #BS_ACTIVE
    ldy #<ORB_TIME
    jsr boss_set
    lda #>ORB_TIME
    sta boss_timer+1
@done:
    rts
@active:
    cmp #BS_ACTIVE
    bne @hurt
    dec bub_t                   ; lay a larva now and then
    bne :+
    jsr lay_larva
:   jsr boss_tick
    bne @done
    lda #0
    sta boss_eye_want
    lda #120
    bne @embers_home
@hurt:
    lda frame                   ; blinking with pain
    lsr a
    lsr a
    lsr a
    and #1
    sta boss_eye_want
    jsr boss_tick
    bne @done
    lda #0
    sta boss_eye_want
    lda boss_hp
    asl a
    asl a
    asl a
    asl a
    adc #40
@embers_home:                   ; A = frames to sleep
    tay
    ldx #0
    jsr ember_home
    ldx #3
    jsr ember_home
    lda #BS_SLEEP
    jmp boss_set

; ember_home: X = slot. An ember still out goes back into the queen.
ember_home:
    lda en_type,x
    cmp #T_ORB
    bne :+
    lda #ES_NONE
    sta en_state,x
:   rts

; queen_ember: X = slot (if free). An ember (an orb) out of a random sac.
queen_ember:
    lda en_state,x
    bne @busy
    lda #T_ORB
    sta en_type,x
    lda #ES_WALK
    sta en_state,x
    lda #0
    sta en_hop,x
    sta en_timer,x
    jsr rand
    and #3
    cmp #3
    bcc :+
    lda #0                      ; (the middle sac a bit more often)
:   tay
    lda boss_bx
    asl a
    asl a
    asl a
    clc
    adc queen_sac_x,y
    sec
    sbc #8
    sta en_x,x
    lda boss_by
    asl a
    asl a
    asl a
    clc
    adc queen_sac_y,y
    sec
    sbc #8
    sta en_y,x
    jsr upd_orb_pick
    jmp sfx_appear
@busy:
    rts

; lay_larva: a snuffer beetle hatches on a free spawn ledge (slots 1-2), but
; not right next to a moth. Sooner as she weakens.
lay_larva:
    lda boss_hp
    asl a
    asl a
    asl a
    asl a
    adc #60                     ; 3.1s at full health, 1.3s at the end
    sta bub_t
    ldx #1
@find:
    lda en_state,x
    beq @got
    inx
    cpx #3
    bne @find
    rts
@got:
    stx ei
    jsr spawn_enemy
    jsr nearest_moth
    ldx ei
    lda near_d
    cmp #LARVA_SAFE
    bcs :+
    lda #30                     ; too close: try again in half a second
    sta bub_t
    rts
:   lda #ES_WALK
    sta en_state,x
    lda #40
    sta en_timer,x
    jmp sfx_spit

; -----------------------------------------------------------------------------
; boss parts (called through the enemy type table, X = slot)

; The orb drifts to a spot, hovers there (that's when you can loop it), then
; moves on. It hovers for less time as the owl weakens.
;   en_by / en_vy = target x / y, en_timer = hover time left, en_hop = bob phase
upd_orb:
    inc en_hop,x
    lda en_timer,x
    beq @move
    dec en_timer,x              ; hovering: a gentle bob
    bne @bob
    jmp upd_orb_pick            ; hover over: choose the next spot
@bob:
    lda en_hop,x
    lsr a
    and #63
    tay
    lda sine,y
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    clc
    adc en_vy,x
    sta en_y,x
    rts
@move:
    lda en_by,x                 ; one pixel a frame toward the target
    jsr step_toward_x
    lda en_vy,x
    jsr step_toward_y
    lda en_x,x
    cmp en_by,x
    bne @ret
    lda en_y,x
    cmp en_vy,x
    bne @ret
    lda boss_hp                 ; arrived: hover (2.9s, down to 2.1s when hurt)
    asl a
    asl a
    asl a
    asl a
    adc #110
    sta en_timer,x
@ret:
    rts

upd_orb_pick:                   ; choose where to go next
    jsr rand
    and #127
    clc
    adc #56
    sta en_by,x                 ; x 56..183
    jsr rand
    and #63
    clc
    adc #112
    sta en_vy,x                 ; y 112..175
    rts

; step_toward_x / _y: move enemy X one pixel toward A
step_toward_x:
    cmp en_x,x
    beq @d
    bcc :+
    inc en_x,x
    rts
:   dec en_x,x
@d: rts
step_toward_y:
    cmp en_y,x
    beq @d
    bcc :+
    inc en_y,x
    rts
:   dec en_y,x
@d: rts

; Bubbles rise to a random height, hover a while (loop them then!), then
; float off and pop at the ceiling.
;   en_by = base x, en_vy = hover height, en_timer = hover time, en_hop = wobble
upd_bubble:
    lda frame
    and #1
    bne @wobble
    inc en_hop,x
    lda en_y,x
    cmp en_vy,x                 ; still rising to its height?
    beq @hover
    bcc @rise                   ; (above it already: hover is over, keep going)
@rise:
    dec en_y,x
    lda en_y,x
    cmp #28
    bcs @wobble
    lda #ES_NONE                ; popped at the ceiling
    sta en_state,x
    jmp sfx_tick
@hover:
    dec en_timer,x
    bne @wobble
    dec en_vy,x                 ; done hovering: rise on (target moves up)
    lda #28
    sta en_vy,x
@wobble:
    lda en_hop,x
    and #63
    tay
    lda sine,y
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    clc
    adc en_by,x
    sta en_x,x
    rts

upd_feather:
    lda en_vy,x
    jsr vel_split
    lda en_yf,x
    clc
    adc tmp_f
    sta en_yf,x
    lda en_y,x
    adc tmp_b
    sta en_y,x
    cmp #216
    bcs @gone
    lda frame                   ; sway
    and #1
    bne :+
    inc en_hop,x
:   lda en_hop,x
    and #63
    tay
    lda sine,y
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    clc
    adc en_by,x
    sta en_x,x
    lda en_x,x                  ; landed on rock?
    clc
    adc #4
    pha
    lda en_y,x
    clc
    adc #7
    tay
    pla
    jsr is_solid
    bcs @gone
    lda en_x,x                  ; deadly
    sta kill_x
    clc
    adc #1
    sta ex0
    adc #5
    sta ex1
    lda en_y,x
    clc
    adc #1
    sta ey0
    adc #5
    sta ey1
    jmp box_kill_x
@gone:
    lda #ES_NONE
    sta en_state,x
    rts

; boss_hit: X = the weak point (orb/bubble) that was looped
boss_hit:
    lda #ES_NONE
    sta en_state,x
    lda #24
    sta shake_t
    lda #1
    sta light_dirty
    jsr sfx_boss_hit
    lda game_mode               ; 1000 for whoever closed the loop
    beq :+
    ldx ls_a
    lda #1
    ldy #2
    jsr add_score
:   ldx ei
    dec boss_hp
    beq @defeated
    lda boss_type
    cmp #BOSS_TOAD
    beq @toad
    lda #BS_HURT                ; owl, queen
    ldy #50
    jmp boss_set
@toad:
    lda #0
    sta boss_eye_want
    sta tongue_len
    lda #BS_HURT
    ldy #40
    jmp boss_set
@defeated:
    lda #48
    sta shake_t
    lda #0
    sta boss_eye_want
    sta tongue_len
    ldy #MAX_EN-1               ; everything it sent out vanishes
:   sta en_state,y
    dey
    bpl :-
    ldx #MAX_PLAYERS-1          ; 5000 for everyone still in
@pay:
    lda p_state,x
    beq @np
    lda #5
    ldy #2
    jsr add_score
@np:
    dex
    bpl @pay
    ldx ei
    lda #JG_CLEAR
    jsr play_jingle
    lda #BS_DEAD
    ldy #150
    jmp boss_set

; -----------------------------------------------------------------------------
; eye_swap: rewrite the eye tiles toward boss_eye_want, 6 tiles a frame
eye_swap:
    lda boss_eye
    cmp boss_eye_want
    bne :+
    rts
:   lda vq_len
    cmp #VQ_MAX-5
    bcc :+
    rts                         ; not enough room this frame
:   lda #6
    sta tmp_f
@cell:
    ldx boss_eye_i
    lda boss_type
    cmp #BOSS_QUEEN
    beq @queen
    cmp #BOSS_OWL
    bne @toad
    cpx #OWL_EYE_CELLS
    bcs @done
    lda owl_eye_dx,x
    clc
    adc boss_bx
    sta tmp_cx
    lda owl_eye_dy,x
    clc
    adc boss_by
    sta tmp_cy
    lda owl_eye_closed,x
    ldy boss_eye_want
    beq :+
    lda owl_eye_open,x
:   jmp @put
@toad:
    cpx #TOAD_EYE_CELLS
    bcs @done
    lda toad_eye_dx,x
    clc
    adc boss_bx
    sta tmp_cx
    lda toad_eye_dy,x
    clc
    adc boss_by
    sta tmp_cy
    lda toad_eye_closed,x
    ldy boss_eye_want
    beq @put
    lda toad_eye_open,x
    jmp @put
@queen:
    cpx #QUEEN_EYE_CELLS
    bcs @done
    lda queen_eye_dx,x
    clc
    adc boss_bx
    sta tmp_cx
    lda queen_eye_dy,x
    clc
    adc boss_by
    sta tmp_cy
    lda queen_eye_closed,x
    ldy boss_eye_want
    beq @put
    lda queen_eye_open,x
@put:
    jsr queue_cell
    inc boss_eye_i
    dec tmp_f
    bne @cell
    rts
@done:
    lda boss_eye_want
    sta boss_eye
    lda #0
    sta boss_eye_i
    rts

; draw_tongue: sprite segments straight up from the toad's mouth
draw_tongue:
    lda boss_type
    cmp #BOSS_TOAD
    bne @none
    lda tongue_len
    beq @none
    lda mouth_y
    sta tmp
    lda tongue_len
    lsr a
    lsr a
    lsr a
    beq @none
    sta tmp_f                   ; segments
    ldy #OAM_EXTRA
@seg:
    lda tmp
    sec
    sbc #8
    sta tmp
    sec
    sbc #1
    sta oam,y
    lda #SPR_TONGUE
    ldx tmp_f
    cpx #1
    bne :+
    lda #SPR_TONGUE_TIP
:   sta oam+1,y
    lda #0
    sta oam+2,y
    lda mouth_x
    sec
    sbc #4
    sta oam+3,y
    iny
    iny
    iny
    iny
    dec tmp_f
    bne @seg
@none:
    ldx ei
    rts

.segment "RODATA"
shake_tab:
    .byte 0, 2, $FE, 3, $FD, 2, $FE, 1
.segment "CODE"

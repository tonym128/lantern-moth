; =============================================================================
; Lantern Moth - enemies
;
; Every enemy slot has a type and a state. All capturable types share one life
; cycle:
;
;   WALK --loop around it--> COCOON --0.75s--> FIREFLY --a moth touches it--> collected
;    ^                                           |
;    +---- WAKE <--------- 7s, not collected ----+
;
; WALK is "doing its thing" for each type:
;   BUNNY   paces its ledge, hops now and then. Deadly to touch.
;   BAT     flies about for 3s (bolting from moths), then dozes in mid-air for 4s;
;           a dozing bat only startles when you come very close. Deadly.
;   BEETLE  paces its ledge and EATS trail dots it touches. Eating one breaks
;           that trail: everything older can no longer close a loop. Deadly.
;   WISP    hovers a few seconds, flits to a nearby spot, hovers again. Harmless,
;           but touching it steals your light for 4 seconds.
;   MIMIC   looks just like rock in the dark. When a moth's light reaches it, it
;           wakes and chases along its ledge for 3s. Deadly only while awake.
;   SPIDER  drops down its thread, hangs 3s, climbs back up, and spits webs
;           that slow you. Deadly.
; Boss parts (boss.s) use the same slots: ORB and BUBBLE are weak points (loop
; them); FEATHER falls and kills, and can't be caught.
;
; Points: 100, 200, 400, 800 for the 1st-4th enemy caught in one loop, doubled
; for a team loop, paid to whoever collects the firefly.
;
; Per-type use of the slot fields:
;   en_by   base y (ledge walkers, spider rest y, wisp centre) / feather & bubble base x
;   en_hop  bunny hop step / phase (wisp, spider, orb, bubble, feather) / mimic awake timer
;   en_vx   bat velocity / beetle chomp timer / spider thread top
;   en_vy   bat velocity / feather fall speed
;   en_dir  walkers: direction; bat: wander x velocity
; =============================================================================

MAX_EN       = 4         ; OAM rotation assumes a power of two

ES_NONE      = 0
ES_WALK      = 1
ES_WAKE      = 2
ES_COCOON    = 3
ES_FIREFLY   = 4

T_BUNNY   = 0            ; (order matches ENEMY_CHARS in make_assets.py)
T_BAT     = 1
T_BEETLE  = 2
T_WISP    = 3
T_MIMIC   = 4
T_SPIDER  = 5
T_ORB     = 6            ; boss parts
T_BUBBLE  = 7
T_FEATHER = 8

COCOON_TIME  = 45
FIREFLY_TIME = 210       ; x2 frames (7 seconds)
FIREFLY_WARN = 60
FIREFLY_TOP  = 32
WAKE_TIME    = 60

BAT_FLEE     = 56        ; |dx|+|dy| at which a bat bolts
BAT_FAST     = 22        ; 1/16 px per frame
BAT_STARTLE  = 20        ; a dozing bat wakes when a moth is this close (|dx|+|dy|)
BAT_FLY      = 180
BAT_DOZE     = 240
MIMIC_AWAKE  = 180
DIM_TIME     = 240       ; a wisp's touch: frames of reduced light
SLOW_TIME    = 180       ; a web hit: frames of slowness
WEB_EVERY    = 150
WEB_LIFE     = 120

SPR_BUNNY    = $04
SPR_COCOON   = $0C
SPR_FIREFLY  = $0E

OAM_EXTRA    = 168       ; spider threads (5 sprites per slot) / toad tongue
OAM_WEB      = 248

.include "../gen/tiles.inc"

.segment "ZEROPAGE"
en_type:     .res MAX_EN
en_vx:       .res MAX_EN
en_vy:       .res MAX_EN
en_yf:       .res MAX_EN
web_t:       .res 1
web_x:       .res 1
web_y:       .res 1
web_xf:      .res 1
web_yf:      .res 1
web_vx:      .res 1
web_vy:      .res 1
near_dx:     .res 1      ; nearest_moth results (moth - enemy, signed)
near_dy:     .res 1
near_d:      .res 1      ; |dx| + |dy|, 255 = no moth
kill_x:      .res 1      ; x of whatever is killing a moth (its spirit drifts away)

.segment "CODE"

; init_enemies: spawn the enemies of cur_level
init_enemies:
    ldx cur_level
    lda lv_speed,x
    sta en_speed
    lda lv_nen,x
    sta tmp_d
    ldx #MAX_EN-1
@l:
    lda #ES_NONE
    sta en_state,x
    cpx tmp_d
    bcs @next
    lda #ES_WALK
    sta en_state,x
    txa                         ; stagger their first decisions
    asl a
    asl a
    asl a
    asl a
    adc #20
    sta en_timer,x
    jsr spawn_enemy             ; (after: some types set their own timer)
@next:
    dex
    bpl @l
    lda tmp_d
    sta en_left
    lda #0
    sta fireflies
    sta web_t
    rts

; spawn_enemy: put enemy X back at its spawn point, as its type. Preserves X.
spawn_enemy:
    stx tmp
    lda cur_level
    asl a
    asl a
    ora tmp
    tay
    lda lv_type,y
    sta en_type,x
    lda lv_spawn_x,y
    sta en_x,x
    lda lv_spawn_y,y
    sta en_y,x
    sta en_by,x
    lda lv_aux,y
    sta en_vx,x                 ; spider: thread top (0 for the others)
    lda #0
    sta en_xf,x
    sta en_yf,x
    sta en_hop,x
    sta en_vy,x
    txa
    and #1
    sta en_dir,x
    lda en_type,x
    cmp #T_BAT
    bne :+
    lda #0                      ; bats: flying, no wander velocity yet
    sta en_dir,x
    sta en_by,x
    lda #BAT_FLY
    sta en_value,x
    rts
:   cmp #T_WISP
    bne :+
    lda en_x,x                  ; wisps: hover where they are
    sta en_vx,x
    lda en_y,x
    sta en_vy,x
    lda #120
    sta en_timer,x
    rts
:   cmp #T_SPIDER
    bne :+
    lda #60                     ; spiders: resting at the top a moment
    sta en_yf,x
:   rts

; -----------------------------------------------------------------------------
; update_enemies: also counts enemies left (en_left) and the light they carry.
update_enemies:
    lda #0
    sta tmp_d
    sta tmp_f
    ldx #0
@loop:
    stx ei
    lda en_state,x
    beq @next
    lda en_type,x               ; boss parts don't count toward a clear
    cmp #T_ORB
    bcs :+
    inc tmp_d
:   jsr carries_light
    bcc @act
    lda en_y,x                  ; light signature: sum of their blocks
    clc
    adc #4
    and #$F0
    sta tmp
    lda en_x,x
    clc
    adc #4
    lsr a
    lsr a
    lsr a
    lsr a
    ora tmp
    sec
    adc tmp_f
    sta tmp_f
@act:
    lda tmp_d                   ; (the updates below use these temps freely)
    pha
    lda tmp_f
    pha
    jsr @update
    pla
    sta tmp_f
    pla
    sta tmp_d
@next:
    ldx ei
    inx
    cpx #MAX_EN
    bne @loop
    jmp @counted
@update:
    lda en_state,x
    cmp #ES_WALK
    bne :+
    jmp type_dispatch
:   cmp #ES_WAKE
    bne :+
    dec en_timer,x
    bne @up_ret
    lda #ES_WALK
    sta en_state,x
    lda #40
    sta en_timer,x
@up_ret:
    rts
:   cmp #ES_COCOON
    bne :+
    jmp update_cocoon
:   jmp update_firefly
@counted:
    lda tmp_d
    sta en_left
    lda tmp_f                   ; rebuild the light when a light-carrier moves block
    cmp fireflies
    beq :+
    sta fireflies
    lda #1
    sta light_dirty
:   jmp update_web

; type_dispatch: run enemy X's WALK routine (they all end with rts)
type_dispatch:
    lda en_type,x
    asl a
    tay
    lda type_update+1,y
    pha
    lda type_update,y
    pha
    rts

; carries_light: C=1 if enemy X lights its block (fireflies, wisps, boss lights)
carries_light:
    lda en_state,x
    cmp #ES_FIREFLY
    beq @yes
    cmp #ES_WALK
    bne @no
    lda en_type,x
    cmp #T_WISP
    beq @yes
    cmp #T_ORB
    beq @yes
    cmp #T_BUBBLE
    beq @yes
@no:
    clc
    rts
@yes:
    sec
    rts

; -----------------------------------------------------------------------------
; shared helpers

; nearest_moth: X = enemy. -> mp = nearest living moth ($FF none), near_dx/dy
; (moth centre - enemy centre, signed, clamped), near_d = |dx|+|dy| (255 max).
; Preserves X.
nearest_moth:
    lda #$FF
    sta mp
    sta near_d
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
    lda plr+P_POSX,y            ; dx = moth x - enemy x (both top-left, 16 wide)
    sec
    sbc en_x,x
    sta tmp_c
    lda plr+P_POSY,y
    sec
    sbc en_y,x
    sta tmp_r
    lda tmp_c                   ; |dx| + |dy|
    bpl :+
    eor #$FF
    clc
    adc #1
:   sta tmp_b
    lda tmp_r
    bpl :+
    eor #$FF
    clc
    adc #1
:   clc
    adc tmp_b
    bcc :+
    lda #$FF
:   ldy tmp2
    cmp near_d
    bcs @nm
    sta near_d
    sty mp
    lda tmp_c
    sta near_dx
    lda tmp_r
    sta near_dy
@nm:
    iny
    cpy #MAX_PLAYERS
    bne @m
    rts

; touch_kill: kill any vulnerable moth overlapping enemy X's body box (16x16
; enemies: x+2..x+13, y+4..y+15). Only during play.
touch_kill:
    lda en_x,x
    sta kill_x
    clc
    adc #2
    sta ex0
    adc #11
    sta ex1
    lda en_y,x
    clc
    adc #4
    sta ey0
    adc #11
    sta ey1
    ; fall through
; box_kill_x: kill any vulnerable moth overlapping ex0..ey1 (it drifts away
; from kill_x). Returns with X = ei.
box_kill_x:
    lda game_mode
    cmp #GM_PLAY
    bne @safe
    lda phase
    cmp #PH_PLAY
    bne @safe
    ldx #0
@moth:
    lda p_state,x
    cmp #PS_ALIVE
    bne @nm
    lda p_invuln,x
    bne @nm
    jsr moth_box_x
    jsr box_overlap
    bcc @nm
    lda kill_x
    jsr kill_player
@nm:
    inx
    cpx #MAX_PLAYERS
    bne @moth
@safe:
    ldx ei
    rts

; ledge_step: walkers. A = speed (subpixels per frame). Steps one pixel when
; the subpixels wrap; turns around at walls and ledge ends. Preserves X.
ledge_step:
    clc
    adc en_xf,x
    sta en_xf,x
    bcc @done
    lda en_dir,x
    bne @look_left
    lda en_x,x
    clc
    adc #16
    jmp @look
@look_left:
    lda en_x,x
    sec
    sbc #1
@look:
    sta edx
    lda en_by,x                 ; wall ahead?
    clc
    adc #8
    tay
    lda edx
    jsr is_solid
    bcs @turn
    lda en_by,x                 ; ground ahead?
    clc
    adc #16
    tay
    lda edx
    jsr is_solid
    bcc @turn
    lda en_dir,x
    bne :+
    inc en_x,x
    rts
:   dec en_x,x
@done:
    rts
@turn:
    lda en_dir,x
    eor #1
    sta en_dir,x
    rts

; random_turn: now and then pick a new direction (en_timer counts down)
random_turn:
    dec en_timer,x
    bne @no
    jsr rand
    and #63
    adc #40
    sta en_timer,x
    jsr rand
    and #3
    bne :+
    lda en_dir,x                ; 1 in 4: turn round
    eor #1
    sta en_dir,x
:   sec                         ; C=1: a decision was made
    rts
@no:
    clc
    rts

; -----------------------------------------------------------------------------
upd_bunny:
    jsr random_turn
    bcc @hop                    ; on a decision, maybe hop
    jsr rand
    and #1
    beq @hop
    lda en_hop,x
    bne @hop
    lda #1
    sta en_hop,x
@hop:
    lda en_hop,x
    beq @walk
    inc en_hop,x
    lda en_hop,x
    cmp #HOP_LEN
    bcc :+
    lda #0
    sta en_hop,x
:   tay
    lda en_by,x
    sec
    sbc hop_table,y
    sta en_y,x
@walk:
    lda en_speed
    jsr ledge_step
    jmp touch_kill

upd_beetle:
    jsr random_turn
    lda en_speed                ; three-quarter bunny speed
    lsr a
    lsr a
    sta tmp
    lda en_speed
    sec
    sbc tmp
    jsr ledge_step
    lda en_vx,x                 ; chomp animation
    beq :+
    dec en_vx,x
:   txa                         ; sniff a row of cells every 2 frames (staggered),
    eor frame                   ; not on frames already busy with a loop
    and #1
    ora search_done
    ora busy_frame
    bne :+
    jsr beetle_sniff
:   jmp touch_kill

; beetle_sniff: eat one trail cell touching the beetle (its 2x2 cells and the
; ring of cells around them). A loop flown 2 cells clear of its ledge is safe.
beetle_sniff:
    lda en_y,x
    lsr a
    lsr a
    lsr a
    sec
    sbc #1
    sta r0                      ; first row
    lda en_x,x
    lsr a
    lsr a
    lsr a
    sec
    sbc #1
    sta c0                      ; first column
    lda frame                   ; one of the 4 rows per sniff (all 4 in 8 frames)
    lsr a
    and #3
    sta r1
@row:
    lda r0
    clc
    adc r1
    cmp #30
    bcs @next_row
    sta tmp_cy
    lda #3
    sta c1
@col:
    lda c0
    clc
    adc c1
    cmp #32
    bcs @next_col
    sta tmp_cx
    jsr cnt_locate              ; any dots in this cell?
    stx tmp2
    ldx tmp_b
    lda cell_cnt,y
    and cnt_mask,x
    ldx tmp2
    cmp #0
    beq @next_col
    jmp eat_cell                ; one cell per sniff
@next_col:
    dec c1
    bpl @col
@next_row:
    rts

; eat_cell: X = beetle. Every dot on (tmp_cx, tmp_cy) is eaten, and each
; trail it belonged to is broken there.
eat_cell:
    lda #1
    sta search_done             ; this frame's heavy job (the light waits)
    lda #12
    sta en_vx,x                 ; chomp!
    stx tmp2
    ldy #TRAIL_LEN*2-1
@dot:
    lda trail_cx,y
    cmp tmp_cx
    bne @nd
    lda trail_cy,y
    and #$7F
    cmp tmp_cy
    bne @nd
    lda trail_age,y
    cmp #$FF
    beq @nd
    sta tmp_age
    lda #$FF
    sta trail_age,y
    lda trail_cy,y              ; close it
    and #$7F
    sta trail_cy,y
    sty tmp_r                   ; close every older dot of that trail
    tya
    and #TRAIL_LEN
    tax
@older:
    lda trail_age,x
    cmp #$FF
    beq :+
    cmp tmp_age
    bcc :+
    lda trail_cy,x
    and #$7F
    sta trail_cy,x
:   inx
    txa
    and #TRAIL_LEN-1
    bne @older
    ldy tmp_r
@nd:
    dey
    bpl @dot
    jsr cnt_locate              ; the cell is empty now
    ldx tmp_b
    lda cell_cnt,y
    and cnt_clear,x
    sta cell_cnt,y
    ldx tmp2
    jsr level_tile_at
    jsr queue_cell
    jmp sfx_chomp

upd_mimic:
    lda en_hop,x
    bne @awake
    jsr light_class             ; asleep: does a moth's light reach it?
    cmp #1
    bne @done
    lda #MIMIC_AWAKE
    sta en_hop,x
    jmp sfx_appear
@awake:
    dec en_hop,x
    bne :+
    lda en_by,x                 ; back to sleep, back to being a rock
    sta en_y,x
    rts
:   jsr nearest_moth            ; chase along the ledge
    lda mp
    bmi :+
    lda near_dx
    asl a                       ; sign -> carry
    lda #0
    rol a                       ; 1 = moth is to the left
    sta en_dir,x
:   lda #$C0
    jsr ledge_step
    lda frame                   ; scuttle bounce
    lsr a
    and #3
    tay
    lda en_by,x
    sec
    sbc mimic_bounce,y
    sta en_y,x
    jmp touch_kill
@done:
    rts

; Wisps hover at a spot (~3s), then flit a short way to another spot near
; where they started. Loop one while it hovers.
;   en_vx/en_vy = target, en_timer = hover time left, en_hop = bob phase
upd_wisp:
    inc en_hop,x
    lda en_timer,x
    beq @flit
    dec en_timer,x
    bne @bob
    jsr wisp_pick               ; hover over: choose the next spot
    jmp wisp_touch
@bob:
    lda en_hop,x                ; hovering: bob
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
    jmp wisp_touch
@flit:
    lda en_vx,x
    jsr step_toward_x
    lda en_vy,x
    jsr step_toward_y
    lda en_x,x
    cmp en_vx,x
    bne wisp_touch
    lda en_y,x
    cmp en_vy,x
    bne wisp_touch
    lda #180                    ; arrived: hover here
    sta en_timer,x
    ; fall through
wisp_touch:                     ; touching it steals your light (no harm otherwise)
    lda game_mode
    cmp #GM_PLAY
    bne @done
    lda en_x,x
    clc
    adc #2
    sta ex0
    adc #11
    sta ex1
    lda en_y,x
    clc
    adc #2
    sta ey0
    adc #11
    sta ey1
    ldx #0
@moth:
    lda p_state,x
    cmp #PS_ALIVE
    bne @nm
    lda p_dim,x
    bne @nm
    jsr moth_box_x
    jsr box_overlap
    bcc @nm
    lda #DIM_TIME
    sta p_dim,x
    lda #1
    sta class_dirty
    jsr sfx_steal
    ldy ei                      ; and it flits off at once
    lda #0
    sta en_timer,y
@nm:
    inx
    cpx #MAX_PLAYERS
    bne @moth
    ldx ei
@done:
    rts

; wisp_pick: next spot within +-32 x / +-16 y of the wisp's spawn point
wisp_pick:
    stx tmp2
    lda cur_level
    asl a
    asl a
    ora tmp2
    tay
    jsr rand
    and #63
    sec
    sbc #32
    clc
    adc lv_spawn_x,y
    sta en_vx,x
    jsr rand
    and #31
    sec
    sbc #16
    clc
    adc lv_spawn_y,y
    sta en_vy,x
    rts

; Spiders rest at the top of their thread, drop 32px, hang there (~3s: loop
; it now), climb back up, rest, and so on. They spit webs at you throughout.
;   en_by = rest y, en_vx = thread top, en_vy = 0 rest / 1 drop / 2 hang / 3 climb,
;   en_yf = time left in this stage, en_timer = web timer
upd_spider:
    lda en_vy,x
    bne @moving
    dec en_yf,x                 ; resting at the top
    bne @web
    inc en_vy,x
    jmp @web
@moving:
    cmp #1
    bne @hanging
    inc en_y,x                  ; dropping
    lda en_by,x
    clc
    adc #32
    cmp en_y,x
    bne @web
    inc en_vy,x
    lda #180
    sta en_yf,x
    jmp @web
@hanging:
    cmp #2
    bne @climbing
    dec en_yf,x
    bne @web
    inc en_vy,x
    jmp @web
@climbing:
    lda frame
    and #1
    bne @web
    dec en_y,x
    lda en_y,x
    cmp en_by,x
    bne @web
    lda #0
    sta en_vy,x
    lda #100
    sta en_yf,x
@web:
    dec en_timer,x              ; spit a web now and then
    bne @touch
    lda #WEB_EVERY
    sta en_timer,x
    lda web_t
    bne @touch
    jsr nearest_moth
    lda near_d
    cmp #140
    bcs @touch
    lda en_x,x
    clc
    adc #4
    sta web_x
    lda en_y,x
    clc
    adc #10
    sta web_y
    lda #0
    sta web_xf
    sta web_yf
    lda near_dx                 ; velocity ~ direction to the moth
    jsr web_speed
    sta web_vx
    lda near_dy
    jsr web_speed
    sta web_vy
    lda #WEB_LIFE
    sta web_t
    jsr sfx_spit
@touch:
    jmp touch_kill

; web_speed: A = signed distance -> signed speed in 1/16 px (dist/4, at least
; 6 and at most 24 either way)
web_speed:
    cmp #$80
    ror a
    cmp #$80
    ror a
    bmi @neg
    cmp #24
    bcc :+
    lda #24
:   rts
@neg:
    cmp #$E8
    bcs :+
    lda #$E8
:   rts

; Bats fly for ~3s (fleeing any moth that comes near), then doze in mid-air
; for ~4s. A dozing bat only startles when a moth comes really close, so you
; can loop one while it dozes.
;   en_hop = doze time left (0 = flying), en_value = flight time left
; bat_home: Y = index of bat X's spawn point (its roost) in lv_spawn_x/_y.
bat_home:                       ; (not tmp: update_enemies counts with it)
    lda cur_level
    asl a
    asl a
    sta tmp_cy
    txa
    ora tmp_cy
    tay
    rts

upd_bat:
    jsr nearest_moth
    lda en_hop,x
    beq @flying
    lda near_d                  ; dozing: startled?
    cmp #BAT_STARTLE
    bcc @wake
    dec en_hop,x
    bne :+
@wake:
    lda #0
    sta en_hop,x
    lda #BAT_FLY
    sta en_value,x
:   jmp touch_kill
@flying:
    lda en_value,x              ; 0 = flying home to roost
    bne @count
    lda near_d
    cmp #BAT_FLEE
    bcs @homing
    lda #60                     ; a moth is close: flee first, roost later
    sta en_value,x
    bne @awake
@homing:
    jsr bat_home                ; one pixel a frame toward its roost
    lda lv_spawn_x,y
    jsr step_toward_x
    jsr bat_home
    lda lv_spawn_y,y
    jsr step_toward_y
    lda #0
    sta en_vx,x
    sta en_vy,x
    jsr bat_home
    lda lv_spawn_x,y
    cmp en_x,x
    bne :+
    lda lv_spawn_y,y
    cmp en_y,x
    beq @doze                   ; home: doze
:   jmp touch_kill
@count:
    dec en_value,x
    jmp @awake
@doze:
    lda #BAT_DOZE
    sta en_hop,x
    jmp touch_kill
@awake:
    lda near_d
    cmp #BAT_FLEE
    bcs @wander
    lda near_dx                 ; flee: away from the moth, fast
    bmi :+
    lda #<-BAT_FAST
    bne :++
:   lda #BAT_FAST
:   sta tmp_c                   ; target vx
    lda near_dy
    bmi :+
    lda #<-(BAT_FAST*2/3)
    bne :++
:   lda #BAT_FAST*2/3
:   sta tmp_r                   ; target vy
    jmp @steer
@wander:
    dec en_timer,x
    bne @keep
    jsr bat_home                ; new wander direction, kept near its roost
    lda en_x,x
    sec
    sbc lv_spawn_x,y
    sta r0                   ; x - home x
    lda en_y,x
    sec
    sbc lv_spawn_y,y
    sta c0                   ; y - home y
    lda r0                   ; x: random, unless 48px+ from home
    bmi @xneg
    cmp #48
    bcc @xrnd
    lda #<-6
    bne @xset
@xneg:
    cmp #<-48
    bcs @xrnd
    lda #6
    bne @xset
@xrnd:
    jsr rand
    and #15
    sec
    sbc #8
@xset:
    sta en_dir,x
    lda c0                   ; y: random, unless 32px+ from home
    bmi @yneg
    cmp #32
    bcc @yrnd
    lda #<-4
    bne @yset
@yneg:
    cmp #<-32
    bcs @yrnd
    lda #4
    bne @yset
@yrnd:
    jsr rand
    and #7
    sec
    sbc #4
@yset:
    sta en_by,x
    jsr rand
    and #63
    adc #50
    sta en_timer,x
@keep:
    lda en_dir,x
    sta tmp_c
    lda en_by,x
    sta tmp_r
@steer:
    lda en_vx,x                 ; ease velocity toward the target
    jsr @ease_c
    sta en_vx,x
    lda en_vy,x
    jsr @ease_r
    sta en_vy,x
    ; move x
    lda en_vx,x
    jsr vel_split               ; -> tmp_b = whole px, tmp_f = frac
    lda en_xf,x
    clc
    adc tmp_f
    sta tmp_age                 ; new frac
    lda en_x,x
    adc tmp_b
    sta edx                     ; new x
    lda en_vx,x                 ; probe the leading edge
    bmi :+
    lda edx
    clc
    adc #14
    jmp :++
:   lda edx
    clc
    adc #1
:   pha
    lda en_y,x
    clc
    adc #8
    tay
    pla
    jsr is_solid
    bcs @bounce_x
    lda edx
    cmp #12
    bcc @bounce_x
    cmp #229
    bcs @bounce_x
    sta en_x,x
    lda tmp_age
    sta en_xf,x
    jmp @move_y
@bounce_x:
    jsr @flip_vx
@move_y:
    lda en_vy,x
    jsr vel_split
    lda en_yf,x
    clc
    adc tmp_f
    sta tmp_age
    lda en_y,x
    adc tmp_b
    sta edx                     ; new y
    lda en_vy,x
    bmi :+
    lda edx
    clc
    adc #14
    jmp :++
:   lda edx
    clc
    adc #2
:   tay
    lda en_x,x
    clc
    adc #8
    jsr is_solid
    bcs @bounce_y
    lda edx
    cmp #24
    bcc @bounce_y
    cmp #208
    bcs @bounce_y
    sta en_y,x
    lda tmp_age
    sta en_yf,x
    jmp touch_kill
@bounce_y:
    lda en_vy,x
    eor #$FF
    clc
    adc #1
    sta en_vy,x
    lda en_by,x
    eor #$FF
    clc
    adc #1
    sta en_by,x
    jmp touch_kill
@flip_vx:
    lda en_vx,x
    eor #$FF
    clc
    adc #1
    sta en_vx,x
    lda en_dir,x
    eor #$FF
    clc
    adc #1
    sta en_dir,x
    rts
@ease_c:                        ; A = current; move 2 toward tmp_c
    cmp tmp_c
    beq @eased
    bmi :+                      ; (signed compare is fine in this small range)
    sec
    sbc #2
    cmp tmp_c
    bpl @eased
    lda tmp_c
    rts
:   clc
    adc #2
    cmp tmp_c
    bmi @eased
    lda tmp_c
@eased:
    rts
@ease_r:
    cmp tmp_r
    beq @eased
    bmi :+
    sec
    sbc #1
    rts
:   clc
    adc #1
    rts

; vel_split: A = signed speed in 1/16 px -> tmp_b = whole pixels (signed),
; tmp_f = fraction (1/256)
vel_split:
    sta tmp_f
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    sta tmp_b
    lda tmp_f
    asl a
    asl a
    asl a
    asl a
    sta tmp_f
    rts

; -----------------------------------------------------------------------------
; the web: one at a time, shared by all spiders
update_web:
    lda web_t
    bne :+
    rts
:   dec web_t
    beq @gone
    lda web_vx
    jsr vel_split
    lda web_xf
    clc
    adc tmp_f
    sta web_xf
    lda web_x
    adc tmp_b
    sta web_x
    lda web_vy
    jsr vel_split
    lda web_yf
    clc
    adc tmp_f
    sta web_yf
    lda web_y
    adc tmp_b
    sta web_y
    cmp #20
    bcc @gone
    lda web_x                   ; hit rock?
    clc
    adc #4
    pha
    lda web_y
    clc
    adc #4
    tay
    pla
    jsr is_solid
    bcs @gone
    lda game_mode               ; hit a moth? it's slowed
    cmp #GM_PLAY
    bne @done
    lda web_x
    sta ex0
    clc
    adc #7
    sta ex1
    lda web_y
    sta ey0
    clc
    adc #7
    sta ey1
    ldx #0
@moth:
    lda p_state,x
    cmp #PS_ALIVE
    bne @nm
    jsr moth_box_x
    jsr box_overlap
    bcc @nm
    lda #SLOW_TIME
    sta p_slow,x
    lda #1
    sta hud_dirty
    jsr sfx_tick
    jmp @gone
@nm:
    inx
    cpx #MAX_PLAYERS
    bne @moth
@done:
    rts
@gone:
    lda #0
    sta web_t
    rts

; -----------------------------------------------------------------------------
update_cocoon:
    dec en_timer,x
    bne @done
    lda #ES_FIREFLY
    sta en_state,x
    lda en_x,x                  ; 8x8 firefly from the middle of the cocoon
    clc
    adc #4
    sta en_x,x
    lda en_y,x
    clc
    adc #4
    sta en_y,x
    lda #FIREFLY_TIME
    sta en_timer,x
@done:
    rts

update_firefly:
    lda frame
    and #1
    bne @collect
    dec en_timer,x
    bne @rise
    jsr spawn_enemy             ; escaped: it goes home and wakes up
    lda #ES_WAKE
    sta en_state,x
    lda #WAKE_TIME
    sta en_timer,x
    rts
@rise:
    lda frame
    and #6
    bne @collect
    lda en_y,x
    cmp #FIREFLY_TOP
    bcc @collect
    dec en_y,x
@collect:
    lda en_x,x                  ; generous pickup box
    sec
    sbc #3
    sta ex0
    adc #13
    sta ex1
    lda en_y,x
    sec
    sbc #3
    sta ey0
    adc #13
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
    ldx ei
    rts
@got:
    ldy ei                      ; X = the moth that got it
    lda #ES_NONE
    sta en_state,y
    lda game_mode
    beq :+                      ; no points on the title screen
    lda en_value,y
    ldy #3                      ; hundreds
    jsr add_score
:   jsr sfx_collect
    ldx ei
    rts

; -----------------------------------------------------------------------------
; capture_enemies: called once per closed loop while `inside` holds its
; interior. Enemies inside are cocooned; boss weak points take a hit.
capture_enemies:
    lda #1
    ldy ls_team
    beq :+
    asl a
:   sta combo                   ; first one: 100 (200 for a team loop)
    ldx #0
@loop:
    stx ei
    lda en_state,x
    cmp #ES_WALK
    beq @check
    cmp #ES_WAKE
    bne @next
@check:
    lda en_type,x
    cmp #T_FEATHER
    beq @next
    lda en_y,x                  ; two points down the middle
    clc
    adc #5
    jsr @test
    bcs @caught
    ldx ei
    lda en_y,x
    clc
    adc #12
    jsr @test
    bcc @next
@caught:
    ldx ei
    lda en_type,x
    cmp #T_ORB
    bcc @cocoon
    jsr boss_hit                ; a boss weak point
    jmp @next
@cocoon:
    lda #ES_COCOON
    sta en_state,x
    lda #COCOON_TIME
    sta en_timer,x
    lda combo
    sta en_value,x
    asl combo
@next:
    ldx ei
    inx
    cpx #MAX_EN
    bne @loop
    rts
@test:                          ; A = pixel y, x = middle of enemy ei
    lsr a
    lsr a
    lsr a
    tay
    ldx ei
    lda en_x,x
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    jmp cell_inside

; -----------------------------------------------------------------------------
; Drawing. Each enemy owns 4 OAM slots; the order rotates every frame so that
; if more than 8 sprites share a scanline the flicker is shared out.
build_enemy_oam:
    ldx #0
@loop:
    stx ei
    txa
    clc
    adc frame
    and #MAX_EN-1
    asl a
    asl a
    asl a
    asl a
    adc #OAM_ENEMIES
    sta eo
    lda en_state,x
    cmp #ES_WALK
    beq @active
    cmp #ES_WAKE
    beq @wake
    cmp #ES_COCOON
    beq @cocoon
    cmp #ES_FIREFLY
    bne @hide
    jsr draw_firefly
    jmp @next
@wake:
    lda frame
    and #4
    bne @hide
@active:
    jsr draw_enemy
    jmp @next
@cocoon:
    jsr draw_cocoon
    jmp @next
@hide:
    jsr hide_slots
@next:
    ldx ei
    inx
    cpx #MAX_EN
    bne @loop
    jmp draw_extras

hide_slots:
    ldy eo
    lda #$FF
    sta oam,y
    sta oam+4,y
    sta oam+8,y
    sta oam+12,y
    rts

; light_class: sprite palette for enemy X from the nearest moth's light
;   within 1 block -> palette 1 (lit), 2 -> palette 2 (dim), else 3 (dark)
light_class:
    lda #3
    sta tmp2
    ldy #0
@moth:
    lda last_m,y
    cmp #$FF
    beq @nm
    lda en_x,x
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    sec
    sbc last_m,y
    bcs :+
    eor #$FF
    adc #1
:   sta tmp
    lda en_y,x
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    lsr a
    sec
    sbc last_m+1,y
    bcs :+
    eor #$FF
    adc #1
:   cmp tmp
    bcs :+
    lda tmp
:   clc
    adc bloom
    cmp tmp2
    bcs @nm
    sta tmp2
@nm:
    iny
    iny
    cpy #2*MAX_PLAYERS
    bne @moth
    ldy tmp2
    lda enemy_light,y
    rts

; draw_enemy: picks the tiles, layout and palette for enemy X's type
draw_enemy:
    lda en_type,x
    cmp #T_FEATHER
    bne :+
    jmp draw_feather
:   tay
    lda type_pal,y              ; $FF = by light, else a fixed palette
    bpl :+
    jsr light_class
:   sta epal
    ldy en_type,x
    lda type_tile,y
    sta etile
    lda type_anim,y             ; animation: frame bit -> +frame size
    beq @no_anim
    and frame
    beq @no_anim
    lda type_fsize,y
    clc
    adc etile
    sta etile
@no_anim:
    lda en_type,x               ; specials
    cmp #T_BUNNY
    bne :+
    lda en_hop,x                ; airborne bunnies stand still
    beq @layout
    lda #SPR_BUNNY
    sta etile
    jmp @layout
:   cmp #T_MIMIC
    bne :+
    lda en_hop,x
    bne @mimic_awake
    lda #2                      ; asleep: navy specks on see-through - it
    sta epal                    ; looks like rock in the dark
    lda #SPR_MIMIC
    sta etile
    jmp @layout
@mimic_awake:
    lda #SPR_MIMIC+4
    sta etile
    jmp @layout
:   cmp #T_BEETLE
    bne @layout
    lda en_vx,x                 ; chomping: shudder
    beq @layout
    lda #SPR_BEETLE+4
    sta etile
@layout:
    ldy en_type,x
    lda type_kind,y
    beq draw_full
    jmp draw_mirror

; draw_full: 4 tiles TL TR BL BR; facing left = flipped with columns swapped
draw_full:
    lda en_dir,x
    beq :+
    lda #$40
:   ora epal
    sta eflip
    ldy eo
    jsr put_rows
    lda etile
    sta oam+1,y
    clc
    adc #1
    sta oam+5,y
    adc #1
    sta oam+9,y
    adc #1
    sta oam+13,y
    lda eflip
    sta oam+2,y
    sta oam+6,y
    sta oam+10,y
    sta oam+14,y
    lda en_x,x
    sta tmp
    clc
    adc #8
    sta tmp_c
    lda en_dir,x
    beq :+
    lda tmp
    pha
    lda tmp_c
    sta tmp
    pla
    sta tmp_c
:   lda tmp
    sta oam+3,y
    sta oam+11,y
    lda tmp_c
    sta oam+7,y
    sta oam+15,y
    rts

; draw_mirror: left half (2 tiles) drawn twice, the right copy flipped
draw_mirror:
    ldy eo
    jsr put_rows
    lda etile
    sta oam+1,y
    sta oam+5,y
    clc
    adc #1
    sta oam+9,y
    sta oam+13,y
    lda epal
    sta oam+2,y
    sta oam+10,y
    ora #$40
    sta oam+6,y
    sta oam+14,y
    lda en_x,x
    sta oam+3,y
    sta oam+11,y
    clc
    adc #8
    sta oam+7,y
    sta oam+15,y
    rts

; put_rows: Y = OAM offset; y positions of a 16x16 enemy X
put_rows:
    lda en_y,x
    sec
    sbc #1
    sta oam,y
    sta oam+4,y
    clc
    adc #8
    sta oam+8,y
    sta oam+12,y
    rts

draw_feather:
    jsr hide_slots
    ldy eo
    lda en_y,x
    sec
    sbc #1
    sta oam,y
    lda frame
    lsr a
    lsr a
    lsr a
    and #1
    ora #SPR_FEATHER
    sta oam+1,y
    lda #0
    sta oam+2,y
    lda en_x,x
    sta oam+3,y
    rts

draw_cocoon:
    lda #SPR_COCOON
    sta etile
    lda #1
    sta epal
    jsr draw_mirror
    lda frame                   ; gentle sway
    lsr a
    lsr a
    lsr a
    and #3
    tay
    lda en_x,x
    clc
    adc sway_table,y
    ldy eo
    sta oam+3,y
    sta oam+11,y
    clc
    adc #8
    sta oam+7,y
    sta oam+15,y
    rts

draw_firefly:
    jsr hide_slots
    lda en_timer,x
    cmp #FIREFLY_WARN
    bcs :+
    lda frame
    and #8
    bne @done
:   ldy eo
    lda en_y,x
    sec
    sbc #1
    sta oam,y
    lda frame
    lsr a
    lsr a
    and #1
    ora #SPR_FIREFLY
    sta oam+1,y
    lda #$03
    sta oam+2,y
    lda frame
    lsr a
    lsr a
    lsr a
    and #7
    tay
    lda en_x,x
    clc
    adc wobble_table,y
    ldy eo
    sta oam+3,y
@done:
    rts

; draw_extras: spider threads, the web, the toad's tongue (OAM 168-255)
draw_extras:
    ldy #OAM_EXTRA
    lda #$FF
:   sta oam,y
    iny
    iny
    iny
    iny
    bne :-
    ldx #0
@spider:
    lda en_state,x
    cmp #ES_WALK
    bne @ns
    lda en_type,x
    cmp #T_SPIDER
    bne @ns
    stx tmp2                    ; 5 thread sprites per slot, from the body up
    txa
    asl a
    asl a
    clc
    adc tmp2                    ; slot * 5
    asl a
    asl a
    adc #OAM_EXTRA
    tay
    lda en_y,x
    sta tmp                     ; draw upward from just above the body
    lda #5
    sta tmp_f
@seg:
    lda tmp
    sec
    sbc #8
    bcc @ns
    sta tmp
    cmp en_vx,x                 ; reached the thread's top?
    bcc @ns
    sec
    sbc #1
    sta oam,y
    lda #SPR_THREAD
    sta oam+1,y
    lda #2
    sta oam+2,y
    lda en_x,x
    clc
    adc #4
    sta oam+3,y
    iny
    iny
    iny
    iny
    dec tmp_f
    bne @seg
@ns:
    inx
    cpx #MAX_EN
    bne @spider
    lda web_t                   ; the web
    beq :+
    lda web_y
    sec
    sbc #1
    sta oam+OAM_WEB
    lda #SPR_WEB
    sta oam+OAM_WEB+1
    lda #1
    sta oam+OAM_WEB+2
    lda web_x
    sta oam+OAM_WEB+3
:   jmp draw_tongue

hide_enemy_oam:
    lda #OAM_ENEMIES
    sta eo
@l:
    jsr hide_slots
    lda eo
    clc
    adc #16
    sta eo
    cmp #OAM_ENEMIES+16*MAX_EN
    bne @l
    rts

.segment "RODATA"
type_update:
    .word upd_bunny-1, upd_bat-1, upd_beetle-1, upd_wisp-1, upd_mimic-1, upd_spider-1
    .word upd_orb-1, upd_bubble-1, upd_feather-1
;               bunny       bat       beetle      wisp      mimic      spider      orb      bubble      feather
type_tile:  .byte SPR_BUNNY, SPR_BAT, SPR_BEETLE, SPR_WISP, SPR_MIMIC, SPR_SPIDER, SPR_ORB, SPR_BUBBLE, SPR_FEATHER
type_kind:  .byte 0,         1,       0,          0,        0,         1,          0,       0,          2   ; 0 full, 1 mirror
type_pal:   .byte $FF,       $FF,     $FF,        3,        $FF,       $FF,        3,       3,          0   ; $FF = by light
type_anim:  .byte 8,         8,       8,          8,        0,         16,         8,       16,         0   ; frame bit
type_fsize: .byte 4,         2,       4,          4,        4,         2,          4,       4,          1
HOP_LEN = 22
hop_table:
    .byte 0, 2, 4, 6, 7, 8, 9, 10, 10, 11, 11, 11, 11, 10, 10, 9, 8, 7, 6, 4, 2, 0
mimic_bounce:
    .byte 0, 2, 3, 2
enemy_light:
    .byte 1, 1, 2, 3
sway_table:
    .byte 0, 1, 0, $FF
wobble_table:
    .byte 0, 1, 2, 2, 1, 0, $FF, $FF
.segment "CODE"

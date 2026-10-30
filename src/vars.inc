; =============================================================================
; Lantern Moth - all RAM (declared first so zero-page addressing is used)
; =============================================================================

.segment "ZEROPAGE"
; ---------------------------------------------------------------- scratch
ptr:        .res 2
ptr2:       .res 2
tmp:        .res 1
tmp2:       .res 1
tmp_cx:     .res 1
tmp_cy:     .res 1
tmp_age:    .res 1
tmp_r:      .res 1
tmp_c:      .res 1
tmp_f:      .res 1
tmp_d:      .res 1
tmp_b:      .res 1
acc:        .res 1
frame:      .res 1
nmi_ready:  .res 1
lag_frames: .res 1      ; frames where game logic overran (should stay 0)
loading:    .res 1      ; set while the screen is off for a load (lag not counted)
vq_dropped: .res 1      ; tile writes lost to a full vblank queue (should stay 0)
paused:     .res 1      ; play is paused (Start); also mutes the jingles

; ---------------------------------------------------------------- current player
; This block is swapped in/out of plr[] so the movement and trail code works
; on whichever moth is being updated. Keep it contiguous and PB_SIZE long.
pblock:
pos_xf:     .res 1
pos_x:      .res 1      ; top-left of the 16x16 moth
pos_yf:     .res 1
pos_y:      .res 1
vx_lo:      .res 1
vx_hi:      .res 1
vy_lo:      .res 1
vy_hi:      .res 1
flap_timer: .res 1
flap_anim:  .res 1
last_cx:    .res 1
last_cy:    .res 1
trail_head: .res 1      ; absolute index into the trail arrays (includes toff)
PB_SIZE = * - pblock
; derived per load (not saved)
cur_p:      .res 1
toff:       .res 1      ; 0 or 64: this player's half of the trail arrays
pad:        .res 1
pad_new:    .res 1
c_acc:      .res 1
c_fric:     .res 1
c_max_lo:   .res 1
c_max_hi:   .res 1
c_nmax_lo:  .res 1
c_nmax_hi:  .res 1
c_flap_lo:  .res 1
c_flap_hi:  .res 1
c_flapt:    .res 1

; movement scratch
new_f:      .res 1
cand_x:     .res 1
cand_y:     .res 1
box_x0:     .res 1
box_x1:     .res 1
box_y0:     .res 1
box_y1:     .res 1
new_cx:     .res 1
new_cy:     .res 1

; ---------------------------------------------------------------- video
vq_len:     .res 1
hud_send:   .res 1
hud_dirty:  .res 1
mask_val:   .res 1

; ---------------------------------------------------------------- light
bloom:      .res 1      ; 3 = dark .. 0 = full light
bloom_timer:.res 1
light_dirty:.res 1      ; force a light rebuild this frame
last_m:     .res 4      ; light cache: block of moth 0 (x,y), moth 1 (x,y)
last_bloom: .res 1
mmx:        .res 1      ; block of the moth whose light window is being built
mmy:        .res 1
ar:         .res 1
ac:         .res 1
r0:         .res 1
r1:         .res 1
c0:         .res 1
c1:         .res 1
ac_lo:      .res 1
ac_hi:      .res 1
ar_hi:      .res 1
flare_timer:.res 1
class_dirty:.res 1      ; moths moved block / light radius changed
light_owed: .res 1      ; a light rebuild was put off to spread the work
scroll_x:   .res 1      ; screen shake (boss hits), used by the NMI
scroll_nt:  .res 1

; ---------------------------------------------------------------- loops
ls_state:   .res 1      ; loop pipeline stage (see trail.s)
ls_team:    .res 1      ; 1 = this loop uses both moths' trails
ls_a:       .res 1      ; player whose new dot closed the loop
ls_h:       .res 1      ; that new dot
ls_k1:      .res 1      ; A's dot the loop starts from
ls_k2:      .res 1      ; team: B's dot touching ls_h
ls_j2:      .res 1      ; team: B's dot touching A's trail elsewhere
ls_best:    .res 1
ls_i:       .res 1
ls_mode:    .res 1      ; polygon walk: 0 = toggle edges, 1 = unmark boundary
ls_prev:    .res 1
ls_minx:    .res 1
ls_maxx:    .res 1
ls_miny:    .res 1
ls_maxy:    .res 1
captures:   .res 1      ; loops closed (testing)
team_caps:  .res 1      ; team loops closed (testing)
best_d:     .res 1
ea:         .res 1
eb:         .res 1
fm_i:       .res 1
fm_o:       .res 1
dz_h:       .res 1      ; dissolve_open arguments
dz_d:       .res 1
dz_toff:    .res 1
dz_die:     .res 1

; ---------------------------------------------------------------- enemies
ei:         .res 1
seed:       .res 2      ; 16-bit LFSR state (never all zeros)
rand_t:     .res 1
en_speed:   .res 1
en_left:    .res 1      ; enemies not yet collected
fireflies:  .res 1
combo:      .res 1
mbx0:       .res 1
mbx1:       .res 1
mby0:       .res 1
mby1:       .res 1
ex0:        .res 1
ex1:        .res 1
ey0:        .res 1
ey1:        .res 1
eo:         .res 1
epal:       .res 1
etile:      .res 1
eflip:      .res 1
edx:        .res 1
mp:         .res 1      ; moth index in overlap loops

; ---------------------------------------------------------------- game
game_mode:  .res 1
phase:      .res 1
phase_timer:.res 2
num_players:.res 1
stage:      .res 1
time_sec:   .res 1
time_frac:  .res 1
stage_time: .res 1      ; time_sec at the start of this stage (restored on retry)
fps:        .res 1      ; 60 NTSC, 50 PAL
tally:      .res 1
sweep_row:  .res 1
pw_state:   .res 1      ; 0 none, 1 waiting to appear, 2 on screen
pw_x:       .res 1
pw_y:       .res 1
pw_type:    .res 1
pw_timer:   .res 1      ; quarter seconds
pw_sub:     .res 1
banner_on:  .res 1
jg_ptr:     .res 2
jg_timer:   .res 1
deaths:     .res 1      ; testing
cur_level:  .res 1      ; level being played (stage number, or TITLE_LEVEL)
cur_map:    .res 2      ; its packed map in ROM (collision + trail restore)
lt_t:       .res 1      ; level_tile_at scratch

; ---------------------------------------------------------------- title
menu_sel:   .res 1
ai_wp:      .res 1
logo_lit:   .res 1
title_timer:.res 2

.segment "OAM"
oam:        .res 256

; Stack page leftovers ($0100-$01BF; the stack itself stays well above)
.segment "LOWBSS"
inside:      .res 120        ; 30 rows x 32 cells, 1 bit each: current loop's interior
team_grid = inside           ; (the team search uses it before the interior is built)
flare_meta:  .res 32         ; 15 rows x 16 blocks, 1 bit each (+1 spare row)
hud_buf:     .res 32

.segment "BSS"
trail_cx:    .res TRAIL_LEN*2
trail_cy:    .res TRAIL_LEN*2  ; bit 7 (TRAIL_OPEN): can still be part of a new loop
trail_age:   .res TRAIL_LEN*2  ; $FF = unused
cell_cnt:    .res 240          ; live dots per cell, 2 bits each (3 = "3 or more")
vq_hi:       .res VQ_MAX
vq_lo:       .res VQ_MAX
vq_tile:     .res VQ_MAX
attr_shadow: .res 64           ; what the NMI uploads
attr_base:   .res 64           ; keep layer + flare, before the moths' light
attr_keep:   .res 64           ; light that stays (title logo, stage-clear sweep)
attr_work:   .res 64           ; the light being built (copied to attr_shadow when done)
pal_shadow:  .res 32
cclass:      .res 32           ; per moth: column distance class (16 each)
rclass:      .res 32           ; per moth: row distance class
banner_buf:  .res 20           ; 2 lines x 10 chars
plr:         .res 16*MAX_PLAYERS
p_state:     .res MAX_PLAYERS
p_lives:     .res MAX_PLAYERS
p_power:     .res MAX_PLAYERS
p_invuln:    .res MAX_PLAYERS
p_stimer:    .res MAX_PLAYERS
p_dim:       .res MAX_PLAYERS    ; frames of stolen light (wisp)
p_slow:      .res MAX_PLAYERS    ; frames of slowness (web)
p_score:     .res 6*MAX_PLAYERS  ; decimal digits, most significant first
hi_score:    .res 6
joy:         .res MAX_PLAYERS
joy_prev:    .res MAX_PLAYERS
joy_new:     .res MAX_PLAYERS
pads:        .res MAX_PLAYERS    ; what the moths obey (joy, or the attract AI)
pads_new:    .res MAX_PLAYERS
en_state:    .res 4
en_x:        .res 4
en_xf:       .res 4
en_y:        .res 4
en_by:       .res 4
en_dir:      .res 4
en_timer:    .res 4
en_hop:      .res 4
en_value:    .res 4              ; points (x100) when its firefly is collected

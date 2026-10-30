; =============================================================================
; Lantern Moth - trails and loops
;
; Each moth drops a glowing dot whenever its centre enters a new 8x8 cell.
; Player p's dots live at trail_*[p*64 .. p*64+63] as a ring buffer.
;
; LOOPS. When a new dot touches an older open dot of the same moth (at least
; MIN_LOOP back), the dots between them form a polygon. With two players, a new
; dot touching the OTHER moth's trail starts a team search: if the other trail
; also touches ours somewhere else, the two trail pieces form a polygon.
;
; Interior = scanline parity: every polygon edge that steps between row r and
; r+1 XORs all cells right of it on row r into a 32x30 bitmask. Cells toggled
; an odd number of times are inside. No flood fill, no stack.
;
; The work is spread over several frames (ls_state):
;   1-5  team search: grid of A's dots, grow it by one cell (2 frames), scan
;         B's dots (2 frames), find the joint
;   6    toggle polygon edges
;   7    clear the polygon's own cells, check something is inside -> capture
;   8    zip the trail away, cocoon enemies inside, chime, team power-up
;   9    build the flare shape and start it
; No new loop is looked for while the pipeline is busy.
; =============================================================================

LS_IDLE    = 0
LS_GRID    = 1
LS_GROW_H  = 2
LS_GROW_V  = 3
LS_SCAN    = 4
LS_JOINT   = 5
LS_EDGES   = 6
LS_UNMARK  = 7
LS_FINISH  = 8
LS_FLARE   = 9
SCAN_DOTS  = 32         ; B dots checked per frame by the team scan

.segment "ZEROPAGE"
busy_frame: .res 1
search_done:.res 1
.segment "BSS"
p_pend:     .res MAX_PLAYERS
.segment "ZEROPAGE"
new_dot:    .res 1          ; the dot add_trail just dropped
ls_dir:     .res 1          ; team: +1 / -1 walking B's trail from k2 to j2
ls_btoff:   .res 1
tail_tick:  .res 1
gw:         .res 8          ; team grid growing: two 32-bit rows

.segment "CODE"

; reset_trails: clear both players' trails and the loop pipeline
reset_trails:
    ldx #TRAIL_LEN*2-1
@l:
    lda #$FF
    sta trail_age,x
    lda #0
    sta trail_cy,x              ; (closed)
    dex
    bpl @l
    ldx #239
    lda #0
@c:
    sta cell_cnt,x
    dex
    bne @c
    sta cell_cnt
    lda #LS_IDLE
    sta ls_state
    sta flare_timer
    sta vq_len
    sta p_pend
    sta p_pend+1
    rts

; -----------------------------------------------------------------------------
; add_trail: current moth. Drops a dot on entering a new cell, then looks for
; a loop it closes.
add_trail:
    lda pos_x
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    sta new_cx
    lda pos_y
    clc
    adc #8
    lsr a
    lsr a
    lsr a
    sta new_cy
    cmp last_cy
    bne @changed
    lda new_cx
    cmp last_cx
    bne @changed
    jmp loop_search
@changed:
    lda new_cx
    sta last_cx
    lda new_cy
    sta last_cy

    ; reusing a slot that still holds a live dot: erase it first
    ldx trail_head
    lda trail_age,x
    cmp #$FF
    beq @free
    lda #$FF
    sta trail_age,x
    lda trail_cy,x              ; close it
    and #$7F
    sta trail_cy,x
    jsr cell_remove
    bcs @free
    jsr level_tile_at
    jsr queue_cell
@free:
    lda new_cx
    sta trail_cx,x
    sta tmp_cx
    lda new_cy
    sta tmp_cy
    ora #TRAIL_OPEN             ; a new dot can be part of a loop
    sta trail_cy,x
    lda #0
    sta trail_age,x
    jsr cell_add
    lda #TILE_TRAIL
    jsr queue_cell
    jsr ring_next
    sta trail_head
    ldx cur_p
    lda #1
    sta p_pend,x                ; this dot needs a loop check
    ; fall through

; loop_search: check the moth's newest dot for a loop it closes. At most one
; search per frame (they're the expensive part), and none while a loop is
; being processed; a check that has to wait stays pending.
loop_search:
    ldx cur_p
    lda p_pend,x
    beq @busy
    lda search_done
    ora ls_state
    ora light_owed              ; the light waited last frame: it goes first
    bne @busy
    lda #0
    sta p_pend,x
    lda #1
    sta search_done
    lda trail_head              ; the newest dot
    sec
    sbc #1
    and #TRAIL_LEN-1
    ora toff
    sta new_dot
    tax
    lda trail_cy,x            ; already zipped away?
    bpl @busy
    lda trail_cx,x
    sta new_cx
    lda trail_cy,x
    and #$7F
    sta new_cy
    jsr find_solo_loop
    bcs @found
    jmp find_team_start
@found:
    lda new_dot
    sta ls_h
    lda #0
    sta ls_team
    lda cur_p
    sta ls_a
    lda best_d
    sta ls_best
    lda #LS_EDGES
    sta ls_state
@busy:
    rts

; ring_next: X = trail index -> A = next index in the same player's ring
ring_next:
    txa
    clc
    adc #1
    and #TRAIL_LEN-1
    sta tmp
    txa
    and #TRAIL_LEN
    ora tmp
    rts

; find_solo_loop: oldest open dot of this moth that the new dot (ls_h) touches,
; at least MIN_LOOP back. C=1 with ls_k1 / best_d if found.
find_solo_loop:
    lda #0
    sta best_d
    ldy toff
@scan:
    lda trail_cx,y              ; cheapest test first: near the new dot?
    sec
    sbc new_cx
    clc
    adc #1
    cmp #3
    bcs @next
    lda trail_cy,y
    and #$7F
    sec
    sbc new_cy
    clc
    adc #1
    cmp #3
    bcs @next
    lda trail_cy,y            ; open implies alive
    bpl @next
    sty tmp
    lda new_dot
    sec
    sbc tmp
    and #TRAIL_LEN-1
    cmp #MIN_LOOP
    bcc @next
    cmp best_d
    bcc @next
    sta tmp_d
    sta best_d
    sty ls_k1
@next:
    iny
    tya
    and #TRAIL_LEN-1
    bne @scan
    lda best_d
    cmp #1                      ; C=1 if found
    rts

; touches_new: Y = dot. C=0 if it is the same cell as, or next to, (new_cx, new_cy)
touches_new:
    lda trail_cx,y
    sec
    sbc new_cx
    clc
    adc #1
    cmp #3
    bcs @no
    lda trail_cy,y
    and #$7F
    sec
    sbc new_cy
    clc
    adc #1
    cmp #3
@no:
    rts                         ; C=0: touching, C=1: not touching

; find_team_start: does the new dot touch the other moth's open trail?
find_team_start:
    lda num_players
    cmp #2
    bne @no
    lda cur_p
    eor #1
    tax
    lda trail_off,x
    tay
@scan:
    lda trail_cx,y              ; inline touch test, cheapest rejection first
    sec
    sbc new_cx
    clc
    adc #1
    cmp #3
    bcs @next
    lda trail_cy,y
    and #$7F
    sec
    sbc new_cy
    clc
    adc #1
    cmp #3
    bcs @next
    lda trail_cy,y
    bpl @next
    sty ls_k2                   ; any touching dot will do
    lda new_dot
    sta ls_h
    lda cur_p
    sta ls_a
    lda #1
    sta ls_team
    lda #LS_GRID
    sta ls_state
    rts
@next:
    iny
    tya
    and #TRAIL_LEN-1
    bne @scan
@no:
    rts

; -----------------------------------------------------------------------------
; update_loops: run one stage of the loop pipeline. Called once per frame
; before the moths move.
update_loops:
    ldx ls_state
    bne :+
    rts
:   lda #1
    sta busy_frame              ; heavy stage: the light waits a frame
    lda ls_jump_hi-1,x
    pha
    lda ls_jump_lo-1,x
    pha
    rts

.segment "RODATA"
.define LS_ROUTINES team_grid_build-1, grid_grow_h-1, grid_grow_v-1, team_scan-1, team_joint-1, loop_edges-1, loop_unmark-1, finish_capture-1, start_flare-1
ls_jump_lo: .lobytes LS_ROUTINES
ls_jump_hi: .hibytes LS_ROUTINES
.segment "CODE"

abort_loop:
    lda #LS_IDLE
    sta ls_state
    rts

; team_grid_build: bitmask of A's open dots, except the few next to the junction
team_grid_build:
    ldx #119
    lda #0
@clr:
    sta team_grid,x
    dex
    bpl @clr
    ldx ls_a
    ldy trail_off,x
@dot:
    lda trail_cy,y            ; (open implies alive)
    bpl @next
    sty tmp
    lda ls_h
    sec
    sbc tmp
    and #TRAIL_LEN-1
    cmp #TEAM_MIN
    bcc @next
    lda trail_cy,y
    and #$7F
    asl a
    asl a
    sta tmp
    lda trail_cx,y
    lsr a
    lsr a
    lsr a
    ora tmp
    tax
    lda trail_cx,y
    and #7
    sty tmp2
    tay
    lda team_grid,x
    ora set_bit,y
    sta team_grid,x
    ldy tmp2
@next:
    iny
    tya
    and #TRAIL_LEN-1
    bne @dot
    lda #LS_GROW_H
    sta ls_state
    rts

; The scan asks "is any of the 9 cells round this B dot in A's grid?". Growing
; A's grid by one cell in every direction first turns that into a single bit
; test. Rows are 4 bytes, column 0 in bit 7 of the first byte.

; grid_grow_h: every set cell also sets its left and right neighbours
grid_grow_h:
    ldx #0
@row:
    .repeat 4, I
        lda team_grid+I,x
        sta gw+I
        sta gw+4+I
    .endrep
    asl gw+3                    ; gw+0..3: shifted toward column 0
    rol gw+2
    rol gw+1
    rol gw+0
    lsr gw+4                    ; gw+4..7: shifted toward column 31
    ror gw+5
    ror gw+6
    ror gw+7
    .repeat 4, I
        lda team_grid+I,x
        ora gw+I
        ora gw+4+I
        sta team_grid+I,x
    .endrep
    txa
    clc
    adc #4
    tax
    cpx #120
    bne @row
    lda #LS_GROW_V
    sta ls_state
    rts

; grid_grow_v: ...and the rows above and below. gw+0..3 = the previous row as
; it was before this pass, gw+4..7 = the current row as it was.
grid_grow_v:
    lda #0
    .repeat 4, I
        sta gw+I
    .endrep
    tax
@row:
    .repeat 4, I
        lda team_grid+I,x
        sta gw+4+I
        ora gw+I
        sta team_grid+I,x
    .endrep
    cpx #0
    beq @first
    .repeat 4, I
        lda team_grid-4+I,x
        ora gw+4+I
        sta team_grid-4+I,x
    .endrep
@first:
    .repeat 4, I
        lda gw+4+I
        sta gw+I
    .endrep
    txa
    clc
    adc #4
    tax
    cpx #120
    bne @row
    ; set up the scan of B's trail
    lda ls_a
    eor #1
    tax
    lda trail_off,x
    sta ls_btoff
    sta ls_i
    lda #$FF
    sta ls_j2
    lda #0
    sta ls_best
    lda #LS_SCAN
    sta ls_state
    rts

; team_scan: SCAN_DOTS of B's dots per frame. The B dot touching A's trail that is
; farthest along B's trail from k2 becomes j2.
team_scan:
    lda #SCAN_DOTS
    sta tmp_f
@dot:
    ldy ls_i
    lda trail_cy,y            ; (open implies alive)
    bpl @next
    jsr near_grid
    bcc @next
    ldy ls_i                    ; how far along B's trail from k2: age difference
    ldx ls_k2                   ; (open dots age in lockstep, so age = order)
    lda trail_age,y
    sec
    sbc trail_age,x
    bcs :+
    eor #$FF
    adc #1
:   cmp #8
    bcc @next
    cmp ls_best
    bcc @next
    sta ls_best
    sty ls_j2
@next:
    inc ls_i
    lda ls_i
    and #TRAIL_LEN-1
    beq @done
    dec tmp_f
    bne @dot
    rts
@done:
    lda ls_j2
    cmp #$FF
    beq :+
    lda #LS_JOINT
    sta ls_state
    rts
:   jmp abort_loop

; near_grid: Y = dot. C=1 if its cell is in the grown team_grid (that is, any
; of the 9 cells around it holds one of A's dots). Changes X and Y.
near_grid:
    lda trail_cy,y
    and #$7F
    asl a
    asl a
    sta tmp_r                   ; row * 4
    lda trail_cx,y
    lsr a
    lsr a
    lsr a
    ora tmp_r
    tax
    lda trail_cx,y
    and #7
    tay
    lda team_grid,x
    and set_bit,y
    cmp #1                      ; C = bit set
    rts

; team_joint: the A dot that touches j2, farthest back from h -> k1
team_joint:
    ldy ls_j2
    lda trail_age,y
    cmp #$FF
    beq @abort
    lda trail_cx,y
    sta new_cx
    lda trail_cy,y
    and #$7F
    sta new_cy
    lda #0
    sta best_d
    ldx ls_a
    ldy trail_off,x
@scan:
    lda trail_cy,y            ; (open implies alive)
    bpl @next
    sty tmp
    lda ls_h
    sec
    sbc tmp
    and #TRAIL_LEN-1
    cmp #TEAM_MIN
    bcc @next
    cmp best_d
    bcc @next
    sta tmp_d
    jsr touches_new
    bcs @next
    lda tmp_d
    sta best_d
    sty ls_k1
@next:
    iny
    tya
    and #TRAIL_LEN-1
    bne @scan
    lda best_d
    beq @abort
    ; direction along B from k2 toward j2: toward newer dots if j2 is younger
    ldx ls_j2
    ldy ls_k2
    lda trail_age,x
    cmp trail_age,y
    lda #1
    bcc :+
    lda #$FF
:   sta ls_dir
    lda #LS_EDGES
    sta ls_state
    rts
@abort:
    jmp abort_loop

; -----------------------------------------------------------------------------
loop_edges:
    ldx #119
    lda #0
@clear:
    sta inside,x
    dex
    bpl @clear
    lda #0
    sta ls_mode
    jsr walk_poly
    lda #LS_UNMARK
    sta ls_state
    rts

loop_unmark:
    lda #$FF
    sta ls_minx
    sta ls_miny
    lda #0
    sta ls_maxx
    sta ls_maxy
    lda #1
    sta ls_mode
    jsr walk_poly
    ldx #119                    ; anything inside?
    lda #0
@any:
    ora inside,x
    dex
    bpl @any
    cmp #0
    bne @capture
    jmp abort_loop
@capture:
    inc captures
    lda ls_team
    beq :+
    inc team_caps
:   lda #LS_FINISH
    sta ls_state
    rts

; walk_poly: visit the polygon's vertices in order.
;   mode 0: toggle every edge (prev -> cur), including the closing edge
;   mode 1: clear each vertex's own cell from `inside`, track the bounding box
; Vertices: A's trail from k1 to h; for team loops then B's trail from k2 to j2.
walk_poly:
    lda ls_k1
    sta ls_prev
    tax
    jsr @visit_first
    ldx ls_k1
@a:
    cpx ls_h
    beq @a_done
    jsr ring_next
    tax
    jsr @visit
    jmp @a
@a_done:
    lda ls_team
    beq @close
    ldx ls_k2
    jsr @visit
@b:
    cpx ls_j2
    beq @close
    txa
    clc
    adc ls_dir
    and #TRAIL_LEN-1
    ora ls_btoff
    tax
    jsr @visit
    jmp @b
@close:
    lda ls_mode
    bne @done
    lda ls_prev
    sta ea
    lda ls_k1
    sta eb
    jsr edge_cross
@done:
    rts
; @visit: X = vertex. Preserves X.
@visit:
    lda ls_mode
    bne @visit_first
    lda ls_prev
    sta ea
    stx eb
    stx ls_prev
    stx tmp2
    jsr edge_cross
    ldx tmp2
    rts
@visit_first:
    lda ls_mode
    beq @ret
    stx tmp2
    lda trail_cx,x              ; bounding box
    cmp ls_minx
    bcs :+
    sta ls_minx
:   cmp ls_maxx
    bcc :+
    sta ls_maxx
:   lda trail_cy,x
    and #$7F
    cmp ls_miny
    bcs :+
    sta ls_miny
:   cmp ls_maxy
    bcc :+
    sta ls_maxy
:   lda trail_cy,x              ; clear the vertex's cell
    and #$7F
    asl a
    asl a
    sta tmp
    lda trail_cx,x
    tay
    lsr a
    lsr a
    lsr a
    ora tmp
    tax
    tya
    and #7
    tay
    lda inside,x
    and clear_bit,y
    sta inside,x
    ldx tmp2
@ret:
    rts

; edge_cross: toggle the parity mask for the edge trail[ea] -> trail[eb]
edge_cross:
    ldx ea
    ldy eb
    lda trail_cy,y
    and #$7F
    sta tmp_r
    lda trail_cy,x
    and #$7F
    cmp tmp_r
    beq @flat                   ; horizontal edges never cross a scanline
    bcc @a_top
    lda trail_cy,y              ; b is the upper end
    and #$7F
    sta tmp_r
    lda trail_cx,y
    jmp @toggle
@a_top:
    lda trail_cy,x
    and #$7F
    sta tmp_r
    lda trail_cx,x
@toggle:
    tay                         ; column where the edge leaves row tmp_r
    lda tmp_r
    asl a
    asl a
    tax
    lda inside,x
    eor suffix0,y
    sta inside,x
    lda inside+1,x
    eor suffix1,y
    sta inside+1,x
    lda inside+2,x
    eor suffix2,y
    sta inside+2,x
    lda inside+3,x
    eor suffix3,y
    sta inside+3,x
@flat:
    rts

; -----------------------------------------------------------------------------
; finish_capture: trail zips away, enemies inside are cocooned, chime. Team
; loops also drop a power-up in the middle.
finish_capture:
    lda ls_team
    bne @team
    ldx ls_a                    ; solo: the loop's own dots zip away
    lda trail_off,x
    sta dz_toff
    lda ls_h
    sta dz_h
    sec
    sbc ls_k1
    and #TRAIL_LEN-1
    sta dz_d
    jsr dissolve_open
    jsr capture_enemies
    jsr sfx_capture
    jmp @done
@team:
    ldx #0                      ; team: both trails zip away
    jsr dissolve_player_trail
    ldx #1
    jsr dissolve_player_trail
    jsr capture_enemies
    jsr team_power_drop
    lda #JG_TEAM
    jsr play_jingle
    jsr sfx_capture
@done:
    lda #LS_FLARE
    sta ls_state
    rts

; start_flare: interior -> flare shape (a frame after the capture, which is
; the heavier one), then the flare starts
start_flare:
    lda #0
    sta fm_i
    sta fm_o
@meta:
    ldx fm_i
    lda inside,x
    ora inside+4,x
    tay
    lda pair_tab,y
    asl a
    asl a
    asl a
    asl a
    sta acc
    lda inside+1,x
    ora inside+5,x
    tay
    lda pair_tab,y
    ora acc
    ldy fm_o
    sta flare_meta,y
    lda inside+2,x
    ora inside+6,x
    tay
    lda pair_tab,y
    asl a
    asl a
    asl a
    asl a
    sta acc
    lda inside+3,x
    ora inside+7,x
    tay
    lda pair_tab,y
    ora acc
    ldy fm_o
    sta flare_meta+1,y
    iny
    iny
    sty fm_o
    lda fm_i
    clc
    adc #8
    sta fm_i
    cmp #120
    bne @meta

    jsr build_flare_base
    lda #FLARE_TIME
    sta flare_timer
    lda #1
    sta light_dirty
    lda #LS_IDLE
    sta ls_state
    lda #1                      ; no new loop search on top of this frame
    sta search_done
    rts

; update_flare: count the flare down; when it ends, back to the kept light
update_flare:
    lda flare_timer
    beq @done
    dec flare_timer
    bne @done
    ldx #63
@cp:
    lda attr_keep,x
    sta attr_base,x
    dex
    bpl @cp
    lda #1
    sta light_dirty
@done:
    rts

; dissolve_player_trail: X = player. All its open dots zip away.
dissolve_player_trail:
    lda trail_off,x
    sta dz_toff
    txa
    asl a
    asl a
    asl a
    asl a
    tay
    lda plr+P_HEAD,y
    sec
    sbc #1
    and #TRAIL_LEN-1
    ora dz_toff
    sta dz_h
    lda #TRAIL_LEN-1
    sta dz_d
    ; fall through

; dissolve_open: in the trail at dz_toff, every open dot is closed so it can't
; anchor another loop. Dots up to dz_d back from dz_h also dissolve, newest
; first, one per frame (a "zip"): their age is set so the normal ager erases
; them. Older dots just keep fading on their own.
dissolve_open:
    ldx dz_toff
@zip:
    lda trail_cy,x              ; open? (open implies alive)
    bpl @znext
    and #$7F
    sta trail_cy,x
    stx tmp
    lda dz_h
    sec
    sbc tmp
    and #TRAIL_LEN-1
    cmp dz_d
    beq :+
    bcs @znext
:   sta tmp
    lda #TRAIL_DIE-1
    sec
    sbc tmp
    cmp trail_age,x             ; never make a dot younger than it is
    bcc @znext
    sta trail_age,x
@znext:
    inx
    txa
    and #TRAIL_LEN-1
    bne @zip
    rts

; cell_inside: A = cell x, Y = cell y. C=1 if inside the current loop.
cell_inside:
    sta tmp_c
    tya
    asl a
    asl a
    sta tmp
    lda tmp_c
    lsr a
    lsr a
    lsr a
    ora tmp
    tax
    lda tmp_c
    and #7
    tay
    lda inside,x
    and set_bit,y
    beq :+
    sec
    rts
:   clc
    rts

; -----------------------------------------------------------------------------
; update_trail: fade dots at TRAIL_FADE, erase them at TRAIL_DIE.
; Each moth's dots are aged on alternate frames, by 2 (half the work per frame).
; A moth with the tail power-up skips one of every 3 agings.
update_trail:
    lda frame
    and #1
    tax
    stx mp
    bne :+
    inc tail_tick               ; counts moth 0's agings
:   lda tail_tick
    cmp #3
    bcc :+
    lda #0
    sta tail_tick
:   lda game_mode               ; title screen: the attract moth's trail ages
    bne :+                      ; only 1 time in 3 (it's a showcase)
    lda tail_tick
    cmp #2
    beq @age
    rts
:   lda tail_tick
    bne @age                    ; tick 0 is the skipped one
    lda p_power,x
    and #PW_TAIL
    beq @age
    rts
@age:
    lda trail_off,x
    tax
@loop:
    lda trail_age,x
    cmp #$FF
    beq @next
    clc
    adc #2
    bcc :+
    lda #TRAIL_DIE              ; (never wrap past 255)
:   sta trail_age,x
    cmp #TRAIL_FADE
    beq @fade
    cmp #TRAIL_FADE+1
    bne @check_die
@fade:
    lda trail_cx,x              ; (no check for a brighter dot on the same
    sta tmp_cx                  ; cell: at worst it dims a moment early)
    lda trail_cy,x
    and #$7F
    sta tmp_cy
    lda #TILE_TRAIL_FAINT
    jsr queue_cell
    jmp @next
@check_die:
    cmp #TRAIL_DIE
    bcc @next
    lda #$FF
    sta trail_age,x
    lda trail_cy,x              ; close it
    and #$7F
    sta trail_cy,x
    jsr cell_remove
    bcs @next
    jsr level_tile_at           ; put back whatever the level had there
    jsr queue_cell
@next:
    inx
    txa
    and #TRAIL_LEN-1
    bne @loop
    rts

; Per-cell dot counters, so "is another dot still on this cell?" needs no scan.
; cell_cnt holds 2 bits per cell (byte = row*8 + col/4); 3 means "3 or more",
; and only then does removing a dot fall back to counting the trail.

; cnt_locate: (tmp_cx, tmp_cy) -> Y = byte, tmp_b = field index (0-3)
cnt_locate:
    lda tmp_cx
    and #3
    sta tmp_b
    lda tmp_cy
    asl a
    asl a
    asl a
    sta tmp
    lda tmp_cx
    lsr a
    lsr a
    ora tmp
    tay
    rts

; cell_add: a dot was placed at (tmp_cx, tmp_cy). Preserves X.
cell_add:
    jsr cnt_locate
    stx tmp2
    ldx tmp_b
    lda cell_cnt,y
    and cnt_mask,x
    cmp cnt_mask,x
    beq @sat                    ; already "3 or more"
    lda cell_cnt,y
    clc
    adc cnt_one,x
    sta cell_cnt,y
@sat:
    ldx tmp2
    rts

; cell_remove: X = a dot that just died (age already $FF). Sets tmp_cx/tmp_cy
; to its cell. C=1 if other live dots remain there. Preserves X.
cell_remove:
    lda trail_cx,x
    sta tmp_cx
    lda trail_cy,x
    and #$7F
    sta tmp_cy
    jsr cnt_locate
    stx tmp2
    ldx tmp_b
    lda cell_cnt,y
    and cnt_mask,x
    cmp cnt_mask,x
    beq @count
    lda cell_cnt,y
    sec
    sbc cnt_one,x
    sta cell_cnt,y
    and cnt_mask,x              ; any left?
    ldx tmp2
    cmp #1
    rts
@count:                         ; saturated: count the live dots here
    sty tmp_r
    lda #0
    sta tmp_d
    ldy #TRAIL_LEN*2-1
@lp:
    lda trail_cx,y
    cmp tmp_cx
    bne @nx
    lda trail_cy,y
    and #$7F
    cmp tmp_cy
    bne @nx
    lda trail_age,y
    cmp #$FF
    beq @nx
    inc tmp_d
@nx:
    dey
    bpl @lp
    lda tmp_d                   ; field = min(3, count)
    cmp #3
    bcc :+
    lda #3
:   tay
    lda cnt_val,y               ; value for field 0..3...
    ldy tmp_b
:   dey                         ; ...shifted into place
    bmi :+
    asl a
    asl a
    jmp :-
:   sta tmp
    ldy tmp_r
    lda cell_cnt,y
    and cnt_clear,x
    ora tmp
    sta cell_cnt,y
    ldx tmp2
    lda tmp_d
    cmp #1
    rts

; queue_cell: A = tile to write at (tmp_cx, tmp_cy) next vblank. Preserves X.
queue_cell:
    ldy vq_len
    cpy #VQ_MAX
    bcs @full
    sta vq_tile,y
    lda tmp_cy
    lsr a
    lsr a
    lsr a
    ora #$20
    sta vq_hi,y
    lda tmp_cy
    asl a
    asl a
    asl a
    asl a
    asl a
    ora tmp_cx
    sta vq_lo,y
    iny
    sty vq_len
    rts
@full:
    inc vq_dropped              ; a tile went missing (the tests watch this)
    rts

.segment "RODATA"
cnt_mask:  .byte $03, $0C, $30, $C0
cnt_one:   .byte $01, $04, $10, $40
cnt_clear: .byte $FC, $F3, $CF, $3F
cnt_val:   .byte 0, 1, 2, 3
.segment "CODE"

; queue_tile_at: A = tile, X = column, Y = row (any row, e.g. title text)
queue_tile_at:
    stx tmp_cx
    sty tmp_cy
    jmp queue_cell

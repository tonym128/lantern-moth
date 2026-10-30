; =============================================================================
; Lantern Moth - constants
; =============================================================================

; ---------------------------------------------------------------- hardware
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOY1      = $4016
JOY2      = $4017
APUFRAME  = $4017
DMCFREQ   = $4010
APUSTATUS = $4015
SQ1_VOL   = $4000
SQ1_SWEEP = $4001
SQ1_LO    = $4002
SQ1_HI    = $4003
SQ2_VOL   = $4004
SQ2_SWEEP = $4005
SQ2_LO    = $4006
SQ2_HI    = $4007
NOISE_VOL = $400C
NOISE_LO  = $400E
NOISE_HI  = $400F

CTRL_VAL  = %10001000   ; NMI on, sprites from $1000, bg from $0000, +1 increment
MASK_VAL  = %00011110   ; show bg + sprites, including the left 8 pixels

BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

; ---------------------------------------------------------------- moth physics
; Velocities are 8.8 fixed point (high byte = pixels, low byte = 1/256 px)
GRAVITY   = $000C       ; ~0.05 px/frame^2, floaty
MAX_FALL  = $0140       ; 1.25 px/frame
FLAP_ANIM = 8           ; frames of fast wingbeat after a flap
;                 normal  speed   control
ACC_N     = $18
ACC_S     = $22
ACC_C     = $30         ; control: snappier steering...
FRIC_N    = $10
FRIC_C    = $28         ; ...and stopping
MAX_N     = $0180       ; 1.5 px/frame
MAX_S     = $0240       ; speed: 2.25 px/frame
FLAP_N    = $FE90       ; -1.44 px/frame
FLAP_C    = $FF00       ; control: gentler flaps, more often = finer hovering
FLAPT_N   = 14          ; frames between auto-flaps while A is held
FLAPT_C   = 8

PW_SPEED   = $01        ; p_power bits
PW_CONTROL = $02
PW_TAIL    = $04

; hitbox inside the 16x16 sprite
HB_LEFT   = 3
HB_TOP    = 3
HB_SIZE   = 9

; ---------------------------------------------------------------- players
MAX_PLAYERS = 2
PS_OUT    = 0           ; not playing / no lives left
PS_ALIVE  = 1
PS_SPIRIT = 2           ; dead, waiting for the other moth to revive it
START_LIVES = 3
MAX_LIVES   = 9
SPAWN_SAFE  = 90        ; invulnerable frames at stage start
REVIVE_SAFE = 120       ; ...and after being revived
SPIRIT_DRIFT = 48       ; frames a spirit drifts away from what killed it

; ---------------------------------------------------------------- trail
TRAIL_LEN  = 64         ; dots per player (power of two)
TRAIL_OPEN = $80        ; trail_cy bit: the dot can still be part of a new loop
TRAIL_FADE = 140        ; age when a dot goes faint
TRAIL_DIE  = 210        ; age when it disappears (~3.5s, ~5.2s with the tail power-up)
MIN_LOOP   = 10         ; a solo loop needs at least this many dots
TEAM_MIN   = 6          ; team loops: dots this close to the junction don't count
FLARE_TIME = 63

; background tiles
TILE_BACK        = $00
TILE_TRAIL       = $05
TILE_TRAIL_FAINT = $06
TILE_SPACE       = $20

VQ_MAX = 12             ; max single-tile nametable writes per frame

; ---------------------------------------------------------------- game flow
GM_TITLE = 0
GM_PLAY  = 1

PH_INTRO  = 0
PH_PLAY   = 1
PH_DEAD   = 2
PH_TIMEUP = 3
PH_CLEAR  = 4
PH_OVER   = 5
PH_END    = 6

STAGE_TIME   = 60       ; seconds per stage (unused time carries over, plus this)
MAX_TIME     = 99
INTRO_TIME   = 120
DEAD_TIME    = 120
TIMEUP_TIME  = 150
OVER_TIME    = 240
END_TIME     = 400
LOW_TIME     = 10       ; tick every second below this

POWER_DELAY  = 48       ; quarter seconds into a stage before the power-up appears
POWER_LIFE   = 40       ; quarter seconds it stays
POWER_WARN   = 12       ; ...blinking for this long at the end

; OAM layout (byte offsets)
OAM_MOTHS   = 0         ; 2 x 4 sprites
OAM_ENEMIES = 32        ; 4 x 4 sprites
OAM_POWER   = 96        ; 2 sprites
OAM_BANNER  = 104       ; 16 sprites

# Lantern Moth

A cute single-screen arcade game for the NES. NROM-256 (mapper 0: 32KB PRG + 8KB CHR),
no extra chips. Written in ca65 assembly (cc65 toolchain).

You're a moth carrying a light through dark caves. Fly a loop with your glowing trail
around a cave creature to wrap it in a cocoon. It turns into a firefly, and you fly into it
to collect it. Collect every creature to clear the stage. Every 5th stage is a boss. Two players can share the cave
and close loops together.

## Controls
| | |
|---|---|
| D-pad left/right | drift |
| A or B | flap (hold to keep flapping) |
| Start | pause / resume (either pad) |
| Title: Up/Down/Select | 1 or 2 players |
| Title: Start | play |

## The game
- **15 stages**: 12 cave stages and a boss on stages 5, 10 and 15. The first 8 cave
  stages introduce a new creature every stage or two. Stages 11-14 mix them, with
  faster walkers.
- **Pause**: Start greys the picture, shows PAUSE and stops everything, sound included.
  Stage 1's intro banner reads LOOP THEM! as a first hint.
- **Instant death**: touching an enemy (or a feather, or the tongue) kills a moth.
- **3 lives** per player (up to 9 with extra-life power-ups).
- **Two players**: when a moth dies it becomes a pale spirit. The spirit drifts about
  40px away from what killed it and floats there. The other moth touches it to revive
  it, and the revived moth is invulnerable for 2 seconds. When no moth is alive, the
  stage restarts after a short pause (players with no lives left stay out), with the
  clock back where it was when the stage started. Game over
  when nobody has lives left.
- **Timer**: 60 seconds per stage. Time left over carries into the next stage, plus
  another 60s (max 99). Running out of time costs every player still in a life, and
  the stage restarts with 60s. Under 10s the clock ticks and its digits blink.
- **Score**:
  - Bunnies: 100, 200, 400, 800 for the 1st to 4th bunny caught in one loop. The points
    go to **whoever collects the firefly**.
  - Clearing a stage: 50 points per second left, paid to every player still in.
  - Power-ups: 500.
- **Team loops**: a loop made from both moths' trails counts. It drops a **team
  power-up** in the middle (whoever grabs it gets it), and its fireflies are worth double.
- **Power-ups** appear about 12s into each stage at one of the stage's spots and stay
  for 10s. They last until you lose a life:
  - **S**peed: top speed 1.5 → 2.25 px/frame.
  - **C**ontrol: snappier steering and stopping, gentler, faster flaps for fine hovering.
  - **T**ail: the trail lasts 50% longer (~5s), so you can make bigger loops.
  - **Heart**: +1 life, instant.
- **Enemies** (each pauses at some point, because a loop takes a few seconds to fly):
  | | Behaviour | How to catch it |
  |---|---|---|
  | Dust bunny | walks its ledge | loop the ledge |
  | Shadow bat | flutters near its roost and flees light at speed; every few seconds it flies home and dozes for 4s | loop it while it dozes at its roost; don't brush it (closer than ~20px wakes it) |
  | Snuffer beetle | walks its ledge and *eats trail dots*, breaking your loop | loop wide around it, quickly |
  | Mimic stone | a harmless rock until lit, then it wakes and chases along its ledge for 3s | loop it while it's still asleep, or bait it awake and loop the ledge |
  | Wisp | flits between spots, hovers 3s at each. Touching it **steals your light** for 4s (your blocks go dimmer) | loop it while it hovers |
  | Moth-eater spider | drops on a thread, hangs, climbs back; spits sticky webs that **slow you** for 3s | loop it while it hangs at the bottom |
- **Bosses**, drawn in the background tiles and shaken with scroll on every hit:
  - **The Great Owl** (stage 5, 4 hits): sleeps, opens its eyes and releases a glowing
    **orb** from its chest, which drifts and hovers around the hall. Loop the orb while it
    hovers. Feathers fall while it's awake.
  - **The Cave Toad** (stage 10, 6 hits): blows **bubbles** that rise and hover, and
    lashes out its **tongue** at moths above its mouth. Loop the bubbles; one loop round
    two bubbles is two hits.
  - **The Snuffer Queen** (stage 15, 8 hits): the snuffer beetles' mother. When she
    wakes, an **ember** drifts out of one of the glowing sacs on her shell and hovers
    like the owl's orb. Loop it. Meanwhile she lays **larvae** (snuffer beetles that
    eat trails) on the ledges, faster as she weakens, never right next to a moth.
    At half health two embers come out at once.
  - Each hit is 1000 points, the win 5000 to every player still in.
- **Title screen**: an attract-mode moth glides around the logo. The logo is made of
  game tiles, and every block its light touches stays lit. Its route closes a loop
  around "MOTH", which flares gold. Bunnies wander below and plants grow on the logo.
  Once the logo is fully lit it holds for a few seconds, then goes dark and starts again.

## How it looks good on a stock NES
- **Light is all attributes and palettes**: each 16×16 block is dark, dim, lit or
  flaring. No tiles are spent on light.
- The **cave back wall** only exists in the lit palette, so light *reveals* it.
- **Bunnies show only their eyes in the dark**, through sprite palette swaps by
  distance from the nearest moth.
- **Fireflies carry their own light**: the block a firefly is in turns lit.
- **Stage clear**: the whole cave lights up row by row.
- **Palette cycling** gives a candle flicker on glowing things, twinkling eyes, and the
  fading flare.
- **Mirrored sprites**: moths and cocoons store only their left half.

## Build
```
make            # python3 make_assets.py, then ca65 + ld65 -> lantern.nes, then usage
make run        # play it in RetroArch (Mesen core); override RETROARCH= / NES_CORE=
make test       # automated tests (needs Node)
```
Needs cc65 (ca65/ld65) and Python 3. Test in [Mesen](https://www.mesen.ca/): `lantern.dbg` gives it source-level debugging, and watching `lag_frames` and `vq_dropped` in its memory viewer shows any frame that ran too long or lost a tile write.

## Making levels
Stages are text maps in `levels/` (32×30 characters):

| char | | char | |
|---|---|---|---|
| `#` | rock | `.` | air |
| `m` | glow mushroom | `w` | glow flower |
| `g` | grass | `f` | fern |
| `v` | hanging vine | `p` | power-up spot (1-4) |
| `b` | dust bunny: left cell, two rows above its ledge (1-4) | `1` `2` | moth starts |
| `e` | snuffer beetle (on a ledge, like `b`) | `s` | mimic stone (on a ledge) |
| `a` | shadow bat (in open air) | `o` | wisp (in open air) |
| `k` | spider: under rock, within 8 rows | `O` `T` `Q` | owl / toad / queen boss (top-left cell of the art) |

At most 4 enemies per stage. On a boss stage the enemy letters (up to 3) are spawn
points the boss fills itself, such as the queen's larva ledges, and none are there at
the start.

Rows 0-1 are the HUD and row 2 is the ceiling, so keep those `#` (the build checks
that rows 0-1 match row 2, because they aren't stored). Stage order and
bunny speeds are the `STAGES` list at the top of `make_assets.py`.

**The validator**: a loop has to go *around* what it catches, so every bunny needs a
free-standing ledge with room to fly round it. That means 2 cells of air beside the
ledge, 3 rows above the bunny and 2 rows below the ledge (the same for `e` and `s`).
Bats and wisps need open air around their start (a bat's start is its roost, so it needs ~38px of air all round), and a spider needs rock above it to
hang from and clear air below for its whole drop. `make` refuses a level that breaks
this and says which rock is in the way.

## Source
| File | |
|---|---|
| `src/lantern.s` | reset, NTSC/PAL detection, NMI, main loop, input, screen loading |
| `src/player.s` | moth movement and power-up physics, spirits, revives, deaths, moth sprites |
| `src/trail.s` | trails, the loop pipeline (solo and team), dissolving, per-cell dot counts |
| `src/light.s` | attribute lighting, flare, palettes |
| `src/enemies.s` | all six enemy types, webs, cocoons, fireflies |
| `src/boss.s` | the owl and toad: states, eye blinks, orbs, bubbles, feathers, tongue, screen shake |
| `src/game.s` | stage flow, timer, score, lives, power-ups, HUD, banners |
| `src/title.s` | title screen and attract mode |
| `src/sound.s` | sound effects (pulse 1, noise) and jingles (pulse 2) |
| `src/defs.inc`, `src/vars.inc` | constants, all RAM |
| `make_assets.py` | pixel art, font, levels, lookup tables, jingles → `gen/` |
| `boss_art.py` | the procedurally drawn owl and toad (eyes open and closed) |
| `tests/` | automated playthrough tests (see below) |

### How loop detection works
Each moth drops a dot whenever its centre enters a new 8×8 cell. When a new dot touches
an older dot of the same trail, the dots between them form a polygon. With two players,
a dot touching the *other* moth's trail starts a team search instead. If the two trails
also touch somewhere else, the two trail pieces form the polygon.

The interior uses **scanline parity**. Every polygon edge that steps between two rows
XORs all cells to its right on that row into a 32×30 bitmask, using precomputed tables.
Cells toggled an odd number of times are inside. There's no flood fill and no stack.

The work is spread over several frames: the team search, toggling edges, checking the
interior, cocooning and zipping the trail away, then building the flare. Doing it all at
once would overrun a frame.

### Frame budget
Every frame has to fit in about 27,000 CPU cycles (NTSC). What I measured:

| Situation | Worst frame |
|---|---|
| 1 player | ~20,000 |
| Title screen | ~19,000 |
| 2-player stress test, every stage (both moths fast, crossing trails, team loops) | ~23,900 |
| NMI (vblank uploads) | ~1,300 of ~2,270 |

No dropped frames in any test. What keeps it there:
- The light is rebuilt only when a moth enters a new block, or a firefly does, and only
  near the moths.
- With two moths, the light build is split over 2 frames.
- Trails age on alternate frames.
- At most one loop search runs per frame, and none on the frame the flare starts.
- The team search grows A's dot grid by one cell first (2 frames), so checking each
  of B's dots is a single bit test rather than 9.
- "Is another dot on this cell?" is a 2-bit counter per cell rather than a search.
- A light rebuild waits a frame when a loop search (or a beetle bite) ran this frame.
- Beetles sniff for trail dots every 4th frame, skipping busy frames.
- Boss eyes open and close 6 tiles per frame through the vblank queue.

### Memory
- PRG: ~22.8KB of 32KB, so ~10KB free.
- **Stage maps are packed 4 bits a cell** (448 bytes a stage instead of 960, ~7KB for
  all 16 levels). Cave tiles $00-$0E are stored directly. The value $F means "look
  in this level's overlay", a rectangle of up to 16x16 cells holding the boss art or
  the title text. `level_tile_at` reads a cell directly (no unpacking pass, so
  collision stays cheap), and `load_nametable` builds the screen through it.
- CHR: background has 185 boss tiles (bosses are BG, so they light like the cave):
  $60-$FF first, then the gaps the cave tiles and font leave below $60 (16 still
  free). `solid_tab` marks rock and every boss tile solid wherever it landed. Sprites
  have the moths, bunnies and the new enemies from $60 up to $95.
- RAM: 136 bytes free in $0300-$07FF, 8 in $0100-$01BF, 22 bytes of zero page. A
  dot's "open" flag (can still be part of a loop) is bit 7 of its `trail_cy`
  rather than a 128-byte array of its own.
- `make` prints this after every build (`usage.py` reads `lantern.map`) and fails
  if PRG or zero page runs short.

## Tests
`tests/` runs the ROM headless in [jsnes](https://github.com/bfirsh/jsnes):
```
make test       # (runs npm install the first time)
make stress
```
The 134 checks cover:
- Title → 1P → all 15 stages cleared by honest loops (no freezing enemies): ledge
  walkers looped round their ledge, bats/wisps/spiders while they pause, all three
  bosses beaten by looping orbs, bubbles and embers. Time bonus, carry-over, THE END, hi score.
- Each enemy's special: bat flees and kills, beetle eats a trail, mimic wakes in light,
  wisp steals light, spider web slows, owl feathers and toad tongue kill, the queen
  wakes, lays larvae and sends two embers at half health.
- 1P death and restart, losing all lives, game over.
- 2P: the spirit drifts from its killer, revive, both dead → restart.
- Time up.
- Every power-up.
- A team loop: cocoon, double value, team power-up, points to the collector.
- Zero lag frames, and no tile writes lost to a full vblank queue.
- Pause, B to flap, the stage 1 hint, the low-time blink, and random seeding.

`npm run stress` flies two moths hard round every stage and reports the worst frame.

The tests move moths by writing their positions, so scripted paths ignore physics. They
test game logic, not feel.

## Not verified / notes
- **Sound**: the register writes are standard, but I couldn't listen to the effects or
  jingles. Check them in Mesen.
- **PAL**: the console's region is detected at boot so the timer counts real seconds on
  PAL (50Hz). The emulator here is NTSC-only, so the PAL path is untested. Movement runs
  at frame rate, so the game itself is ~17% slower on PAL.
- **Cosmetic**: a trail dot that fades while a newer dot is on the same cell dims a
  moment early.
- With two moths, light can lag the moth by one extra frame.
- Bosses and boss-stage pacing were tuned by test scripts, not by hand on a pad. Hover
  times (orb, bubble, wisp, spider, bat doze) are the knobs if a fight feels unfair.

## Next ideas
- Music (FamiStudio, 2A03 only), and a pause on Start.
- Level compression (RLE would roughly halve the 10KB of maps) to make room for more stages.

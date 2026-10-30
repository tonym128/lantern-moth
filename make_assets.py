#!/usr/bin/env python3
"""Builds everything the assembler includes, from human-editable sources.

  levels/*.txt   -> gen/level*.bin (nametables) + gen/levels.inc (spawns, starts, settings)
  pixel art here -> gen/lantern.chr
  lookup tables  -> gen/tables.inc
  note names     -> gen/sound.inc

Level map characters:
  #  rock            L  logo block (title)     .  air
  m  glow mushroom   g  grass   f  fern   v  hanging vine   w  glow flower
  enemies (top-left cell of the 16x16 enemy; 1-4 per stage):
    b  dust bunny   e  snuffer beetle   s  mimic stone    (stand on a ledge: the
                                                           cell two rows above it)
    a  shadow bat   o  wisp             k  spider (hangs under the rock above it)
  O  Great Owl (boss), T  Cave Toad (boss): top-left cell of the boss
  1 2  moth start (top-left cell)    p  power-up spot

Pixel chars: '.' = colour 0 (transparent/backdrop), '1' '2' '3' = palette colours.
"""
import json
import math
import os
import sys

import boss_art

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen")
LEVELS = os.path.join(HERE, "levels")

# ----------------------------------------------------------------------------- stages
# (file, bunny walk speed in 1/256 px per frame)
STAGES = [
    ("stage1.txt", 0x50),
    ("stage2.txt", 0x58),
    ("stage3.txt", 0x60),
    ("stage4.txt", 0x68),
    ("boss1.txt", 0x00),       # Great Owl
    ("stage5.txt", 0x70),
    ("stage6.txt", 0x78),
    ("stage7.txt", 0x80),
    ("stage8.txt", 0x88),
    ("boss2.txt", 0x00),       # Cave Toad
    ("stage9.txt", 0x90),
    ("stage10.txt", 0x98),
    ("stage11.txt", 0xA0),
    ("stage12.txt", 0xA8),
    ("boss3.txt", 0x60),       # Snuffer Queen (her larvae's speed)
]
ENEMY_CHARS = "baeosk"         # order = enemy type numbers in enemies.s
LEDGE_ENEMIES = "bes"
TITLE = "title.txt"
TITLE_SPEED = 0x48


def tile(rows):
    assert len(rows) == 8 and all(len(r) == 8 for r in rows), rows
    p0, p1 = [], []
    for r in rows:
        b0 = b1 = 0
        for i, ch in enumerate(r):
            v = 0 if ch == "." else int(ch)
            b0 |= (v & 1) << (7 - i)
            b1 |= ((v >> 1) & 1) << (7 - i)
        p0.append(b0)
        p1.append(b1)
    return bytes(p0 + p1)


def over(base, top):
    """Draw `top` over `base`; '.' in top is see-through."""
    return ["".join(t if t != "." else b for b, t in zip(br, tr))
            for br, tr in zip(base, top)]


def quads(rows16):
    """16x16 art -> TL, TR, BL, BR tiles."""
    return (tile([r[:8] for r in rows16[:8]]) + tile([r[8:] for r in rows16[:8]]) +
            tile([r[:8] for r in rows16[8:]]) + tile([r[8:] for r in rows16[8:]]))


# ----------------------------------------------------------------------------- background
# Colour use (background palettes):
#   1 = back wall + rock base  (black in the dark palette, so light "reveals" it)
#   2 = rock detail / plants   (faint hint in the dark so you can navigate)
#   3 = glow                   (always visible: trail, mushrooms, text, logo rims)
BACKWALL = ["........", "..1.....", ".1......", ".....1..",
            "........", "1.......", "....11..", "........"]

BG = {
    0x00: BACKWALL,
    # solid tiles are $01-$04 (is_solid checks that range)
    0x01: ["11111111", "11211111", "11111121", "11111111",
           "12111111", "11111211", "11111111", "11121111"],          # rock
    0x02: ["22222222", "21122112", "11111111", "11211111",
           "11111121", "11111111", "12111111", "11111111"],          # rock, top edge
    0x03: ["22222212", "22222212", "11111111", "22122222",
           "22122222", "11111111", "22222122", "22222122"],          # logo bricks
    0x04: ["33333333", "22222212", "11111111", "22122222",
           "22122222", "11111111", "22222122", "22222122"],          # logo, glowing top
    0x05: over(BACKWALL, ["........", "...3....", "..333...", ".33333..",
                          "..333...", "...3....", "........", "........"]),   # trail
    0x06: over(BACKWALL, ["........", "........", "...3....", "..3.3...",
                          "...3....", "........", "........", "........"]),   # trail, faint
    0x07: over(BACKWALL, ["........", "........", "..333...", ".33333..",
                          ".3.3.3..", "...2....", "...2....", "..222..."]),   # glow mushroom
    0x08: over(BACKWALL, ["........", "........", "........", "...2....",
                          ".2.2..2.", ".2.22.2.", "2222.22.", ".222222."]),   # grass tuft
    0x09: over(BACKWALL, ["....2...", "...2.2..", "..2.2.2.", ".2.222..",
                          "2.2.2...", ".2.2....", "..22....", "...2...."]),   # fern
    0x0A: over(BACKWALL, ["...2....", "...2....", "..2.....", "..2..3..",
                          "...2....", "...2....", "..3.2...", "....2..."]),   # hanging vine
    0x0B: over(BACKWALL, ["........", "..3.3...", "...3....", "..3.3...",
                          "...2....", ".2.2....", "..22.2..", "...222.."]),   # glow flower
}
TILE_OF = {"#": 0x01, "L": 0x03, "m": 0x07, "g": 0x08, "f": 0x09, "v": 0x0A, "w": 0x0B}

# 5x7 font, drawn in colour 3 at columns 1-5, rows 0-6. Stored at its ASCII code.
FONT = {
    " ": [""] * 7,
    "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
    "&": [".....", ".#.#.", "#####", "#####", ".###.", "..#..", "....."],   # heart
    "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
    ".": [".....", ".....", ".....", ".....", ".....", ".....", "..#.."],
    ">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
}


def glyph(rows5):
    rows = []
    for i in range(8):
        r = rows5[i] if i < len(rows5) and rows5[i] else "....."
        rows.append("." + r.replace("#", "3") + "..")
    return rows


# ----------------------------------------------------------------------------- sprites
# Moth: only the LEFT half is stored; the right half is the same tiles flipped.
# 1 = outline/eyes/antennae, 2 = body, 3 = wings.
MOTH_FRAMES = [
    ["....1...", ".....1..", "33....22", "3333.212",
     "33333322", "33333322", ".3333322", "..333222",
     "...33.22", "..3333.2", ".33333.2", ".3333..2",
     "..33....", "........", "........", "........"],
    ["....1...", ".....1..", "......22", ".....212",
     "...33322", ".3333322", "33333322", "33333222",
     "3333.222", ".333..22", "..33.3.2", "...3333.",
     "....33..", "........", "........", "........"],
]

# Dust bunny, 16x16 facing RIGHT. 1 = outline + pupils, 2 = fur, 3 = eye whites.
BUNNY_FRAMES = [
    ["................", ".....1....1.....", "....121..121....", "....121..121....",
     "...1122112211...", "..122222222221..", ".12222222222221.", ".12223322223321.",
     ".12223122223121.", ".12222222222221.", "1222222222222221", "1222222222222221",
     ".12222222222221.", "..122222222221..", "...1111111111...", "....11....11...."],
    ["................", "................", "....11....11....", "...1221..1221...",
     "...1122112211...", "..122222222221..", ".12222222222221.", ".12223322223321.",
     ".12223122223121.", "1222222222222221", "1222222222222221", "1222222222222221",
     ".12222222222221.", "..122222222221..", "...1111111111...", "...11......11..."],
]

COCOON = [
    "......1111......", "....11333311....", "...1333333331...", "..132222222231..",
    "..133333333331..", ".13333333333331.", ".12222222222221.", ".13313133131331.",
    ".13333133133331.", ".12222222222221.", ".13333333333331.", "..133333333331..",
    "..132222222231..", "...1333333331...", "....11333311....", "......1111......",
]

FIREFLY_FRAMES = [
    ["..1..1..", "...11...", ".221122.", "22211222",
     ".2.33.2.", "..3333..", "..3333..", "...33..."],
    ["..1..1..", "...11...", "...11...", ".221122.",
     "22.33.22", "2.3333.2", "..3333..", "...33..."],
]

# Power-up icons (moth palette: 1 red, 2 cream, 3 white)
ICONS = [
    ["....33..", "...332..", "..332...", ".3333333", "33333332",
     "...332..", "..332...", ".32....."],                                   # speed: bolt
    ["...3....", "...3....", "..323...", "3332333.", ".32223..",
     "..323...", ".3...3..", "3.....3."],                                   # control: star
    ["......33", ".....333", "..2.3333", ".2.23333", "2.2.333.",
     ".2.2....", "2.2.....", ".2......"],                                   # tail: comet
    [".11.11..", "1311111.", "1311111.", "1111111.", ".11111..",
     "..111...", "...1....", "........"],                                   # life: heart
]
def mirror(left):
    """8-wide left half -> 16-wide symmetric art"""
    return [r + r[::-1] for r in left]


def radial(fn):
    """16x16 art from fn(dx, dy) -> colour, centred between pixels 7 and 8"""
    rows = []
    for y in range(16):
        rows.append("".join(str(fn(x - 7.5, y - 7.5)) if fn(x - 7.5, y - 7.5) else "."
                            for x in range(16)))
    return rows


# Shadow bat (symmetric): 1 body/outline, 2 wing membrane, 3 eyes
BAT_FRAMES = [mirror([
    "........", "1.......", "11......", "121.....", "1221....", "12221..1", "122221.1",
    "12222111", "12221131", "1221.111", "121...11", "11.....1", "1.......",
    "........", "........", "........"]), mirror([
    "........", "........", "........", "........", ".......1", "......11", ".....111",
    "....1111", "...11131", "..122111", ".1222211", "12222211", "1222221.",
    "122221..", "1221....", "11......"])]

# Snuffer beetle, facing right: 1 outline/legs, 2 shell, 3 eye
BEETLE_FRAMES = [[
    "................", "................", "................", "................",
    "................", "................", "......11111.....", "....112222211...",
    "...12222222221..", "..1222212222211.", "..12222122222131", "..1222212222221.",
    ".11111111111111.", "..1.1..1..1.1...", ".1..1..1..1..1..", "................"], [
    "................", "................", "................", "................",
    "................", "................", "......11111.....", "....112222211...",
    "...12222222221..", "..1222212222211.", "..12222122222131", "..1222212222221.",
    ".11111111111111.", ".1..1..1..1..1..", "..1.1..1..1.1...", "................"]]


def _rock16():
    # the background rock-top + rock tiles with colours swapped (sprite colour 1
    # is navy in the dark palette, like background colour 2): a convincing rock
    top = ["22222222", "21122112", "11111111", "11211111", "11111121", "11111111", "12111111", "11111111"]
    fill = ["11111111", "11211111", "11111121", "11111111", "12111111", "11111211", "11111111", "11121111"]
    sw = lambda r: r.translate(str.maketrans("12", "21"))
    return [sw(r) * 2 for r in top + fill]


# asleep: the rock's dark fill is see-through (the cave behind is black), only
# the navy specks are drawn - in the dark it can't be told from real rock
MIMIC_SLEEP = [r.replace("2", ".") for r in _rock16()]
MIMIC_AWAKE = [list(r) for r in _rock16()]
for (ex, ey) in ((4, 5), (11, 5)):                 # eyes
    for dx in (0, 1):
        for dy in (0, 1):
            MIMIC_AWAKE[ey + dy][ex + dx] = "3"
for x in range(3, 13):                             # jagged mouth
    MIMIC_AWAKE[10 + (x % 2)][x] = "3"
MIMIC_AWAKE = ["".join(r) for r in MIMIC_AWAKE]


def _wisp(phase):
    def f(dx, dy):
        dy2 = dy - 1.5
        d = math.hypot(dx, dy2)
        if d < 2.6:
            return 3
        if d < 4.2:
            return 2
        if d < 5.6:
            return 1
        # flickering flame tip above
        flame_x = math.sin(phase + dy * 0.9) * 1.2
        if -7.5 <= dy < -3 and abs(dx - flame_x) < (dy + 8) * 0.35:
            return 2 if abs(dx - flame_x) < 0.8 else 1
        return 0
    return radial(f)


WISP_FRAMES = [_wisp(0.0), _wisp(2.2)]


def _sym_left(rows16):
    return [r[:8] for r in rows16]


# Spider (symmetric): 1 legs/outline, 2 body, 3 eyes. Thread attaches at the top.
SPIDER_FRAMES = [mirror([
    ".......1", "1......1", ".1.....1", "..1...11", "1..1.122", ".1.11222", "..112232",
    "...12222", "1..12222", ".1112222", "...12222", "..1.1222", ".1...111", "1.......",
    "........", "........"]), mirror([
    ".......1", ".......1", "1......1", ".1....11", "..1..122", "1..11222", ".11.2232",
    "...12222", "...12222", "1..12222", ".1112222", "...11222", "..1..111", ".1......",
    "1.......", "........"])]
THREAD = ["...1...."] * 8
WEB = ["..1.1...", "1..3..1.", ".13331..", "333333..", ".13331..", "1..3..1.", "..1.1...", "........"]


def _orb(glow):
    def f(dx, dy):
        d = math.hypot(dx, dy)
        if d < 5.2:
            crater = math.hypot(dx + 1.5, dy + 1) < 1.3 or math.hypot(dx - 2, dy - 1.8) < 1.0
            return 2 if crater else 3
        if d < 6.3:
            return 1
        if glow and d < 7.5 and (int(dx * 3 + dy * 5) % 3 == 0):
            return 1
        return 0
    return radial(f)


ORB_FRAMES = [_orb(False), _orb(True)]


def _bubble(r):
    def f(dx, dy):
        d = math.hypot(dx, dy)
        if r - 1.2 <= d < r:
            return 3
        if math.hypot(dx + 2.5, dy + 2.5) < 1.2:
            return 3                                   # shine
        if d < r - 1.2:
            return 1
        return 0
    return radial(f)


BUBBLE_FRAMES = [_bubble(7.2), _bubble(6.6)]
FEATHER_FRAMES = [
    [".......2", "......22", ".....232", "....232.", "...232..", "..232...", ".2.2....", "2......."],
    ["2.......", ".2......", "..22....", "..2322..", "...2322.", "....232.", ".....22.", "......2."]]
TONGUE = ["..1111..", "..1121..", "..1111..", "..1211..", "..1111..", "..1121..", "..1111..", "..1211.."]
TONGUE_TIP = ["........", "..1111..", ".112211.", ".122221.", ".112211.", "..1111..", "..1111..", "..1111.."]

SPARKLE = ["........", "...3....", "...3....", ".33.33..", "...3....",
           "...3....", "........", "........"]


# (name, frames, kind): full = 4 tiles flipped by direction, mirror = left half
# drawn twice, single = one 8x8 tile
SPRITE_SETS = [
    ("BAT", BAT_FRAMES, "mirror"),
    ("BEETLE", BEETLE_FRAMES, "full"),
    ("MIMIC", [MIMIC_SLEEP, MIMIC_AWAKE], "full"),
    ("WISP", WISP_FRAMES, "full"),
    ("SPIDER", SPIDER_FRAMES, "mirror"),
    ("THREAD", [THREAD], "single"),
    ("WEB", [WEB], "single"),
    ("ORB", ORB_FRAMES, "full"),
    ("BUBBLE", BUBBLE_FRAMES, "full"),
    ("FEATHER", FEATHER_FRAMES, "single"),
    ("TONGUE", [TONGUE], "single"),
    ("TONGUE_TIP", [TONGUE_TIP], "single"),
]
SPRITE_BASE = {}

# ----------------------------------------------------------------------------- bosses
# Boss art becomes background tiles from $60 up (solid: is_solid treats $60+ as rock).
BOSS_TILES = {}            # tile pixels -> index
BOSS_FIRST = 0x60


def boss_tile_index(t):
    if not any(any(r) for r in t):
        return 0x00                                     # empty: plain cave air
    # empty pixels show the cave back wall so the boss blends into the cave
    t = tuple(tuple(v if v else (1 if BACKWALL[y][x] == "1" else 0) for x, v in enumerate(r))
              for y, r in enumerate(t))
    if t not in BOSS_TILES:
        slots = boss_slots()
        assert len(BOSS_TILES) < len(slots), f"too many boss tiles (room for {len(slots)})"
        BOSS_TILES[t] = slots[len(BOSS_TILES)]
    return BOSS_TILES[t]


def boss_slots():
    """Background tile numbers boss art may use: $60-$FF first, then any gap the
    cave tiles and the font leave below $60 (never $20, the space)."""
    used = set(BG) | {ord(c) for c in FONT} | {0x00, 0x20}
    return list(range(BOSS_FIRST, 0x100)) + [i for i in range(1, BOSS_FIRST) if i not in used]


def boss_cells(art):
    h, w = len(art) // 8, len(art[0]) // 8
    return [[boss_tile_index(tuple(tuple(art[ty * 8 + y][tx * 8:tx * 8 + 8]) for y in range(8)))
             for tx in range(w)] for ty in range(h)]


BOSSES = {"O": boss_art.owl, "T": boss_art.toad, "Q": boss_art.queen}
BOSS_CHARS = "OTQ"         # order = boss type numbers in boss.s (1, 2, 3)
BOSS_INFO = {}             # char -> dict(open cells, closed cells, size)


def prepare_bosses():
    for ch, fn in BOSSES.items():
        op, cl = boss_cells(fn(True)), boss_cells(fn(False))
        BOSS_INFO[ch] = {"open": op, "closed": cl, "w": len(op[0]), "h": len(op)}


def build_chr():
    chr_rom = bytearray(8192)
    for idx, art in BG.items():
        chr_rom[idx * 16:idx * 16 + 16] = tile(art)
    spr = b""
    for f in MOTH_FRAMES:                      # $00-$03
        spr += tile(f[:8]) + tile(f[8:])
    for f in BUNNY_FRAMES:                     # $04-$0B
        assert all(len(r) == 16 for r in f) and len(f) == 16
        spr += quads(f)
    assert all(r == r[::-1] for r in COCOON)
    spr += tile([r[:8] for r in COCOON[:8]]) + tile([r[:8] for r in COCOON[8:]])  # $0C-$0D
    for f in FIREFLY_FRAMES:                   # $0E-$0F
        spr += tile(f)
    for f in ICONS:                            # $10-$13
        spr += tile(f)
    spr += tile(SPARKLE)                       # $14
    chr_rom[0x1000:0x1000 + len(spr)] = spr
    # new enemies from $60 (after the font)
    extra = b""
    def add(t):
        nonlocal extra
        idx = 0x60 + len(extra) // 16
        extra += t
        return idx
    for name, frames, kind in SPRITE_SETS:
        first = None
        for f in frames:
            assert all(len(r) == (8 if kind == "single" else 16) for r in f), name
            if kind == "full":
                i = add(quads(f))
            elif kind == "mirror":
                assert all(r == r[::-1] for r in f), f"{name} must be symmetric"
                i = add(tile([r[:8] for r in f[:8]]) + tile([r[:8] for r in f[8:]]))
            else:
                i = add(tile(f))
            first = i if first is None else first
        SPRITE_BASE[name] = first
    assert 0x60 + len(extra) // 16 <= 0x100
    chr_rom[0x1600:0x1600 + len(extra)] = extra
    # boss tiles in the background table from $60
    for t, idx in BOSS_TILES.items():
        chr_rom[idx * 16:idx * 16 + 16] = tile(["".join(str(v) if v else "." for v in r) for r in t])
    for ch, g in FONT.items():                 # font at ASCII codes, both tables
        t = tile(glyph(g))
        o = ord(ch) * 16
        chr_rom[o:o + 16] = t
        chr_rom[0x1000 + o:0x1000 + o + 16] = t
    return bytes(chr_rom)


# ----------------------------------------------------------------------------- levels
def read_map(name):
    rows = [l.rstrip("\n") for l in open(os.path.join(LEVELS, name)) if l.strip()]
    assert len(rows) == 30, f"{name}: need 30 rows, got {len(rows)}"
    for y, r in enumerate(rows):
        assert len(r) == 32, f"{name} row {y}: {len(r)} chars"
    return rows


def nametable(rows, text=None):
    out = bytearray()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            t = TILE_OF.get(ch, 0x00)
            if ch in "#L":
                above = rows[y - 1][x] if y > 0 else ch
                if above != ch:
                    t += 1                      # top-edge variant
            out.append(t)
    for (r, c, s) in (text or []):
        for i, ch in enumerate(s):
            out[r * 32 + c + i] = ord(ch)
    for ch, info in BOSS_INFO.items():
        for (bx, by) in find(rows, ch):
            for ty, line in enumerate(info["closed"]):          # bosses start asleep
                for tx, t in enumerate(line):
                    out[(by + ty) * 32 + bx + tx] = t
    return bytes(out)


ESCAPE = 0x0F     # packed cell value: "look the tile up in the level's overlay"


def pack_map(nt, name):
    """Packs a 32x30 nametable into 4 bits a cell, returning (cells, overlay).

    cells:   rows 2-29, two cells a byte (even column in the high nibble). Tiles
             $00-$0E are stored as they are. Rows 0-1 are not stored: they must
             match row 2 (the ceiling), and the game reads row 2 for them.
    overlay: (x, y, bytes) for the rectangle of tiles $0F and up (boss art,
             title text), 16 bytes a row, or None.
    """
    rows = [nt[y * 32:(y + 1) * 32] for y in range(30)]
    assert rows[0] == rows[2] and rows[1] == rows[2], f"{name}: rows 0-1 must be rock like row 2"
    big = [(x, y) for y in range(2, 30) for x in range(32) if rows[y][x] >= ESCAPE]
    overlay = None
    if big:
        ox, oy = min(x for x, _ in big), min(y for _, y in big)
        w, h = max(x for x, _ in big) - ox + 1, max(y for _, y in big) - oy + 1
        assert w <= 16 and h <= 16, f"{name}: big tiles span {w}x{h} cells (max 16x16)"
        ov = bytearray((h - 1) * 16 + w)
        for y in range(h):
            for x in range(w):
                ov[y * 16 + x] = rows[oy + y][ox + x]
        overlay = (ox, oy, bytes(ov))
    nib = lambda t: t if t < ESCAPE else ESCAPE
    cells = bytes((nib(rows[y][x]) << 4) | nib(rows[y][x + 1]) for y in range(2, 30) for x in range(0, 32, 2))
    return cells, overlay


def solid(ch):
    return ch in "#LX"


def with_bosses(rows):
    """Map with each boss region filled with 'X' (solid where the art is)."""
    g = [list(r) for r in rows]
    for ch, info in BOSS_INFO.items():
        for (bx, by) in find(rows, ch):
            for ty, line in enumerate(info["closed"]):
                for tx, t in enumerate(line):
                    g[by + ty][bx + tx] = "X" if t else "."
    return ["".join(r) for r in g]


def find(rows, ch):
    return [(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == ch]


def validate_stage(name, rows):
    """Every bunny must stand on a free ledge a moth can fly all the way around:
    2 cells of air on both sides of the ledge, 3 rows above the bunny, 2 below the ledge."""
    errs = []
    rows = with_bosses(rows)
    ledge_spawns = [p for ch in LEDGE_ENEMIES for p in find(rows, ch)]
    for (bx, by) in find(rows, "a") + find(rows, "o"):      # flyers: open air around
        bad = [(x, y) for y in range(by - 1, by + 3) for x in range(bx - 1, bx + 3) if solid(rows[y][x])]
        if bad:
            errs.append(f"flyer at {bx},{by}: needs open air around it, rock at {bad[0]}")
    for (bx, by) in find(rows, "a"):        # bats doze at their roost: room to loop round it
        cx, cy = bx * 8 + 8, by * 8 + 8
        bad = [(x, y) for y in range(max(0, by - 6), min(30, by + 7)) for x in range(max(0, bx - 6), min(32, bx + 8))
               if solid(rows[y][x]) and (x * 8 + 4 - cx) ** 2 + (y * 8 + 4 - cy) ** 2 < 38 ** 2]
        if bad:
            errs.append(f"bat at {bx},{by}: its roost needs ~38px of air all round to loop it, rock at {bad[0]}")
    for (bx, by) in find(rows, "k"):                         # spiders: rock above, room to drop
        if not any(solid(rows[y][bx]) or solid(rows[y][bx + 1]) for y in range(max(0, by - 8), by)):
            errs.append(f"spider at {bx},{by}: no rock within 8 rows above to hang from")
        bad = [(x, y) for y in range(by, by + 8) for x in range(bx - 2, bx + 4) if solid(rows[y][x])]
        if bad:
            errs.append(f"spider at {bx},{by}: needs 4 rows to drop and room to loop, rock at {bad[0]}")
    for (bx, by) in ledge_spawns:
        ly = by + 2
        if not (solid(rows[ly][bx]) and solid(rows[ly][bx + 1])):
            errs.append(f"bunny at {bx},{by}: no ledge two rows below")
            continue
        s = bx
        while solid(rows[ly][s - 1]):
            s -= 1
        e = bx + 1
        while solid(rows[ly][e + 1]):
            e += 1
        bad = [(x, y) for y in range(by - 3, by + 5) for x in range(s - 2, e + 3)
               if solid(rows[y][x]) and not (y == ly and s <= x <= e)]
        if bad:
            errs.append(f"bunny at {bx},{by}: rock at {bad[0]} blocks the loop around ledge {s}-{e}")
    for ch in "12":
        (x, y), = find(rows, ch)
        if any(solid(rows[yy][xx]) for yy in (y, y + 1) for xx in (x, x + 1)):
            errs.append(f"start {ch} at {x},{y} is in rock")
    if errs:
        sys.exit(f"{name}:\n  " + "\n  ".join(errs))


def logo_mask(rows):
    """1 bit per 16x16 metatile that contains logo blocks (15 rows x 2 bytes)."""
    bits = [[0] * 16 for _ in range(15)]
    for (x, y) in find(rows, "L"):
        bits[y // 2][x // 2] = 1
    out = []
    for r in bits:
        out.append(sum(b << (7 - i) for i, b in enumerate(r[:8])))
        out.append(sum(b << (7 - i) for i, b in enumerate(r[8:])))
    return out, sum(map(sum, bits))


def build_levels():
    lines = ["; generated by make_assets.py - do not edit",
             f"STAGE_COUNT = {len(STAGES)}",
             f"TITLE_LEVEL = {len(STAGES)}"]
    levels = list(STAGES) + [(TITLE, TITLE_SPEED)]
    tab = {k: [] for k in ("nen", "speed", "p1x", "p1y", "p2x", "p2y", "npw", "boss", "bossx", "bossy")}
    spx, spy, pwx, pwy, sptype, spaux = [], [], [], [], [], []
    mask, count = [0] * 30, 0
    overlays = []
    for i, (name, speed) in enumerate(levels):
        rows = read_map(name)
        is_title = name == TITLE
        if not is_title:
            validate_stage(name, rows)
        text = [(21, 11, "PUSH START"), (23, 12, "1 PLAYER"), (24, 12, "2 PLAYERS")] if is_title else None
        cells, ov = pack_map(nametable(rows, text), name)
        open(os.path.join(GEN, f"level{i}.bin"), "wb").write(cells)
        if ov:
            open(os.path.join(GEN, f"level{i}_ov.bin"), "wb").write(ov[2])
        overlays.append(ov)
        bun = sorted([(x, y, ENEMY_CHARS.index(ch)) for ch in ENEMY_CHARS for (x, y) in find(rows, ch)],
                     key=lambda e: (e[1], e[0]))
        boss = [(x, y, 1 + BOSS_CHARS.index(ch)) for ch in BOSS_CHARS for (x, y) in find(rows, ch)]
        assert boss or 1 <= len(bun) <= 4, f"{name}: 1-4 enemies"
        if boss:
            # a boss lays its enemies itself (none at the start), and slot 0 is
            # its weak point: its enemies' spawn points are slots 1-3
            assert len(bun) <= 3, f"{name}: a boss stage has at most 3 enemy spawn points"
            bun = [(0, 0, 0)] + bun
        pw = find(rows, "p")
        assert is_title or 1 <= len(pw) <= 4, f"{name}: 1-4 power-up spots"
        (x1, y1), = find(rows, "1")
        p2 = find(rows, "2") or [(x1, y1)]
        tab["nen"].append(0 if boss else len(bun))
        tab["speed"].append(speed)
        tab["p1x"].append(x1 * 8); tab["p1y"].append(y1 * 8)
        tab["p2x"].append(p2[0][0] * 8); tab["p2y"].append(p2[0][1] * 8)
        tab["npw"].append(len(pw))
        tab["boss"].append(boss[0][2] if boss else 0)
        tab["bossx"].append(boss[0][0] if boss else 0)
        tab["bossy"].append(boss[0][1] if boss else 0)
        for j in range(4):
            bx, by, bt = bun[j] if j < len(bun) else (0, 0, 0)
            spx.append(bx * 8); spy.append(by * 8); sptype.append(bt)
            aux = 0
            if j < len(bun) and ENEMY_CHARS[bt] == "k":      # spider: y where its thread starts
                filled = with_bosses(rows)
                y = by - 1
                while y > 0 and not (solid(filled[y][bx]) or solid(filled[y][bx + 1])):
                    y -= 1
                aux = (y + 1) * 8
            spaux.append(aux)
            px, py = pw[j] if j < len(pw) else (0, 0)
            pwx.append(px * 8); pwy.append(py * 8)
        if is_title:
            mask, count = logo_mask(rows)
    lines.append("lv_map_lo:\n    .byte " + ", ".join(f"<level{i}_map" for i in range(len(levels))))
    lines.append("lv_map_hi:\n    .byte " + ", ".join(f">level{i}_map" for i in range(len(levels))))
    ovl = lambda i, f: f(i) if overlays[i] else "0"
    lines.append("lv_ov_lo:\n    .byte " + ", ".join(ovl(i, lambda i: f"<level{i}_ov") for i in range(len(levels))))
    lines.append("lv_ov_hi:\n    .byte " + ", ".join(ovl(i, lambda i: f">level{i}_ov") for i in range(len(levels))))
    lines.append("lv_ov_x:\n    .byte " + ", ".join(str(o[0]) if o else "0" for o in overlays))
    lines.append("lv_ov_y:\n    .byte " + ", ".join(str(o[1]) if o else "0" for o in overlays))
    # packed row offsets by cell row (rows 0-1 read row 2)
    offs = [max(y, 2) * 16 - 32 for y in range(30)]
    lines.append("lv_row_lo:\n    .byte " + ", ".join(str(o & 255) for o in offs))
    lines.append("lv_row_hi:\n    .byte " + ", ".join(str(o >> 8) for o in offs))
    for k in ("nen", "speed", "p1x", "p1y", "p2x", "p2y", "npw", "boss", "bossx", "bossy"):
        lines.append(f"lv_{k}:\n    .byte " + ", ".join(str(v) for v in tab[k]))
    for k, v in (("lv_spawn_x", spx), ("lv_spawn_y", spy), ("lv_pw_x", pwx), ("lv_pw_y", pwy),
                 ("lv_type", sptype), ("lv_aux", spaux)):
        lines.append(f"{k}:\n    .byte " + ", ".join(str(n) for n in v))
    lines.append("logo_mask:\n    .byte " + ", ".join(f"${b:02X}" for b in mask))
    lines.append(f"LOGO_BLOCKS = {count}")
    # boss eye swaps: cells that differ between eyes open and closed
    for ch, label in (("O", "owl"), ("T", "toad"), ("Q", "queen")):
        info = BOSS_INFO[ch]
        cells = [(tx, ty, info["open"][ty][tx], info["closed"][ty][tx])
                 for ty in range(info["h"]) for tx in range(info["w"])
                 if info["open"][ty][tx] != info["closed"][ty][tx]]
        assert len(cells) <= 18, f"{label}: {len(cells)} eye cells (swapped 6 a frame, max 18)"
        lines.append(f"{label.upper()}_EYE_CELLS = {len(cells)}")
        lines.append(f"{label}_eye_dx:\n    .byte " + ", ".join(str(c[0]) for c in cells))
        lines.append(f"{label}_eye_dy:\n    .byte " + ", ".join(str(c[1]) for c in cells))
        lines.append(f"{label}_eye_open:\n    .byte " + ", ".join(f"${c[2]:02X}" for c in cells))
        lines.append(f"{label}_eye_closed:\n    .byte " + ", ".join(f"${c[3]:02X}" for c in cells))
    lines.append(f"OWL_W = {BOSS_INFO['O']['w']}\nOWL_H = {BOSS_INFO['O']['h']}")
    lines.append(f"TOAD_W = {BOSS_INFO['T']['w']}\nTOAD_H = {BOSS_INFO['T']['h']}")
    lines.append(f"QUEEN_W = {BOSS_INFO['Q']['w']}\nQUEEN_H = {BOSS_INFO['Q']['h']}")
    lines.append("queen_sac_x:\n    .byte " + ", ".join(str(x) for x, _ in boss_art.QUEEN_EMBERS))
    lines.append("queen_sac_y:\n    .byte " + ", ".join(str(y) for _, y in boss_art.QUEEN_EMBERS))
    # solid_tab[tile]: 1 for rock (tiles $01-$04) and every boss tile
    solid_tiles = {1, 2, 3, 4} | set(BOSS_TILES.values())
    lines.append("solid_tab:")
    for i in range(0, 256, 32):
        lines.append("    .byte " + ", ".join("1" if t in solid_tiles else "0" for t in range(i, i + 32)))
    lines.append(f"OWL_CHEST_X = {boss_art.OWL_CHEST[0]}\nOWL_CHEST_Y = {boss_art.OWL_CHEST[1]}")
    lines.append(f"TOAD_MOUTH_X = {boss_art.TOAD_MOUTH[0]}\nTOAD_MOUTH_Y = {boss_art.TOAD_MOUTH[1]}")
    for i in range(len(levels)):
        lines.append(f"level{i}_map:\n    .incbin \"gen/level{i}.bin\"")
        if overlays[i]:
            lines.append(f"level{i}_ov:\n    .incbin \"gen/level{i}_ov.bin\"")
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------- lookup tables
def build_tables():
    lines = ["; generated by make_assets.py - do not edit"]
    # suffixN[x]: bits of byte N (columns 8N..8N+7, MSB = leftmost) for columns > x
    for n in range(4):
        vals = []
        for x in range(32):
            k = 8 * n + 7 - x
            vals.append(0xFF if k >= 8 else (0 if k <= 0 else (1 << k) - 1))
        lines.append(f"suffix{n}:\n    .byte " + ", ".join(f"${v:02X}" for v in vals))
    # pair_tab[b]: 8 cell bits -> 4 metatile bits (set if either cell is)
    vals = []
    for b in range(256):
        v = 0
        for i in range(4):
            if b & (0xC0 >> (2 * i)):
                v |= 8 >> i
        vals.append(v)
    # sine: 64 steps per turn, -32..+32
    lines.append("sine:\n    .byte " + ", ".join(f"${(round(32 * math.sin(i * math.pi / 32)) & 0xFF):02X}" for i in range(64)))
    lines.append("pair_tab:")
    for i in range(0, 256, 16):
        lines.append("    .byte " + ", ".join(f"${v:02X}" for v in vals[i:i + 16]))
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------- sound
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def note_period(name):
    n, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NOTE_NAMES.index(n)
    f = 440.0 * 2 ** ((midi - 69) / 12)
    return round(1789773 / (16 * f) - 1)


# jingles for pulse 2: (note or "-" for a rest, frames)
JINGLES = {
    "start":    [("C5", 6), ("E5", 6), ("G5", 6), ("C6", 14)],
    "ready":    [("G4", 8), ("C5", 8), ("E5", 16)],
    "clear":    [("C5", 5), ("E5", 5), ("G5", 5), ("C6", 5), ("-", 4), ("G5", 5), ("C6", 20)],
    "gameover": [("G4", 14), ("F4", 14), ("E4", 14), ("C4", 30)],
    "power":    [("E5", 4), ("G5", 4), ("B5", 4), ("E6", 10)],
    "team":     [("C5", 4), ("G5", 4), ("C5", 4), ("G5", 4), ("C6", 12)],
    "timeup":   [("C5", 10), ("-", 4), ("C5", 10), ("-", 4), ("G4", 24)],
    "end":      [("C5", 8), ("E5", 8), ("G5", 8), ("E5", 8), ("G5", 8), ("C6", 8),
                 ("-", 6), ("G5", 6), ("C6", 30)],
}


def build_sound():
    notes = sorted({n for j in JINGLES.values() for n, _ in j if n != "-"},
                   key=lambda n: -note_period(n))
    idx = {n: i + 1 for i, n in enumerate(notes)}        # 0 = rest
    lines = ["; generated by make_assets.py - do not edit",
             "note_lo:\n    .byte 0, " + ", ".join(f"${note_period(n) & 0xFF:02X}" for n in notes),
             "note_hi:\n    .byte 0, " + ", ".join(f"${note_period(n) >> 8:02X}" for n in notes)]
    for name, seq in JINGLES.items():
        body = ", ".join(f"{idx.get(n, 0)}, {d}" for n, d in seq)
        lines.append(f"jingle_{name}:\n    .byte {body}, $FF")
    names = list(JINGLES)
    lines.append("jingle_lo:\n    .byte " + ", ".join(f"<jingle_{n}" for n in names))
    lines.append("jingle_hi:\n    .byte " + ", ".join(f">jingle_{n}" for n in names))
    for i, n in enumerate(names):
        lines.append(f"JG_{n.upper()} = {i}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    os.makedirs(GEN, exist_ok=True)
    prepare_bosses()
    open(os.path.join(GEN, "tables.inc"), "w").write(build_tables())
    open(os.path.join(GEN, "levels.inc"), "w").write(build_levels())
    open(os.path.join(GEN, "sound.inc"), "w").write(build_sound())
    open(os.path.join(GEN, "lantern.chr"), "wb").write(build_chr())
    open(os.path.join(GEN, "tiles.inc"), "w").write(
        "; generated by make_assets.py - do not edit\n" +
        "".join(f"SPR_{k} = ${v:02X}\n" for k, v in SPRITE_BASE.items()) +
        f"BOSS_TILE_COUNT = {len(BOSS_TILES)}\n")
    json.dump({"stages": [os.path.splitext(f)[0] for f, _ in STAGES], "title": os.path.splitext(TITLE)[0]},
              open(os.path.join(GEN, "stages.json"), "w"))     # stage order, for the tests
    print(f"wrote gen/: chr, tables, sound, {len(STAGES)} stages + title")

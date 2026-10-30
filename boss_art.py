"""Procedural pixel art for the three bosses (background tiles).

Each boss is drawn into a grid of palette indices (0 = empty, 1 = dark fill,
2 = detail/outline, 3 = glow). In the dark palette colour 1 is black and colour 2
a faint navy, so a boss in the dark is a faint silhouette with glowing eyes.
Moth light reveals it in warm browns.
"""
import math


def blank(w, h):
    return [[0] * w for _ in range(h)]


def ellipse(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def outline(g, colour=2):
    """Pixels on the shape's edge become `colour`."""
    h, w = len(g), len(g[0])
    out = [row[:] for row in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or g[ny][nx] == 0:
                    if g[y][x] != 3:
                        out[y][x] = colour
                    break
    return out


# ----------------------------------------------------------------------------- owl
OWL_W, OWL_H = 80, 72          # 10 x 9 tiles


def owl(eyes_open=True):
    g = blank(OWL_W, OWL_H)
    for y in range(OWL_H):
        for x in range(OWL_W):
            body = ellipse(x, y, 40, 46, 30, 24)
            head = ellipse(x, y, 40, 24, 25, 17)
            ear_l = 13 <= x <= 27 and y >= 2 + (27 - x) * 0.7 and y <= 16
            ear_r = 53 <= x <= 67 and y >= 2 + (x - 53) * 0.7 and y <= 16
            branch = y >= 64 and y <= 70
            if body or head or ear_l or ear_r:
                g[y][x] = 1
                if body:                                    # scalloped breast feathers
                    lx = x % 8                              # (tile-aligned so tiles repeat)
                    ly = y % 8
                    if ly == 6 - abs(lx - 4) // 2 and abs(x - 40) < 18 and y > 40:
                        g[y][x] = 2
                    if abs(x - 40) > 19 and (x % 4 == 0) and y > 34:  # wing stripes
                        g[y][x] = 2
            if branch:
                g[y][x] = 2 if ((x % 8) * 3 + y) % 7 == 0 or y in (64, 70) else 1
    # talons over the branch
    for cx in (30, 36, 44, 50):
        for y in range(61, 66):
            g[y][cx] = 3
    g = outline(g, 2)
    # facial disc rims
    for (ex, ey) in ((29, 24), (51, 24)):
        for y in range(ey - 10, ey + 11):
            for x in range(ex - 10, ex + 11):
                d = math.hypot(x - ex, y - ey)
                if 9 <= d < 10.2 and 0 <= y < OWL_H:
                    g[y][x] = 2
    # eyes
    for (ex, ey) in ((29, 24), (51, 24)):
        for y in range(ey - 8, ey + 9):
            for x in range(ex - 8, ex + 9):
                d = math.hypot(x - ex, y - ey)
                if eyes_open:
                    if d < 7:
                        g[y][x] = 3
                    if d < 3.2:
                        g[y][x] = 1                     # pupil
                    if 1.5 <= math.hypot(x - ex + 1.5, y - ey + 1.5) < 2.3:
                        g[y][x] = 3                     # catch-light ring
                else:
                    if d < 7:
                        g[y][x] = 1
                    if abs(y - (ey + 1 - (x - ex) ** 2 / 14)) < 0.8 and abs(x - ex) < 7:
                        g[y][x] = 3                     # sleepy closed lid
    # beak
    for y in range(31, 40):
        half = (39 - y) * 0.45
        for x in range(40 - 3, 41 + 3):
            if abs(x - 40) <= half:
                g[y][x] = 3
    return g


# ----------------------------------------------------------------------------- toad
TOAD_W, TOAD_H = 112, 72       # 14 x 9 tiles


def toad(eyes_open=True):
    g = blank(TOAD_W, TOAD_H)
    for y in range(TOAD_H):
        for x in range(TOAD_W):
            body = ellipse(x, y, 56, 56, 54, 32) and y < TOAD_H
            bump_l = ellipse(x, y, 30, 22, 15, 14)
            bump_r = ellipse(x, y, 82, 22, 15, 14)
            if body or bump_l or bump_r:
                g[y][x] = 1
                # warty spots (tile-aligned pattern so interior tiles repeat)
                if (x % 8, y % 8) in ((2, 1), (6, 5), (1, 6)) and y > 30:
                    g[y][x] = 2
            # front feet on the floor
            for fx in (22, 90):
                if abs(x - fx) < 10 and y >= 64:
                    g[y][x] = 1 if abs(x - fx) < 8 else 2
    g = outline(g, 2)
    # wide mouth
    for x in range(14, 99):
        y = int(44 + 5 * math.sin((x - 14) / 85 * math.pi))
        g[y][x] = 2
        g[y + 1][x] = 2
    # throat sac (glows faintly)
    for y in range(52, 66):
        for x in range(42, 71):
            if ellipse(x, y, 56, 58, 13, 6):
                g[y][x] = 2 if (x + y) % 3 else 3
    # eyes
    for (ex, ey) in ((30, 20), (82, 20)):
        for y in range(ey - 9, ey + 10):
            for x in range(ex - 9, ex + 10):
                d = math.hypot(x - ex, y - ey)
                if eyes_open:
                    if d < 8:
                        g[y][x] = 3
                    if abs(y - ey) < 1.5 and abs(x - ex) < 6:
                        g[y][x] = 1                     # slit pupil
                else:
                    if d < 8:
                        g[y][x] = 1
                    if abs(y - ey - 1) < 0.8 and abs(x - ex) < 7:
                        g[y][x] = 3
    return g


# where things come out of the bosses, in pixels inside the art
OWL_CHEST = (40, 50)
TOAD_MOUTH = (56, 44)


# ----------------------------------------------------------------------------- snuffer queen
# Built from tile-aligned straight and 45-degree edges and
# an 8px-periodic shell texture, so most of her 12x8 cells repeat a few tiles
# (NES background tiles can't be flipped, so repetition is the only saving).
QUEEN_W, QUEEN_H = 96, 64      # 12 x 8 tiles


def queen(eyes_open=True):
    g = blank(QUEEN_W, QUEEN_H)
    # shell: an octagon over rows 0-5 with 16px 45-degree corners
    for y in range(48):
        for x in range(QUEEN_W):
            cut = 16
            if x + y < cut or (QUEEN_W - 1 - x) + y < cut:
                continue
            if x + (47 - y) < cut or (QUEEN_W - 1 - x) + (47 - y) < cut:
                continue
            g[y][x] = 1
            if (x % 8, y % 8) in ((2, 2), (5, 5)):            # pitted shell
                g[y][x] = 2
            if x in (47, 48):                                   # wing-case seam
                g[y][x] = 2
    # three glowing ember sacs on the shell: where her weak points come from
    for (sx, sy) in ((20, 20), (76, 20), (48, 12)):
        for y in range(sy - 4, sy + 4):
            for x in range(sx - 4, sx + 4):
                if 0 < x < QUEEN_W and math.hypot(x - sx + 0.5, y - sy + 0.5) < 3.6:
                    g[y][x] = 3
    # head over the bottom of the shell
    for y in range(40, 60):
        for x in range(32, 64):
            if ellipse(x, y, 47.5, 48, 16, 12):
                g[y][x] = 1
    # legs: 45-degree strokes out of the shell's lower sides
    for i in range(3):
        for t in range(16):
            for (x0, d) in ((24 - i * 8, -1), (71 + i * 8, 1)):
                x, y = x0 + d * t, 40 + t
                if 0 <= x < QUEEN_W and y < QUEEN_H:
                    g[y][x] = 2
    g = outline(g, 2)
    # mandibles: glowing hooks under the head
    for t in range(10):
        for (x0, d) in ((40, -1), (55, 1)):
            x, y = x0 + d * int(3 * math.sin(t / 9 * math.pi)), 56 + t // 2
            if y < QUEEN_H:
                g[y][x] = 3
    # eyes: one cell each, so opening them swaps only 2 tiles
    for (ex, ey) in ((36, 50), (59, 50)):
        for y in range(ey - 3, ey + 4):
            for x in range(ex - 3, ex + 4):
                d = math.hypot(x - ex, y - ey)
                if eyes_open:
                    if d < 3.2:
                        g[y][x] = 3
                    if d < 1.2:
                        g[y][x] = 1
                elif abs(y - ey) < 0.6 and abs(x - ex) < 3:
                    g[y][x] = 3
    return g


QUEEN_EMBERS = ((20, 20), (76, 20), (48, 12))

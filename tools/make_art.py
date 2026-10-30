#!/usr/bin/env python3
"""Renders the game's own pixel art (make_assets.py, boss_art.py) as big PNGs for
the website and the printed materials:  python3 tools/make_art.py docs/media/art

Colours are the game's palettes (src/light.s palette_rom), as the jsnes NTSC
table shows them, so the art matches the screenshots.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import boss_art          # noqa: E402
import make_assets as M  # noqa: E402

NES = {0x01: "#0000b4", 0x07: "#401800", 0x10: "#e7d5c4", 0x16: "#bc1900", 0x17: "#b15400",
       0x27: "#f7b400", 0x28: "#ffe000", 0x30: "#ffffff", 0x37: "#ffda9a", 0x38: "#f8ed88"}
MOTH1 = (0x16, 0x37, 0x30)          # sprite palette 0: red / cream / white
MOTH2 = (0x01, 0x10, 0x30)          # sprite palette 1: blue / silver / white
LIT = (0x07, 0x17, 0x38)            # background palette 1: the cave in the light
GLOW = (0x17, 0x27, 0x38)


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


def render(rows, pal, scale, name, out):
    """rows: strings of '.', '1'-'3' (or lists of ints 0-3)."""
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            v = c if isinstance(c, int) else (0 if c == "." else int(c))
            if v:
                im.putpixel((x, y), rgb(NES[pal[v - 1]]))
    im = im.resize((w * scale, h * scale), Image.NEAREST)
    im.save(os.path.join(out, name + ".png"))


def main(out):
    os.makedirs(out, exist_ok=True)
    moth = M.mirror(M.MOTH_FRAMES[0])
    render(moth, MOTH1, 16, "moth", out)
    render(moth, MOTH2, 16, "moth2", out)
    render(M.mirror(M.MOTH_FRAMES[1]), MOTH1, 16, "moth-flap", out)
    sprites = {
        "bunny": (M.BUNNY_FRAMES[0], MOTH2), "bat": (M.BAT_FRAMES[0], MOTH2),
        "beetle": (M.BEETLE_FRAMES[0], (0x07, 0x17, 0x38)), "wisp": (M.WISP_FRAMES[0], (0x10, 0x37, 0x30)),
        "mimic": (M.MIMIC_AWAKE, LIT), "spider": (M.SPIDER_FRAMES[0], MOTH2),
        "firefly": (M.FIREFLY_FRAMES[0], GLOW), "cocoon": (M.COCOON, MOTH2),
        "orb": (M.ORB_FRAMES[1], GLOW), "bubble": (M.BUBBLE_FRAMES[0], (0x01, 0x10, 0x30)),
    }
    for name, (rows, pal) in sprites.items():
        render(rows, pal, 12, name, out)
    for i, name in enumerate(("speed", "control", "tail", "heart")):
        render(M.ICONS[i], MOTH1, 12, "power-" + name, out)
    for name, fn in (("owl", boss_art.owl), ("toad", boss_art.toad), ("queen", boss_art.queen)):
        render(fn(True), LIT, 6, "boss-" + name, out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "docs/media/art")

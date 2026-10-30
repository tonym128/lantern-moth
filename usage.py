#!/usr/bin/env python3
"""Prints ROM and RAM use from lantern.map and fails the build when something
runs out (or close to it).

    python3 usage.py lantern.map
"""
import sys

# (segments, capacity in bytes, minimum free bytes before the build fails)
AREAS = [
    ("PRG",              ("CODE", "RODATA"), 0x8000 - 6, 256),   # less the vectors
    ("zero page",        ("ZEROPAGE",),      0x100,      4),
    ("$0100 (no stack)", ("LOWBSS",),        0xC0,       0),
    ("RAM $0300-$07FF",  ("BSS",),           0x500,      0),
]


def segments(path):
    sizes, inside = {}, False
    for line in open(path):
        if line.startswith("Segment list:"):
            inside = True
        elif inside and line.strip() == "" and sizes:
            break
        elif inside:
            parts = line.split()
            if len(parts) == 5 and all(c in "0123456789ABCDEFabcdef" for c in parts[3]):
                sizes[parts[0]] = int(parts[3], 16)
    return sizes


def main(path):
    sizes = segments(path)
    ok = True
    for name, segs, cap, keep in AREAS:
        used = sum(sizes.get(s, 0) for s in segs)
        free = cap - used
        flag = ""
        if free < keep:
            flag, ok = f"  <- under {keep} B free", False
        print(f"  {name:18} {used:6} / {cap:6} B used, {free:5} free ({100 * used / cap:4.1f}%){flag}")
    if not ok:
        sys.exit("usage.py: out of room (see above)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "lantern.map")

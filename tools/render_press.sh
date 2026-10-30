#!/bin/sh
# Renders the print materials in press/ to docs/press/ with headless Chromium:
# a 300 dpi PNG of each fixed piece, and a PDF of everything at its page size.
#   tools/render_press.sh [piece ...]      (default: all of them)
set -e
cd "$(dirname "$0")/.."
OUT=docs/press
mkdir -p "$OUT"
CHROME=${CHROME:-chromium}
run() { timeout 120 "$CHROME" --headless --no-sandbox --disable-gpu --hide-scrollbars --virtual-time-budget=6000 "$@" >/dev/null 2>&1; }

# name  width height  png-scale (96 px/in * scale = dpi)
pieces="
label       336  288 3.125
box-front   504  696 3.125
box-back    504  696 3.125
cartridge   576  672 2
manual      528  816 2
pamphlet   1056  816 2
"
want=${*:-label box-front box-back cartridge manual pamphlet}
echo "$pieces" | while read -r name w h scale; do
  [ -n "$name" ] || continue
  case " $want " in *" $name "*) ;; *) continue ;; esac
  url="file://$PWD/press/$name.html"
  # (multi-page pieces: the PNG is the first page, a preview for the website)
  run --force-device-scale-factor="$scale" --window-size="$w,$h" --screenshot="$OUT/$name.png" "$url"
  run --no-pdf-header-footer --print-to-pdf="$OUT/$name.pdf" "$url"
  echo "  $OUT/$name.png  $OUT/$name.pdf"
done

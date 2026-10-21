#!/bin/bash
# SKYRUSH Blender wrapper (headless, factory startup). Runs queue on the machine-wide 'heavy' slots.
#   tools/blender.sh run <script.py> [-- args]        run a build/export script
#   tools/blender.sh preview <in.glb|in.blend> <name> [--views a,b,..] [--light studio|night|both]
#                                                     [--size WxH] [--target-height M]
#        renders views to ~/m/skyrush/captures/blender/<name>_<light>_<view>.jpg plus a contact
#        sheet <name>_<light>.jpg, and prints mesh/material/texture stats (flags untextured materials)
#   views: front34 rear34 side front rear top under close_front34 close_side close_rear (default: 8 views)
set -u
ROOT="$HOME/m/skyrush"
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
SLOTS="$ROOT/tools/slots.py"
cmd="${1:-}"; shift || true
case "$cmd" in
  run)
    script="$1"; shift || true
    [ "${1:-}" = "--" ] && shift
    python3 "$SLOTS" heavy 4 --timeout 2400 -- "$BLENDER" -b --factory-startup --python-exit-code 1 --python "$script" -- "$@" ;;
  preview)
    in="$1"; name="$2"; shift 2 || true
    out="$ROOT/captures/blender"; mkdir -p "$out"
    python3 "$SLOTS" heavy 4 --timeout 900 -- "$BLENDER" -b --factory-startup --python-exit-code 1 \
      --python "$ROOT/blender/tools/preview.py" -- --in "$in" --out "$out/$name" "$@" || exit 1
    for sheet in "$out/$name"_studio "$out/$name"_night; do
      ls "$sheet"_*.png >/dev/null 2>&1 || continue
      files=( $(ls "$sheet"_*.png | sort) )
      n=${#files[@]}; cols=4; rows=$(( (n + cols - 1) / cols ))
      ffmpeg -v error -y -pattern_type glob -i "${sheet}_*.png" \
        -vf "scale=640:-2,tile=${cols}x${rows}:padding=4:color=0x202020" -frames:v 1 -q:v 3 "$sheet.jpg"
      for f in "${files[@]}"; do
        sips -Z 1280 -s format jpeg -s formatOptions 75 "$f" --out "${f%.png}.jpg" >/dev/null && rm -f "$f"
      done
      echo "sheet: $sheet.jpg"
    done ;;
  *)
    sed -n '2,10p' "$0"; exit 2 ;;
esac

#!/bin/bash
# Downloads the CC0 (Poly Haven) files the look-dev scene needs into ./tex. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p tex
B=https://dl.polyhaven.org/file/ph-assets
get() { [ -s "tex/$2" ] || curl -fsSL --retry 3 -m 300 -o "tex/$2" "$1"; }
for m in diff nor_gl rough; do get "$B/Textures/jpg/2k/asphalt_02/asphalt_02_${m}_2k.jpg" "asphalt_02_${m}_2k.jpg"; done
for m in diff nor_gl arm; do get "$B/Textures/jpg/2k/granite_tile_03/granite_tile_03_${m}_2k.jpg" "granite_tile_03_${m}_2k.jpg"; done
get "$B/HDRIs/hdr/2k/shanghai_bund_2k.hdr" "shanghai_bund_2k.hdr"
# Texture conditioning (DOSSIER 5.4): Bund granite must average ~#ABAAA3; the raw scan averages #645A52.
if [ ! -s tex/granite_bund_diff_2k.jpg ]; then
  ffmpeg -v error -y -i tex/granite_tile_03_diff_2k.jpg \
    -vf "hue=s=0.55,lutrgb=r='clip(val*1.78,0,255)':g='clip(val*1.88,0,255)':b='clip(val*1.90,0,255)'" \
    -q:v 2 tex/granite_bund_diff_2k.jpg
fi
echo "assets ok: $(ls tex | wc -l) files"

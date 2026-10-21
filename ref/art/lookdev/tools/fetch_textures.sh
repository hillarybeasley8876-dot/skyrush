#!/bin/bash
# SKYRUSH texture shopping list -> local files (DOSSIER section 5). All assets are CC0 (Poly Haven, ambientCG).
# Usage: bash fetch_textures.sh [OUT_DIR]   (default ./tex_src). Needs curl, unzip, python3, ffmpeg (for 5.4).
# Downloads are untrusted data: zips are kept in OUT/_zips/ and ONLY image files (*.jpg *.exr *.hdr) are extracted
# (.blend/.usdc/.mtlx/.tres inside ambientCG zips are never unpacked or opened).
set -euo pipefail
OUT="${1:-./tex_src}"
mkdir -p "$OUT/polyhaven" "$OUT/ambientcg" "$OUT/hdri" "$OUT/_zips"

PH_TEX="${PH_TEX:-asphalt_02 clean_asphalt aerial_asphalt_01 asphalt_track concrete rough_concrete concrete_wall_008
painted_concrete_02 granite_tile_03 granite_tile_04 dark_brick_wall brick_wall_08 church_bricks_03 square_tiles_03
concrete_pavement_02 bark_platanus japanese_sycamore corrugated_iron_02 rusty_metal_02 blue_metal_plate gravel_stones
metal_grate_rusty leather_red_02 forest_leaves_02}"
PH_HDRI="${PH_HDRI-shanghai_bund vignaioli_night hansaplatz kloppenheim_07_puresky}"
ACG="${ACG:-Asphalt025C Asphalt024C Asphalt033 Asphalt020L Road007 Concrete046 Concrete034 Concrete035 PavingStones136
PavingStones144 TactilePaving001 TactilePaving003 Bricks056 Bricks034 Bricks032 Metal027 PaintedMetal014 Metal009
Metal051A Metal050A Rust007 CorrugatedSteel007A Fabric004 Rubber001 Leather026 Leather020 Leather034C Fabric082A
SurfaceImperfections001 SurfaceImperfections002 Smear005 Fingerprints002 Leaking004 Leaking009 Leaking016A
LeafSet027 Grass004 Gravel022 Grate002 ManholeCover007 ManholeCover009 ManholeCover011 RoadLines013 RoadLines031A
AsphaltDamageSet001 AsphaltDamageSet002 GraffitiSet001 Tape001 Tape003 Facade009 Facade013 Facade017 DiamondPlate008A}"
ACG_HDRI="${ACG_HDRI-NightEnvironmentHDRI002}"   # lists can be overridden from the environment

get() { # url dest
	[ -s "$2" ] && return 0
	curl -fsSL --retry 3 -m 600 -A "skyrush-fetch/1.0" -o "$2.part" "$1" && mv "$2.part" "$2"
}

ph_maps() { # print "url" lines for diffuse(any name), nor_gl, rough, arm (jpg) and disp (png) of one asset
	curl -fsSL --retry 3 -m 60 "https://api.polyhaven.com/files/$1" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
for key in ("Diffuse", "coll1", "nor_gl", "Rough", "arm"):
    u = d.get(key, {}).get("2k", {}).get("jpg", {}).get("url")
    if u:
        print(u)
u = d.get("Displacement", {}).get("2k", {}).get("png", {}).get("url")
if u:
    print(u)'
}

for id in $PH_TEX; do
	mkdir -p "$OUT/polyhaven/$id"
	urls=$(ph_maps "$id") || { echo "ERROR: Poly Haven API failed for $id" >&2; exit 1; }
	for url in $urls; do get "$url" "$OUT/polyhaven/$id/$(basename "$url")"; done
	[ "$(find "$OUT/polyhaven/$id" -type f | wc -l)" -ge 3 ] || { echo "ERROR: too few maps for $id" >&2; exit 1; }
done
for id in $PH_HDRI; do
	get "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/${id}_2k.hdr" "$OUT/hdri/${id}_2k.hdr"
done

for id in $ACG $ACG_HDRI; do
	kind="2K-JPG"; [[ " $ACG_HDRI " == *" $id "* ]] && kind="2K"
	zip="$OUT/_zips/${id}_${kind}.zip"
	get "https://ambientcg.com/get?file=${id}_${kind}.zip" "$zip"
	dest="$OUT/ambientcg/$id"; [ "$kind" = "2K" ] && dest="$OUT/hdri"
	mkdir -p "$dest"
	before=$(find "$dest" -type f | wc -l)
	# exit code 11 = some pattern (e.g. *.exr) had no match; that is expected
	unzip -o -q -j "$zip" '*.jpg' '*.exr' '*.hdr' -d "$dest" || [ $? -eq 11 ]
	after=$(find "$dest" -type f | wc -l)
	[ "$after" -gt "$before" ] || [ "$before" -gt 0 ] || { echo "ERROR: no images extracted from $zip" >&2; exit 1; }
done

# 5.4 conditioning: Bund granite must average ~#ABAAA3 (raw scan averages #645A52).
G="$OUT/polyhaven/granite_tile_03"
if [ -s "$G/granite_tile_03_diff_2k.jpg" ] && [ ! -s "$G/granite_bund_diff_2k.jpg" ]; then
	ffmpeg -v error -y -i "$G/granite_tile_03_diff_2k.jpg" \
		-vf "hue=s=0.55,lutrgb=r='clip(val*1.78,0,255)':g='clip(val*1.88,0,255)':b='clip(val*1.90,0,255)'" \
		-q:v 2 "$G/granite_bund_diff_2k.jpg"
fi

echo "polyhaven: $(find "$OUT/polyhaven" -type f | wc -l) files, ambientcg: $(find "$OUT/ambientcg" -type f | wc -l) files,"\
" hdri: $(find "$OUT/hdri" -type f | wc -l) files"

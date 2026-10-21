#!/bin/bash
# SKYRUSH Godot wrapper. All runs queue on machine-wide slots (tools/slots.py).
#   tools/godot.sh import                      import changed assets (serialized project-wide)
#   tools/godot.sh check [--only=res://a/,res://b/]
#                                              import, then load every script/scene/shader; exit 1 on errors
#   tools/godot.sh test <res://path/test.gd> [-- args]
#                                              headless SceneTree test script (physics/logic), 120 Hz fixed
#   tools/godot.sh shot --scene res://x.tscn --out <name> [--shots <spec>] [--warm N] [--size WxH]
#                                              windowed capture -> ~/m/skyrush/captures/<name>_<shot>.jpg
#   tools/godot.sh run <res://scene.tscn> [seconds]  windowed smoke run, prints errors + fps, quits
#   tools/godot.sh drive --timeline=res://x.json [--shots=1,4] [--log=/abs.csv] [game options]
#                                              scripted input play-through (windowed), telemetry print
#   tools/godot.sh movie --movie=/abs/out.avi --timeline=res://x.json [...]  same, recorded at 60 fps
#   tools/godot.sh perf --skip-menu [--spawn=x,y,z,yaw] [--warm=240]   draw calls/objects per subsystem
#   tools/godot.sh play                       launch the game normally (no slot, for humans)
set -u
ROOT="$HOME/m/skyrush"
PROJ="$ROOT/game"
GODOT=/opt/homebrew/bin/godot
SLOTS="$ROOT/tools/slots.py"
mkdir -p "$ROOT/captures" "$ROOT/tmp"

do_import() {
  local req; req=$(date +%s)
  python3 "$SLOTS" import 1 --timeout 2400 -- "$ROOT/tools/godot_import.sh" "$req" >"$ROOT/tmp/last_import.log" 2>&1
  local code=$?
  grep -E "ERROR|SCRIPT ERROR|Failed" "$ROOT/tmp/last_import.log" | grep -v "^\s*at:" | head -40
  return $code
}

# Dev runs render at high and never read/write the player's settings file (core/settings.gd skips
# user://settings.cfg when --quality is given), unless the caller passes its own --quality=.
QUALITY="--quality=high"
for a in "$@"; do case "$a" in --quality=*) QUALITY="$a";; esac; done

cmd="${1:-}"; shift || true
case "$cmd" in
  import)
    do_import ;;
  check)
    do_import
    python3 "$SLOTS" light 6 -- "$GODOT" --headless --path "$PROJ" -s res://tools/check_all.gd -- "$@" ;;
  test)
    script="$1"; shift || true
    [ "${1:-}" = "--" ] && shift
    do_import >/dev/null
    file="$PROJ/${script#res://}"
    if grep -q "^extends SceneTree" "$file" 2>/dev/null; then
      # legacy SceneTree tests: run directly (they must not reference autoloads/class_names at compile time)
      python3 "$SLOTS" light 6 -- "$GODOT" --headless --fixed-fps 120 --path "$PROJ" -s "$script" -- "$@" "$QUALITY"
    else
      python3 "$SLOTS" light 6 -- "$GODOT" --headless --fixed-fps 120 --path "$PROJ" \
        -s res://tools/test_host.gd -- --test="$script" "$@" "$QUALITY"
    fi ;;
  shot)
    do_import >/dev/null
    python3 "$SLOTS" heavy 4 -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/capture.gd -- --outdir="$ROOT/captures" "$@" "$QUALITY" ;;
  run)
    scene="$1"; secs="${2:-20}"
    do_import >/dev/null
    python3 "$SLOTS" heavy 4 -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/smoke_run.gd -- --scene "$scene" --seconds "$secs" "$QUALITY" ;;
  drive)
    do_import >/dev/null
    python3 "$SLOTS" heavy 4 -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/autodrive.gd -- --outdir="$ROOT/captures" "$@" "$QUALITY" ;;
  movie)
    out=""; rest=()
    for a in "$@"; do case "$a" in --movie=*) out="${a#--movie=}";; *) rest+=("$a");; esac; done
    [ -z "$out" ] && { echo "movie: --movie=/abs/path.avi required"; exit 2; }
    do_import >/dev/null
    python3 "$SLOTS" heavy 4 --timeout 1800 -- "$GODOT" --path "$PROJ" --write-movie "$out" --fixed-fps 60 \
      -s res://tools/autodrive.gd -- --outdir="$ROOT/captures" "${rest[@]}" "$QUALITY" ;;
  perf)
    do_import >/dev/null
    python3 "$SLOTS" heavy 4 -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/perf_probe.gd -- "$@" "$QUALITY" ;;
  play)
    exec "$GODOT" --path "$PROJ" ;;
  *)
    sed -n '2,18p' "$0"; exit 2 ;;
esac

#!/bin/bash
# Regenerates every SKYRUSH audio asset from source.
#
#   tools/audio/build.sh          # sfx, world sfx, music (offline, deterministic)
#   tools/audio/build.sh --voice  # also re-downloads the Chinese voice lines (needs the
#                                  # internal YS-API over the IOA VPN)
#
# After a rebuild run `tools/godot.sh import` and then
# `python3 tools/audio/patch_loop_imports.py` + `tools/godot.sh import` again, so the seamless
# loops get loop=true in their .import files.
set -eu
ROOT="$HOME/m/skyrush"
PY=/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1
"$PY" -I tools/audio/gen_sfx.py
"$PY" -I tools/audio/gen_sfx_ui.py
"$PY" -I tools/audio/gen_world.py
"$PY" -I tools/audio/gen_music.py
if [ "${1:-}" = "--voice" ]; then
  "$PY" -u -I tools/audio/gen_voice.py
fi
# the intermediate wavs are deleted by the generators, the voice mp3 cache stays
find "$ROOT/tmp/audio" -maxdepth 1 -name '*.wav' -delete 2>/dev/null || true
# import the new files, flag the seamless loops, import again
tools/godot.sh import
python3 tools/audio/patch_loop_imports.py
tools/godot.sh import
echo "audio assets rebuilt"

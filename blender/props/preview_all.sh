#!/bin/bash
# Render a night + studio preview sheet for every prop (unit: props).
#   tools/blender.sh preview <glb> <name> --views front34,side,close_front34
set -u
cd "$HOME/m/skyrush" || exit 1
for f in game/assets/props/street/*.glb; do
  n=$(basename "$f" .glb)
  tools/blender.sh preview "$f" "prop_$n" --views front34,side,close_front34 --size 1100x760 \
    >/dev/null 2>&1
  echo "sheet $n"
done
for f in game/assets/props/sites/*.glb; do
  n=$(basename "$f" .glb)
  tools/blender.sh preview "$f" "prop_$n" --views front34,side --size 1100x760 >/dev/null 2>&1
  echo "sheet $n"
done
echo "PREVIEW ALL DONE"

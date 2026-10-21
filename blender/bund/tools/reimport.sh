#!/bin/bash
# Force Godot to re-import the Bund glbs (the build is deterministic, so the source md5
# does not change and Godot skips the import).
set -u
cd "$(dirname "$0")/../../.."
rm -f game/.godot/imported/bund_*.md5 game/.godot/imported/bund_*.scn
rm -f game/.godot/imported/bund_*.ctex
touch game/assets/bund/*.glb.import
sleep 1
tools/godot.sh import

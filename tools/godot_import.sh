#!/bin/bash
# Runs under the import slot: tools/slots.py import 1 -- tools/godot_import.sh <request_epoch>
# Coalescing: if an import that STARTED after this request already finished (stamp mtime >= request
# time), it covered every file the caller wrote before asking -> skip. Otherwise also skip when no
# project file changed since the last import; else run `godot --import` and stamp its start time.
# tools/import_doctor.py runs first and forces an import when it had to reset invalid assets.
ROOT="$HOME/m/skyrush"
PROJ="$ROOT/game"
STAMP="$ROOT/jobs/.slots/import.stamp"
req="${1:-0}"
# Heal assets Godot marked invalid (scanned mid-write) and orphan .import files; any reset forces an import.
doctor=$(python3 "$ROOT/tools/import_doctor.py" "$PROJ")
echo "$doctor"
healed=$(echo "$doctor" | tail -1 | awk '{print $2}')
if [ -f "$STAMP" ] && [ "${healed:-0}" = "0" ]; then
  stamp_t=$(stat -f %m "$STAMP")
  if [ "$stamp_t" -ge "$req" ] && [ "$req" -gt 0 ]; then
    echo "[import] coalesced: an import started at $(date -r "$STAMP" +%H:%M:%S) already covered this request"
    exit 0
  fi
  changed=$(find "$PROJ" -path "$PROJ/.godot" -prune -o -type f -newer "$STAMP" ! -name "*.import" ! -name "*.uid" -print -quit 2>/dev/null)
  if [ -z "$changed" ]; then
    echo "[import] up to date (no changes since $(date -r "$STAMP" +%H:%M:%S))"
    exit 0
  fi
fi
next="$STAMP.next.$$"
touch "$next"
/opt/homebrew/bin/godot --headless --path "$PROJ" --import
code=$?
if [ $code -eq 0 ]; then mv "$next" "$STAMP"; else rm -f "$next"; fi
exit $code

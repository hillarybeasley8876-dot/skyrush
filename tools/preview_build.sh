#!/bin/bash
# Interim playable preview (core-owned): freezes a copy of game/ (incl. the .godot import cache) in
# ~/m/skyrush-preview/game so workers' mid-edit files cannot break it, checks that every script
# parses, and (re)writes a launcher app on the Desktop that runs the copy with the Godot binary.
#   tools/preview_build.sh            snapshot + check + launcher
#   tools/preview_build.sh --no-sync  only re-check the existing snapshot and rewrite the launcher
# The release build is a real export (see tools/workflows/README.md); this is only for play-testing.
set -euo pipefail
ROOT="$HOME/m/skyrush"
SNAP="$HOME/m/skyrush-preview"
GODOT="/opt/homebrew/bin/godot"
APP="$HOME/Desktop/飞驰申城 SKYRUSH 预览版.app"
LOG="$SNAP/build.log"

mkdir -p "$SNAP"
if [ "${1:-}" != "--no-sync" ]; then
  echo "[preview] snapshot game/ -> $SNAP/game"
  rsync -a --delete --exclude 'tests/' "$ROOT/game/" "$SNAP/game/"
  git -C "$ROOT" rev-parse --short HEAD > "$SNAP/REVISION" 2>/dev/null || echo "unversioned" > "$SNAP/REVISION"
  date "+%Y-%m-%d %H:%M" >> "$SNAP/REVISION"
fi

echo "[preview] import (only files that changed since the cache was copied)"
"$GODOT" --headless --path "$SNAP/game" --import > "$LOG" 2>&1 || { echo "[preview] import FAILED, see $LOG"; exit 1; }

echo "[preview] script check"
"$GODOT" --headless --path "$SNAP/game" -s res://tools/check_all.gd >> "$LOG" 2>&1 || true
summary=$(grep -E "^CHECK [0-9]+ files" "$LOG" | tail -1 || true)
failed=$(grep -c "^CHECK FAIL" "$LOG" || true)
if [ -z "$summary" ]; then
  echo "[preview] the check did not finish (no summary line), see $LOG"
  exit 2
fi
echo "[preview] $summary"
if [ "$failed" -gt 0 ]; then
  grep -E "^CHECK (FAIL|ERROR)" "$LOG" | head -20
  echo "[preview] not publishing a broken snapshot; fix or re-sync later"
  exit 2
fi

echo "[preview] launcher -> $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launch</string>
  <key>CFBundleIdentifier</key><string>local.skyrush.preview</string>
  <key>CFBundleName</key><string>SKYRUSH Preview</string>
  <key>CFBundleDisplayName</key><string>飞驰申城 SKYRUSH 预览版</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.9-preview</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
cat > "$APP/Contents/MacOS/launch" <<LAUNCH
#!/bin/bash
exec "$GODOT" --path "$SNAP/game" "\$@"
LAUNCH
chmod +x "$APP/Contents/MacOS/launch"
if [ -f "$ROOT/game/icon.png" ]; then
  sips -s format icns "$ROOT/game/icon.png" --out "$APP/Contents/Resources/icon.icns" > /dev/null 2>&1 \
    || echo "[preview] icon conversion failed (launcher works without it)"
fi
echo "[preview] done: $(tr '\n' ' ' < "$SNAP/REVISION")"

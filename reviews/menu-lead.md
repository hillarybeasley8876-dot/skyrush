# Lead notes for menu (mandatory)

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## CORE CHANGE (10-20 10:20)
Settings no longer reads/writes user://settings.cfg when the run has --quality=... (every tools/godot.sh run
passes --quality=high). Tests must check the in-memory state (Settings.quality / volumes) and the `changed`
signal, not the file. The settings screen still persists in the real game (no --quality option).

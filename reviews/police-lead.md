# Lead notes for police (mandatory)
P-INT1 (lead integration run): a heat-1 pursuit starts immediately at spawn ("警方追捕! 嫌疑车辆，立即靠边停车!") although the player
  only touched a building wall. Infractions are only those in the gameplay dossier §3.4 (hit a police car, > 160 km/h in sight of a patrol,
  hitting traffic in sight, toll evasion) — never walls/props, never in the first 10 s after spawn/respawn.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

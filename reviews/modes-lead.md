# Lead notes for modes (mandatory)

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT4 — lead integration drive 10-20 09:55 (tmp/lead/int4.log)
M-INT1: `mode_director.gd:127 _place_player_at_spawn` (from start_mode → _start_free at boot) calls
  `Game.world.get_spawn_transform` while the real world is still building (it builds for ~10–40 s) →
  "Nonexistent function 'spawns' in base 'Nil'" in world.gd:158, and the player would sit at the origin.
  Core now provides `Game.world_built()` and `await Game.world_ready()` (core/game.gd); main.gd freezes the
  player and places it when the world is built. Every WorldBase call in modes/rivals (spawns, routes, grids)
  must `await Game.world_ready()` first; show the loading state instead of starting the countdown early.

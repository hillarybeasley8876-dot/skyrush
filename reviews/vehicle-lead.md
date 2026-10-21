# Lead notes for vehicle (mandatory)
V-INT1 (lead integration run): after a nitro tap `telemetry.boost_kind` stays "nitro" for the rest of the run with n2 = 0 and speed 0
  (car blocked by a wall) — boost state must end on its timer regardless of speed/contacts and `boost_ended` must fire.
1. `player_input.gd` must ignore all driving input while `Game.mode == &"menu"` or the SceneTree is paused (the menu unit shows a title screen over the running world; the car must stay parked).
2. Rivals/police/traffic reuse `ArcadeCar` with AI input via `set_controls()`, `set_drift()`, `use_nitro()`, `request_hop()`; document the full AI-facing API (incl. barrel roll and launch) at the top of `arcade_car.gd` and in status.
3. On `Events.takedown` where the player is the attacker: +50 N₂ (+25 per streak step if the damage unit passes a streak count — read its status) for the player car.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

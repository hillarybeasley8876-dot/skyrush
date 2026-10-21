# Lead notes for audio (mandatory)
A-INT1 (lead integration run in main.tscn, 01:10): `res://audio/world_emitters.gd:83` "Trying to cast a freed object" — 37,000 errors in
  ~90 s (cars despawned by traffic are still referenced; check `is_instance_valid()` before casting, and disconnect/forget emitters on
  tree_exiting). `res://audio/oneshot_pool.gd:105` accesses `.playing` on Nil (462×) and a typed `Array[AudioStreamPlayer3D]`
  receives a plain AudioStreamPlayer (344× "Attempted to use 'has' an object of type 'AudioStreamPlayer'"). Zero engine errors in a
  60 s main.tscn run is part of acceptance (`tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu`).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

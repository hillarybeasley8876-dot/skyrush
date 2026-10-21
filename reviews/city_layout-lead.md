# Lead notes for city_layout (mandatory)
C-INT1: the player spawn in city.json does not lie on a road (the game spawned at (-131.7, 0, 298.2) inside a block). Validator rule:
  every spawn (player, police, rival grids, route grids) is within 0.5 m of a lane centre-line at the lane height and its heading within
  10° of the lane direction; put the player spawn on the Bund road southbound near (−100, 0, −250) or as SPEC says.
1. The street grids are perfectly axis-aligned rectangles everywhere — it reads like SimCity, not Shanghai. Rotate/skew grids per district: the D1 heritage streets must run perpendicular/parallel to the Bund road (they follow the river curve; the cross streets Guangdong/Fuzhou/Hankou/Jiujiang/Nanjing Rd meet the Bund at the real angles), D3/D4 Puxi grids tilted ~8–15° like the real Huangpu/Luwan street pattern with a few diagonal or curved streets, Lujiazui streets following Century Ave and the ring road. Keep right angles inside a district where real, but no single global grid.
2. Blocks must not sit under elevated decks or ramps (the roads unit needs room for piers and the under-deck streets): keep ≥ 2 m from the deck footprint (deck width incl. wings) — add a validator rule.
3. Make sure every sky lane, launch pad and route is drawn on map.png with its label so the lead can review them at a glance.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

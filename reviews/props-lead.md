# Lead notes for props (mandatory)
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
PR-ART1 (lead): magnolia lamp globes blow out to white blobs — emission E2–3 with an opal gradient so the 9 petals read; same
  for any lamp head that blooms into a disc.
PR-ART2 (lead): the charging station reads dark and uninviting. It is a hero gameplay site: continuous cyan LED fascia line
  `#00E5FF` (E3), bright 5500 K under-canopy (emissive panels E2 + the world unit's lights), green bays `#1E9E5A` with white
  numbers, lit red "VOLTA" post text, glowing kW readouts, the 7 m totem with a lightning bolt. Same energy for the gas station
  underside (white LED downlights) — both must pop at 100 m.
PR-INT1 (lead perf probe `tools/godot.sh perf --skip-menu`, 01:20): one guide gantry instance costs **64 draw calls** (its truss members,
  panels and lights are separate meshes/materials). Every prop must ship as ONE mesh node per material family (merge all static
  parts in Blender; ≤ 3 surfaces for street props, ≤ 8 for gantries/sites; separate nodes only for parts that move, break or switch
  emission — e.g. `Lens_*`, `Barrier_*`, `Support_*`, `LaneSignal_*`). Put the per-prop surface count in status.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT3 — lead integration drive 10-20 09:00 (evidence: captures/lead_int3_t2_0.jpg / _t6_0 / _t10_0 / _t14_0 (lead integration drive 10-20 09:00, `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,6,10,14 --out=lead_int3`, all 13 units real))
PR-INT2: in the game the traffic-light poles and arms read as BROWN WOOD (telephone poles), not painted steel. Shanghai signal masts
  are dark grey / silver-grey galvanised steel (ART.md palette: steel #5A5F66 rough 0.45, metallic 0.8) with a black signal head
  and a reflective yellow/black back plate; bases have a concrete plinth. Check the material in-engine (MaterialLibrary swap) — a
  Blender-only preview is not evidence.

# Lead notes for roads (mandatory)
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
TILE-TEX (lead, 08:05, mandatory): the tiles embed their own copies of the same textures (roads 731 MB / blocks 658 MB of glb).
  Export every city tile with `export.export_glb(path, ..., shared_texture_dir="../_tex")` (new core option in
  blender/lib/export.py): writes `<tile>.gltf + .bin` and ONE shared copy of each image in `game/assets/city/_tex/` (shared by
  roads and blocks). Delete the old `.glb` tiles (and their .import) after switching; the world unit must load `.gltf` tiles
  (it should glob both extensions). Target: total city tile data ≤ 250 MB.
IMPORT-PERF (lead, 07:40): city tile glbs (≈1.4 GB, 192 files) made every Godot import take 30–60 min and blocked all 21
  units behind the import lock. The lead set `meshes/generate_lods=false` and `meshes/create_shadow_meshes=false` in every
  `game/assets/city/{roads,blocks}/*.glb.import` — keep these .import files (Godot keeps options when you overwrite the glb with
  the same name; for NEW tile files copy those two lines into their .import after the first import). Also: rebuild only the
  tiles you changed (`--only`), and keep each tile ≤ 15 MB (merge, share materials, no duplicate embedded textures — reference
  the shared texture library images instead of embedding copies in every tile).
R1. **Under-deck blue is a flat glowing ceiling** — far too much saturated area (see skyrush_underdeck/interchange captures).
    Real Shanghai: two ~4 m bands of blue-violet light on the cantilever wing undersides along the deck edges (dossier
    §2.5), the central box-girder underside stays dark concrete. Assign `SH_soffit_blue` ONLY to the wing undersides
    (2 strips, 3.5 m each), the LED tube strip (emissive, thin) to the drip edge, and `SH_concrete_pier`-style concrete to
    the girder bottom flange and webs. Under-deck frames must pass the art dossier SAT budget (zone underdeck 5–26 %).
R2. Kerbs, sidewalks, medians and tunnel walls render as flat untextured colours (beige/tan) — every surface needs its
    texture set (granite kerb, paving + tactile strip, enamel tunnel panels with the colour stripe and joints, concrete).
R3. Show one capture per district at driver eye height on the REAL city once buildings exist — note in status which
    tiles are verified.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT3 — lead integration drive 10-20 09:00 (evidence: captures/lead_int3_t2_0.jpg / _t6_0 / _t10_0 / _t14_0 (lead integration drive 10-20 09:00, `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,6,10,14 --out=lead_int3`, all 13 units real))
R-INT1: at the spawn junction the corner sidewalk/island pieces sit on the carriageway at road level (pale tan slabs the car drives
  over, t2) and there is no visible kerb. Junction corner geometry must follow the kerb radii of the real road widths, raised
  0.15 m with a kerb face, never overlapping the lanes. Also verify the wet-road look in main.tscn (see environment E-INT1): the
  asphalt must show reflections and puddles in the game, not only in your preview.

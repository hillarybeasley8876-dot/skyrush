# Lead notes for buildings (mandatory)
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
BL-ART1 (lead, blocks_*.jpg): lit windows are flat cream rectangles — no interior, too bright, too uniform. All glazing must use
  shader logic with variety: dark reflective glass for most, lit interiors with depth (interior parallax or an interior atlas:
  curtains, ceiling lamps, shelves), warm/neutral/cool/TV-blue mix, E ≤ 1.0 (never blooms). Shikumen windows: wooden frames + panes.
BL-ART2: shikumen gates need real stone door frames (granite, 0.25 m deep, carved pediment relief), black lacquer double doors with
  brass ring knockers recessed 0.3 m, lane gates with the 「xx里」 plaque; roofs with real tile texture and ridge details.
BL-ART3: break repetition: per-house variation (laundry poles with clothes, AC units, potted plants, satellite dishes, shop signs,
  wall lamps, open/closed shutters, weathering streaks); no two neighbouring modules identical.
BL-ART4: no black void around buildings — each block has ground cover to the kerb (paving, lane paving, small plazas, planters).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## ART-NIGHT (10-20 10:20, evidence: captures/lead_view1_{bund,lujiazui,dragon,yanan,spiral,sky,toll,charge}.jpg, captures/lead_view2_{pudong,pearl,pillar}.jpg (main.tscn --skip-menu --env-only)) — mandatory, see ART.md §11 (the 2–8 % lit rule is withdrawn)
B-NIGHT1: offices 20–30 % lit windows in CLUSTERED floors (whole floor bands + scattered), cool white;
  residential 15–25 % warm scattered with curtain/TV variety. Today the towers are uniform polka-dot grids.
B-NIGHT2: 50 % of the generic Pudong towers get cool white LED edge/crown lines; roofs > 100 m a red
  aviation beacon (1 Hz). The white cone tops (lead_view2_pudong) read as toys: replace with lit crowns,
  setbacks, antennas or mechanical floors.
B-NIGHT3: shop fronts at street level lit (glazed, warm interiors) with signs every 10–20 m on commercial streets.
Also: at the time of the lead capture only 38 of ~135 block tiles existed (rebuild in progress) — never leave
the game without its tiles for longer than one export; export to a temp name and swap (atomic).

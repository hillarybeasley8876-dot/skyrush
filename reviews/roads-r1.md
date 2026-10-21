# roads review round 1 — VERDICT: FAIL

## Scores (0-10): function 2, visual 2, code 4

Summary: the generator is well split into modules and the wet asphalt + GB markings read well, but the
structure is broken. Every pier stands ON TOP of its deck, so no deck has a support. The soffit is still one
blue ceiling. Ramps overlap the main decks. The tunnel puts four lanes inside one bore that is too narrow.
lanes.json covers about half of most roads and has no ramp links. Every local material has a 512² diffuse
map only. None of the three lead notes is met.

## MUST-FIX

1. **Piers stand on top of the decks, so no deck has a support.** `piers.build()` uses the deck path point `p`
   (z = deck height) as the column origin. The column therefore runs from the deck surface up to 2×deck−2 m and
   the cap sits in the sky.
   Measured in `roads_-3_1.glb` at pier (−1347.64, 721.19): SH_concrete_pier spans y 9.26…16.74 with asphalt
   at 9.3, and there is nothing between the ground and the girder. Also, `road_furniture.json` `piers[].y` =
   deck height. The cap runs 16 m ALONG the road (`tangent * x`) and hides inside the girder depth.
   The portal frames have a fixed 12 m span and land on other decks; one stands in the lane in
   `captures/review_roads_r1_gore.jpg` and `captures/review/roads/geo_sheet.jpg` (panel 5).
   **Do:**
   - Column base on the ground (z = 0, or the terrain height once it exists). Girder underside zg = deck − 2.0.
   - Column 2.0 × 3.0 m, R 0.4, from the ground to zg − cap depth.
   - Hammerhead cap ACROSS the road (along `right`): 16 m long, 2.6 m wide along the road, 2.0 m deep at the
     column tapering to 1.2 m at the tips, top = zg.
   - Portal span = the lower road's asphalt width + 2 × 1.5 m. Check both columns with `blocked()`. Beam top = zg.
   - No column may cross any other carriageway or deck between the ground and zg (shift ±6 m, then portal).
   - Pier record: y = ground, plus a `deck_y` field.
   - Give every column a closed collider (a `-convcolonly` box). Today cars drive through piers.
   **Verify:**
   - 0 SH_concrete_pier triangles above deck_y + 0.05 within 9 m of any pier.
   - 0 lane samples with pier concrete 0.1–1.3 m above the lane. My check `tmp/review/lane_block.py` finds
     3 610 such samples (4.7 %): ns_elevated 2 019, yanan_elevated 699, nanpu_pudong_loop 290.
   - Capture under the deck at (−1347, 1.7, 738) and compare with
     `ref/shanghai/img/02_elevated_roads/under_elevated_2009.jpg`.

2. **Lead R1 not met: the soffit is still one blue ceiling, with no LED strip and no cantilever wing.**
   `deck.build_soffit` puts SH_soffit_blue on the wings, webs and bottom flange. `LED = "Road_Led_Soffit"` is
   never used. `girder_profile` is a trapezoid (one slope from the drip edge to the flange), so there is no wing.
   - `review_roads_r1_underdeck.jpg` / `_pier_close.jpg`: the whole underside is blown out to white.
   - `geo_sheet.jpg` panels 2–3: the whole underside is soffit material.
   - The environment unit's current `SH_soffit_blue.tres` has `tex_mean = null`; file that as a request. Your
     material assignment is still the main fault.
   **Do:**
   - Section: slab → 0.25 m drip face → wing underside, width = min(3.5 m, 0.25 × deck width), z −0.25 at the
     tip → −0.45 at the root → web down to the bottom flange (half-width 0.30 × deck width) at −2.0 → flange.
   - SH_soffit_blue ONLY on the two wing undersides. UV v = 0 at the drip edge → 0.5 at the wing root (the
     shader then draws its strip only at the drip edge); u = metres along the deck.
   - Webs, flange and drip faces get SH_concrete_pier.
   - LED tube 0.06 × 0.06 m under the drip edge (x = ±(half − 0.15)), material Road_Led_Soffit. Colour from
     style `soffit_led` (#5A3DFF), energy 4.5: art dossier §2.3 tier E3. It is 9.0 now, which is the E4 hero
     tier; Road_Led_Bridge is 8.0 → 4.5 too.
   - Delete the scupper boxes floating under the deck edge (orange box in `planter_closeup.jpg`, right), or hang
     them from the drip edge with a down-pipe.
   **Verify:**
   - A Blender material-colour section render shows blue only on the 2 wing strips.
   - Godot capture under the deck: SAT 5–26 % (`python3 ref/art/lookdev/tools/screenshot_stats.py`), girder
     bottom reads as dark concrete. Compare with `01_dragon_pillar_interchange/interchange_night_6658.jpg`.

3. **lanes.json is truncated, has dead ends, has no links at ramp attaches and funnels lanes into one point.**
   - `lanes._segments()` limits lane-path indices with `len(road.path)` (the 4 m mesh path) instead of
     `len(road.lpath)`, so the last segment stops early. Coverage:
     - yanan_elevated: x −1990…−1553 only (≈440 m of 1 669 m)
     - inner_ring 28 %, nanpu_bridge 27 %
     - yanan_tunnel 27 %: it ends at x −96 and never reaches the river
     - 74 of 123 roads are under 80 %
   - 177 dead-end lanes inside the map (`next == []`). Example: `yanan_elevated_0_fwd0` ends mid-deck at
     (−1553, 9.7, 728).
   - 63 attach ends have no lane link (yanan_elevated→yanan_east_ramp, ns_elevated→inner_ring,
     spiral_approach→nanpu_spiral_lower …).
   - Every lane ends at the junction centre. 28 lane ends share (1351.5, 0, −192.5), and `yanan_rd_surface_0_fwd0`
     and `_fwd2` close from 7.5 m apart to 0 m over the last 12 m, crossing each other. Your "worst 0.000 m"
     continuity result only passes because of this.
   **Do:**
   - Lanes stop at the stop line and keep their lateral offset.
   - Junction movements become connector lanes: a cubic Bezier from the in-lane end to the out-lane start,
     sampled every 2 m, y interpolated, with `turn`. Allow only plausible movements (right lane → right/straight,
     left lane → left/straight).
   - At attaches, link the parent lane(s) on the attach side to the ramp lanes.
   **Extend test_lanes.gd:**
   - Coverage per road ≥ 95 % of (length − junction trims).
   - Dead ends only at a listed set of map-edge ends.
   - ≥ 1 link per attach end.
   - Lateral offset at the stop line = design offset ± 0.3 m.
   - No end point shared by lanes from different approaches.

4. **Ramp attaches overlap the main decks.**
   - The xizang and chongqing on/off-ramps start ON the parent's centreline: ramp_xizang_off starts at
     (−1010.68, 553.91), and yanan_elevated at s = 1021.85 is (−1010.51, 553.75). So the ramp's asphalt, girder,
     parapets and planters cross the main lanes.
   - Interchange ramps end 7–168 m from their `at` point (ramp_rt_nb_eb: 167.7 m), so
     `attaches._attach_point` (which uses `at`) puts the gore in the wrong place.
   - Chevrons are painted across the main lanes (`geo_sheet.jpg` panel 6). There is no taper or widening.
   **Do:**
   - Find each attach by projecting the ramp end onto the parent (nearest point), not from `at`.
   - Shift the ramp's taper stretch sideways so its inner edge meets the parent's outer edge.
   - Build the taper as a widening of the parent deck: 1:25 for off-ramps, a 150 m acceleration lane for
     on-ramps (dossier §2.6). On that side, remove the parent's parapet and planters up to the gore nose and give
     the widened stretch one girder and one soffit.
   - Gore: a paved wedge between the two edge lines beyond the nose, 45° chevrons with 45 cm bars inside the
     wedge only, and a crash cushion at the nose.
   - File a city_layout request listing every attach whose end is more than 1 m from its parent.
   **Verify:** material-colour top views of ramp_xizang_off, ramp_chongqing_on and one interchange ramp show no
   parapet, planter or pier crossing a lane; the sweep test (item 5) passes along both roads.

5. **The collision drive test does not test what the brief asks.**
   - `test_drive_collision.gd` covers 11 of 1 488 lanes. It starts at each lane's midpoint, slides a box straight
     for 1.25 s, and counts it as blocked only if it moved less than 0.4 m.
   - The drivable collider is tagged `extras.surface = "concrete"`; it must be `"asphalt"`.
   - Piers and tunnel walls have no colliders.
   **Do:** a deterministic sweep of EVERY lane and connector. At each 2 m step:
   - A ray from y+2 to y−3 must hit a road collider within 0.15 m of the lane y.
   - A box shape-cast 1.9 × 1.0 × 4.6 m at y+0.75 from step i to i+1 must hit nothing.
   Add 20 dynamic shots at 90 m/s (CCD) into parapets at 15° and 45°; none may tunnel. Print counts per road.
   My approximate check (lane centres rebuilt from city.json) finds barrier colliders 0.1–1.3 m above the lane
   centre at 737 samples on 24 roads (zhongshan_e2_s 208, lujiazui_ring_rd 150, inner_ring 96, pudong_south_rd
   88, yanan_elevated 57), and visible parapets inside lanes at 367 samples. Your exact test must reach 0.

6. **Tunnel: one bore for two carriageways.** yanan_tunnel is 2+2 with a 7.5 m median, so its carriageways sit
   at ±3.75…±10.75 m. `tunnel.build_bore` builds one bore around the centreline, clamped to ±4.9 m, so every lane
   runs through the wall (asphalt half-width 11.25 m). The walls have no collider.
   `review_roads_r1_tunnel.jpg`: flat grey walls, one continuous LED strip, black bore.
   **Do (dossier §4):**
   - Two Ø 11 m bores, each centred on its carriageway (±7.25 m): 7.5 m roadway + 0.3 m concrete kerbs.
   - Walls: enamel panels #ECEFF0 from Y 0.5 to 3.2 m with 1.2 × 0.6 m joints; a 0.3 m stripe at Y 1.2 m
     (#2C6BD8); dark #3A3D42 above 3.2 m with its own concrete texture (not the tinted enamel).
   - LED luminaires 1.2 m long every 2.4 m at both ceiling corners, not one continuous strip.
   - Jet-fan pairs Ø 1.2 × 5 m every 250 m, lane signals every 150 m, green exit signs every 80 m.
   - Thick closed wall colliders.
   - `tunnel_light` records every 12 m per bore in road_furniture.json for the world's light pool, plus a request
     to the world unit.
   **Verify:** a capture inside each bore at 1.1 m; the sweep test passes through the tunnel.

7. **Lead R2 not met, and "贴图纹理什么都要细化" is not met: the local materials are flat.**
   - Every Road_* material has only a 512² procedural diffuse map (glTF: baseColorTexture only,
     `doubleSided: true`). `materials.retarget()` deletes the library roughness and normal maps.
   - Texel density: paving 284, ivy 256, enamel 256, steel 171 px/m. Target is ≥ 512 (dossier §15).
   - The textures read as noise (`captures/review/roads/tex_contact.jpg`): ivy looks like green felt,
     bougainvillea like polka dots, the planter row like brown planks.
   - Sidewalks, kerbs and tunnel walls render flat (`review_roads_r1_sidewalk_close.jpg`, `_tunnel.jpg`).
   **Do:**
   - Kerb → `SH_kerb`; sidewalk → `SH_sidewalk`. Both now exist in `game/shaders/materials`.
   - Tactile strip → `mats.pbr(tex="TactilePaving003")`, tinted yellow.
   - Every other Road_* material: diffuse + nor_gl + rough (+ ao), ≥ 2048², ≥ 512 px/m, single-sided.
   - Procedural maps must output a normal map and a roughness map derived from the height field.
   - Ivy: alpha leaf cards from a 2048² atlas (5-lobed leaves 6–10 cm, 3–4 greens around #2F5A2A), patchy from
     0 to 7.6 m with an organic top edge — not a sleeve.
   - Steel #9AA4AE: bolt rows, chipped paint, rust streaks. Expansion joint: finger teeth and a rubber strip in
     the normal map.
   - Concrete detail you own:
     - Leaking004/016A drip decals under the deck edges and cap ends.
     - Vertex-colour dirt (art dossier §4.3): bottom 0.6 m → 70 %, top 0.8 m under the drip → 80 %.
     - White 0.6 × 0.3 m pier number plates ("YA-243" style).
   - Medians: low shrubs (the brief asks for them), not bare soil.
   - Share materials across tiles (the brief requires it). Today Godot extracts 235 per-tile JPGs
     (`roads_<tx>_<tz>_<map>.jpg`, 61 copies in VRAM). Strip the images from every non-SH material at export and
     bind shared `game/assets/city/roads/materials/*.tres`. Do it either through each tile's `.import`
     (`_subresources` → materials → `use_external/enabled=true`, `use_external/path`), written by the generator,
     or through a post-import script in your folder.
   **Verify:**
   - `tools/blender.sh preview` on a tile lists normal + rough for every Road_* material.
   - 0 `roads_*_*.jpg` files.
   - Captures at 3 m / 20 m / 100 m of kerb, sidewalk, parapet, pier and tunnel wall show relief and roughness
     breakup.

8. **The planters do not read as the "10+5" pot row.** They are a continuous swept trough plus a swept hedge tube
   with a 2048×256 strip texture. At 1.1 m they read as a dark brown/green band (`review_roads_r1_parapet_close`,
   `_nanpu`, `planter_closeup.jpg`): no white pots and no magenta.
   **Do** (the brief asks for instanced or merged pots, with the strip only beyond 80 m):
   - Pots 0.60 × 0.25 × 0.25 m, #EDEDE8, 1 cm bevel, 2 cm gaps, soil stains down the outer face, a black Ø 2 cm
     drip pipe on top; ≤ 12 tris per pot.
   - Plants: 2 crossed alpha cards per pot from a 2048² atlas — bougainvillea bracts #C2185B on #3E7D32 leaves,
     privet #B5C534. Jitter ±10 % scale and ±15° yaw. Let them overhang the outer face (ref
     `01_dragon_pillar_interchange/interchange_ground_2025.jpg`).
   - Rhythm: 10 magenta + 5 privet.
   - Merge the pots in 64 m chunks with visibility_range_end 90 m, and keep the strip with
     visibility_range_begin 80 m (post-import script).
   - Keep every tile ≤ 400 k tris and report the new per-tile maximum.

9. **road_furniture.json.**
   (a) No traffic lights. `junction_furniture()` computes `stop` and never emits a light. Add a `traffic_light`
       per approach of every `signals: true` junction: pole at the right kerb at the stop line, mast arm over the
       lanes, facing the approach.
   (b) Gantry texts cycle a fixed list (`SIGN_TEXTS[i % len]`). The gantry on 延安高架 at (−1490, 727) reads
       "延安高架路", "西藏中路 出口 500m" can appear anywhere, and there are no 300/100 m exit gantries. Generate
       the texts from the network:
       - "<exit road> 出口 500m/300m/100m" before each off-ramp.
       - Every ~500 m, a direction sign naming the next two destinations ahead (dossier §2.6; ref
         `02_elevated_roads/yanan_elev_east_of_xizang_2025.jpg`).
   (c) 208 trees and 76 lamps cut through a deck above them (114 of the trees are on yanan_rd_surface), and 10
       lamps stand inside yanan_tunnel. Add an overhead clearance check: no item may reach within 0.5 m of any
       road surface above it.
   (d) 92 duplicate CableAnchor names, because left and right share `CableAnchor_<road>_<s>`: add a _L/_R suffix.
       Remove the 22 anchors on waibaidu_bridge (a truss bridge with no cables).
   (e) Sign text "Yan'an Rd (surface)": drop the generator's parenthesised qualifiers.

10. **Lead R3 not done.** Buildings exist (`game/assets/city/blocks`, 256 files) and `res://world/world.tscn`
    loads your tiles. Capture one view per district at 1.1 m in the world scene and list the verified tiles in
    status. My world captures (`review_roads_r1_world_deck.jpg`, `_under.jpg`) show plane trees growing through
    the Yan'an elevated and no supports under the deck.

11. **Cleanup and project rules.**
    - Remove dead code: `deck.LED`, `stop` in `furniture.junction_furniture`, `markings.build_gore` (the code
      uses `attaches.build_gore`), `profiles.planter_profile`, `profiles.deck_profile` (a duplicate of
      `deck.girder_profile`), `lanes._keep_refs`, and the stale `textures/*.png` + `.import` files (the .jpg
      versions are the ones in use).
    - Replace magic numbers with named, sourced constants:
      - piers: portal 12.0 / 1.2
      - deck: scupper 15.0 / (0.60, 0.30, 0.40) / 0.55
      - furniture: 5.5 / 8.0 / 2.5
      - attaches: 12 / 0.2 / 0.4
      - junctions: 1.5 / 3.0 / 3.4 / 9.0
      - tunnel: 0.8 / 5.4 / 6.1 / 4.2
    - Delete your scratch files in /tmp (`/tmp/dbg5.py`, eight `/tmp/shot*.log`, `/tmp/tiles.log`). Use only
      `tmp/roads/`.
    - Godot shots were started in the background with `( … &); sleep N`. That is forbidden; run them in the
      foreground.
    - Correct status/roads.md. It claims T-piers with hammerhead caps, deck LED strips and "every link within
      0.000 m", and none of these hold.

## SHOULD-FIX
- The junction fill sits 1 cm below the carriageway (FILL_DROP), which leaves a step and a stacked overlap at every
  junction edge. Meet the cut road ends with shared vertices instead.
- Add 公交专用 bus-lane text and straight-left / left arrows. `game/assets/fonts/NotoSansSC-Variable.ttf` is in the
  repo now, and `ref/art/lookdev/tools/bake_road_glyphs.py` exists. Add Ø 0.7 m manholes and skid-mark quads
  (dossier §15, asphalt row).
- The dash phase restarts at every run (`add_dashed` starts at `t = s0`). Carry the phase from the road's s so
  dashes stay 6/9 m across tile and junction seams.
- Kerbs: a 2 cm top chamfer. Parapets: a real safety-shape inner face (0.5 → 0.25 m, dossier §2.4), a coping, and
  delineator discs every 4 m.
- `textures.save` writes into `game/assets/city/roads/textures` even when --out is given. Route it through --out
  so a build can be checked in a scratch directory (I did not rebuild, because a rebuild would overwrite your files).
- Type the GDScript loop variables (`for path: String in _tiles()`).
- File a request to environment/shaders: `SH_soffit_blue.tres` has `tex_mean = null`, which blows out the wash.

## Verified OK
- `check` is clean. `test_lanes` 8/0 and `test_drive_collision` 4/0 run and pass, but both tests are too weak
  (items 3 and 5).
- Budgets: max 319 182 tris (`roads_-3_1`, 18 MB), 16 objects per tile (≈96 draw calls for 9 tiles). The preview
  with all 61 tiles runs at 64–142 fps at 1600×900.
- The wet asphalt reads well at 5 m (cracks, patches, puddles), and the R/G vertex colours are present. GB
  markings: 15 cm, 6/9 m and 2/4 m dashes, 20 cm edge lines, 15 cm yellow, 5 mm above the asphalt.
- Code checks: kerb returns R 9 m with a crosswalk and stop line on every arm; expansion joints every 30 m;
  bridge edge girders with a #3D7BFF LED line; `-colonly` meshes per tile with 0.60 m barriers.
- `minimap.json` matches SCHEMA (123 roads). Files are ≤ 400 lines (max 294), tests extend Node, functions are
  typed, and every Write/Edit stayed inside your owned paths.

## Evidence
- `tools/godot.sh check --only=res://assets/city/roads/` → `CHECK 4 files, 0 failed, 0 engine errors`.
- `tools/godot.sh test …/test_lanes.gd` → 8 checks, 0 failures. `…/test_drive_collision.gd` → `no car fell (0 of
  11)`, 4 checks, 0 failures.
- `tools/blender.sh preview roads_-3_1.glb review_roads_r1_tile` → `tris=319182`. The Road_* materials have a
  single 512² image each; the SH_* materials are untextured (stripped by design).
- Godot captures (preview scene): `captures/review_roads_r1_{deck_eye,parapet_close,underdeck,pier_close,junction,`
  `sidewalk_close,gore,nanpu,tunnel,aerial}.jpg`. World scene: `captures/review_roads_r1_world_{deck,street,under}.jpg`.
- Sheets in `captures/review/roads/`: sheetA–C, world_sheet, geo_sheet (Blender material colours: piers on the
  decks, all-blue underside, portal in the lane, chevrons on the main lanes), planter_closeup, tex_contact,
  ref_compare (`yanan_elev_east_of_xizang_2025.jpg` and `interchange_night_6658.jpg` next to our deck and
  underdeck), worker_sheet.
- Analysis scripts in `tmp/review/`: `glb_mesh.py`, `lane_block.py` (lane blocking), `furn_clear.py` (items
  through decks); the lane and attach numbers come from python checks over lanes.json and city.json.

# props review round 2 — VERDICT: FAIL

## Scores (0-10): function 5, visual 3, code 5

Progress since r1 is real: one mesh node per material family (surface budgets pass), the sign atlas is
correct and legible, the V-flip bug is fixed, `Deploy` exists, the unit dropped from 393 MB to 12 MB, and the
cyan LED line and red gas fascia now read. But the camera still sees a grey-box world. The root cause is one
design bug: the 1 m surface-atlas tile is wrapped per vertex, so almost every face over 1 m shows a single
smeared row of texels. Poles, islands, columns, booths and trunks read as wood grain, and roofs and soffits are
flat planes. The same bug is behind the lead's PR-INT2 "brown wood" masts. Two lead notes (PR-INT2, PR-ART2)
are still open, and the toll plaza has functional layout errors. The user asked for refined textures
everywhere ("贴图纹理什么都要细化"). Fix every item below, re-run all evidence, and correct status/props.md.
It must state only facts you measured.

## MUST-FIX

1. **The surface atlas cannot tile: `u % 1.0` per vertex collapses or stretches every face over 1 m.**
   `blender/props/atlas.py:surface_uv()` (called by `geom.py:161 map_surface_uv()` and `kit.quad/quads`) maps
   each loop's metre UV with `% SURFACE_METRES`. Example: a 7 m arm has u = 0 at both ends, so the arm samples
   one texel column. A 6.4 m mast runs from v = 0 to v = 0.4, which stretches 0.4 m of tile over 6.4 m. A
   70 × 24 m soffit gets four near-identical corners. Area-weighted texel density of `Prop_Surface` + `Prop_Soffit`
   (`python3 tmp/review/props_r2_texsum.py`), share of area **below 256 px/m** (target 512):
   gas_station **99.8 %** of 18 311 m², toll_plaza **99.7 %**, charge_station **99.7 %**, sky_lane_pad 99.6 %,
   scaffold 98.6 %, guide_gantry_19/27/34 96 %, bus_stop 93 %, billboard_pole 94 %, plane_tree_1..3 90–91 %,
   metro_entrance 90 %, lamp_deck_double 89 %, lamp_street 79 %, lamp_magnolia 79 %, traffic_light_mast 61 %.
   Only bin, cone, planters, hydrant, e_scooter and noise_wall are mostly correct. You can see it in
   `captures/review_props_r2_{toll_booth,gas_col5,gas_soffit,tree_trunk}.jpg`,
   `captures/review/props/r2/crops_detail.jpg` and the in-game `captures/review_props_r2_game_tl.jpg`: wood-grain
   streaks on masts, islands, columns, booth walls and plane-tree trunks, and uniform soffits and roofs. The game
   instances `plane_tree_1` 19 587×, `road_name_sign` 9 462×, `lamp_street` 5 209× and `traffic_light_mast` 1 620×,
   so this bug is on every street in the city. The `wear_band()` cylinders (1.0 m tall, so v = 1 % 1 = 0)
   collapse too.
   **Do:** stop atlasing surfaces that tile. Keep the sign atlas for printed boards only, where it is correct.
   Replace `Prop_Surface` / `Prop_Soffit` with ≤ 4 tileable families: REPEAT textures, UV = metres / tile
   size, no modulo.
   - `Prop_Metal`: 1024² per 2 m (512 px/m), neutral light-grey base.
   - `Prop_Mineral`: concrete, kerb and pavement, from the CC0 sets already in `game/assets/textures/`
     (`rough_concrete`, `Concrete046`, `concrete`).
   - `Prop_Panel`: ACP canopy roof, soffit, fascia and facade.
   - `Prop_Bark`: trunks and branches.
   Tint each part with a vertex colour. In Blender, write a `COLOR_0` attribute per part and multiply it into
   Base Color with a Color Attribute node, so the previews match. In Godot, point each family at an external
   `res://assets/props/materials/<family>.tres` (StandardMaterial3D, same maps,
   `vertex_color_use_as_albedo = true`) through the `.glb.import` `_subresources` → `materials` →
   `use_external/enabled=true` and `use_external/path`. Your own `test_vc.gd` proves why this is needed: the
   importer keeps COLOR_0 but sets the flag to false. If that route fails, use one material per colour that
   shares the same maps (`Prop_Galv`, `Prop_PaintRed`, ...), within ≤ 3 surfaces for street props and ≤ 8
   static surfaces for sites. Cylinders: set u = angle/2π × round(circumference / tile) so the seam closes.
   **Verify:** `tmp/review/props_r2_texsum.py` (or your own copy in `tmp/props/`) shows ≤ 5 % of every glb's
   area below 300 px/m. Add `_check_texel_density()` to `test_props.gd`: per triangle,
   sqrt(UV area × tex px² / world area) for non-sign surfaces; FAIL above 5 %. Take Godot 5 m captures of a gas
   column, a toll island with its booth, a mast and a tree trunk: no streaks.

2. **Tile content is flat or blocky (ART.md §5 a–d, dossier §15).** In `tools/signs/surf_lib.py:_value_layer()`,
   `fx = (...)[:, None]` and `fy = (...)[None, :]` are transposed against `v00[y, x]`. The x weight therefore
   varies along y, so every fbm octave is stepwise along x. That is the square-cell pattern on concrete, pavement,
   kerb, canopy, soffit, facade, bay_green and rusty (`captures/review/props/r2/atlas_diff.jpg`). It only runs
   because every tile is square. Per-tile stats (`python3 tmp/review/props_r2_tiles.py`):
   - Albedo luminance σ ≤ 2.4/255 on 13 tiles: red_paint 0.4, steel_dark 0.8, blue 0.8, green 0.8,
     plastic 1.0, orange 1.2, teal 1.2, gold 1.5, yellow 1.7, silver 1.8, white_paint 2.1, chrome 2.1,
     alu 2.4. These are flat colours.
   - Roughness σ ≤ 0.03 on 25 of 29 tiles: no roughness breakup.
   - Mean normal deviation 2.6–6.4° on every metal.
   - At 5 m there are no visible chips, scratches, grime or drips, although the status claims all of them.
   **Do:** swap the two index expressions (`fx[None, :]`, `fy[:, None]`). Give each family from item 1 physical
   detail in all four maps:
   - metal: chipped paint edges showing grey primer (≥ 2 % of the area), fine scratches, a grime/water-stain
     gradient toward the foot, roughness breakup σ ≥ 0.08 (use `SurfaceImperfections001` as the mask);
   - panel: 6 mm seams, rivet heads, faint drip streaks below seams;
   - mineral: the CC0 photo sets instead of fbm.
   Albedo σ ≥ 6/255 at 1:1 on every family. Keep the bases mid-to-light grey so the vertex tints stay accurate.
   **Verify:** put a stats table in status (σL, σR, normal deviation per family) and a 1:1 crop sheet of each
   family. Godot 5 m captures must show chips, scratches and grime.

3. **PR-INT2 (lead, mandatory) is not done.** Status does not mention it and there is no in-engine evidence.
   `traffic_light_mast` (`blender/props/signs.py:21-56`):
   - The mast and arm use the `galv` tile (`#86888E`), not steel `#5A5F66`, and 61 % of the mast area is below
     256 px/m (item 1). That stretch is the wood grain the lead saw.
   - There is no back plate: `HeadBack` is a 0.12 × 0.26 m dark box.
   - The lenses are Ø 0.23 m with no arrows (dossier §9 asks for "arrow lenses"), and they ship lit at E5 / E4.4.
   **Do:**
   - mast and arm steel `#5A5F66`, roughness 0.45, metallic 0.8, with the item-1 metal detail;
   - head black `#111113`;
   - a reflective back plate 0.60 × 1.40 m behind the head: yellow `#F2C200` 60 mm border and black field;
   - a concrete plinth Ø 0.7 × 0.25 m with a galvanised base flange and 4 bolts;
   - lenses Ø 0.30 m, red on top, shipped dark (E0; the world unit switches them on).
   **Verify:** in-game capture
   `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --cams="tl:-267,1.6,107:-261,3.6,115:66"`
   (junction of Sichuan Rd and Yan'an Rd). The mast must read as dark silver-grey steel with no grain. Quote
   the capture in status.

4. **PR-ART2 (lead, mandatory) is not met: the forecourts are black under bright ceilings.** Mean forecourt
   luminance under the canopy is 25–33/255 at the gas station (`review_props_r2_gas_col5.jpg`, `_gas_soffit.jpg`)
   and 16/255 at the charging hub (`_charge_20.jpg`), while the soffit itself is 182/255. The value structure is
   inverted. At 100 m both sites read as one thin line (`review_props_r2_{gas,charge}_100.jpg`). Details:
   - `Prop_Soffit` emission is a flat factor 0.6 (E0.6, not E2), and with collapsed UVs it is a plain white
     plane with no panels or diffusers.
   - The gas station and the charging hub each ship ONE `Light` marker (at the pylon or totem) and none under
     the canopy, so the world unit cannot light the forecourt.
   - The charge dispensers are red: `charge.py:31` sets `TEAL = "red_paint"`, but dossier §8.2 says teal
     `#00A6A6`. The posts read mid-grey.
   - "VOLTA" and the kW readouts are about 10 px tall at 6 m, and the totem bolt is invisible at 20 m
     (`captures/review/props/r2/crops_charge.jpg`).
   **Do:**
   - (a) `Light_<n>` Empties (local +Y pointing down) under each canopy on a 10 m grid: gas ≈ 6 × 3, charge
     7 × 2, toll one per two lanes at the canopy front. List them in status for the world unit;
     `preview_props.gd` already turns them into spots.
   - (b) One baked ground light-pool quad per canopy at +0.02 m: alpha-blended, emissive `#FFF4E8`, soft
     rectangle with downlight hot spots, E0.6–0.8 at the centre fading to 0 about 2 m past the canopy edge.
     The forecourt then reads lit even when the world's light pool is full (ART §4: ground light decals).
   - (c) Soffit at E2 `#FFF4E8` on the panel family, with seams and diffuser squares.
   - (d) Charging hub: dispensers teal `#00A6A6` with white bodies; posts white `#F2F2F2`, 0.34 × 0.60 × 1.95 m,
     with "VOLTA" ≥ 0.12 m tall in lit red `#E31937` at E2.5; kW readout ≥ 0.35 × 0.20 m at E2.5 facing the
     bay; totem bolt ≥ 1.5 m tall at E3 on both faces.
   **Verify:** forecourt mean luminance ≥ 90/255 in the driver-view captures (quote the numbers), and each site
   reads as a pool of light at 100 m.

5. **Toll plaza lane furniture is wrong in three ways** (`blender/props/toll.py:177-193 _barrier_arm`, `_lanes`).
   - **Every arm points away from its own lane.** Take lane 1 (Godot z 50.7…53.9, `LaneSignal_1` at z 52.3).
     The post is correctly on island 1 at z 50.35, but the arm runs along local +Y with rot_z 0, i.e. toward the
     island. Lowered (rotation reset) it covers z 50.35 → 47.35: 1.85 m over its own island and 1.15 m into
     lane 2, while lane 1 stays open. All 20 arms are mirrored the same way (Barrier_20 included). The test
     checks only the AABB size, so it passes anyway.
   - **The stripes cannot show.** `geom.py:222 map_strip_uv()` sets `u = (y + L/2)/L` on a box that starts at
     y = 0, so u runs 0.5…1.5. Half of every arm samples outside the `barrier_arm` cell, and the arms render
     black in `review_props_r2_toll_booth.jpg`.
   - **Booths and direction.** The barrier stands upstream of its booth (POST_X −2.4, booth x −1.5…1.5,
     traffic +X), but drivers pay first and then the arm lifts. Dossier §7.2 specifies **10 + 10 lanes,
     traffic E–W**, yet all 20 lanes face +X: every `LaneSignal_*` sits at x −10.05 and the single ETC gantry at
     x −40 spans both carriageways.
   **Do:**
   - arm direction = −side (rot_z π when side > 0); `u = y / ARM_LEN`;
   - posts downstream of the booth window (x +2.4 for eastbound);
   - mirror the north carriageway (lanes 11–20) as westbound: signals and lane labels on the east face
     (x +10.05) facing +X, booth on the driver's left (the island on the lane's +Z side), barrier at x −2.4,
     and a second ETC gantry at x +40 that spans only those lanes (the first spans only lanes 1–10).
   **Verify:** extend the test. With the rotation reset, each `Barrier_<n>` must overlap ≥ 2.6 m of its lane
   (lane centre ± 1.6 m) and ≤ 0.4 m of any island, and the westbound `LaneSignal_*` must face +X. A 5 m
   capture must show 0.5 m red/white bands.

6. **PR-INT1 (lead, mandatory) is not fully met: the toll plaza has 22 unnecessary draw calls.** `finalize()` keeps
   every node whose name starts with a dynamic prefix. So `EtcGantry`, `EtcGantryLower`, `EtcGantryWeb_1..19`
   and `CanopyStreaks` ship as 22 separate nodes, and the toll plaza totals 88 surfaces. Nothing moves, breaks
   or switches the ETC gantry.
   **Do:**
   - Match exact contract names, not prefixes: `Lens_R/A/G`, `Barrier_<n>`, `LaneSignal_<n>_Red/_Green`,
     `Support_<n>`, `Spikes`, `Chevron_<n>`, gas `Canopy`, `BayNumbers`.
   - Merge the ETC truss and the streak decal into the static mesh.
   - While there, build the ETC truss as the 0.9 × 0.9 m box truss r1 item 3 asked for. Today it is a flat
     two-chord truss 0.32 m thick.
   **Verify:** the test prints toll_plaza ≤ 8 static surfaces and the dynamic surfaces equal the contract
   nodes (20 + 40).

7. **The close-up props are still crude (r1 items 8 and 9 not met).** These are what the camera passes at 2–10 m.
   - **bike_share** (`furniture.py:72 _bike`; `captures/blender/prop_bike_share_studio_close_front34.jpg`):
     the tyres are 12-segment flat-shaded rings that look octagonal, the tubes have 4–6 sides, the frame is a
     "V" from hub to saddle to hub, and the baskets are solid cubes.
     **Do:** torus tyres 24 × 6, smooth-shaded; rims with a spoke alpha disc; a step-through share-bike frame
     (head tube, curved down tube to the bottom bracket, seat tube, chain stays, seat stays, rear carrier)
     with 8-sided smooth tubes; a wire basket as an alpha card; saddle, mudguards and QR plate. Stay ≤ 3k tris.
   - **planter_pot_bougainvillea** (`captures/blender/prop_planter_pot_bougainvillea_studio.jpg`): the bracts
     are 30 cm flat pink discs and the leaves are large cards with stair-stepped alpha edges. These boxes line
     every elevated parapet (dossier §2.4).
     **Do:** dense masses of 3–5 cm bracts in magenta `#C2185B` / `#E04A8C` on 0.4–0.6 m cluster cards, small
     leaves, alpha with a 2–4 px soft edge (render the foliage atlas at 2× and downsample), cascading over the
     box lip. Apply the same treatment to privet.
   - **plane_tree_1..3**: the canopy is sparse in the Godot preview (single-leaf cards).
     **Do:** 200+ cluster cards (many leaves per card) of 1.5–2.5 m, plus the bark from item 1.
   - **Toll booths** (dossier §7.2): 50 % glass (the upper 1.4 m) with mullions, white `#EDEDED`, red stripe
     `#D9161C`, and a lit interior ceiling panel `#FFD7A0` at E1.5.
   - **Fuel dispensers**: a red/white cabinet with rounded edges, nozzle holsters, hoses and the LED price
     window.
   - **Charge dispensers**: a 2.2 m teal/white cabinet with the overhead cable boom and holstered connectors.
   **Verify:** per-prop close sheets framed on the whole object, plus Godot captures at 5 m.

8. **Process and code rules** (worker rules, CONTRACTS §3, lead project-wide rules).
   - `tools/signs/prop_surfaces.py` is **569 lines** (limit 400): split it by family. Functions over 60 lines:
     `prop_surfaces.build` (81), `foliage.build` (73) and `prop_atlas._specific_table` (85; fine if it is pure
     data, otherwise split it).
   - Scratch inside `game/`: delete `game/assets/props/tests/test_vc.gd` and `vc_test.glb` (with their
     `.uid` / `.import` files).
   - Scratch in `/tmp`, which is forbidden: delete `/tmp/glbtest/`, `/tmp/ac_a.glb`, `/tmp/h1.txt`,
     `/tmp/status_head.md` and `/tmp/status_tail.md`. Use `tmp/props/` only.
   - Rename `charge.py:31 TEAL = "red_paint"`: the name contradicts the value.
   - status/props.md: the surface table has 3 headers but 2 values per row. Remove the unverified claims:
     "512 px/m on every surface tile" (item 1 shows otherwise), and "wear bands + rain-streak decals on columns,
     posts and dispensers" (only toll_plaza uses `Prop_Streaks`, and no glb uses `Prop_Wear`). Add a PR-INT2
     entry.
   **Verify:** `wc -l` and a function-length check show nothing over the limits; `ls game/assets/props/tests`
   and `ls /tmp` are clean.

## SHOULD-FIX
- **Magnolia (PR-ART1):** the shades no longer blow out (E2.4 opal; PR-ART1 is satisfied on emission), but they
  read as 9 closed eggs on straight arms (`captures/review/props/r2/crops_detail.jpg`). Make them tulip or cup
  shades opening upward with a 3–5 lobe rim and a dark cast cup at the base, on curved arms.
- **Toll fascia (dossier §7.2):** bull-nose radius 1.2 m in `#A7ACB1`, metallic 0.7. The name panel belongs at
  the fascia centre; today it is a separate green board standing on the roof. It should be ≥ 24 m wide (it is
  8 m) so it reads at 100 m like `07_toll_plaza/toll_g4_xinyang_2023.jpg`.
- **Gas brand:** an 8 m panel on a 60 m fascia. Repeat 中国石华 SINOPEX on both long faces at ≥ 16 m with
  logo end caps (`08_fuel_and_charging/sinopec_hangzhou_2018.jpg`).
- **Gas store:** it is a dark box. Give it a glass front with a warm lit interior (ART §11, "shop fronts lit")
  and an EZ-JOY band ≥ 0.8 m tall.
- **Unused images in `game/assets/props/textures/`:** 99 images, of which only `billboard_ad`, `bus_ad`,
  `neon_blade` and `roadname_nanjing` are used (by `world/env/lookdev_city.gd`). Move the rest out of `game/`
  (IMPORT-CHURN). The status says 57.
- **Guide gantries rebuild every time:** guide_gantry_19/27/34 change bytes on every build. Round vertex
  positions to 1e-4 before export so unchanged builds keep their bytes.
- **Spike strip:** `Deploy` is a single rotation channel on `Spikes`; an accordion extension would read better.
- **`localtex.py:41` monkey-patches core `mats.tex_path`.** After item 1 the unit can load its own images
  without patching core; keep the core request in status.
- **Core `.import` files rewritten:** the props glbs reference core textures in place, and Godot rewrote 3
  core-owned files when it imported them (`concrete_pavement_{diff,nor_gl,rough}.jpg.import` at 10:16–10:17:
  compress 0→2, mipmaps on). Report this to the lead in status; do not edit those files yourself.
- **Sheet framing:** `*_close_front34` sheets of the traffic light and the magnolia show only the pole. Frame
  the head. In the lineup the 1.75 m figure is a few pixels tall, so add a close crop of the first 20 m.

## Verified OK
- `tools/godot.sh check --only=res://assets/props/` → `CHECK 4 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/props/tests/test_props.gd` → 80 PASS lines, `PASS props contract (0 failures)`.
- **Surface budgets:** every street prop has ≤ 3 static surfaces, sites ≤ 6 static (except item 6). Tris:
  street ≤ 2 472 (lamp_magnolia), sites 326–7 802.
- **Contract nodes and data:**
  - `Lens_R/A/G`, `Barrier_1..20`, `LaneSignal_<n>_Red/_Green`, `Support_1..6` (gas), `Support_1/2`
    (billboard), `Spikes`;
  - `ChargeArea` extras (centre, size 40 × 18 × 2.4, id), per-row `Prop_Chevron_*`, `SH_hologram` on the gate,
    `Light_1/Light_2` on the deck lamp;
  - `SignMount_*`, with the guide-sign bottom at 5.50 m;
  - `Deploy` animation (0.6 s);
  - collision proxies: gas 18, charge 22, toll 57;
  - no Blender `.00x` node names.
- **Sign text** is correct Chinese + English throughout `prop_signs.png` (atlas `captures/review/props/r2/atlas_signs.jpg`):
  申城西收费站 SHENCHENG WEST TOLL, 中国石华 SINOPEX, 易快 EZ-JOY, the guide panels, 飞行航道 SKY LANE ▲ 300 m,
  the 今日油价 board, the 92# price window, VOLTA, 500 kW, 香港路 Xianggang Rd., ETC 专用 / ETC/人工, 公安 POLICE, the
  metro totem and the bus route board. The road-name sign reads well in game (`review_props_r2_game_tl.jpg`).
- **What now reads:** the cyan LED line is on the outer fascia face and reads at 100 m; the red gas fascia
  reads; the magnolia no longer blooms.
- **IMPORT-CHURN:** external shared atlases (`_tex/`, 3.6 MB), unchanged files keep their bytes and mtime, and
  the unit is 12 MB.
- **Code:** GDScript is statically typed and the test `extends Node`. The worker log (165 Write/Edit calls on
  39 files) shows no edits outside owned paths.
- **Performance:** preview at 1600 × 900 ultra runs 83–171 fps.

## Evidence
- `tools/godot.sh check --only=res://assets/props/` and `tools/godot.sh test …/test_props.gd`, output as above.
- `python3 tmp/review/props_r2_stat.py [-v] game/assets/props/*/*.glb`: nodes, surfaces, materials,
  emission. Results: `Prop_Soffit` emissive [0.6, 0.57, 0.53] at strength 1.0; the toll plaza has 83 nodes and
  88 surfaces, including `EtcGantryWeb_1..19`.
- `python3 tmp/review/props_r2_texel.py <glb> Prop_` and `tmp/review/props_r2_texsum.py`: the px/m shares in
  item 1.
- `python3 tmp/review/props_r2_tiles.py`: per-tile σL, σR and normal deviation (item 2).
- `python3 tmp/review/glbnodes.py game/assets/props/sites/toll_plaza.glb Barrier_ Island LaneSignal_1_ Booth_1`:
  - Barrier_1 hinge (−2.4, 0.95, 50.35), rotation 70° about X, AABB z 49.25–50.42;
  - Island_1 z 48.5–50.7;
  - LaneSignal_1 z 52.3, and all 20 at x −10.05.
- `tools/godot.sh test res://assets/props/tests/test_vc.gd` →
  `mat Prop_Metal albedo_from_vcol=false`; the vertex colour array is present.
- **My Godot captures** (`--quality=ultra --env-only`, 0 errors, 83–171 fps): `captures/review_props_r2_{gas_col5,
  gas_soffit,gas_100,charge_close,charge_20,charge_100,toll_booth,toll_soffit,tl_pole,magnolia,tree_trunk}.jpg`.
  In-game (`--scene=res://main.tscn --skip-menu`): `captures/review_props_r2_game_{tl,tree}.jpg`. Those 8
  errors come from damage/HUD, not props.
- **Sheets:** `captures/review/props/r2/{sheet_close,sheet_mid,sheet_far,crops_detail,crops_charge,crops_drv,
  game_tl_tree,worker_sites_s,lineup,atlas_diff,atlas_signs,blender_close_s,strips}.jpg`.
- **Reference vs game:** `captures/review/props/r2/cmp_ref.jpg` (toll_g4_xinyang_2023, sinopec_hangzhou_2018,
  byd_flash_1000kw_2025).
- **Forecourt luminance** (PIL, mean L of the ground region): gas_soffit 32.9, gas_col5 25.4, charge_20 16.3,
  toll_soffit 54.2; the gas soffit itself is 181.9.
- **Blender:** `tools/blender.sh preview game/assets/props/street/traffic_light_mast.glb review_props_r2_tl
  --views front34,close_front34 --light night` → no UNTEXTURED materials; height 6.42 m.

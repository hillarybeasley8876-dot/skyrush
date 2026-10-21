# npc_cars review round 3 — VERDICT: FAIL

## Scores (0-10): function 4.5, visual 2.5, code 4.5
Round 3 delivered real progress on the pipeline:
- One lofted generator for all the cars.
- Doors and bonnet ray-cast onto the body.
- Red tail bars that come from the red LED rect of the trim sheet.
- Police livery on all three police cars.
- Unique node names, 21 surfaces per traffic car.
- A checker that now really checks things.
- 73 PASS in the Godot test.

The picture is still a grey-box fleet, nowhere near "贴图纹理什么都要细化":
- Every body is FLAT-SHADED (faceted).
- The side windows are stepped "lightning bolts".
- The roofs are flat planks, so sedans read as limos or hearses.
- Every wheel is a black hole.
- The bus, van and truck are untextured-looking boxes with flat disc wheels.
- Every front plate is mirrored.
- The bus route sign is still broken (same UV bug as r2). The bus bumpers float at 2.7 m.
- Next to `taxi_roewe_ei5_2020.jpg`, `police_vw_patrol_2011.jpg` and `bus_yutong_e10_2018.jpg` (v3_ref_compare.jpg)
  none of the models reaches the reference.

False or overstated claims in result.md/status:
- "amber LED route sign … at its true aspect" (false, item 5b).
- "glass sits flush … no ragged edge" (stepped, item 2).
- "smooth car surfaces" (flat shading, item 1).
- "rounded front cap" (the bus front face reaches the full half width, item 5c).
- "the .glb format does not allow external references" (false: see item 8).

Lead notes:
- IMPORT-CHURN: FAIL (item 8).
- N-ART5: a ok, b FAIL (straight ramps + flat roof, item 3), c ok, d FAIL (level 1 + flat shading, item 1),
  e partial (Glass object ok, stepped DLO item 2), f partial (lamps ok, front plates mirrored item 6), g partial
  (variants exist; the lineup is not a side view, item 9).
- Note 1: FAIL (items 1–4).
- Note 2: PASS.
- Note 3: FAIL (item 5).
- Note 4: partial (the paint mix is OK; police read as police at 6–20 m in Godot).

## MUST-FIX
1. **Flat-shaded, faceted bodies (N-ART5 d).**
   - Evidence: sedan Body has 10,170 verts on 3,064 positions, and 74 % of the positions carry split normals
     (bus 35 %). Facets show in every studio view (v3_sedan_studio.jpg, v3_grid_close.jpg).
   - Cause: `body.py:288` uses `add_subsurf(body, 1)`, and no `use_smooth`/`shade_smooth` call exists anywhere in
     `blender/npc_cars`.
   - Fix: after the subsurf apply, call `mesh.shade_smooth()` on Body, Door_*, Hood, Bumper_*, Flares, Glass and
     the wheels.
   - Fix: keep crisp only the crease rows, the glass boundary and the panel rims, with
     `mesh.set_sharp_from_angle(angle=radians(35))` before export. Both API names were checked in this Blender 5.2.
   - Budget: level 2 at today's cage is about 23.6 k tris for the Body alone (budget 25 k per car). Get the look
     with smooth normals first. If the silhouette still shows facets at 5 m, use level 2 on the lead's 28-station
     cage with a 0.24 m cabin pitch (now 0.16) and keep the car ≤ 25 k.
   - Check (check_glb + test): Body split-normal positions ≤ 15 %.
   - Verify: close_front34 studio and night sheets show no facets on the bonnet, wings and rear quarters.
2. **Stepped "lightning-bolt" glass (N-ART5 e, lead note 1).**
   - Cause: `FLANK_GLASS_LOW` runs cowl → C pillar but `FLANK_GLASS_HIGH` only roof_front → roof_rear
     (`body_loft.glass_cells`). Every side window gets a Z-shaped step at the A pillar (v3_grid_side.jpg,
     v3_grid_front34.jpg, v3_grid_close.jpg).
   - The windscreen covers only the centre columns (11–13). From the side, the A pillar reads as a broad white
     wedge.
   - The robotaxi canopy edge is a saw-tooth (v3_grid_close.jpg, bottom right).
   - Fix: build each side window as a ray-cast shell like the doors (`body.shell`). Use a 12×4 grid sampled on the
     finished body, 2 mm proud, `SH_glass_tinted`. Outline:
     - the belt line from the A-pillar foot (cowl_y − 0.05) to the C-pillar foot;
     - straight raked lines up the A and C pillars;
     - the roof edge (glass top) between them.
   - Fix: put black NPC_trim behind the glass so no paint shows in the seams. The B pillar is a black strip 70 mm
     wide.
   - Fix: extend the screen band to the roof-edge columns so the windscreen and backlight wrap to the pillars.
     The A pillar must be ≤ 80 mm wide seen from the side.
   - Fix: the robotaxi canopy gets the same treatment, with a smooth outline that does not follow the cage cells.
   - Verify: side and front34 grids: every window edge is a straight raked line with no step, and the
     windscreen reads dark from the side.
3. **Silhouettes still boxy (lead note 1, N-ART5 b/g).**
   - Cause: `top_z` is straight ramps with a flat roof. The sedan roof is a 1.60 m flat plank (roof_front_y 0.45 →
     roof_rear_y −1.15), the deck is 1.14 m high and the tail vertical, so the sedan reads as a limo or hearse
     (v3_grid_side.jpg, Godot c6_sedan_side).
   - Fix: smooth the top profile through the keys (Catmull-Rom or Bezier; N-ART5 b says "smoothed"). Keep only the
     cowl crease.
   - sedan_ev: roof crown 1.47 m at y ≈ +0.10 (45 % of L from the nose), dropping to 1.40 at y −0.55. Backlight
     15–18° down to the deck at y −1.75, z 1.02. Tail 0.98 with a 30 mm lip.
   - suv_ev: roof drop ≤ 30 mm, D pillar ≤ 20° from vertical. Black cladding on the arches, 100–140 mm (the
     `Flares` of suv_ev use `SH_car_paint_npc` today, so make them NPC_trim), plus black lower sills.
   - hatch_ev: round DRL pods ⌀ 0.16 m (not the sedan bar) and a tailgate ≤ 15° from vertical.
   - robotaxi: a cyan #19E6FF E2 LiDAR ring (`LiDAR` uses the white `NPC_lamp_front` today), a black canopy from
     the nose to the roof rear, and a sliding-door seam. The door panel currently shows as a lighter misfit
     rectangle (v3_grid_side.jpg).
   - Verify: in the orthographic side lineup (item 9) each type can be named without labels and matches the
     proportions of taxi_roewe_ei5_2020.jpg / police_vw_patrol_2011.jpg.
4. **Every wheel is a black hole (r2 item 8 not done).**
   - Godot c6_sedan_side at 6.5 m: mean luminance 12/255 in the rim zone vs 17/255 on the tyre ring. The rims are
     darker than the rubber.
   - The rim is a 256 px disc in the corner of the 1024×2048 `npc_wheel.png` (6 % of the sheet), and it reads
     dark at any distance.
   - Cars: model the 5-twin-spoke rim as geometry (or as a rim face with its own 1024² texture): machined
     #A6ABAF, pockets #1C1E21, a centre cap, and a brake disc #5A5D60 with a caliper behind the spokes. Round the
     tyre shoulder.
   - Bus, van, truck: the wheels are flat black discs (v3_grid_big.jpg). Build 22.5" steel wheels (#9A9EA3,
     10 studs, a hub cap, 8 hand holes) in tyres with tread and sidewall normals.
   - Verify: rim luminance ≥ 2× tyre at 6 m in Godot, and the rims read lighter than the tyres at 20 m.
5. **Bus (lead note 3): still a box, plus 3 hard bugs.**
   (a) The bumpers float at roof height. `boxdetail.py:121` `w, h, z0, z1 = sign["front"]` overwrites the
       `z0 = sp["z0"]` of line 54. Lines 166–177 then build Bumper_F/Bumper_R at glTF y 2.68–2.92 m: the black
       bars above the windscreen (v3_plates_crop.jpg). The bus has no bumper at the bottom, and the damage unit
       will tear the "bumpers" off the roof line.
       - Fix: rename the sign variables. Split the 193-line `build_box_details` into one function per part.
       - Test: Bumper_F/R top < 0.9 m.
   (b) The route sign is still black. `_panel(..., (0, 0, 1024, 256))` goes through `set_uv_quad(size=1024)`,
       which gives v 0–0.25: the top quarter of the 1024×256 `sign_bus_front.png`. Godot 9 m front shot: 0 amber
       pixels.
       - Fix: compute the rect from the image's real size, so v 0–1.
       - Check: SignRoute's UV covers ≥ 90 % of its image.
       - Verify: > 2,000 amber pixels in a 9 m Godot front shot, with 申城公交 71路 legible.
   (c) The shape is still the grey box (v3_grid_big.jpg, v3_ref_compare.jpg).
       - The front face reaches |x| = 1.275 at z −6.00, so there is no 0.45 m plan radius.
       - The windscreen is two dark panes with a white mullion.
       - The wheels sit in front of the skirt with no arch cut-outs.
       - The doors are black NPC_trim slabs under one node, `Doors`.
       - Build it like bus_yutong_e10_2018.jpg:
         - a rounded front cap (r ≥ 0.45 m);
         - a wrap windscreen 2.3 × 1.8 m raked 8–10°;
         - a continuous dark glazed band;
         - arch cut-outs with liners;
         - glazed double doors named `Door_FR` / `Door_RR`;
         - side and rear route signs.
   - Van and truck: the same pass for the cabs (raked, wrapped screens, real mirrors), bumpers, and the wheels
     from item 4.
6. **Number plates.**
   (a) Every FRONT plate is mirrored, in Blender (sedan "沪A·D71345" reversed) and in Godot (robotaxi, c5_patrol).
       The rear plates read correctly (v3_plates_crop.jpg).
       - Fix: flip u on front-facing plates and text. On a front face (glTF −Z) the viewer's right is −X.
       - Test: on every Plate island, u increases toward the viewer's right.
   (b) The van, truck and bus plates sample a blank strip (v3_boxplates.jpg).
       - UV v 0.31–0.47 × u 0–0.5 (van) / 0.5–1.0 (truck) / 1.0–1.5 (bus, which wraps) straddles two cells of the
         2048×480 atlas, so the plate shows the edges of two green plates with no characters.
       - The brief asks for blue 沪B·xxxxx plates on the van and truck, and the bus has its own 沪A·12345D cell.
       - Fix: take the rects from the atlas cell table with the real image height (480).
       - Check: every Plate UV island lies inside one cell.
7. **Geometry under the ground.** The van, truck and bus `Trim` reach glTF y = −0.045 (the cars: 0.002).
   - Fix: keep chassis and skirt bottoms ≥ 0.01 m.
   - Check + test: min Y ≥ −0.005 for every mesh of every model.
8. **IMPORT-CHURN (lead, 08:40, mandatory). Nothing done yet.**
   (1) `texlib.save()` and `build.export_glb()` always rewrite. Every rebuild re-imports 12 .glb, 143 extracted
       images and 155 .import files, under the team-wide import lock.
       - Fix: generate to memory or `tmp/npc_cars/`, compare bytes with the file on disk, and write only on change.
       - The .glb export is not byte-deterministic (status). Diff two exports, find the cause, fix it, then
         compare.
       - Verify: a second `build.py` run prints "unchanged" for all 12 models and 26 textures.
   (2) Texture sizes:
       - `npc_wheel.png` 1024×2048 (most of it flat tyre): make it 1024² with a large rim area (item 4).
       - `livery_taxi.png` 2048×1024 holds one skirt strip: drop it (item 10c) or use 1024×512.
       - The police liveries stay 2048×1024 (that is the brief's size).
   (3) Stop Godot's per-glb copies: 143 images (4.8 MB) such as `bus_npc_black_plastic.jpg` sit next to the .glb
       files.
       - Fix: in each owned `*.glb.import`, set `gltf/embedded_image_handling` to discard, and map the NPC_*
         materials through `_subresources` to external `game/assets/cars/npc/materials/*.tres` that use
         `textures/*.png` (r2 item 13). Godot supports this; the .glb paths that traffic/police/vehicle load stay
         the same.
       - Verify: `ls game/assets/cars/npc/*_npc_*.* | wc -l` → 0 and `du -sh game/assets/cars/npc` ≤ 12 MB.
   (4) Report the texture count and total MB in status (now 26 sheets / 3.4 MB + 143 copies / 4.8 MB +
       17.3 MB glb).
9. **Lineup + evidence (N-ART5 g, brief acceptance).**
   - `lineup_five.jpg` is a 3/4 perspective, and the "figure" is a grey post.
   - Fix: render an ORTHOGRAPHIC SIDE lineup of all 12 vehicles in one image: same scale, ground line, a 1 m grid
     and a human silhouette 1.75 m tall (capsule body + head).
   - Fix: re-capture `preview_npc.tscn` after the final build. `npc_preview_t2_0.jpg` (08:08) and `lineup_*.jpg`
     (08:18) predate the 08:22 .glb files.
10. **Texture detail (the user: 贴图纹理什么都要细化).**
    (a) Black plastic.
        - `npc_black_plastic.png` is 512² cloud noise with a 256² normal. Stretched over the bus skirt it reads as
          wood grain (v3_grid_big.jpg, bus close-up).
        - Fix: a 1024² fine stipple/grain (0.2–0.4 mm features) plus a matching normal, box-projected in metres
          with `lib/uv.py` (0.5 m tile), so it never stretches.
    (b) Mirrors and door handles are plain black boxes (v3_grid_close.jpg).
        - Mirrors: model a cap (body colour or gloss black), a glass face (#0B0E13, metallic 0.8) and an LED
          repeater strip.
        - Handles: flush, in a 3 mm recess.
    (c) Taxi.
        - In game the skirt is teal × the silver livery RGB, which renders dark teal, not #A9ADB1 (c6_taxi_r).
          Give the skirt its own `NPC_taxi_skirt` material. That removes the dependency on the shaders request.
        - The roof box is 0.74 m wide (`extras.py:66`); r2 asked ≥ 0.9 m.
        - The box needs emissive white 申城出租 on the front AND rear faces plus "TAXI", legible in a 6 m Godot shot.
    (d) Police liveries.
        - The claimed spray speckle and drips are not visible: each livery is a 26 KB PNG at 2048×1024 (v3_tex.jpg).
        - Add 1–4 px wheel-spray speckle, denser toward the arches, plus vertical drips, at ≤ 25 % #2E2A26.
    (e) `NPC_grille` (no normal) and `NPC_roof_number` (no normal, no roughness): add a normal map and roughness
        breakup.
11. **Code rules.**
    (a) `build.py` copies the glTF export instead of using `blender/lib/export.export_glb` (CONTRACTS §2: "Use them;
        do not copy them"). Use the lib. If WEBP is needed, request a lib option in status.
    (b) Magic numbers in logic: inline float literals per file are details.py 98, boxdetail.py 102, extras.py 77,
        drone.py 80, lineup.py 76. Examples:
        - `details.py:49` `z_nose - 0.215`;
        - `details.py:78` `_z_floor(sp) + 0.155`;
        - `details.py:140` mirror box sizes;
        - `boxdetail.py:141-142` van livery corners `-2.3, 0.95 … 0.9, 1.85`;
        - `extras.py:51-54` police roof-number quad `ry = -0.95`, `±0.32`, `±0.16`;
        - `extras.py:66` `(0.74, 0.24, 0.16)`.
        Move them into `spec.py` tables or named constants.
    (c) Long functions: `build_box_details` 193 lines (it hides the z0 bug of item 5a), `build_box_vehicle` 98,
        `build_details` 61. Split them into parts of ≤ 40 lines.
    (d) `test_npc_assets.gd` is at 399 lines. Split it (e.g. `test_npc_nodes.gd` + `test_npc_materials.gd`), then
        add the new tests from items 1, 5, 6 and 7.

## SHOULD-FIX
- **Lengths:** the cars are 63–65 mm short (sedan 4.787 vs 4.85, SUV 4.685 vs 4.75, hatch 3.885 vs 3.95, robotaxi
  4.135 vs 4.20) because the subsurf pulls in the nose and tail. Push the end stations out by the measured shrink.
- **Tail bars:** in Godot they render salmon (240,120,100) (c5_rear), not a deep red. Try emission 3 with the
  #3A0508 gaps and check r ≥ 2.5·g on the lit pixels. Keep it coordinated with the hero car's values.
- **Bumpers:** Bumper_F does not wrap the corners (sedan x ±0.80 of ±0.95, 16 cm deep). r2 asked ≥ 0.25 m round
  each corner.
- **Materials:** `SH_car_paint_police` / `SH_car_paint_taxi` are exported twice per .glb (two material entries with
  one name). Merge them (−1 surface).
- **Fallback glass:** `SH_glass_tinted` exports OPAQUE black. Export it as BLEND alpha 0.55 (dossier §4.8) so the
  modelled interior shows wherever the runtime swap is absent.
- **Scratch:** files went to `tmp/` root (`tmp/police_sheets.log`, `tmp/body_old.py`) and `tmp/npc/`. Use
  `tmp/npc_cars/` only (all deleted now, good).

## Verified OK
- `tools/godot.sh check --only=res://assets/cars/npc/` → `CHECK 3 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_assets.gd` → 73 PASS / 0 FAIL, rc=0. The test
  `extends Node` and is statically typed.
- Previews (all 12): no UNTEXTURED material; nodes per contract (root named after the file, Body, Glass,
  Wheel_*, Bumper_F/R, Hood, Door_*, Lamp_F/R, Light_Front/Rear, LightBar + LightBar_Red/Blue + Siren on police,
  Spot on the drone); no duplicate names.
- Surfaces: traffic cars 21, police 25–26, drone 17.
- Tris: cars 15.2–18.5 k, van 5.2 k, truck 7.7 k, bus 7.1 k, drone 2.5 k (all within budget).
- `check_glb.py` now really reads `material`; only the 2 known width notes remain (bus/truck mirrors).
- Lamps: Lamp_F samples the white LED rect (232,242,255). Lamp_R samples the red rect (255,32,48) / (58,5,8);
  NPC_lamp_brake is a separate material. The night sheets show red tail bars and glowing DRL bars on every car.
- Light bar: LightBar_Red emissive (1.0, 0.014, 0.030) E12, LightBar_Blue (0.023, 0.107, 1.0) E12; Siren on the roof.
- Godot (MaterialLibrary.apply, real environment):
  - Police patrol right flank: navy band, pinstripe, 天巡 SKYPOL on the front door, 沪-07 by the rear door
    (c6_patrol_r).
  - The taxi renders teal.
  - Capture errors=0; 96–126 fps with 15 vehicles + drone.
- Drone: rotor origins on the hubs (±0.509, 0.075, ±0.509); Spot points down; no `texCoord: -1`.
- Doors are closed shells with level tops (test). No doubleSided flag on the opaque car materials.
- Ownership: the job log shows Write/Edit only in `blender/npc_cars/**`, `game/assets/cars/npc/**`,
  `status/npc_cars.md` and the job result; scratch was deleted. The unit's paths are untracked in git (not yet
  committed by the lead).

## Evidence
- **Godot check:** `tools/godot.sh check --only=res://assets/cars/npc/` → `CHECK 3 files, 0 failed, 0 engine errors,
  0 warnings`.
- **Godot test:** `tools/godot.sh test res://assets/cars/npc/tests/test_npc_assets.gd` → 73 `PASS` lines, rc=0.
- **Previews:** `tools/blender.sh preview game/assets/cars/npc/<m>.glb ../review/npc_cars/r3_<m> --views
  front34,rear34,side,front,rear,close_front34 --light both` for all 12 models.
  - Sedan: `PREVIEW objects=19 tris=17926 size(m) x=2.08 y=4.79 z=1.46`; materials list without UNTEXTURED.
  - Bus `tris=7144 size 3.10×12.06×3.25`, van `5246`, truck `7694`.
  - Sheets: `captures/review/npc_cars/r3_<model>_{studio,night}*.jpg`.
- **Reviewer grids** (`captures/review/npc_cars/`):
  - v3_sedan_studio.jpg (facets, mirrored front plate);
  - v3_grid_side.jpg, v3_grid_front34.jpg, v3_grid_rear34.jpg (the 8 cars; stepped glass, flat roofs);
  - v3_grid_night.jpg (red tail bars, box bus/van/truck);
  - v3_grid_big.jpg (bus/van/truck/drone: flat disc wheels, wood-grain skirt);
  - v3_grid_close.jpg (facets, lightning-bolt DLO, box mirrors, robotaxi saw-tooth canopy);
  - v3_tex.jpg (texture sheets);
  - v3_ref_compare.jpg (vs taxi_roewe_ei5_2020 / police_vw_patrol_2011 / bus_yutong_e10_2018);
  - v3_plates_crop.jpg (mirrored front plates in Blender and Godot, black bus sign, bumper bar at the roof);
  - v3_boxplates.jpg (the atlas strip the van/truck plates sample).
- **Godot captures:** `tools/godot.sh shot --scene=/Users/minimax/m/skyrush/tmp/review/npc_cars/r3/review_npc_r3.tscn
  --out=review_npc_cars_r3 --cams=...` → 11 shots, `CAPTURE errors=0 warnings=0`, 96–126 fps.
  - Shots: c5_patrol, c5_taxi, c5_rear, c6_sedan_side, c6_patrol_r, c6_taxi_r, c20_row, c50, c100, c9_bus,
    c8_vantruck (in `captures/review/npc_cars/review_npc_cars_r3_*.jpg`).
  - Sheets: v3_godot_close.jpg, v3_godot_far.jpg.
  - The scene loads the real environment, applies MaterialLibrary per car and sets §4.7 paints through
    `base_color_override`.
- **Pixel stats** (`tmp/review/npc_cars/r3/redstat.py`, `brightcol.py`):
  - c9_bus: amber = 0.
  - c5_rear tail-bar pixels: (240,120,100).
  - c6_sedan_side wheels: luminance by radius [12.1, 11.2, 16.8, 26.1] (rim darker than tyre).
- **glTF audit** (`tmp/review/npc_cars/r3/glb3.py`, `nodegeo.py`, `shading.py`, `texc.py`):
  - Bus Bumper_F/R at y 2.68–2.92.
  - SignRoute UV v 0.00–0.25.
  - Plate UVs: van u 0–0.5, truck 0.5–1.0, bus 1.0–1.5, all at v 0.31–0.47.
  - Box vehicles: min Y −0.045.
  - Sedan Body: 74 % split-normal positions.
  - Bus front face: |x| = 1.275 at z −6.00.
  - suv_ev Flares = SH_car_paint_npc.
  - robotaxi LiDAR = NPC_lamp_front.
- **Unit checker:** `python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb` → `total problems: 2` (the
  bus/truck widths).
- **Code:** `grep -n "add_subsurf\|use_smooth\|shade_smooth" blender/npc_cars/*.py` → only `body.py:288
  add_subsurf(body, 1)`. The z0 overwrite is at `boxdetail.py:54` / `:121` / `:166-177`. `texlib.save` →
  unconditional `img.save(path)`.
- **Files:** `du -sh game/assets/cars/npc` → 26M; 143 extracted per-glb images (4.8 MB) + 155 `.import`;
  `textures/` 26 PNG, 3.4 MB.
- **Job log** (`tmp/review/npc_cars/r3/logpaths.py`): all Write/Edit targets are inside owned paths (+ the job
  result.md).

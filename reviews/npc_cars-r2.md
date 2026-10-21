# npc_cars review round 2 — VERDICT: FAIL

## Scores (0-10): function 3, visual 2, code 3
Round 2 fixed real things. The lamps are on the right ends, the car primitives have UVs, colours are hex tokens,
the preview is Y-up, the bus has 2 axles (6.0 m wheelbase, 2.6/3.4 m overhangs), the plate atlas uses the
right formats, and the tyre normal has valid embossed lettering. But at 5, 20 and 50 m the fleet still looks
like a grey-box kit:
- 8 cars share one slab body with black rectangles stuck on.
- The tail lights glow white.
- Every plate is hidden behind opaque quads.
- The interior atlas tiles over every headliner and shows through the glass.
- The van cab has no roof and no front.
- 2 of the 3 police cars have no livery.
- The bus front is a flat slab with a broken route sign.
None of the 4 lead notes is met. Several result.md claims are false: duplicate names "gone", END CHUNK
markers "gone", `knots_at` "removed", the lineup "painted from the §4.7 mix", and check_glb "0 problems"
(that checker never runs, see item 12).
Lead notes: note 1 FAIL (items 5–8), note 2 FAIL (items 1–2), note 3 FAIL (items 5e, 9), note 4 FAIL (items 4,
14e).

## MUST-FIX
1. **Tail lights glow WHITE, not red (lead note 2).**
   - Cause: `NPC_lamp_rear` uses emissiveFactor [1,1,1] × strength 4 × emissiveTexture `npc_trim`. Lamp_R's UVs
     (u 0.50–0.75, v 0.50–0.62) sit on the same white LED strip as Lamp_F: pixels (232,242,255) and
     (120,140,170), mean (181,194,213). The red base-colour tint (0.32,0.02,0.03) does not touch emission.
   - Evidence: the night rear renders have 0 saturated-red pixels (r2_sedan_ev_night_rear.jpg,
     r2_bus_night_rear.jpg). In Godot r2g_c5_taxi_rear.jpg every car shows a blue-white bar from behind, so it
     reads as oncoming traffic.
   - Fix: add a red LED rect to `atlas.TRIM` and UV Lamp_R into it: 128×4 px stripes, 50 % duty, lit #FF2030,
     gap #3A0508 (ref/art §4.8). Or drop the emission texture and use emissiveFactor = hex_lin("#FF2030").
   - Fix: give the brake segments their own material `NPC_lamp_brake` (#FF2030, E4) so traffic can drive them.
   - Build assert in `check_assets`: Lamp_R's mean emission (factor × mean texel over its UV bbox) has R ≥ 4·G
     and R ≥ 4·B. Lamp_F is near-white (min channel ≥ 0.8 × max).
   - Verify: the night rear sheets of all 11 ground vehicles show red bars. A rear Godot shot has saturated-red
     pixels > 0.
2. **The lamps float off the body.**
   - Front: Lamp_F's DRL is ONE flat quad, 1.45 m × 27 mm, at z −2.429 (glTF). The nose at |x| > 0.70 is at
     z −2.30, so the bar ends hang 13 cm in front of the car. The inner edges of the headlamp quads are at
     z −2.483, 58 mm proud of the nose (−2.425).
   - Rear: Lamp_R reaches z +2.49; the body ends at +2.42.
   - Result: the sedan bbox is 4.97 m long, not 4.85 m (preview `size(m) x=2.14 y=4.97`).
   - Fix (details.build_lamps): build each lamp as a strip of ≥ 16 segments. Ray-cast EVERY vertex column onto
     the body (BVHTree.ray_cast along ∓Y) and offset it 2 mm along the hit normal. Or inset the body faces in a
     lamp groove (bmesh inset, then push in 4 mm) and assign the lamp material there.
   - Fix: give the headlamps a lens over a dark housing with a projector ring (from the trim atlas).
   - Build assert: every lamp vertex is within 5 mm of the body (`BVHTree.find_nearest`).
   - Verify: the sedan bbox length is 4.85 ± 0.02 m. The close_front34 night render shows the bar following the
     nose curve.
3. **Every number plate is hidden.**
   - Front of the sedan (glTF −Z is the front): Bumper_F is an opaque black quad at z −2.421. The plate "frame"
     is a full opaque NPC_trim quad (0.47 × 0.17 m) at −2.427. The plate is at −2.417, behind both.
   - The rear is built the same way. No plate is visible in any Blender or Godot view.
   - Fix: make the frame a ring (outer 470 × 170 mm, inner 444 × 144 mm), or a backing BEHIND the plate. The
     plate must be the front-most surface: 2 mm proud of its backing, inside an 8 mm plate pocket modelled into
     the bumper (geometry, not a cover quad).
   - Fix: add the embossed-character normal that r1 item 3c asked for (NPC_plate has no normalTexture).
   - Verify: 5 m Godot front and rear shots show a legible 沪A·Dxxxxxx. Add a test that ray-casts from 1 m in
     front of the plate centre and hits the Plate surface first.
4. **The police interceptor and the police SUV are not police cars.**
   - Cause: `spec.INTERCEPTOR` and `spec.POLICE_SUV` are built with `livery=None`.
   - Result: they get `SH_car_paint_npc`, the traffic paint, which the traffic unit will repaint black, blue or
     silver. They have no UV1, no navy band and no 天巡 SKYPOL (r2_police_interceptor_studio*.jpg,
     r2_police_suv_studio*.jpg). In the 50 m Godot crop (v2_lineup_50m.jpg) they are plain white cars.
     The brief asks for "same livery family".
   - Fix: livery="police", POLICE_WHITE and `SH_car_paint_police`.
   - Fix: build a livery sheet for each car from its own L and door positions. Keep 天巡 SKYPOL ≥ 60 mm clear of
     both arches (r1 found "天巡 SKYPO" cut off by the arch).
   - Test: all three police roots carry SH_car_paint_police with ARRAY_TEX_UV2 on Body and Door_*.
   - Verify: Godot shots of both flanks of both cars at 6 m (as in r2p_patrol_right.jpg).
5. **The panels and body geometry are broken.**
   (a) The right doors are 19 cm shorter than the left ones.
       - Door_FR/RR top at y 0.72 m; Door_FL/RL top at 0.91–0.92 m; the glass starts at 0.96 m.
       - This leaves a 24 cm black hole above the right doors on every 4-door car (side views in
         v2_fleet_cars.jpg).
       - Fix: use one beltline table for both sides, mirrored. Assert |top(Door_xL) − top(Door_xR)| < 5 mm.
   (b) The rear doors and the robotaxi doors are flat cards on a curved flank (Door_RL: x-extent 0.005 m,
       49 verts). Cut every door out of the body shell so it keeps the body curvature: 4 mm seam, 25 mm
       thickness (solidify), dark inner panel 22 mm behind.
   (c) Bumper_F and Bumper_R are single 4-vertex black quads (1.52 × 0.24 m, zero depth) on all 8 cars.
       - They are detachable crash parts (CONTRACTS §6). A flat card flying off a car reads as a bug.
       - Build a body-colour 3D bumper cover: wraps ≥ 0.25 m round each corner, 0.15–0.25 m deep, ≥ 400 tris.
         Inset the black textured intake, the plate pocket and the DRL groove, and give it its own inner dark
         surface.
   (d) Saw-tooth faces at the robotaxi's front arch (Godot r2h_taxi_sign.jpg, left car). Clean the boolean and
       model an arch lip.
   (e) The van cab has no roof and no front.
       - From outside you see the seats and floating glass planes (r2_van_studio_front34.jpg, Godot
         r2h_van_cab.jpg).
       - Cause: the windscreen cutter in boxcar.build_box_vehicle (`slab(cy1 - 0.26, cy1 + 0.2, ...)` with rake)
         removes most of the raked cab.
       - Fix: rebuild the cab as a closed shell: a windscreen opening with a 70 mm frame, A-pillars, a roof, and
         the glass seated 10 mm inside.
       - Add a check: no boundary edges on Body/Cab outside the declared openings.
6. **Eight cars share one slab body (lead note 1).**
   - Sedan, SUV, hatch, robotaxi, the three police cars and the taxi are one body scaled. All have a flat
     vertical nose with black rectangles, slab sides and the same greenhouse (v2_fleet_cars.jpg). At 30–80 m
     only the height differs.
   - Give each its own profile. Invent the styling; use real 2025–26 Chinese EV proportions:
     - sedan_ev: fastback. Bonnet leading edge 0.70 m, cowl 0.95 m, windscreen 27–30° from horizontal. Roof
       peak at 45 % of L from the nose, rear glass 15–18°, short deck, overhangs ≈ 0.90 / 0.97 m.
     - suv_ev: flat roof at 1.68 m, near-vertical D-pillar (≤ 20° from vertical), 100–140 mm black arch
       cladding, skid-plate lower bumper, bonnet at 0.95 m.
     - hatch_ev: rounded 2-box with plan corner radius ≥ 0.25 m, short bonnet, upright tailgate, round DRL
       graphics. Cute, like a 3.95 m Wuling-Bingo-class car.
     - robotaxi: one-box pod. The windscreen starts at the nose (no bonnet), a wrap-around dark canopy, an
       emissive LiDAR ring (#19E6FF, E2), one large sliding door per side, white body with a black canopy.
     - police_interceptor: 1.25 m tall, +40 mm arch flares, splitter, fastback, wide stance.
   - Nose and tail: loft them with plan corner radii ≥ 0.20 m and a body-colour fascia. Put the DRL bar in a
     20 mm groove. Make the lower intake an inset black textured grille (trim-atlas mesh), not a stuck-on
     rectangle.
   - Verify: side, front and 3/4 grids (320 px tiles) in which each type can be named without labels, plus a
     50 m Godot shot.
7. **The interior atlas tiles over every headliner, and atlas fragments land on the black trim.**
   - `Interior` (NPC_interior_trim) has box UVs u −1.50..1.50, v −0.64..2.32 over the whole npc_interior atlas.
     Gauge dials and seat tiles repeat across the headliner and pillars. Through the glass they read as a grey
     checker with blue arcs (v2_sedan_studio4.jpg close-up, v2_godot4.jpg).
   - Body's NPC_trim primitive has box UVs u −1.91..1.91, v −0.89..2.89 over the whole npc_trim atlas, so rim,
     grille and LED tiles land on the black trim.
   - Fix: never box-UV over an atlas. Either map each part into its own rect with set_uv_rect, or use a
     separate tileable texture (headliner fabric: ambientCG Fabric082A at 0.3 m; black plastic grain for trim).
   - Keep the cabin dark (headliner #2A2B2E, seats #1C1D20) so the glass reads dark, as in
     taxi_roewe_ei5_2020.jpg.
   - Build check: every UV of an atlas material lies inside one declared rect per face island.
8. **The wheels read as black holes.**
   - NPC_rim is a flat disc texture (one ring and 10 dots) on the wheel face: no spokes, no brake disc.
   - Cars: model a 19" aero rim. 5 twin spokes as geometry, machined face #A6ABAF with dark pockets #1C1E21, a
     centre cap, and a brake disc (#5A5D60, drilled normal) and caliper visible between the spokes. The tyre
     needs a rounded shoulder, not a cylinder.
   - Box vehicles: 22.5" steel wheels with 10 studs and a hub cap.
   - Verify: a close_side render and a 5 m Godot side shot. At 20 m the rims read lighter than the tyres.
9. **Bus (lead note 3).**
   - What is wrong: the front is a flat slab. The windscreen and side windows read as open holes
     (r2_bus_studio_front34.jpg, v2_ref_compare.jpg). There is no black window band, and the wheels are hidden
     behind a box skirt.
   - The front route sign is broken. SignRoute is 0.58 × 0.32 m with UVs v 0.00–0.25. It shows the top quarter
     of sign_bus_front.png (the text fills v 0–0.45), squeezed from 1024×64 px into a 1.8:1 quad. Godot at 7 m
     shows 0 amber pixels (r2h_bus_front.jpg).
   - Build it like bus_yutong_e10_2018.jpg:
     - rounded front cap, plan corner radius ≥ 0.45 m;
     - wrap-around windscreen ≈ 2.3 × 1.8 m, raked 8–10°;
     - one continuous dark glazed band from front to rear (SH_glass_tinted);
     - white roof with a 0.25 m battery/AC pod;
     - arch cut-outs with the tyres visible;
     - two glazed double doors on the RIGHT side (+X): the front door ahead of the front axle, the middle door
       behind it;
     - an amber LED destination sign, 1.9 × 0.30 m, above the windscreen ("申城公交 71路", UV the text rect at
       its true aspect), a side sign by the front door, and "71" at the rear.
   - Verify: bus front34, side and rear renders next to the reference. A 7 m Godot front shot shows legible
     amber text.
10. **Duplicate contract names (claimed fixed, not fixed).**
    - bus: Door, Door.001–.003, Glass + Glass.001, Lamp_F + Lamp_F.001, Lamp_R + Lamp_R.001,
      SignRouteSide + .001.
    - van: Door/.001, Glass/.001, Lamp_F/.001, Lamp_R/.001, Livery/.001.
    - truck: the same, plus Wheel_RL.001 / Wheel_RR.001 (a tandem axle).
    - Godot imports these as Lamp_F_001, Glass_001, Wheel_RL_001 (printed by my review scene).
    - Fix: join each group right after it is built. For example, `hex_box("Glass", …)` for the windscreen runs
      after `common.join(glass_parts, "Glass")` and creates a second node. Give the truck 2 axles, with dual rear
      tyres inside Wheel_RL/RR (origin on the axle).
11. **Drone.**
    - Rotor_* origins are 0.15 m off the hub: Rotor_FL origin x −0.359 vs blade centre −0.51; Rotor_FR +0.659
      vs +0.51. Spinning them orbits the blade. Put each origin on its hub (the *_blur discs are already right).
    - NPC_drone_trim and NPC_prop_blur still export `"texCoord": -1`: a metallicRoughnessTexture on meshes with
      no UVs, so r1 item 2 was not done for the drone. Add UVs or drop the texture.
12. **The checks are blind. This is how items 3, 4, 10 and 11 slipped through.**
    - check_glb.py loops over `prim.get("materials", [])`. glTF primitives have `"material"` (an int), so the
      UV check never runs and always prints 0 problems. The tangent check named in its docstring does not exist.
    - The test's `_duplicates` looks for ".001", but Godot turns "." into "_". Match `_\d{3}$` and require every
      contract name to be unique in the whole tree.
    - The UV test only looks at albedo and normal textures. Include roughness, metallic, emission and AO.
    - `MAX_SURFACES := 32` was raised so that 31 passes. The r1 target is ≤ 24.
    - Add tests for: red rear-lamp emission (item 1), the plate being front-most (3), the police material + UV2
      on all three police cars (4), and equal door tops (5a). Include the police roots in the preview ground
      check.
13. **Draw calls, double-sided materials and file size (r1 item 9 not done).**
    - Surfaces per car are 26–31 (target ≤ 24).
    - Every material in all 12 glbs exports `doubleSided: true` (Blender backface culling off). That doubles the
      fragment work on closed shells and hides inverted faces. TaxiDecal, TaxiDecal.001 and the bus SignRoute
      have inward normals: the mirrored-text fix flipped the faces instead of the UVs.
    - Godot still extracts 79 per-glb texture copies (`*_npc_*.png`). 11 stale `textures/plate_*.png`
      (10-19 22:52) and the old `<car>_plate_*.png` are still there. The folder is 55 MB (r1: 30 MB; target
      ≤ 12 MB).
    - Fix: `use_backface_culling = True` on every opaque material. Decal and sign normals point outward; flip
      only u.
    - Fix: one `NPC_interior` material for seat, dash and liner (−2 surfaces). One `NPC_wheel` material holding
      the tyre and rim albedo + normal in one atlas (−4 surfaces). Merge the plate frame into Trim. That gives 19
      surfaces for the sedan.
    - Fix: external NPC_* materials (game/assets/cars/npc/materials/*.tres → textures/*.png) through each
      .glb.import `_subresources`, plus `gltf/embedded_image_handling=0`. Delete the stale files.
    - Verify: the glb2 audit shows ≤ 24 prims per car, `ls game/assets/cars/npc/*_npc_*.png` → none,
      `du -sh` ≤ 12 MB.
14. **Texture detail (the user: 贴图纹理什么都要细化 — refine every texture).**
    (a) Taxi skirt and grime.
        - In Godot the paint shader multiplies teal × the livery RGB, so the "silver" skirt renders dark teal
          (r2p_taxi_left.jpg). Its grime is grey polka dots (leopard print, v2_tex_decals.jpg).
        - The skirt must be #A9ADB1. Either request `use_livery = true` for SH_car_paint_taxi / _police from the
          shaders unit and keep the skirt in the livery RGBA (alpha 1), or build the skirt as its own
          `NPC_taxi_skirt` material.
        - Grime = fine 1–4 px wheel-spray speckle, denser toward the arches, plus vertical drip streaks, at
          ≤ 25 % opacity #2E2A26. No discs.
    (b) The police band's grime is blotchy scattered dashes: give it the same treatment as (a). On the left
        flank 沪-07 lands on the front wing (u ≈ 0.28, while the left rear door is u 0.66–0.81) and is not
        visible in r2p_patrol_left.jpg. Put it by the rear door on both flanks.
    (c) Taxi roof box.
        - From the front at 4.6 m it is a dark brown box with no legible 申城出租 (r2h_taxi_sign.jpg).
          sign_taxi_roof.png is white text on black RGB, and an opaque material ignores the alpha.
        - Make the box teal #1E8C8A with white emissive text (E3) on the FRONT and REAR faces, plus a small
          "TAXI", ≥ 0.9 m wide.
    (d) NPC_trim, NPC_interior_*, NPC_plate, NPC_rim, NPC_sign_* and NPC_decal_* have constant roughness and no
        normal map (ART §5 b, c). Add roughness breakup and normals: plastic grain, leather, machined rim, plate
        emboss.
    (e) Lineup (lead note 4).
        - lineup.py `_tint` sets `mat.diffuse_color`, which only the viewport uses. That is why lineup_34.jpg is
          all white. Set the Principled Base Color input instead.
        - Include black #0E0F11 and grey #5A5F63 (no car uses them now).
        - Stand the 1.75 m figure in the FRONT row next to the sedan.
        - Re-render after the final build: lineup_34.jpg is from 01:52 and the glbs are from 02:32.
15. **Code hygiene (claimed done, not done).**
    - `# --- END CHUNK ---` is still in body.py:329, details.py:305 and spec.py:250.
    - `knots_at` (geom.py:37) is still defined and unused.
    - boxcar.py has 240 inline float literals (r1: 129), e.g. `cy1 - 0.24`, `hw * 0.98 - 0.18`, `L * 0.5 - 0.30`,
      `z0 - 0.12`, `hw * 0.8`. Move them into the spec tables or named constants.
    - Report results truthfully in result.md.

## SHOULD-FIX
- Light_Front (z −2.31) sits 11 cm inside the nose. Put Light_Front and Light_Rear on the lens surface.
- npc_plates.png wastes about 40 % of its area (2048×960 with black bottom rows). Crop it to 2048×512 or fill
  the space with dirt variants.
- The brief extras are still missing: charge-port flap, badge recess, third brake light.
- Delete the debug captures captures/blender/dbg_*.{jpg,png}.
- The status request about `maxf` in glass_tinted.gdshader is stale (there is no `maxf` there now). Remove it.

## Verified OK
- `tools/godot.sh check --only=res://assets/cars/npc/` → `CHECK 3 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_assets.gd` → 36 PASS / 0 FAIL (blind spots: item 12).
- Lamp_F is at the front and Lamp_R at the rear on all 11 ground vehicles. The front DRL glows near #EAF2FF.
- Every car primitive carries the TEXCOORD sets its materials use. `"texCoord": -1` appears only in the drone
  (item 11).
- Colour tokens: NPC_lightbar_red emissive (1.0, 0.014, 0.030), blue (0.023, 0.107, 1.0). Traffic paint base
  (0.807, 0.807, 0.791) = #E8E8E6.
- Plate atlas content: green gradient with black text and 6 characters after 沪A (沪A·D71345), blue 沪B·44127,
  the bus's split 沪A·12345D, rivets. (Hidden in the models, see item 3.)
- Tyre normal: tread grooves and an embossed "SKYRUSH CITYGRIP 235/45 R19", encoded as valid normals.
- Bus: 2 axles, wheelbase 6.0 m, overhangs 2.6/3.4 m, Wheel_FL/FR/RL/RR. Light_Front/Rear exist on bus, van and
  truck.
- Markers: Light_Front's −Z points to (0,0,−1) and Light_Rear's to (0,0,+1) on every model. The Siren is on the
  roof. The drone's Spot points down.
- Police patrol livery in Godot: navy band, yellow pinstripe, 天巡 SKYPOL on the front door. The text reads
  correctly (not mirrored) on both flanks (r2p_patrol_right/left.jpg).
- Preview scene is Y-up: roots at y = 0, camera at (3, 3, −30) looking along (0, −0.071, 0.997), 4 omni lights,
  MaterialLibrary.apply.
- Budgets: cars 16.0–19.4 k tris, van 5.6 k, truck 9.0 k, bus 8.5 k, drone 2.5 k. Widths and heights match the
  brief. Lengths run 0.06–0.12 m long because the lamps stick out (item 2).
- Ownership: the job log shows writes only in blender/npc_cars/**, game/assets/cars/npc/**,
  status/npc_cars.md and tmp/npc (deleted). All files are ≤ 400 lines (largest: boxcar.py, 370). The GDScript
  is statically typed and `extends Node`.

## Evidence
- `tools/blender.sh preview game/assets/cars/npc/<m>.glb ../review/npc_cars/r2_<m>` for all 12 models.
  - Sedan: `objects=18 tris=18079 size(m) x=2.14 y=4.97 z=1.47`.
  - Nodes: bus lists Door, Door.001–.003, Glass.001, Lamp_F.001, Lamp_R.001. Truck lists Wheel_RL.001 and
    Wheel_RR.001.
  - No UNTEXTURED flag.
  - Sheets: captures/review/npc_cars/r2_<model>_studio*.jpg and _night*.jpg.
- Reviewer grids in captures/review/npc_cars/:
  - v2_sedan_studio4.jpg, v2_night4.jpg (white rear bars), v2_fleet_cars.jpg (8 identical bodies,
    right-door holes)
  - v2_big4.jpg (bus, van with no cab roof, truck, drone)
  - v2_ref_compare.jpg (vs taxi_roewe_ei5_2020, police_vw_patrol_2011, bus_yutong_e10_2018)
  - v2_tex_decals.jpg, v2_tex_atlases.jpg
- Godot (scratch tmp/review/npc_cars/review_npc2.tscn and review_npc3.tscn: real environment.tscn,
  MaterialLibrary.apply, §4.7 colours via base_color_override):
  - r2g_c5_patrol, r2g_c5_taxi_rear (white tail bars), r2g_c12_big, r2g_c20_row, r2g_c50 (grids: v2_godot4.jpg,
    v2_lineup_50m.jpg, v2_c5_patrol_crop.jpg)
  - r2h_taxi_sign, r2h_bus_front, r2h_van_cab (v2_godot_close4.jpg)
  - r2p_patrol_right/left, r2p_taxi_left, r2p_patrol_top (v2_godot_livery4.jpg)
  - The scene printed `REVIEW nodes bus: ... Door_001, Door_002, Door_003, Glass_001, Lamp_F_001, Lamp_R_001,
    SignRouteSide_001` and `truck: ... Wheel_RL_001, Wheel_RR_001`. Capture: errors=0.
- `python3 -I ref/art/lookdev/tools/screenshot_stats.py`:
  - r2g_c20_row: SAT 0.243 % FAIL, P95 0.329 FAIL.
  - r2g_c50: SAT 0.005 % FAIL.
  - In both, no red tail lights and no accents.
- Reviewer scripts in tmp/review/npc_cars/. Copy their logic into your own checks.
  - glb2.py: UV/texCoord audit; prims per car 26/26/26/26/30/30/31/31 (cars), van 26, truck 28, bus 28,
    drone 17; drone badUV=8.
  - mats2.py: materials, emission, doubleSided.
  - uvdata.py: decoded UV ranges (Lamp_R u 0.50–0.75 v 0.50–0.62; Interior and Body trim box UVs over the
    atlas).
  - pos.py: plate, bumper and lamp vertex depths.
  - facing.py: inward-facing decals → TaxiDecal, TaxiDecal.001, bus SignRoute.
- Other checks:
  - `python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb` → `total problems: 0` (a no-op, item 12).
  - `du -sh game/assets/cars/npc` → 55M; `ls game/assets/cars/npc/*_npc_*.png | wc -l` → 79.
  - `grep -n "END CHUNK"` → body.py:329, details.py:305, spec.py:250.

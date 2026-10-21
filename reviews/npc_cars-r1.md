# npc_cars review round 1 — VERDICT: FAIL

## Scores (0-10): function 3, visual 2, code 4
The pipeline idea (parametric specs, a PIL texture generator, contract nodes, inner surfaces behind panels)
is sound. The output is not: the 12 models are grey-box quality, the lamps and plates are broken on every car,
most textured parts have no UVs, the Godot preview is built Z-up, and none of the 4 lead notes are met.
The result.md claims ("greenhouse faceting visible only in extreme close-ups", "preview captured, 0 errors")
do not hold up when you look at the images.

## MUST-FIX
1. **Lamps are broken on every car (lead note 2).** `Lamp_F` sits at the REAR and `Lamp_R` at the FRONT
   (sedan_ev: Lamp_F y −2.24..−2.20 while Bumper_F/Light_Front are at y +2.16..+2.43). Both are 2-poly quads
   lying FLAT on top of the nose/tail (z-thickness 0.01 m, mean normal (0,−0.42,−0.91) = facing down). So
   no head or tail light shows in any view. Lamp_F's emission is also multiplied by `npc_trim.png` sampled
   without UVs: texel (21,22,25), which is effectively black. Night sheets and my Godot shots show no headlights
   and no tail lights. In the c20 shot SAT is 0.28 %, so the cars vanish at night.
   Fix (details.py `build_lamps`/`_surface_quad`): use the real front ring (+Y). Place each lamp by
   ray-casting the finished body (mathutils.bvhtree.BVHTree.FromObject → ray_cast along −Y/+Y at (x,z)) and
   orient it to the hit normal. Model a full-width front DRL bar (≥ 1.40 m × 25–40 mm, #EAF2FF, strength 6),
   two slim headlamp units, a full-width rear bar (≥ 1.30 m × 30–50 mm, #FF2030, strength 4) and brake
   segments. Give the lamps UVs into an LED-segment strip (ref/art §4.8: 128×4 px stripes, 50 % duty) or use a
   plain emission colour; never use an emission texture without UVs. Add a build assert: Lamp_F centroid y > 0,
   Lamp_R centroid y < 0, mean normal · (±Y) > 0.6.
   Verify: `tools/blender.sh preview game/assets/cars/npc/sedan_ev.glb sedan_ev`: in the night front and rear
   views the bars glow. In a Godot night shot at 20 m the head and tail bars are clearly visible.
2. **Textured meshes have no UVs (the glb writes `texCoord: -1`, which is invalid glTF).** In every car:
   Plate, Lamp_F, Lamp_R, Glass, Seat_*, Dashboard, CabinLiner/Console/SteeringWheel, Inner_*, ArchFlare (NPC),
   taxi RoofSign + RoofSignFace. In the bus: Body, Roof, Door*, Skirt*, Bumper_*, Lamp_*, Glass*. The whole
   police_drone. Each of these renders as ONE texel: plates are blank #E8ECF0, the taxi roof sign is black
   (texel (0,0,0,0)), seats and dash are flat grey, and the glass grime is gone. The root cause is
   `_surface_quad`, `build_roof_sign`, interior.py, drone.py and the boxcar shell: they never create the `UVMap`
   that `materials.image_mat/plain_mat` read.
   Fix: every mesh with an image material gets the UV map its node graph names: uv.box_uv for tiling,
   meshutil.planar_uv/set_uv_rect for decals and atlas parts. Add a pre-export guard in build.py that fails
   the build if any Image Texture references a missing UV map.
   Verify: run `python3 tmp/review/npc_cars/nouv.py game/assets/cars/npc/*.glb` (reviewer's script; copy
   the logic into your own check) → zero NO-UV lines. The glb JSON has 0 `"texCoord": -1`.
3. **Mirrored text and wrong plates.**
   (a) The bus front route sign reads mirrored ("路17交公城申", captures/blender/bus_studio_front34.jpg). So do
   the van/truck/bus front plates (van_studio_front34.jpg). `planar_uv(axis=1)` on a +Y-facing face runs u
   against the viewer. `planar_uv(axis=0)` never flips per side, so the −X flank of the taxi door decal, the
   van livery and the bus side sign are mirrored too.
   Fix: flip u by facing direction, using the viewer-right rule as add_livery_uv already does. Render
   both flanks plus front and rear to prove every text reads correctly.
   (b) The car plates are horizontal (Plate normal (0,−0.35,0.94)) on top of the front bumper, and there is
   no rear plate. Fix: vertical 440×140 mm plates front and rear, recessed 5–10 mm, with a black frame.
   (c) The format is wrong. The brief says "沪A·Dxxxxx": 6 characters after 沪A ("D7K21" has 5). The small NEV
   plate is gradient green (light at the top → green at the bottom) with BLACK characters
   (ref/shanghai/SHANGHAI_DOSSIER.md vehicles row). The 12 m bus is a large NEV: yellow-green split plate,
   "沪A·12345D". Add an embossed-character normal, rivets and road dirt.
4. **Silhouettes and body surfaces (lead note 1).** Sedan, SUV, hatch, robotaxi and the police cars are the
   same box. The A/C pillars are stair-stepped (8–10 steps visible in the full-car side view,
   captures/review/npc_cars/sedan_ev_studio.jpg). The nose and tail are one dark "fan cap" with an X of shading
   wedges over the whole fascia. The doors are flat slabs with wide black gaps. The hatch is not "cute,
   rounded". The robotaxi is not a 2-seat pod (it has 4 doors and 4 seats). police_suv has no ram bar. Fix the
   structure, not with patches:
   (a) cabin.py: make the daylight-opening outline (A-pillar line, roof rail, C/D-pillar line, beltline)
   grid iso-lines, with rows that follow the pillar rake, so that pillar edges are straight or curved lines
   and never cell steps.
   (b) Replace the fan caps with lofted nose/tail sections (≥ 6 sections over the last 0.6 m, with corner
   radii) closed by a quad grid. Use a body-colour fascia, a recessed black lower intake and a DRL groove.
   Use weighted/custom normals (auto-smooth 35–40°) so no wedges show.
   (c) Flush panels with ≤ 6 mm seams. Real wheel-arch cut-outs with black textured liners, and tyres that
   fill the arch (gap ≤ 40 mm).
   (d) Give each model its own design: sedan = fastback, steep A-pillar rake, short overhangs; SUV = taller,
   flatter roof, chunky arch cladding; hatch = rounded 2-box; robotaxi = 2-seat pod with a wrap-around canopy
   and a sensor ring (emissive LiDAR); interceptor = low, wide, with a splitter; police_suv = ram bar
   (≥ 1.6 m wide, black, textured) and push bumper.
   Verify: side, front and 3/4 lineup renders. All models must read differently at 30–80 m.
5. **Bus, van, truck and drone are grey boxes (lead note 3).**
   - Bus: it has 3 axles (Wheel_ML/MR/RRL/RRR). A 12 m Yutong-E10-class city bus has 2 axles
     (ref/shanghai/img/09_street_details/bus_yutong_e10_2018.jpg): wheelbase ≈ 6.0 m, front overhang ≈ 2.6 m,
     rear overhang ≈ 3.4 m. It needs a rounded front cap, a huge raked windshield, a black window band,
     2 glazed doors and arch cut-outs.
   - Van and truck: cabs with a raked windscreen (≥ 15°), mirrors on arms, grille and lamps, cab doors
     Door_FL/Door_FR, and arch cut-outs.
   - Bus, van and truck all lack the Empties `Light_Front` and `Light_Rear` (brief). The bus lacks
     `Wheel_RL/RR`.
   - Duplicate contract names: bus Lamp_F + Lamp_F.001, Glass + .001/.002, Door + Door.001. Join each into one
     node.
   - Drone: a ring has no blades. Add 2-blade props plus a blur disc, a shaped shell with SKYPOL livery,
     saturated strobes and nav lights.
6. **Colour space.** palette.py feeds sRGB hex values in as linear floats with no conversion. The taxi
   renders #61C4C2 instead of #1E8C8A. Light-bar red emission (1.0,0.09,0.12) comes out ≈ #FF5461 instead of
   POLICE_RED #FF2030. Blue (0.16,0.36,1.0) comes out ≈ #70A1FF instead of #2A5CFF. The rear lamp (1,0.11,0.16)
   should be #FF2030.
   Fix: add one `hex_lin("#RRGGBB")` helper (sRGB→linear) and keep every colour as a hex token from ART.md §3 /
   ref/art §4.7–4.8 in a constants table. No raw float colours.
   Verify in the glb JSON: NPC_lightbar_red emissive ≈ (1.0,0.014,0.030), blue ≈ (0.023,0.107,1.0), taxi
   base ≈ (0.013,0.262,0.254).
7. **Godot preview scene and test are Z-up (CONTRACTS §1: Godot is Y-up).** preview_npc.tscn puts the cars at
   y = −2 (under the ground plane) and van/truck/bus at y = +9 (floating). The camera is at (3,−34,10),
   looking UP at the undersides: captures/review/npc_cars/r1_preview_t2_0.jpg and r1_preview_eye.jpg. The test
   locks this bug in (`fwd.y < 0.1` → FAIL).
   Fix: put every root at y = 0, in rows along X with ≥ 1 m gaps. Set the camera at y 1.6–4 m looking slightly
   down. Add 3–4 OmniLights (LED #D9E8FF, sodium #FFB46B). In `_ready`, call MaterialLibrary.apply and set
   `base_color` per car from the §4.7 mix (as in tmp/review/npc_cars/review_npc.gd). The test must assert
   root y ≈ 0 and −0.4 < fwd.y < 0.
   Verify: `tools/godot.sh shot --scene=res://assets/cars/npc/preview_npc.tscn --out=npc_preview --times=2.0`
   shows all 12 vehicles standing on the ground with their lamps lit.
8. **Texture detail is flat everywhere (user: "贴图纹理什么都要细化").**
   - livery_*.png is opaque RGB with exactly one colour per band and zero noise. Make it RGBA: transparent
     where the body paint shows, so the SH_car_paint `livery_tex` decal plus grime work. Add: grime and road
     film low on the navy band, edge wear at panel seams, a micro-patterned retro-reflective look on the
     yellow pinstripe, and a small unit code "沪-07" by the rear door.
   - Put "天巡 SKYPOL" on the FRONT doors on both flanks. Right now it lands on the rear door on the left
     flank because u is mirrored about y = 0: mirror about the door centre instead. The text also collides
     with the front arch on the interceptor and police_suv ("天巡 SKYPO" is cut off).
   - roofnum_*.png is generated but never used: put "沪-07" on the roof (characters ≥ 0.5 m) for the drone view.
   - npc_trim: real grille mesh, LED segments, projector/reflector lamp internals, textured rubber, a machined
     rim with a visible brake disc, sidewall lettering in the tyre normal (e.g. "SKYRUSH CITYGRIP 235/45 R19",
     18 mm caps).
   - npc_interior: seat stitching/perforation, a dash screen UI, a steering-wheel grip.
   - npc_paint_rough 512 → 1024, two-scale breakup. The glass grime must actually be mapped (item 2).
   - decal_van: `decal_text` only draws lines[0], so "SHENCHENG EXPRESS" is silently dropped. Fix the
     function and add courier graphics: a stripe and a fictional phone "400-6688-0000".
   - Taxi (brief: "roof light (emissive), door text, number"). The roof sign must be a teal box with emissive,
     legible "申城出租" on both faces (today it is black). Add door text on both flanks, a fleet number
     (e.g. "沪交 T-0731") and the phone "6688 1234". Add the silver-grey #A9ADB1 lower skirt every Shanghai
     taxi has (ref/shanghai dossier) as a UV2 livery like the police one, and request `use_livery` for the
     taxi paint from the shaders unit in status.
   Verify: the texture contact sheet plus 5 m Godot shots show legible text, wear and LED segments.
9. **Draw calls and shared textures (brief: shared sets "to keep draw calls low").** Each car has 42–47 mesh
   primitives (47 on the taxi). Godot extracted 12 copies of every shared sheet (30 MB, e.g. sedan_ev_npc_trim.png,
   police_patrol_npc_trim.png), so nothing is shared at runtime.
   Fix: merge non-detachable static parts by material. Seats, dash, console, steering wheel and liner become
   ONE `Interior` node (CONTRACTS §6). Merge Inner_* where possible. Handles, mirrors and flares go into Body.
   Target ≤ 24 surfaces per car. Plates go into one shared plate atlas material. Make NPC_* external shared
   materials (game/assets/cars/npc/materials/*.tres that reference textures/*.png) through each glb's import
   `_subresources` → `use_external`, and delete the per-glb copies.
   Verify: primitives per car ≤ 24, `ls game/assets/cars/npc/*_npc_*.png` → none, `du -sh` ≤ 12 MB.
10. **The test passes broken assets.** The per-model lists drop brief names: taxi/robotaxi skip Hood, Door_*
    and Bumper_*; van/truck/bus skip Light_Front/Rear and Wheel_RL/RR; interceptor and police_suv skip
    Light_Front/Rear. Nothing checks UVs, lamp placement or ground contact.
    Fix: one REQUIRED list for every ground vehicle (Body, Glass, Wheel_FL/FR/RL/RR, Bumper_F/R, Lamp_F, Lamp_R,
    Light_Front, Light_Rear) plus per-type extras (Hood/Door_* for cars, LightBar/_Red/_Blue/Siren for police,
    RoofSign for taxi, SignRoute for bus, Spot/Strobe_* for drone). Assert: Lamp_F AABB centre z < 0 (Godot
    −Z forward) and Lamp_R > 0; every textured surface has ARRAY_TEX_UV; no duplicate contract names;
    surfaces ≤ 24.
11. **Lineup (lead note 4).** Every car is white except the taxi. Paint each car differently from the §4.7
    mix (#E8E8E6 white, #0E0F11 black, #9DA3A8 silver, #1F3A5F blue, #5A5F63 grey), taxi #1E8C8A, police
    #F2F4F5. Put the 1.75 m figure beside the sedan in the FRONT row (now it is tiny at the far end). Add a
    50 m view in which the police read as police: navy band, lit light bar, "天巡 SKYPOL" legible.
12. **Code hygiene (global rules).**
    - Dead functions: `_rect_uv`, `_row_range`, `bpy_material_names`, `centre_uv`, `fan_cap`, `grid_object`,
      `knots_at`.
    - `# --- END CHUNK ---` leftovers in body/boxcar/cabin/details/geom/spec.py.
    - gen_textures.py swallows errors (`except Exception: pass` and a fallback to the PIL default font, which
      renders CJK as tofu). Raise instead.
    - boxcar.py has 129 inline float literals (`z1 - 0.52`, `L / 2 - 1.1`, …). Move them into spec.py tables
      or named constants.
    - SH_car_paint_police appears twice. ArchFlare samples the 6 m livery with TEXCOORD_0 (metre box UVs),
      so livery fragments tile on the flares. Give the flares UV1 or a no-livery paint.

## SHOULD-FIX
- Livery texel density: 2048 px over 6 m = 341 px/m. Span the sheet over L + 0.1 m (≈ 420 px/m; ref/art §5.2
  asks 512+ in hero zones).
- Body heights run +4–5 cm over the brief (sedan 1.52 vs 1.47, hatch 1.60 vs 1.55, interceptor 1.30 vs 1.25).
- Black textured plastic for lower cladding, side skirts and bumpers. Plus a charge-port flap, badge recess and
  a third brake light.
- Put the npc_trim "plate" rect to use, or remove it from atlas.py.

## Verified OK
- `tools/godot.sh check --only=res://assets/cars/npc/` → `CHECK 2 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_assets.gd` → 25 PASS / 0 FAIL (weak, see 10).
- Triangle budgets: cars 20.0–21.9 k, van 5.4 k, truck 7.2 k, bus 8.0 k, drone 1.9 k. Lengths and widths
  within ±8 cm of the brief.
- Wheel origins sit at the wheel centre (local bbox centre 0,0,0). Sedan wheelbase 2.98 m, track 1.60 m,
  tyre Ø 0.69 m. Bus tyre Ø 0.96 m.
- Light_Front/Light_Rear (cars) point ±Y correctly. Siren is on the roof (z 1.59). The drone `Spot` +Y
  points down. LightBar_Red is on the left (−X) and LightBar_Blue on the right.
- Inner dark surfaces sit behind Hood/Door_* (Inner_*). The police livery uses UV2 (`UV1` → TEXCOORD_1).
- No 警徽, 公安 or POLICE text. Fonts are Noto Sans SC.
- Ownership: per jobs/npc_cars/log.jsonl the worker wrote only blender/npc_cars/**, game/assets/cars/npc/**,
  status/npc_cars.md and tmp/npc (deleted). All .py files ≤ 400 lines (max 392). The GDScript test is
  statically typed and `extends Node`.

## Evidence
- Contract and stats: `tools/blender.sh preview game/assets/cars/npc/sedan_ev.glb ../review/npc_cars/sedan_ev`
  → objects=37 tris=21208 size 2.14×4.85×1.52, no UNTEXTURED flag, but `SH_car_paint_npc.001` and
  `NPC_cabin_liner.001` are duplicates. Sheets: captures/review/npc_cars/sedan_ev_studio.jpg and _night.jpg
  (no lamp glow anywhere).
- Geometry: tmp/review/npc_cars/inspect.py (Blender) printed `Lamp_F lo=(-0.52 -2.24 0.88) hi=(0.52 -2.20
  0.89) polys=2 avg_n=(0.00 -0.42 -0.91) uv=[]`, `Bumper_F lo y 2.16`, `Plate ... avg_n=(0.00 -0.35 0.94)
  uv=[]`, `Glass ... uv=[]`. inspect2.py: bus wheels Wheel_FL/FR/ML/MR/RRL/RRR (3 axles).
- UVs: tmp/review/npc_cars/nouv.py lists every textured primitive without TEXCOORD (see item 2). The GLB
  JSON shows `"texCoord": -1` on plate, lamp, glass, seat and dash materials.
- Colours: the police_patrol glb shows `NPC_lightbar_red emis [1, 0.09, 0.12]`, `blue [0.16, 0.36, 1]`, and
  taxi base `[0.12, 0.55, 0.54]`.
- Draw calls: 42–47 primitives per car (python glb count). 30 MB in game/assets/cars/npc/.
- Godot (my scratch scene tmp/review/npc_cars/review_npc.tscn: real environment.tscn, MaterialLibrary.apply,
  §4.7 colours) gave captures/review/npc_cars/r1_c5_taxi, r1_c5_patrol_rear, r1_c5_sedan_side, r1_c12_big,
  r1_c20_row and r1_c100 .jpg (sheets: sheet_godot_close.jpg, sheet_godot_far.jpg). At 5 m: black X-capped
  fascias, no lit lamps. At 20 m: unlit boxes, only the police bars glow. At 100 m: unreadable.
  `screenshot_stats.py r1_c20_row.jpg` → SAT 0.278 % (FAIL), P95 0.387 (FAIL).
- Worker preview: captures/review/npc_cars/r1_preview_t2_0.jpg (fleet seen from below) and
  r1_preview_eye.jpg (cars under the ground, big vehicles floating at 9 m).
- Reference comparison: captures/review/npc_cars/ref_compare.jpg (taxi_roewe_ei5_2020 / police_vw_patrol_2011 /
  bus_yutong_e10_2018 vs our taxi / police_patrol / bus). The refs have real proportions, dark glass, lit
  lamps, a silver taxi skirt and a 2-axle bus. Ours are boxes with mirrored text.
- Texture sheet: captures/review/npc_cars/textures_sheet.jpg (flat livery, white-on-flat-green plates,
  grey taxi roof sign).
- Lead notes 1–4: all four unmet (items 1, 4, 5, 11).

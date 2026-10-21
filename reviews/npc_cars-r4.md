# npc_cars review round 4 — VERDICT: FAIL

## Scores (0-10): function 5.0, visual 4.0, code 5.0
Round 4 fixed the biggest r3 problem. All 8 cars now come from the lead's `lib/car_body.py`, and the lead's spec
values are copied exactly. As a result:
- the bodies are smooth;
- the window line (DLO) is clean;
- the roofs are crowned;
- the police cars read as police from 6 to 50 m in Godot;
- the right-side wheels are real 5-twin-spoke alloys.

The fleet is still far from "贴图纹理什么都要细化":
- **Every left-side wheel is built inside out.** The barrel and the black brake disc sit outboard of the tyre, so the
  wheel shows as a black hole or a "tin can" in Godot. China drives on the right, so this is the side the player passes.
- **Every car has two UNTEXTURED materials.** This fails the brief's acceptance.
- **The intake, fog lamps and diffuser are buried in the bumper shells.**
- **The taxi roof sign is mirrored.**
- **The livery smears across the hood, deck and nose.**
- **Dark triangles show where the doors overlap the arches.**
- **The fronts are identical slabs.**
- **The bus, van and truck are still boxes.**

False or unverified claims in result.md/status:
- "the brake disc (#5B5D61)": since the worker's 02:07 UTC edit it uses black `NPC_trim`.
- "`embedded_image_handling=1` (embed as WebP), so no new copies are written": 1 is *Extract Textures*, and 134 copies exist.
- "no UNTEXTURED": `preview` was never run in round 4.
- "lineup in the §4.7 traffic mix with a 1.75 m figure": every car is white and no figure is visible.

Lead notes:
- **LEAD-NPCBODY**
  - 1: PASS.
  - 2: PASS.
  - 3 (wheels): FAIL (items 1, 2).
  - 4 (fascias): FAIL (item 3).
  - 5 (box vehicles): partial. The bus bevel, 1.0 m wheels, 1.4 m pillars, sign aspect and bumpers are OK; the bus front
    cap and the van/truck cabs are not (item 11).
  - Blender lineup: FAIL (item 9). Godot lineup: OK.
- **IMPORT-CHURN**
  - (1): partial (item 8).
  - (2): FAIL (item 7).
  - (3): FAIL (item 7).
  - (4): PASS.
- **N-ART5 / notes 1–4**
  - The body items are solved by the generator.
  - Note 1: partial (hatch and robotaxi identity, door/arch triangles; items 6, 10).
  - Note 2: PASS.
  - Note 3: FAIL (item 11).
  - Note 4: FAIL in Blender (item 9), OK in Godot.

## MUST-FIX
1. **Left-side wheels are inside out on all 11 wheeled models (LEAD-NPCBODY 3).**
   - Evidence (sedan_ev.glb, local metres):
     - The tyre spans x −0.117…0.117.
     - Wheel_FR rim: x −0.031…0.108 (correct).
     - Wheel_FL/RL rim: x −0.242…−0.102, and the brake disc + caliper (NPC_trim) at −0.188…−0.133. Both sit
       **12.5 cm outside the tyre face**.
     - Bus Wheel_FL rim at x −1.33, against a body half-width of 1.275.
   - Godot shows it plainly. `review_npc_cars_r4b_w_left.jpg` is a silver tube with 10 notches around a black disc (the
     disc sits in front of the spokes). `_w_right.jpg` is a proper alloy. In `review_npc_cars_r4_c5_sedan.jpg` the left
     wheels look like tin cans.
   - Cause: `wheels.py:116/119/123/126/134/135` always offsets toward −X (`face_x - …`). That is only right when
     face = +1. The worker's Blender previews only show the right flank, so it was never seen.
   - Fix: build the rim and brake for face = +1 and mirror the bmesh for the left wheels (x·−1 plus
     `bmesh.ops.reverse_faces`), or multiply every inward offset by `face`.
   - Test: for every Wheel_*, all rim/brake vertices satisfy |x| ≤ ww/2 + 2 mm, and the FL/FR meshes mirror each other
     within 1 mm.
   - Verify: Godot close shots of both flanks show 5 twin spokes and a grey disc behind them.
2. **UNTEXTURED and off-spec wheel and trim materials (brief acceptance; ART §5; lead 3).**
   - `tools/blender.sh preview` flags:
     - `NPC_rim  images=[] procedural=[]  <-- UNTEXTURED` on all 11 wheeled models;
     - `NPC_gloss_black … <-- UNTEXTURED` on all 8 cars.
   - Rim:
     - Today it is M 0.35, R 0.32 with no maps. The lead asked for #B9BDC3, metallic 1, rough 0.25.
     - Add a 1024² machined/brushed set: circular-brush normal, roughness 0.18–0.35 breakup, darker pockets.
     - Keep metallic 1. If it reads too dark at night, fix that with the environment or reflection probes, not with
       metallic 0.35.
   - Brake: `wheels.py:175` uses `mats["trim"]`. Use `mats["brake"]` (NPC_brake #5B5D61, rough 0.4) with a
     radial-scratch normal, and give the caliper its own colour.
   - NPC_gloss_black (reflectors, mirror caps, pillars): add an orange-peel normal and roughness breakup
     (npc_paint_detail, 0.25 m tiles).
   - Tyre: albedo #141619 (0.007 linear) is below the dossier §4.8 floor of **#2A2A2A**. Add sidewall rough 0.75 and a
     0.55 "tyre-shine" ring.
   - Test: `test_npc_materials.gd` must FAIL any surface whose material has no texture at all
     (`_surfaces_without_uv` skips them today).
3. **Fascia parts are buried in the bumpers; lamps tear (LEAD-NPCBODY 4).**
   - Where the parts sit (`details.build_bumpers` :131-142):
     - Bumper_F is a paint shell, 3 mm proud, z_f+0.01…+0.27, |x| ≤ 0.42 W.
     - The Intake (z_f+0.03…0.115, 1 mm proud) and the FogLamps (|x| 0.335–0.425 W) lie inside it.
     - So does the Diffuser inside Bumper_R.
   - Measured on the sedan at x≈0: intake front z −2.4167 vs bumper −2.4151. They are 1.6 mm apart and z-fight.
   - Result:
     - No black intake on any front (`v4_fronts.jpg`, `r4_*_studio_front.jpg`).
     - The fog lamps show as white L-shaped shards at the lower corners.
     - No diffuser in any rear view.
   - The headlamp reflector is `proud=-0.018` (details.py:49): 18 mm under the skin, so it is invisible. The "unit" is
     only a flat emissive strip.
   - hatch_ev and robotaxi: the DRL bar and Lamp_H break into fragments (top row of `v4_fronts.jpg`). 1–2 mm proud at
     5–10 cm sample spacing is less than the chord sag of the nose.
   - Fix:
     - Build Bumper_F/R as a frame with real openings, or ray-cast the intake, fogs and diffuser against the *bumper*
       and stand them 4–6 mm proud of it.
     - Lamps: sample every ≤ 2 cm, 4 mm proud.
     - Headlamp: a visible black housing 8 mm larger than the LED strip, with the strip 2 mm in front of it.
   - Verify (front/rear orthographic):
     - a black honeycomb intake ≥ 0.9 m wide;
     - two round fog lamps;
     - two headlamp housings;
     - a black diffuser at the rear;
     - no body pixels inside any lamp outline.
4. **Taxi roof sign 申城出租 is mirrored on the front AND the rear face (ART §7).**
   - Evidence: bottom row of `v4_godot_zoom2.jpg`, and `review_npc_cars_r4b_taxi_front.jpg` in Godot.
   - Cause: `extras.py:98 planar_uv(face, axis=1, flip=(sy < 0))` has the flips inverted. A viewer of the +Y face sees +X
     on their left.
   - Fix: `flip=(sy > 0)`.
   - Test: add a RoofSignFace orientation test like "the front plate is not mirrored".
5. **The livery smears over the hood, deck, nose and tail (ART §8: no stretched textures).**
   - Cause: `body.add_livery_uv` (body.py:230-249) is a pure side projection, u from y and v from z, applied to every
     paint face. It also flips u **per vertex** when x < 0.
   - Results:
     - A yellow band across the patrol hood (`v4_close.jpg`).
     - A beige wash over the interceptor deck (`v4_cars_rear34.jpg`).
     - A smeared white glyph on the interceptor nose (`v4_fronts.jpg`).
     - Faces that cross x = 0 span the whole sheet.
   - Fix: pick the flank per FACE (face-centre x). Send faces with |n.x| < 0.5 to a transparent texel, or to a deliberate
     hood/roof design area.
   - Verify: in front34/rear34 and Godot c5_patrol, the hood, deck, nose and tail are clean white, and the band stops at
     the flank edge.
6. **Door shells overlap the wheel arches, leaving dark triangles on every flank (lead note 1).**
   - Sedan: the front door spans y 0.10…1.16, but the arch's rear edge is at ≈1.10 at sill height (axle 1.49, wr 0.347,
     ARCH_MARGIN 0.045). The shell's corner drops into the well and shows its dark back.
   - Seen as black triangles above the front arches in `r4_*_studio_side.jpg` and Godot w_left/w_right.
   - Robotaxi: the sliding door runs to 1.30, 0.30 m into the arch, giving two large triangles.
   - Fix: clip the door outline to the arch circle (r = wr + ARCH_MARGIN + 0.03).
   - Test: no Door_* vertex within that radius of an axle centre in the y-z plane.
7. **IMPORT-CHURN (2)+(3) (lead, mandatory) are still violated.**
   - Extracted copies in `game/assets/cars/npc/`:
     - 134 Godot-extracted per-model copies (`<model>_npc_*.jpg/png/webp`, **7.0 MB**) plus 134 `.import` files,
       dated 10:03–10:04 today.
     - The folder is **31 MB** (r3 target ≤ 12 MB).
     - `gltf/embedded_image_handling=1` means *Extract Textures* in Godot 4. Every model also loads its own copy of every
       sheet (12× VRAM).
   - Fix (r3 8(3)):
     - Set `embedded_image_handling=0` in the 12 owned `*.glb.import` files.
     - Map the NPC_* materials through `_subresources` to shared `materials/*.tres` that use `textures/*.png`.
       Fallback: 2 (Basis Universal).
     - Delete the copies.
   - Verify: after `tools/godot.sh import`, `ls game/assets/cars/npc | grep -c '_npc_'` → 0 and `du -sh` ≤ 12 MB.
   - Dead sheets:
     - `npc_wheel.png` (1024×2048, 2.15 MB) and `npc_wheel_nrm.png` are generated (gen_textures.py:393-394) but no
       material uses them. Delete the sheets and their generator code.
     - `livery_taxi.png` is still 2048×1024 for a skirt strip: make it 1024×512.
8. **IMPORT-CHURN (1): the 8 cars are rewritten on every rebuild.** The worker lists this as a known issue.
   - It can be fixed in the unit, without core: after `car_body.build`, round the Body/ArchLiners positions, then sort
     their verts and faces by the rounded position (bmesh sort / `mesh.sort_elements`), before UVs and normals.
   - Verify: a second `build.py` run prints "unchanged" for all 12 models. Paste the output into status.
9. **Acceptance evidence is incomplete or stale.**
   - No `tools/blender.sh preview` was run in round 4 (job log), but the brief requires studio + night sheets and stats
     per model.
   - `captures/blender/lineup_side.jpg` (10:03) predates the final .glb files (10:25) and is only 1500×258.
   - The lineup's 1.75 m figure is not visible.
   - Every car in it is white: `lineup._tint` (the §4.7 paint mix) does not take effect.
   - The truck's cab is hidden against the bus.
   - Fix:
     - Render at ≥ 3600 px after the final build, with the figure visible beside the sedan.
     - Paint the cars white / silver / blue / black / grey, with 1.4 m gaps.
     - Look at the image before claiming it.
10. **Silhouette and front identity (r3 item 3 leftovers, lead note 1).**
    - hatch_ev is a notchback. deck_y −1.38 against a tail at −1.975 leaves a 0.6 m boot behind the D pillar
      (`r4_hatch_ev_studio_side.jpg`).
      - Make the tailgate ≤ 15° from vertical with no deck.
      - Give it round DRL pods ⌀ 0.16 m.
    - All 8 fronts are the same slab: one DRL bar, two strips and the plate (`v4_fronts.jpg`). Give each type its own
      lamp graphic and lower fascia:
      - SUV / police SUV: a tall black grille block;
      - interceptor: slit lamps and big intakes;
      - robotaxi: a light band and sensor windows.
    - robotaxi: the brief says a "white/black" pod. Make the glass house, pillars and roof black gloss over the white
      body (r3 item 3). Today the roof rails are white and the car reads as an open cage (Godot taxi_front).
11. **Bus / van / truck still read as boxes (lead note 3 mandatory; r3 item 5c).**
    - Bus front:
      - It is flat, with only a 0.14 m bevel.
      - Lead note 3 asks for a rounded front cap (plan radius ≥ 0.45 m) and a wrap windscreen 2.3 × 1.8 m raked 8–10°
        (`bus_yutong_e10_2018.jpg`, `v4_ref_compare.jpg`).
    - Bus doors: Door_FR and Door_RR are single glass quads (2 tris). Add frames, rubbers, a centre seal and handrails.
      All the bus glass together is 30 tris.
    - Bus glass:
      - The bus `SH_glass_tinted` fallback exports OPAQUE.
      - Its 256² grime stretches over 1.4 × 1.0 m panes, so the panes show black "wood grain"
        (`r4_bus_studio_close_front34.jpg`).
      - Fix: BLEND 0.55 and metre UVs.
    - Bus/van/truck wheels are the car alloy. r3 item 4 asked for steel 22.5" wheels: #9A9EA3, 10 studs, hub cap,
      8 hand holes.
    - Van/truck cabs have sharp box edges. Add a bevel ≥ 0.08 m, wrapped screen corners, and grille/bumper lamp clusters.
12. **Texture detail (the user: 贴图纹理什么都要细化).**
    - Black plastic: `npc_black_plastic.png` at 1:1 is still soft cloud noise with no 0.2–0.4 mm grain (`v4_tex.jpg`,
      r3 10a). Add a fine stipple with a matching normal.
    - Police liveries: alpha is 0 everywhere outside the band, so there are 0 speckle or drip pixels on the white body
      (r3 10d).
    - NPC_roof_number: base colour only. Add a normal and roughness (r3 10e).
    - Interior:
      - The seats are stacked boxes, plus a light-grey CabinLiner board that reads as grey-box at 5 m through the
        screen (`r4_*_close_front34.jpg`).
      - Shape the seats: cushion, bolstered back and headrest, 300–500 tris each.
      - Darken the liner to fabric #1A1C20.
      - Close the wheel houses: the robotaxi shows a tyre inside its cabin.
13. **Code rules.**
    - `gen_textures.py` is 423 lines (> 400). Split it.
    - Dead code: `wheels.build_wheel`, `mats["brake"]`/NPC_brake, `mats["paint_plain"]`/NPC_paint_plain,
      `atlas.TRIM["brake"]`, and the wheel sheets from item 7.
    - The magic numbers flagged in r3 11b are still inline:
      - details.py:47/53 `nose - 0.215`;
      - details.py:71 `tail - 0.225`;
      - details.py:78 `tail - 0.30`;
      - details.py:110 `+ 0.155`;
      - extras.py:54-57 `ry = -0.95`, `±0.32/±0.16`;
      - boxdetail.py:98 `0.44, 0.14`.
    - Stale cache: `build._prepare_images` reuses `tmp/npc_cars/tex/<sheet>.jpg` whenever it exists, so an edited sheet
      never reaches the .glb. Re-encode when the source PNG is newer or its bytes differ.
    - Add the tests from items 1, 2, 4 and 6.

## SHOULD-FIX
- **Draw calls:**
  - Each car has 33–42 surfaces (r3: 21). Each wheel is 3 surfaces, so 12 per car.
  - Put tyre, rim and disc on one wheel atlas material, and merge lamp_front, lamp_rear and lamp_brake into one
    emissive atlas material.
  - Target ≤ 24 surfaces per traffic car.
- **Bumper wrap:** Bumper_F spans x ±0.80 of ±0.95. Wrap it ≥ 0.25 m round the corners (r3).
- **Robotaxi glass:** in Godot (rt_side) its wrapped windscreen reads as a pale trapezoid side-on. Add a ≥ 6 cm black
  frit band along every glass edge.
- **Livery blue:** ART §3 gives police livery blue #1E4FB8. The sheet uses the dossier navy (mean RGB 28,43,77 ≈
  #1B2A4E). Ask the lead which one wins. The pinstripe is #F5C400 (OK).
- **Drone node names:** `DroneLivery` / `DroneLivery.001` → `DroneLivery_L` / `DroneLivery_R`.
- **Tail bars:** re-check that the Godot tail bars have r ≥ 2.5·g on the lit pixels (r3 salmon note).

## Verified OK
- **Generator and spec:**
  - All 8 cars call `car_body.build(...)`; `body_loft.py` and `profile.py` are deleted.
  - spec.py carries the lead's values exactly: sedan/taxi/patrol, hatch, and interceptor.
  - The r3 facets, stepped "lightning-bolt" glass and limo roofs are gone: the bodies are smooth and the DLO is clean.
- **Right-side wheels:** real 5 twin-spoke alloys with depth and a visible disc (Godot `review_npc_cars_r4b_w_right.jpg`).
- **Contract nodes** are present in every model:
  - Body, Glass, Wheel_*, Bumper_F/R, Hood, Door_*, Lamp_F/R, Light_Front/Rear;
  - LightBar + LightBar_Red/Blue (E12) + Siren on the police cars;
  - Spot on the drone.
- **Plates:**
  - Front plates are not mirrored (沪A·D0R421 / D2M664 / D71345 / D00111 in `v4_fronts.jpg`).
  - The van and truck carry blue 沪B plates.
- **Bus:**
  - The route signs are legible: 申城公交 71路 front, 71 side, plus the rear sign.
  - The bumpers sit low (test).
  - 1.0 m wheels, 1.4 m pillars, doors on the kerb side (+X).
  - The body is 12.0 × 2.55 m.
- **Lamps:**
  - Front: white E6 from the trim LED rect. Rear: red E4, with brake segments.
  - Every car's DRL and tail bars glow in the night previews.
- **Glass:** the car glass exports as BLEND alpha 0.55 (r3 should-fix) and reads dark in Godot.
- **Budgets:**
  - Tris: cars 19.4–23.4 k, van 8.0 k, truck 9.6 k, bus 9.6 k, drone 1.5 k.
  - Lengths now on spec (sedan 4.85, SUV 4.74, hatch 3.95, robotaxi 4.19).
  - Drone rotors at ±0.81 m (Ø 1.62).
- **Police read as police at 6–50 m:** navy band, #F5C400 pinstripe, 天巡 SKYPOL, 沪-07, and the light bar (Godot
  c5_patrol, c20_row, c50).
- **Taxi:** teal in Godot, the 申城出租 door decal is legible, the skirt material is its own, the roof box is 0.95 m wide.
- **Import churn:**
  - Byte-conditional writes for the sheets and the .glb files (`texlib.save`, `build.export_glb` / `_same_bytes`).
  - Texture count and size are reported (27 sheets / 5.0 MB).
  - The export goes through `lib/export.py`.
- **Ownership:**
  - Every round-4 Write/Edit target is under `blender/npc_cars/**`, `game/assets/cars/npc/**`, `status/npc_cars.md` or
    `tmp/npc_cars/`.
  - Scratch was deleted, apart from the export cache `tmp/npc_cars/tex`.
- **Performance:** 109–149 fps in the review scene (15 vehicles + drone), `CAPTURE errors=0 warnings=0`.

## Evidence
- **Godot check:** `tools/godot.sh check --only=res://assets/cars/npc/` →
  `CHECK 4 files, 0 failed, 0 engine errors, 0 warnings`.
- **Godot tests:**
  - `tools/godot.sh test res://assets/cars/npc/tests/test_npc_nodes.gd` → 84 PASS, rc=0.
  - `tools/godot.sh test res://assets/cars/npc/tests/test_npc_materials.gd` → 14 PASS, rc=0.
  - Logs: `tmp/review/npc_cars/r4/test_*.log`.
- **Unit checker:** `python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb` → `total problems: 0`. It does
  not catch items 1 to 6.
- **Previews:**
  - Command: `tools/blender.sh preview game/assets/cars/npc/<m>.glb ../review/npc_cars/r4_<m> --views
    front34,rear34,side,front,rear,close_front34 --light both` for all 12 models. Logs:
    `tmp/review/npc_cars/r4/preview_<m>.log`.
  - Sedan: `PREVIEW objects=18 tris=21906 size(m) x=2.08 y=4.85 z=1.46`, with `NPC_gloss_black` and `NPC_rim`
    `<-- UNTEXTURED`.
  - Bus: `tris=9554 size 3.10×12.06×3.20`, with `NPC_rim <-- UNTEXTURED`.
  - The drone has no untextured material.
- **Reviewer sheets** (`captures/review/npc_cars/`):
  - `v4_cars_front34.jpg`, `v4_cars_rear34.jpg`, `v4_cars_side.jpg`: the 8 cars, studio.
  - `v4_close.jpg`: close front34 — box interior, door/arch triangles, hood livery smear, robotaxi tyre in the cabin.
  - `v4_fronts.jpg`: identical fronts, torn lamps on hatch and robotaxi, fog-lamp shards, no intake.
  - `v4_big.jpg`: bus/van/truck/drone, the streaky glass.
  - `v4_night_nocrop.jpg`: night previews.
  - `v4_tex.jpg`: texture sheets.
  - `v4_taxisign.jpg`: the mirrored roof sign.
  - `v4_ref_compare.jpg`: against `taxi_roewe_ei5_2020.jpg`, `police_vw_patrol_2011.jpg` and
    `bus_yutong_e10_2018.jpg`.
  - `v4_worker_lineup_side.jpg`: the worker's lineup — no figure, all white.
- **Godot captures:**
  - Scene `tmp/review/npc_cars/r4/review_npc_r4.tscn`: the real environment, MaterialLibrary.apply, and §4.7 paints via
    `base_color_override`.
  - Run 1: `tools/godot.sh shot --scene=…/review_npc_r4.tscn --out=review_npc_cars_r4 --cams=…` → 10 shots: c5_sedan,
    c5_patrol, c5_rear, c6_side, c6_top, c9_bus, c20_row, c10_side_row, c50, c100.
  - Run 2: `--out=review_npc_cars_r4b` → w_left, w_right, rt_side, taxi_front.
  - All files are under `captures/review/npc_cars/review_npc_cars_r4*_*.jpg`. Sheets: `v4_godot_close_nocrop.jpg`,
    `v4_godot_far_nocrop.jpg`, `v4_godot_zoom.jpg`, `v4_godot_zoom2.jpg`.
- **glTF audits** (`tmp/review/npc_cars/r4/rimfaces.py` plus inline numpy over `glb3.load`):
  - Wheel_FL rim x −0.242…−0.102 vs tyre ±0.117; bus Wheel_FL rim −1.33.
  - Materials: NPC_rim no textures, M 0.35 R 0.32. NPC_tyre base 0.007 linear. Bus SH_glass_tinted OPAQUE.
  - Bus Door_FR/RR = 2 tris each; bus Glass 30 tris.
  - Intake front z −2.4167 vs Bumper_F −2.4151.
  - Livery outside the band: alpha 0 everywhere. Navy mean (28,43,77). Yellow (245,196,0).
- **Code and files:**
  - `wc -l`: gen_textures.py 423.
  - `grep`: `wheels.py:175 mats["trim"]` for the brake; `extras.py:98 flip=(sy < 0)`; `palette.py:68 NPC_brake` and
    `:48 NPC_paint_plain` unused; `build_wheel` unused.
  - `ls game/assets/cars/npc`: 134 `<model>_npc_*` copies (7.0 MB); the folder is 31 MB; `*.glb.import`
    `gltf/embedded_image_handling=1`.
- **Job log** (`tmp/review/npc_cars/r4/logpaths.py jobs/npc_cars/log.jsonl 2026-10-20T01:05`):
  - All writes are inside owned paths.
  - No `blender.sh preview` was run in round 4.
  - At 02:07 UTC: "the brake disc uses the shared trim material".
- **Feedback:** none sent. This was the last round.

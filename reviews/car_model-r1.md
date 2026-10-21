# car_model review round 1 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 5.0**: the glb loads, the 41 contract names, empties, pivots and wing poses are right. But there are 6 real bugs: the wing slat sits under the
  floor, both left arch lips were built on the right side, `Brake_Light` is missing, the plate texture repeats 50×, the body UVs overflow,
  and every normal map is blank.
- **visual 3.0**: it does not read as the reveal car (photos 03/09/13). The shell looks triangulated, the glass reads as see-through orange
  plastic, there is a black wall at the cowl, the front is a stack of plates, the rear fan box looks like a speaker box, the plate cannot be read
  and the textures are blank.
- **code 5.0**: the split into modules is clean. But the texture generator fails silently, dossier numbers are retyped, the atlas constants are
  duplicated and disagree with each other, and the test cannot catch any of the bugs above.

**Read `reviews/car_model-lead.md` first.** Your job log has 0 references to it, so none of its 6 mandatory notes were addressed.
All 6 are MUST-FIX below (#7–#11). Work in this order: #1–#6 (cheap bugs), then #7–#11 (lead notes 1–6), then #12–#16.

## MUST-FIX

1. **Every normal map is blank — the "refined textures" do not exist.** In `blender/car/gen_textures.py`, `height_to_normal(h, 1.0)` takes heights
   in metres, but `np.gradient` measures slope per pixel. The slope comes out around 1e-3, so every encoded normal stays at (127,127,255)±1.
   Measured on the shipped PNGs:
   - `body_panel_nor.png` (4096²): 2 unique values, 0.034 % of pixels differ by 1 level.
   - `tyre_nor.png`: 2 unique values.
   - `carbon_nor`, `copv_nor`, `glass_nor`, `gold_nor`, `titanium_nor`, `seat_weave_nor`: **1 unique value**.
   - `blacktrim_nor`: 2 unique values.

   In `tyre_map()`, `height *= mask` (mask = v > 0.72 only) also **wipes out the 2 grooves and 64 sipes**.

   **Do:**
   - Change the signature to `height_to_normal(h_m, px_per_m)` and multiply the gradients by the texel density of each map.
     Body 930; tyre ≈ 2048/(π·0.685) ≈ 950; carbon 1024 px / 0.1 m = 10240; others = map px / tile metres.
   - Apply the lettering mask to the lettering only.
   - Blur `grain_map` noise (σ 1–2 px, 2 octaves) so it does not sparkle.
   - Add a gate in `save()` for every `*_nor.png`: assert per-channel std ≥ 3 levels and ≥ 5 % of pixels ≠ 127/128.
     For the body gap map, require ≥ 0.3 %. If the check fails, the build must fail.

   **Verify:** paste a printout of std/unique counts per map into `jobs/.../result`. Close-ups must show tyre grooves and lettering, carbon
   twill on the diffuser, and gap lines catching light.

2. **Plate unreadable.** `details.py:61` creates `M_Plate` with `tile=0.02`. The Mapping scale becomes 50, so 沪A·D2049R is tiled 50× into
   a fine grid. It shows as a mint panel in Blender and a cyan grid in Godot (`bl_rear_valance.jpg`, `g_nozzles.jpg`).
   **Do:** give the base map `tile=1.0` on the plate's 0..1 UV. Put the grain normal on its own UV or leave it out.
   **Verify:** in a render from 1.2 m behind at Z 0.5, the full plate text is legible.

3. **Left arch lips are missing; the right side has double lips.** `body._surface_x()` always casts from x = +3 toward −X, so the
   `sign=-1` lips land on the right flank:
   - `ArchLip_F_L` bbox x 0.724…0.934
   - `ArchLip_R_L` bbox x 0.810…0.975

   The left arches have no lip (`bl_wheel_RL_left.jpg`), and the right lips overlap each other and z-fight.
   **Do:** cast from `(3.0*sign, y, z)` with direction `(-sign, 0, 0)`.
   **Verify:** see the test in #15. Every `*_L` mesh centre must have x < 0 and every `*_R` centre x > 0.

4. **`Wing_Slat` sits at the world origin, 16 mm below the ground.** Its bbox is x ±0.70, y −0.021…−0.016, z −0.016…+0.016. This is
   also why the preview reports height **1.16** instead of 1.145. `panels.py` builds the slat in wing-local coordinates but parents it with
   `paths.parent_to` (which keeps the world transform). **Do:** use `paths.parent_local`, as the end plates and struts already do.
   **Verify:** the preview prints `z=1.15`, and every Wing child lies within 0.4 m of the Wing origin.

5. **The wing struts poke through the stowed deck.** `Wing_Strut_L/R` reach z 0.870–0.980 at x ±0.44, y −1.86…−1.76. The deck skin is
   about 0.913–0.93, so two posts 5–7 cm tall show in every side and rear view: `r1_studio_side`, `r1_studio_close_rear`, and the notch at the
   tail in `captures/car_model/overlay_side.jpg`.
   **Do:** when stowed, the struts must sit fully under the deck skin (z_max ≤ skin − 5 mm). Either fold them inside, or give them zero
   height and store their deployed geometry or transform in the pose data.
   **Verify:** the side ortho silhouette has no notch, and the side overlay maximum error near the tail is ≤ 2 cm.

6. **Contract names.** CONTRACTS §6 lists a `Brake_Light` mesh; it does not exist. The brief names the nozzle meshes `NozzleMesh_R1…R4` and
   `NozzleMesh_P1…P6`; you shipped `NozzleMesh_Nozzle_R1`.
   **Do:**
   - Add `Brake_Light`: an inner strip of the rear bar, centre 0.9 m, with its own material `M_BrakeLight` (#FF1A2A, emission 0 by
     default, raised at runtime). Document it in the README.
   - Rename the nozzle meshes.
   - Add both to `NODES` in the test.
7. **Lead note 1: the shell looks polygonal/triangulated (NOT fixed).** `Body` has 16 408 tris; **11 612 (71 %) are < 1 mm² and 13 733 (84 %)
   are < 10 mm²** (median 0.41 mm²). These are slivers from `common.bevel(width=0.004, segments=4)` being run *after* the boolean cuts
   (`build_all.py:40`). On top of that, `mesh_utils.triangulate_keep_normals` writes per-face custom normals, there are 0 sharp edges
   (0/40 611), and the loft is not resampled. After a merge there are also 13 edges shared by more than 2 faces and 13 degenerate faces.
   **Do exactly what lead note 1 says:**
   - Resample the loft along Y every ≤ 0.12 m by linear interpolation between the JSON sections.
   - Mark every K-row edge sharp.
   - Bevel 4 mm × **2** segments *before* the booleans, or bevel only the K-row creases with bevel weights.
   - Use smooth shading + a Weighted Normal modifier (face area, keep sharp) instead of the custom-normal triangulation.
   - Assert: no face < 1 mm² and no non-manifold edges on Body.

   Removing the slivers drops the total to about 50k tris. Get back into the 60k–150k range with *real* resolution (loft rows, bevels,
   detail), never with slivers.
   **Verify:** the sliver printout, plus studio `close_front34` and `side` renders with no diagonal shading breaks across the facets.

8. **Lead note 2: the glass is still transparent orange (NOT fixed).** `SH_glass_gold` is still base #5A3F2A, metallic 0.3,
   roughness 0.03, alpha 0.85, coat 0. Through it you can see the cockpit, the COPV tank and the floor, which make the "dark triangles"
   (`r1_studio_close_rear`, `bl_glass_34`). The glass sheet itself is consistent (0 flipped edges after a merge); the triangles come from
   what is behind it.
   **Do:**
   - Set base #3A2718, metallic 0.6, roughness 0.04, alpha 0.95 (BLENDED), coat 1.0. Keep the name `SH_glass_gold`.
   - Make the cabin under the canopy tidy and dark (#12141A). Interior faces must not stand right under the glass.
   - Per dossier §7.1, add the black frit band (30 mm with a 3 mm dot fade) around the windshield and backlight, as a texture.

   **Verify:** in studio front34 and rear34, the canopy reads as one dark bronze-gold glossy shape like
   `03_front_3q_low.jpg` and `12_top_view_drone.jpg`.

9. **Lead note 3: black slot at the cowl (NOT fixed).** Rays from the front camera at the windshield base first hit
   **`Body[M_InnerDark]` at y = 1.60–1.61, z 0.72–0.80**. This is the dark rear wall of the hood cut, standing about 8 cm above the
   hood/glass joint (`r1_studio_front`, `bl_front_corner`, `bl_left_34`).
   **Do:** clip the hood cut so that no `M_InnerDark` face rises above the outer skin. Only the 4 mm line at Y +1.80 and the cowl line at
   +1.61 may show.
   **Verify:** the front and front34 renders show no dark rectangle; a ray probe at y 1.58–1.62 hits glass or paint first.

10. **Lead note 4: front (NOT fixed).** The lower fascia is a stack of separate plates at different depths:
    - `Bumper_F` face at y 2.26;
    - `Intake_Front` + grille recessed 13 cm (y 2.149–2.168);
    - `Splitter`, a vertical carbon plate z 0.112–0.172 that hangs below the bumper.

    It reads like venetian blinds (`bl_front_corner.jpg` vs `03_front_3q_low.jpg`). The headlamp jewels are tiny black boxes, 30×70×38 mm.
    **Do:**
    - Make one smooth black fascia surface that follows the nose V.
    - Make the intake a shallow slot (≤ 30 mm deep) with a flush grille.
    - Make the splitter a thin integrated lip at Z 0.12 reaching Y +2.31. Nothing may go below z 0.12.
    - Build each jewel as 3 bright LED cells (emission 8) inside a black triangular pocket under `HeadlampPanel_L/R` (dossier §7.1),
      clearly visible in the studio front34.

11. **Lead notes 5 + 6: rear (NOT fixed).**
    a) **Light bar.**
       - In the lightbar texture the lens is (48,6,10), only about 3 % of the core's emission, so only the 6 mm core glows.
       - Blender night rear: 0 pixels with R > 200 and G < 90.
       - Godot chase cam at 6.6 m (`g_chase`): a 1–2 px desaturated line, peak RGB 241/160/169.
       - At 20 m: only 8 red pixels.
       - The bar spans x ±0.808, but the JSON `light_bar_rear.x_half` is 0.845.

       **Do:**
       - Make the whole 14 mm lens glow at ≥ 40 % of the core, e.g. (110,10,18), with the core at (255,26,42) and strength 10–12.
       - Read the width from the JSON.
       - Remove the stray black dash at the left end of the bar (`r1_studio_close_rear`).
       - The bars must be the brightest red/white lines in the night previews (lead note 6).
    b) **Fans.** `Fan_R1..R4` (y −2.100…−2.050) sit flush with the tail in a protruding carbon box, so 4 big grilles dominate the valance.
       `bl_rear_valance.jpg` vs `09_rear_closeup_nozzles_plate.jpg` shows the difference. **Do:** recess the fans ≥ 80 mm into dark
       tunnels (Y ≥ −2.00) behind the vertical strakes, so the 4 titanium-ringed nozzles at Z 0.50 are the dominant read.
    c) **Diffuser symmetry.** The diffuser is asymmetric: bbox x −0.650…+0.780. Mirror it; strakes go at X 0, ±0.30, ±0.58.
    d) **Missing comparison.** Write the missing `captures/car_model/compare_rear.jpg`: a render from 1.2 m behind at Z 0.5, hstacked
       with photo 09.
12. **Body atlas: UVs overflow and overlap, and it was never baked (brief §Detail).** `uv_car.body_uv` places the top-rear cell at
    u = 3682 + (x+0.99)·930 px, so **u runs up to 1.345**. The texture wraps: the rear deck samples the front-hood cell, and the
    wing-edge gap line is clipped at the 4096 px border. The nose/tail cell C2 overflows the same way. The README documents A2 as u 1841…3682,
    but the code starts A2 at 3682. The left and right flanks share cell B, and under-faces share the top cells (overlaps). The brief
    asked for a Smart UV Project (2 % margin, no overlaps) and a **Cycles bake** of panel-gap AO + normal at 4096² from the bevelled mesh.
    **Do:**
    - Smart-project Body (island margin 0.02; normalise to 0..1).
    - Bake AO (Cycles, 64 samples) from the assembled car — Body plus all panels — so the real 4 mm gaps darken.
    - Bake the normal from a bevelled high-poly copy.
    - Read the gap list from JSON `panel_lines` plus the dossier §3 door cuts.

    **Verify:** print the Body UV min/max (must be within [0,1]) and the UV island overlap count (must be 0). Show a rear-deck close-up with
    exactly one wing-edge line at Y −1.745 and the door lines on **both** flanks.

13. **Material detail per brief and ART §5 is missing.** No material has a roughness map. 21 of 30 materials carry only a constant normal PNG,
    which hides them from the UNTEXTURED check: M_WheelWhite, M_WheelDark, M_Microsuede, M_RedAccent, M_AmberMarker, M_CabinBlack and others
    all reuse the flat `blacktrim_nor`. Build these with real, measurable texture:
    - **paint:** roughness 0.26–0.30 noise map; 2 % value noise (keep it).
    - **black trim:** library grain normal + roughness 0.5–0.6. Fetch it with `tools/textures/fetch.py ambientcg <Plastic… id>`, as the
      brief says. Arch lips glossier (0.35); today they use the same 0.55.
    - **carbon (strakes, splitter, fan shrouds):** 2×2 twill with 4 mm tows, two tones #141416/#232327, from the ambientCG carbon set or the
      fixed generator. It must be visible at 1 m.
    - **tyres:** base-colour lettering "SKYRUSH TROFEO  295/30 R20" / "335/30 R21" at 25 % white (#D8D8D8) on #161616. Add a roughness map
      at 0.85 with a glossier ring (0.5) near the rim, plus the normal from #1.
    - **wheels:** white blades #E6E6E8 with a 1 mm chamfer highlight. Make the brushed gold #B08458 accents visible between the spokes
      (photo 13 shows gold slots along each spoke). Engrave concentric rings on the hex cap. In `bl_wheel_FR.jpg` the blade tips end in
      jagged white shards — close each blade cleanly at the rim.
    - **nozzles:** titanium #9B958E with concentric machining marks (radial anisotropy or a fine ring normal). The gold throat must grade
      #B08458 → #2A1A0E toward the 30 mm hole.
    - **brake discs:** `disc_map` draws its 12 holes in Cartesian pixels at (128±86) px, but the disc uses polar UVs. Draw them in UV space
      instead (u = i/12, v ≈ 0.8).
    - **interior:** seat weave, microsuede soft noise, COPV filament winding — all real normal maps.

    **Verify:** `tools/blender.sh preview` stats show image textures, and the #1 gate prints std > 0 for every map. Show close-ups at 1 m
    of a tyre, a wheel, a nozzle, the diffuser and the plate.

14. **COPV tank orientation (brief "Lead decisions").** It lies along **Y**: bbox x −0.09…0.33, y −1.095…−0.145. The brief says along **X**,
    behind and to the right of the driver (photo 24). `COPV_Strap_L` and `_R` are exact duplicates with the same bbox. Put the tank along X
    and place one strap near each end.

15. **The test is too weak.** `test_roadster.gd` passes with blank normal maps, a slat under the floor and no left arch lips. Add:
    - (a) every normal texture of the imported materials varies — sample 256 pixels, std > 2/255;
    - (b) every mesh AABB lies inside the car AABB, and no vertex has Godot y < −0.002;
    - (c) `_L` meshes have x < 0 and `_R` meshes x > 0;
    - (d) `Brake_Light` and `NozzleMesh_R1..P6` exist;
    - (e) the `M_Plate` texture transform scale is 1.

16. **Retyped numbers (brief: "load it in code; never retype numbers").**
    - `gen_textures.py` hardcodes `GAP_COWL_Y 1.61`, `GAP_VENT_Y 1.80` and `GAP_WING_Y −1.745`; all three are in JSON `panel_lines`.
    - `panels.py` hardcodes the wing polygon (−1.745, 0.87, −2.085, 0.95) and the strut and slat coordinates; they are in JSON
      `parts.wing`.
    - `uv_car.py` and `gen_textures.py` each define `D`, `A2_U`, `B_V` and `C_V`.

    Read every value from `paths.loft()`, and keep the atlas constants in one module.

## SHOULD-FIX
- Draw calls: 101 mesh objects with 148 material surfaces for one car. Merge static non-contract details per material (cameras, frames,
  reflectors, markers, liners, suspension) to stay under 70 surfaces. Keep contract nodes separate.
- The wheels and tyres take 38 % of the triangles (brief: 30 %). 128 segments per tyre is enough once the normal map carries the detail.
- Top overlay metric reads 59 mm against a 30 mm tolerance. Measure edge to edge at 5 stations instead of "white body" detection.
  Re-run all 3 overlays after #5 and #7.
- The plate is 2 mm proud of the tail face (y −2.092 vs −2.090). Recess it 3 mm inside a 5 mm black frame.
- Python functions over 60 lines: `materials.pbr`, `overlay_render.rear_check` (≈75), `panels.main` (≈63), `thrusters._fans` (≈69).
- `tmp/car_model/sil_*.png` are scratch files; delete them after the overlay run (lead rule).
- Report honestly. The result claimed a "4 mm panel-gap normal", "carbon twill" and "tyre lettering"; none of these exist in the pixels.
  Back each claim with a measured number or a close-up.

## Lead notes status (`reviews/car_model-lead.md`)
| note | status |
|---|---|
| 1 smooth flat panels, crisp creases | FAIL (#7) |
| 2 glass | FAIL (#8) |
| 3 hood slot | FAIL (#9) |
| 4 front lip, bar, jewels | FAIL (#10); the front bar alone is OK |
| 5 rear bar, nozzles, compare | FAIL (#11) |
| 6 emissives glow | FAIL (#11a) |
| rules: tests `extends Node` | OK |
| rules: scratch deleted | SHOULD-FIX |

## Verified OK
- Godot check: `CHECK 2 files, 0 failed, 0 engine errors, 0 warnings`.
- Godot test: all PASS lines present (41 contract names, contract materials, bbox 1.977 × 1.145 × 4.491, hub heights, wing poses).
- All 16 Empties are at the brief positions with the correct +Y direction:
  - `Nozzle_R1..R4` at (±0.12/±0.36, −2.085, 0.50), direction −Y;
  - `Nozzle_P1..P4` direction −Z; `Nozzle_P5/P6` direction ∓X;
  - `Light_Front` (0, 2.30, 0.44) +Y; `Light_Rear` (0, −2.10, 0.85) −Y;
  - `Camera_Hood`, `Seat_Driver`, `Fan_Intake`.
- Root `Roadster` Empty sits at the origin.
- Wheel origins are at the hub centres, (±0.78, 1.413, 0.343) and (±0.815, −1.413, 0.367), with rotation 0. The `Tyre_*` children touch
  z = 0.000. `Caliper_*` are separate and do not spin.
- `Door_L/R` pivot at (±0.90, 0.86, 0.66). `Wing` origin is at (0, −1.745, 0.913), with `poses` = {stowed 0, low_drag 1,
  high_downforce 15, air_brake 60}.
- All detachable panels exist, each with a #141416 inner surface.
- Rear nozzles: 80 mm OD and 34 mm deep. In the macro shot the titanium ring and gold throat read correctly.
- The front bar is 12 mm tall at Z 0.44, x ±0.70, emission 8. The rear bar has emission strength 10 and LED segments at 6.3 mm pitch.
- `plate.png` itself is correct: gradient #F4FBF6 → #48C77E, bold 沪A·D2049R. Only its mapping is broken (#2).
- COPV dimensions: Ø 0.42 × 0.95 m, #E8E8EA, with a red band.
- Side silhouette: overlay error MAE 4 mm, max 16 mm, apart from the strut notch (#5).
- Ownership: the job-log audit shows every write inside `blender/car/**`, `game/assets/cars/roadster/**`, `status/car_model.md` and
  `tmp/car_model/`. Nothing was edited outside the owned paths.
- Code layout: 19 modules, each ≤ 350 lines. The test is static-typed and `extends Node`. The preview scene runs at 251–285 fps.

## Evidence (all run by the reviewer from ~/m/skyrush)

**Commands and output:**
- `tools/blender.sh preview game/assets/cars/roadster/roadster.glb ../review/car_model/r1 --target-height 1.147 --views front34,rear34,side,front,rear,top,close_front34,close_rear`
  → `PREVIEW objects=101 tris=62930 size(m) x=1.98 y=4.49 z=1.16`. No UNTEXTURED lines, but 21 of 30 materials only carry a constant
  `*_nor` PNG.
- `tools/godot.sh check --only=res://assets/cars/roadster/` → 0 errors.
- `tools/godot.sh test res://assets/cars/roadster/tests/test_roadster.gd` → exit 0.
- `tools/godot.sh shot --scene=res://assets/cars/roadster/preview_roadster.tscn --out=review/car_model/g --cams=...` with cams front34low,
  rear_valance, wheel_fl, nozzles, chase, far20, side and top → `CAPTURE errors=0`.
- Texture audit (PIL): the normal-map unique-value counts quoted in #1.
- Inspection scripts in `tmp/review/car_model/`:
  - `inspect.py`: per-object tris and bbox, empties, origins. Wheels plus tyres are 24 112 tris (38.3 %).
  - `inspect_mats.py`: material values, UV ranges (Body u up to 1.345), and the slat at world (0,0,0).
  - `shell_check.py`, `sliver_check.py`: Body has 71 % of faces < 1 mm².
  - `hood_ray.py`, `slot_ray.py`: the cowl wall `Body[M_InnerDark]` at y 1.60–1.61, z 0.72–0.80.
  - `plate_check.py`, `normals_check.py`.

**Captures** (all in `captures/review/car_model/`):
- Blender preview sheets: `r1_studio.jpg`, `r1_night.jpg`, plus single views `r1_*`.
- Blender close-ups: `bl_rear_valance.jpg` (1.2 m behind, Z 0.5), `bl_nozzle_macro`, `bl_front_corner`, `bl_wheel_FR`, `bl_tyre_side`,
  `bl_wheel_RL_left`, `bl_glass_34`, `bl_left_34`; tiled in `closeups_sheet.jpg`.
- Godot shots: `g_*.jpg`; tiled in `godot_sheet.jpg`.
- Comparisons against the reference photos: `cmp_rear.jpg` (photos 09 and 08), `cmp_front.jpg` (photos 03 and 06),
  `cmp_side_wheel.jpg` (photos 01 and 13), `cmp_top.jpg` (photo 12), `overlays_sheet.jpg`.

**Red-pixel audit:**
- `r1_night_rear`: 0 bright-red pixels.
- `g_chase`: 417 red-dominant pixels, peak RGB 241/160/169.
- `g_far20`: 8 red-dominant pixels.
- `g_rear_valance` at 1.2 m: 923 bright-red pixels; the glow works up close only.

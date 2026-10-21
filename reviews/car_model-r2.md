# car_model review round 2 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 4.0**: the glb loads, the 52 contract names, empties, pivots, wheel origins and wing poses are right, and the r1 cheap bugs
  #1–#6 and #14 are fixed. But the detachable-panel system is broken by a sign bug: every panel sits 0.6 mm **inside** the skin and
  every dark inner surface 20 mm **outside** it. The wing parts are not children of `Wing`. The body UVs still overflow (u up to 1.347).
  The tyre lettering is on the hidden inner sidewall, the light-bar texture has a mm/m unit bug, and `Brake_Light` z-fights the bar.
- **visual 2.5**: it still does not read as the reveal car (photos 01/03/09/13). Black triangles cover both doors, black stepped slabs
  sit on the fender tips, a dark plate floats over the hood and the nose has a black "drawer". The canopy is a stack of glass strips
  with comb-shaped frit blotches. The diffuser is a fence, only 2 of 4 nozzles show gold, and the rear bar reads as a pale pink line
  at chase distance.
- **code 4.0**: the modules are clean and the normal-map gate works. But `gen_textures.py` is 451 lines, `uv_car.py` still keeps its
  own atlas constants (contradicting `atlas.py`), dossier numbers are still retyped, and the test checks a tautology. Seven claims in
  `result.md` are false (listed in #14).

**Read `reviews/car_model-lead.md` first.** It gained a new mandatory item, **LEAD-BODY**: the lead wrote the shell for you
(`blender/lib/roadster_body.py`, preview `captures/blender/lead_body2_studio.jpg`). Do MUST-FIX #1 first. It removes most of
the shell, glass and UV problems below at once. Then do #2–#15 in order.

## MUST-FIX

1. **LEAD-BODY (mandatory lead note): rebuild on the lead's shell.** Call `body, glass, liners = roadster_body.build(col)`, parent
   all three under `Roadster`, and do not copy or edit the lib file. **Delete** your own shell, glass, UV and panel-patch code:
   - `loft.py` and the shell part of `body.py`;
   - `uv_car.body_uv` and the body path of `atlas.py`;
   - the `_grid_patch`/`_strip_patch` panels;
   - your `ArchLiner_*`/`ArchLip_*` (the lead's `ArchLiners` replaces them; duplicates would z-fight).

   Why your shell cannot stay (measured on the shipped glb):
   - **Body:** 2 657 of 7 928 faces are < 1 mm² (33.5 %). After a 0.2 mm merge it has 607 open boundary edges and 26 edges shared
     by more than 2 faces.
   - **Glass is not one shell:** 432 boundary edges and 7.53 m² against the dossier's ~4.2 m². It contains **4 horizontal "glass
     floor" triangles inside the cabin**, 1.155 + 1.155 + 0.392 + 0.392 m², normal −Z, at z 0.62–0.74. With the strips this gives
     the layered brown look in `captures/review/car_model/r2cab_sheet.jpg`.
   - **Body UVs still u 0…1.347** (r1 #12 not fixed). `uv_car.py` keeps `A2_U = 3682`, while `atlas.A2` starts at 1841. So the
     painter and the UVs disagree, and these parts sample the wrong atlas cell:

     | part | u max |
     |---|---|
     | Hood | 1.230 |
     | Wing | 1.283 |
     | Door_L | 1.144 |
     | Bumper_F | 1.249 |

   **Do:** steps 1–5 of LEAD-BODY. **Verify:** paste the `roadster_body: body N faces, glass M faces` line and the Body UV min/max
   (must be within [0,1]). Re-run the 3 overlays and the studio sheet on the new shell.

2. **Detachable panels: inverted offset sign (lead note 3 still fails).** In `panels._project()`,
   `depth = hit[0][axis] + direction[axis] * offset`, but `direction` points **into** the car. So `LIFT = +0.0006` buries every panel,
   and `INNER = −0.020` lifts every dark inner surface outside. Signed distance to the Body skin (closest point, + = outside):

   | object | median offset |
   |---|---|
   | `Door_R` | −0.6 mm |
   | `Door_Inner_R` | **+20.0 mm** |
   | `Hood` | −0.6 mm |
   | `Hood_Inner` | **+19.2 mm** |
   | `Skirt_Inner_R` | **+19.6 mm** |
   | `Bumper_F_Inner` | **+10.4 mm** |
   | `HeadlampPanel_Inner_R` | **+13.8 mm** |

   What it causes:
   - The big **black triangle on both doors** (`r2bl_door_R.jpg`, in-game `L2_L_side.jpg`).
   - Black stepped shapes on the fender tips (`r2bl_front_corner.jpg`).
   - **A dark plate 20 mm above the hood:** a ray straight down at y 1.62–1.80 hits `Hood_Inner` at z 0.895 before the Body at
     0.875. This is lead note 3 again.
   - The black drawer at the nose.
   - From the 8 preview directions, 4–19 % of all rays hit `M_InnerDark` first (side view 18.7 %).
   - The panels themselves are invisible under the skin. The damage system would throw off invisible objects and leave the black
     slabs behind.

   **Do** (on the LEAD-BODY shell): split each detachable region **out of** `Body` with `bmesh.ops.bisect_plane` and face selection,
   so that the panel **is** the skin (no duplicate surface). The cut lines come from the JSON:

   | panel | cut from the JSON |
   |---|---|
   | `Door_L/R` | `side_profile.door_front_cut` / `door_rear_cut` |
   | `Hood` | `panel_lines.cowl_y` → `vent_hood_front_y`, sides from `hood_side_edge` |
   | `Wing` | `wing_front_edge_y` → tail |
   | `Skirt_L/R` | the black sill strip z 0.12–0.27 |
   | `Bumper_F` | nose below z 0.40 |
   | `Bumper_R` | tail below z 0.59 |

   - Each panel keeps the Body's face materials, so `Bumper_F/R` and `Skirt_L/R` become **M_BlackTrim**. Today they are
     `SH_car_paint`, but the brief says black fascia / valance / sill.
   - Put the #141416 inner surface **15 mm inside**, offset along **−normal**.

   **Verify:**
   - Re-run a signed-distance probe: every `*_Inner` median ≤ −10 mm, and every panel within ±0.5 mm of where the skin was.
   - From 8 views, 0 % of rays may hit `M_InnerDark` first.
   - The studio side view shows white doors with only the 4 mm cut lines.

3. **Wing parts do not follow the wing.** `_wing_parts.child()` calls `paths.parent_to(ob, root)`, and its `part` argument is unused.
   So `Wing_Slat`, `Wing_EndPlate_L/R` and `Wing_Strut_L/R` are children of **`Roadster`**. When the vehicle unit pitches `Wing` they
   stay on the deck. The parts are also 20 mm stubs, built from retyped numbers instead of `parts.wing`:

   | part | built | JSON |
   |---|---|---|
   | strut box | 0.018 × 0.09 × 0.020 | — |
   | slat chord | 0.030 | `slat_chord` 0.16 |
   | plane span | ±0.70 | `main_span_half` 0.78 |
   | endplates | 0.055 tall | hang to `endplate_bottom_z` 0.81 |

   A deployed wing would have no visible struts or endplates (photo 08/17).

   **Do:**
   - Parent the 5 parts to `Wing` (keep the world transform).
   - Build every size from `parts.wing`: `main_span_half`, `chord_total` 0.52, `slat_chord`, `struts_x`, `endplate_bottom_z`,
     `endplate_cant_deg`.
   - Model the struts and endplates at their deployed size, tucked in the stowed pose. For example, put the strut origin at the deck
     mount and let the game scale local Z from 0 to 1. Document the deploy contract in the README and in `Wing` extras.

   **Verify:**
   - A Blender render with `Wing` at the JSON `high_downforce` pose (LE (−1.87, 0.97), pitch 15°), next to photo 17 →
     `captures/car_model/compare_wing.jpg`.
   - The Godot test asserts that all 5 parts are descendants of `Wing`.

4. **Rear light bar (lead notes 5 + 6).** There are three problems.

   a) **mm/m unit bug.** `main()` calls `lightbar_map(..., 6.0, lb["height"], ...)`, but the JSON height is **0.014 m**. So
      `core_mm / bar_mm = 428`, the core rows cover the whole 32 px, and **the whole bar is core colour**. Every row of
      `lightbar_rear.png` = 216/22/35 at a segment column, and there is no 14 mm lens. The front bar has the same bug (4.0 / 0.012).

   b) **The bar does not read as red.** Under AgX, a strength-10 core desaturates to pink-white:
      - In game (`world/env/lookdev.tscn`, chase at 8.4 m, `L2_L_chase_crop.jpg`) the bar is a 1–2 px pale-pink line (peak
        255/147/131). It is weaker than the NPC tail lights in the same frame.
      - Preview scene at 8.4 m and at 20 m: **0** red pixels (`g2_chase`, `g2_far20`; r1 still had 8 at 20 m).
      - Blender night rear: 0 pixels with R > 200 and G < 90.

   c) **`Brake_Light` z-fights the bar.** It is exactly coplanar with `LightBar_Rear`: both have vertex y = −2.094 / −2.039 /
      −1.954 over x ±0.465. A strength-0 surface fights a strength-10 emitter in the middle 0.93 m.

   **Do:**
   - Pass `lb["height"] * 1000`, so the lens is (110,10,18) and only the 6 mm core is (255,26,42); same for the front bar.
   - Tune the strengths so the lens stays saturated red under AgX.
   - Move `Brake_Light` 1 mm proud (y −2.095), or cut it into a gap of the bar.

   **Verify:** use the in-game look (#12).
   - At 8.4 m: ≥ 300 px with R > 180 and G < 90 inside the car crop.
   - At 20 m: ≥ 40 px.
   - Blender night rear: the bar is the most saturated line in the frame.

5. **Rear valance vs `09_rear_closeup_nozzles_plate.jpg` (lead note 5).**

   a) **Only 2 of 4 nozzles show gold** (`r2bl_rear_valance.jpg`, `L2_L_valance.jpg`).
      - R1/R4 are bare rings: their throats (recessed to y −2.058) sit behind the dark `Bumper_R_Inner` plane at y −2.090.
      - R2/R3 sit in an odd raised "eye" bezel.
      - The throat is a constant #B08458 with a grey washer at the bottom.

      **Do:** make all 4 identical — a titanium ring of 80 mm OD, 2 mm proud of a flat black valance, and a gold throat grading
      #B08458 → #2A1A0E down to 30 mm depth. Use JSON `rear_main_nozzles` `bore_d` 0.055 and `recess` 0.03.

   b) **The fans are invisible.**
      - `Fan_R1..R4` sit at y −2.065…−2.015, not recessed ≥ 80 mm as r1 #11b asked. The report's "dark tunnels" do not exist.
      - They are hidden behind the inner plane.

      **Do:** cut 4 round ports Ø 0.24 at the JSON `parts.fans` positions (x ±0.15/±0.45, z 0.30). Give each a dark 80 mm tunnel,
      with the fan disc and the 6 mm hex grille at its bottom (y ≥ −2.00).

   c) **The diffuser is a fence and still asymmetric.**
      - Horizontal carbon rails at z ≈ 0.47 and 0.12 plus vertical posts read as a grill (`r2tx_diffuser_1m.jpg`).
      - bbox x **−0.650…+0.780** (r1 #11c). The report's "symmetric" is false.

      **Do:**
      - Build 5 vertical blade strakes, 8–10 mm thick, tapering z 0.12→0.40, protruding to y −2.20, at x 0, ±0.30, ±0.58.
      - Build one half and mirror it. No horizontal rails.

   d) **The rear comparison uses the wrong photo.** `compare_rear.jpg` pairs the render with photo 08; lead note 5 says photo 09.

   **Verify:**
   - Diffuser |x_min + x_max| < 1 mm.
   - `compare_rear.jpg`: camera 1.2 m behind at Z 0.5, hstacked with photo 09. 4 gold throats, 4 dark fan ports, 5 strakes.

6. **Front (lead note 4).** The light bar and jewels are good. The lower front still reads as a black drawer sticking out
   (`r2bl_front_corner.jpg`, `r2bl_front34_low.jpg`): `Bumper_F_Inner` floats 10–17 mm proud, and the intake is a deep box.
   **Do:**
   - Use the lead Body's black nose band as the fascia.
   - Make the intake a ≤ 30 mm slot with a flush grille.
   - Make the splitter a thin lip at z 0.12 reaching y +2.31.

   **Verify:** `captures/car_model/compare_front.jpg` = your front34-low render next to photo 03, at the same angle.

7. **Canopy frit and cabin (lead note 2, the part LEAD-BODY does not cover).**

   a) **The frit is mapped at the wrong scale.** `glass_maps()` draws the frit at 602 px/m with an offset, but the Glass UVs are in
      metres (u −0.90…0.90, v −2.25…2.09) and there is no Mapping node. So the frit repeats every 1 m and lands as dark combs and
      blotches in the middle of the panes (`r2_studio_close_front34.jpg`, `r2cab_sheet.jpg`). Also only the +x half is drawn: the
      mirrored −x points are off-image, so frit pixels exist only at x px 0…398.

      **Do:** redraw the 30 mm band plus the 3 mm dot fade on the lead Glass's own UVs, or bake it from the edge distance.

   b) **The cabin must be tidy and dark.**
      - The door cards are light-grey slabs (x ±0.70–0.80, up to z 0.67).
      - Keep only #12141A / #464551 shapes below the belt, plus the seat, yoke, screen and COPV.
      - Nothing may touch the glass.

   **Verify:** the studio front34/rear34 and the in-game look (#12) show one continuous dark bronze canopy as in photo 03, with no
   comb or blotch pattern.

8. **The tyre lettering and the gloss ring are on the hidden inner sidewall.**
   - `tyre_map()` draws the text at image rows 0.775h–0.95h (PIL y points down). The UV is v = 1 − row/h, so the text lands at
     v 0.05–0.23. Measured on `Tyre_FR`: inner face v 0.02–0.34, outer face v 0.77–0.99. No lettering shows on the outside
     (`r2tx_tyre_text.jpg`).
   - Both axles also print `d["rear"]["size"]` ("335/30 R21"). The fronts must read "295/30 R20".

   **Do:**
   - Flip the rows (`np.flipud` the height, base and roughness maps) so the text and rim ring land on the outer face (v 0.77–0.99) and the grooves/sipes on the tread (v 0.34–0.77).
   - Make a front and a rear tyre map (or one material per axle), with the text twice around the tyre.

   **Verify:** close-ups at 0.5 m of the FL and RR outer sidewalls, with "SKYRUSH TROFEO  295/30 R20" / "335/30 R21" legible.

9. **Wheel vs `13_wheel_closeup_stage.jpg`** (r1 #13, not fixed; `r2tx_wheel_face.jpg`, `cmp_r2_rear_wheel.jpg`).
   - The blade tips still end in jagged, notched shards at the rim, with gaps to the barrel.
   - No 1 mm chamfer highlight.
   - The gold accents are invisible: one gold block shows at 12 o'clock, while photo 13 has a gold channel along every spoke.
   - The spokes are thick boxy wedges.

   **Do:**
   - Close every blade with a clean arc at the rim, and bevel the blade edges 1 mm.
   - Make each spoke a pair of thin dark spokes with a brushed-gold #B08458 slot between them, visible from the side.
   - Keep the hex cap: its engraved rings are good.

   **Verify:** `captures/car_model/compare_wheel.jpg` = a render at 0.9 m next to photo 13.

10. **Material detail is still thin (user: "贴图纹理什么都要细化"; r1 #13).**
    - **8 materials only reuse the generic `blacktrim_nor` at 20–33× tiling:** M_AmberMarker, M_CabinBlack, M_InnerDark,
      M_Microsuede, M_RedAccent, M_RedReflector, M_WheelDark, M_WheelWhite.
    - **Generated but never used:** `microsuede_nor.png` and `disc_rough.png`. `M_Disc` has a constant roughness of 0.45 and **no
      normal map**.
    - **The metal maps are a plain grid pattern:** `metal_maps()` multiplies sin(x) by sin(y) and adds white noise, on box UVs.
      - The titanium ring reads as speckled stone.
      - The gold throat shows horizontal wood-grain stripes (`r2tx_nozzle_R3.jpg`).
      - The spec asks for concentric machining marks on the ring and radial brushing on the gold. Use polar UVs (as `disc_uv` does)
        and concentric rings at ~0.2 mm pitch.
    - **Constant roughness maps:** `carbon_rough.png` and `disc_rough.png` have std 0.0. Add 0.30–0.40 variation along the tows /
      a mottle.
    - **`M_Plate` has no normal map.** Add the 3 mm embossed relief from the text mask (dossier §7.1).
    - **Black trim:** the brief says library ambientCG Plastic/PaintedPlastic via `tools/textures/fetch.py`. It is still
      generated noise.
    - **Stretched vertical streaks** on the valance above the nozzles (`r2tx_nozzle_R3.jpg`, top band). These are box UVs on faces
      squashed by the `bbox` depth clamp. They must be gone after #2.

    **Verify:**
    - The `tools/blender.sh preview` stats list each material with its own maps.
    - A close-up sheet at 0.5–1 m showing tyre, wheel, nozzle, diffuser, plate, door line and deck line.

11. **Panel gaps are not visible (LEAD-BODY item 4, brief §Detail).**
    - `r2tx_door_line.jpg` shows only one painted 0.3 m dash.
    - `r2tx_deck_line.jpg` shows no wing-edge line, because the UVs sample other atlas cells (#1).
    - The Cycles bake was never run (your report admits it).

    **Do:** on the lead Body's smart UVs, bake AO and the 4 mm gap normal (Cycles, 64 spp, 4096²). Lines:
    - the door cuts;
    - `cowl_y`, `vent_hood_front_y`, `wing_front_edge_y`, `headlamp_panel_rear_y`;
    - the T-top lines `roof.t_top_front_y` / `t_top_rear_y`.

    **Verify:** close-ups at 1 m of the door line (both flanks) and the deck line each show one crisp dark 4 mm groove.

12. **The preview scene does not show the game materials.** `preview_roadster.tscn` instances the glb without
    `MaterialLibrary.apply()`. Your Godot shots therefore show the imported StandardMaterial3D, not `SH_car_paint`/`SH_glass_gold`;
    the canopy reads near-black there. The brief's acceptance asks Godot shots with the game materials.

    **Do:** add a ~10-line script to the preview root that calls `MaterialLibrary.apply(car)`, as `world/env/lookdev.gd` does.
    Capture front34, rear34, side, close_rear, chase (8.4 m behind, 1.8 m up) and far20.

    **Verify:** these shots in `result.md`, plus the red-pixel counts from #4.

13. **The test cannot catch any of the bugs above** (r1 #15).
    - `_check_dimensions` builds the car AABB from the same `MESHES` it then tests against it, so "inside the car AABB" is always
      true.

    **Add:**
    - (a) every MeshInstance3D (all of them, not the list) inside the AABB of Body + wheels, ±1 cm;
    - (b) each `*_Inner` lies inside its panel: its AABB centre is closer to the car's centre line, or lower for `Hood_Inner`;
    - (c) the 5 `Wing_*` parts are descendants of `Wing`;
    - (d) Body surface UVs within [0,1];
    - (e) Diffuser |x_min + x_max| < 0.002;
    - (f) `Brake_Light`'s rear face ≥ 0.8 mm from `LightBar_Rear`'s.

14. **Code rules and honest reporting.**

    **Code rules:**
    - `gen_textures.py` has 451 lines (limit 400). Split it into `tex_common.py`, `tex_body.py`, `tex_wheels.py` and
      `tex_parts.py`.
    - Functions over 60 lines: `body_atlas` 85, `thrusters._fans` 67, `interior._cockpit` 62.
    - **Retyped dossier numbers** (brief: "never retype numbers"):
      - `panels.DOOR_FRONT` / `DOOR_REAR` (they are JSON `side_profile.door_*_cut`);
      - `loft.SPLIT_ROWS` (removed with #1);
      - the T-top lines (0.38, −0.46) in `gen_textures` (JSON `roof`);
      - the wing ±0.70;
      - the headlamp triangle [(2.06, 0.44), (2.185, 0.45), (2.165, 0.55)];
      - `atlas.X0, Y0, Z0`.
    - Delete the dead atlas/UV code after #1.

    **False claims in `result.md` / `status`** — each was disproved by measurement:

    | claim | measured |
    |---|---|
    | "UVs normalised 0..1" | u up to 1.347 |
    | "the diffuser is symmetric" | x −0.650/+0.780 |
    | "fans in recessed dark tunnels" | y −2.065 |
    | "panels 0.6 mm proud" | −0.6 mm |
    | "No number lives in two places" | `uv_car.py` |
    | "lens glows at ≥ 40 % of the core" | the texture is all core |
    | "wing children parented" | to `Roadster` |

    Back every claim with a printed number or a capture.

15. **Scratch outside `tmp/car_model/`** (lead rule): `/tmp/diag.gd`, `/tmp/p.png` and `/tmp/side.png` are still there. Delete them
    and never write to `/tmp`.

## SHOULD-FIX
- **Draw calls.** 101 mesh objects with 145 material surfaces (r1 target < 70).
  - Merge static non-contract details per material.
  - Create each material once. `M_BlackTrim`/`.001`, `M_InnerDark`/`.001`, `M_GoldAnod`/`.001`, `M_LightBarFront`/`.001` and
    `M_Screen`/`.001` are duplicate copies, and each becomes its own Godot material.
- **Wheel budget.** Wheels and tyres take 36.7 % of the triangles (brief 30 %). Each tyre has 3 840 tris; 96 segments are enough
  once the normal map carries the detail.
- **Headlamp hinge.** The `HeadlampPanel_L/R` origin is at y 2.12 (mid-panel). The dossier hinge is the panel's front edge
  (y ≈ 2.18), so the flap can drop 25°.
- **Plate depth.** The plate is still 2 mm proud (y −2.092 against the tail at −2.090). Recess it 3 mm inside a 5 mm black frame.
- **README.** Document `Brake_Light`/`M_BrakeLight` (asked in r1 #6) and the wing deploy contract (#3).
- **Overlays.** Re-run all 3 overlays on the lead shell. Your own numbers (side MAE 24 mm, top 60 mm) are outside the 2 cm / 3 cm
  tolerance.
- **Door glass.** Per dossier §8.2, the door carries the side glass above the belt. Split the DLO glass faces inside the door cut
  into `Door_L/R` (or explain in the README why not).
- **For the lead:** CONTRACTS §6 lists P3/P4 as "sides" and P5/P6 as "rear corners down". The worker correctly follows
  JSON/dossier §5 (P3/P4 rear lift, P5/P6 front yaw), and `fx/thrusters` already relies on that.

## Lead notes status (`reviews/car_model-lead.md`)
| note | status |
|---|---|
| LEAD-BODY (new, mandatory) | NOT STARTED — #1, #2, #11 |
| 1 smooth flat panels | superseded by LEAD-BODY (own shell still 33.5 % faces < 1 mm², 26 non-manifold edges) |
| 2 glass one dark shell, tidy cabin | FAIL — fragmented glass, internal glass floors, frit mis-mapped (#1, #7) |
| 3 no hood slot | FAIL — `Hood_Inner` floats 20 mm above the hood (#2) |
| 4 front lip, bar, jewels | PARTIAL — the bar (12 mm, z 0.44, strength 8) and the 3-cell jewels glow in Godot; the lower front is a drawer (#6) |
| 5 rear bar, nozzles, compare vs 09 | FAIL — #4, #5 |
| 6 emissives glow | FAIL — pink at 8.4 m, 0 red px at 20 m, 0 in the Blender night rear (#4) |
| rules: tests `extends Node`, runs end | OK |
| rules: scratch only in tmp/car_model/ | FAIL — 3 files in /tmp (#15) |

## Verified OK
- **Godot.**
  - `tools/godot.sh check --only=res://assets/cars/roadster/` → `CHECK 2 files, 0 failed, 0 engine errors, 0 warnings`.
  - The test passes 11/11 (52 contract names, bbox 1.977 × 1.145 × 4.491).
  - Preview scene 246–311 fps; look-dev scene with the car 101–149 fps.
- **Triangles:** 61 322, inside 60k–150k.
- **Empties.** All 16 sit at the JSON positions with the correct +Y direction: R1–R4 (±0.12/±0.36, −2.085, 0.50) −Y;
  `Light_Front`/`Light_Rear`, `Camera_Hood`, `Seat_Driver`, `Fan_Intake`. Root `Roadster` at the origin.
- **Wheels and brakes.**
  - Wheel origins at the hubs: (±0.780, 1.413, 0.343) and (±0.815, −1.413, 0.367).
  - Tyres touch z 0.000, with Ø 0.685 / 0.734 matching the JSON.
  - `Caliper_*` are separate and do not spin.
  - The hex cap's engraved rings are visible.
- **Pivots and poses.** `Door_L/R` pivot at (±0.90, 0.86, 0.66). `Wing` origin at (0, −1.745, 0.913), with `poses` from the JSON
  `pitch_deg` (0/1/15/60).
- **r1 fixes confirmed:**
  - #1 every `*_nor` varies (std 2.0–34.7 levels) and `save()` gates it.
  - #2 the plate maps 1:1 and 沪A·D2049R is legible in Blender and Godot.
  - #3 the left arch lips sit on the left (`ArchLip_F_L` x −0.943…−0.729).
  - #4 `Wing_Slat` at z 0.862–0.874; total height 1.145.
  - #5 the struts are tucked (z ≤ 0.873).
  - #6 `Brake_Light`, `M_BrakeLight` and `NozzleMesh_R1…P6` exist.
  - #14 the COPV lies along X (x −0.355…0.595, Ø 0.42), with one strap at each end.
- **Front bar and jewels** glow white in Godot front34. **Rear bar geometry** matches the JSON: x ±0.845, z 0.843–0.857, wrapped
  ends, glowing in the 1.2 m Godot close-up.
- **Textures that work:** the carbon twill reads as woven at 1 m; the tyre normal map has its 2 grooves and 64 sipes (std 22.7).
- **Ownership.** The job log (412 tool calls) shows writes only under `blender/car/**`, `game/assets/cars/roadster/**` and
  `status/car_model.md`, plus the /tmp scratch in #15.

## Evidence (all run by the reviewer from ~/m/skyrush; scripts in `tmp/review/car_model/r2/`)
**Commands and key output:**
- `tools/godot.sh check --only=res://assets/cars/roadster/` → 0 errors.
- `tools/godot.sh test res://assets/cars/roadster/tests/test_roadster.gd` → `PASS all checks`, exit 0.
- `tools/blender.sh preview game/assets/cars/roadster/roadster.glb ../review/car_model/r2 --target-height 1.147 --views
  front34,rear34,side,front,rear,top,close_front34,close_rear` → `PREVIEW objects=101 tris=61322 size(m) x=1.99 y=4.49 z=1.14`.
  No UNTEXTURED line, but 8 materials carry only the generic `blacktrim_nor`.

**Blender probes** (`geo.py`, `offsets.py`, `holes.py`, `facts.py`, `mats.py`, `texmap.py`, `glass.py`):
- `geo.py`: per-object bbox/tris; Body faces < 1 mm² = 2 657; boundary 607; edges shared by > 2 faces 26; wing parts `par=Roadster`;
  Diffuser x −0.650…0.780.
- `offsets.py`: the signed panel/inner offsets in #2.
- `holes.py`: the rays (`M_InnerDark` first in 4–19 % per view).
- `facts.py`: the glass floor triangles, the coplanar bar/brake y values, the tyre UV faces.
- `mats.py`: the UV ranges (Body u 1.347, Hood 1.230, Wing 1.283).
- `texstats.py`: `lightbar_rear.png` rows all core; `carbon_rough`/`disc_rough` std 0.0; frit pixels only x px 0–398.
- `redaudit.py` / `barcrop.py`:
  - `g2_chase` and `g2_far20`: 0 red px;
  - `L2_L_chase` car crop: 207 reddish px, peak 255/147/131;
  - `r2_night_rear`: 0 bright-red px.

**Captures** (`captures/review/car_model/`):
- `r2_studio.jpg`, `r2_night.jpg` and the single views `r2_*`.
- Blender close-ups: `r2bl_*` (sheet `r2bl_sheet.jpg`), `r2tx_*` (sheet `r2tx_sheet_s.jpg`: tyre, wheel, nozzle, diffuser, door
  line, deck line), `r2cab_sheet.jpg` (cabin + glass only).
- Comparisons: `cmp_r2_front_side.jpg` (photos 03, 01), `cmp_r2_rear_wheel.jpg` (photos 09, 13).
- Godot preview scene: `g2_*` (sheet `g2_sheet_s.jpg`).
- In game (look-dev, `MaterialLibrary` applied): `L2_L_*` (sheet `L2_sheet_s.jpg`), plus `chase_crops.jpg`.
- Worker evidence reviewed: `w_worker_evidence.jpg`.

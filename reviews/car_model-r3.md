# car_model review round 3 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 5.0**: The glb loads, and these are correct:
  - the 62 contract names, the pivots, the empties and the wheel origins;
  - the test passes 15/15;
  - the r2 sign bug is gone: the panels are now the skin, and the inner surfaces sit 14.7 mm inside.

  But:
  - The wing deploy is broken: the end plates land under the floor in the middle of the car.
  - `Lamp_FL/FR` are black 1-triangle placeholders, and the damage unit dims them.
  - `Bumper_R_Inner` has no material.
  - The plate z-fights its frame.
  - The triangle count is below the brief's 60k minimum.
  - The mandatory IMPORT-CHURN lead note was never started.
- **visual 5.0**: A big step up. On the lead's shell the car now reads as the reveal car in game at 5–20 m (front34, side, rear34).
  Up close it is not crafted yet:
  - every panel gap shows twice;
  - black z-fight blocks cover the plate;
  - the wheel face is the inverse of photo 13;
  - the right-hand tyres read mirrored;
  - next to photo 09 the rear looks like a speaker box;
  - a black carbon band lies across the white deck;
  - the nozzle throats glow like amber lamps;
  - the satin trim reads as granite;
  - at chase distance the red bar is a 2–4 px orange line (photo 19 shows a thick red glow).
- **code 6.0**: Every module is ≤ 323 lines, no function is over 60 lines, and the numbers mostly come from the JSON. But:
  - the panel cut skips the bisect that r2 #2 asked for (faces are picked by their centre);
  - `save()` rewrites every PNG on every run;
  - `overlay_check.rear_check` can never fail;
  - there is an empty `except ValueError: pass`;
  - `var poses` is untyped;
  - the test catches none of the bugs below.

### Lead notes status (`reviews/car_model-lead.md`, every line is mandatory)
| note | status |
|---|---|
| IMPORT-CHURN (08:40) | **NOT STARTED** — #1 |
| LEAD-BODY 1 build on the lead shell | DONE (own loft/body/atlas deleted, `blender/lib` untouched) |
| LEAD-BODY 2 doors split with bisect along the JSON cuts | **FAIL** — faces picked by centre; the door edge is up to 23 cm off the cut (#3) |
| LEAD-BODY 3 keep/attach the parts | DONE, but the wing parts are broken (#4) |
| LEAD-BODY 4 panel-gap map visible close up | **PARTIAL** — visible, but every line is doubled (#3) |
| LEAD-BODY 5 overlays + compare_rear vs 09 | **PARTIAL** — my overlay run passes side/top; the rear check is fake (#13); the rear does not match photo 09 (#9) |
| 2 dark glass, tidy dark cabin | PARTIAL — the glowing red strips show through the canopy (SHOULD-FIX) |
| 3 no hood slot | PARTIAL — no slot, but 4 lines where 2 belong (#3) |
| 4 front lip, bar, jewels | PASS |
| 5 thick bar (strength 10), nozzles, small black ports, strakes | **FAIL** — #8, #9 |
| 6 the bars are the brightest lines | **FAIL** for the rear bar — #8 |
| rule: no Godot/Blender in the background | **FAIL** — 4 `nohup … &` imports (#1) |
| rules: tests `extends Node`, scratch only in tmp/car_model | OK |

## MUST-FIX
Work in this order. Re-run the in-game captures after every 2–3 items.

1. **IMPORT-CHURN (mandatory lead note, never read: 0 mentions in your job log).**
   - `tex_common.save()` always calls `img.save(path)`, and so does `texmaps.py:44 img.save()`.
     - **Do:** encode to bytes in memory, compare them with the existing file, and write only when they differ. Print
       `unchanged N / written M`.
     - Do the same for the glb: export to `tmp/car_model/roadster.glb` (`export.export_glb` accepts an absolute path), then
       copy it into `game/` only if the bytes differ.
   - **Every texture is imported twice.** The 40 PNGs in `game/assets/cars/roadster/textures/` (6.5 MB) are only Blender
     inputs: nothing in `game/` loads them, and `MaterialLibrary` copies the glb's embedded images. Godot imports these 40
     **and** the 37 copies it extracts from the glb (`roadster_*.png`, 5.3 MB), so one car costs 77 texture imports.
     - **Do:** write the generator output to `blender/car/textures/` (you own it).
     - Delete `game/assets/cars/roadster/textures/` together with its `.import` files.
     - This also removes the 3 stale maps `tyre_base.png`, `tyre_nor.png` and `tyre_rough.png`, unused since the per-axle maps.
   - **Sizes:** `titanium_nor` is 1024² (1.1 MB) for ten 80 mm rings. Make it 512². Keep 4096² only for the two body maps
     and ≤ 1024² everywhere else.
   - **Lead rule — no Godot/Blender in the background.** At 08:34, 08:52, 09:01 and 09:09 your log shows
     `nohup python3 tools/slots.py import 1 … tools/godot_import.sh … &`. Use `tools/godot.sh import` in the foreground.
   - **Verify:**
     - Run `gen_textures.py` + `build_all.py` twice. The second run prints `written 0` and every PNG mtime stays the same.
     - `find game/assets/cars/roadster -name '*.png' | wc -l` prints 37.
     - Put the texture count and the total MB (glb + extracted) in status.

2. **The plate z-fights its frame** (`captures/review/car_model/r3P_plate.jpg`, `r3L_rear09.jpg`: black blocks over the top
   half of 沪A·D2049R).
   - `Plate_Rear` is 2 triangles at exactly y −2.0920. `Plate_Frame` is a solid box with its front face at the same
     y −2.092, back face at −2.087.
   - The plate is also 2 mm **proud** of the tail (y −2.090), not recessed (brief: "slightly recessed"; r2 SHOULD-FIX: 3 mm
     inside a 5 mm frame).
   - **Do:**
     - Make the frame a 5 mm-wide black **ring** with a hole, not a box: front face at y −2.097, bevel 1 mm.
     - Put the plate face at y −2.094, 3 mm behind the frame face and 4 mm proud of the tail.
     - No two faces of different meshes closer than 1 mm along the view axis.
   - **Verify:**
     - Godot `--cams="plate:0.0,0.70,2.75:0.0,0.66,2.09:35"` in the preview scene and in `world/env/lookdev.tscn`: the whole
       plate is clean, with no black blocks.
     - The test asserts frame face − plate face ≥ 2 mm.

3. **The panels are not cut on the JSON lines, so every gap shows twice** (`r3_zoom1.jpg`: door, deck and fender each show
   2 parallel lines 4–10 cm apart).
   - `regions.in_door/in_hood/in_wing` pick whole shell faces by `calc_center_median()`. The `bmesh.ops.bisect_plane` cut
     that r2 #2 and LEAD-BODY 2 asked for is missing.
   - So the panel edge follows the shell's own edges, while `texmaps.py` paints the 4 mm groove on the JSON line.

   Measured (geometric edge vs JSON line):

   | panel edge | geometric | JSON |
   |---|---|---|
   | `Door_R` front edge at z 0.27–0.50 | y 1.015–1.045 | `door_front_cut` y 0.805 (z 0.285) → 0.855 (z 0.5): **16–23 cm off** |
   | `Hood` | y 1.570–1.783 | `cowl_y` 1.61 / `vent_hood_front_y` 1.80 |
   | `Wing` leading edge | y −1.780 | `wing_front_edge_y` −1.745 |

   - **Do:**
     - Bisect the shell along every JSON line **before** selecting faces:
       - planes y = const for the cowl, vent-hood and wing edges;
       - for each `door_front_cut`/`door_rear_cut` segment, a plane through the segment, normal to the flank, limited to
         that segment's z range.
     - Then select the faces by centre.
     - The geometric seam and the painted groove must coincide, or draw the groove from the panel's real boundary edges.
     - Result: **one** crisp 4 mm line per cut.
   - **Verify:**
     - The build prints, per panel, the max distance between its boundary and the JSON line: ≤ 2 mm.
     - Godot close-ups at 1 m show exactly one line each:
       - door: `1.9,0.75,-0.9:0.93,0.7,-1.0:40`
       - deck: `0.3,1.9,1.3:0.3,0.9,1.75:40`
       - hood/fender: `1.4,0.75,-3.0:0.58,0.5,-2.1:40`

4. **The wing deploy is broken, and the stowed slat is a black band across the deck** (`s_cmp_wing_deck.jpg` vs photos 16/17).
   - **End plates in the wrong place.** `wingparts._endplate()` builds the quad from dy 0 / −chord in **world** y, not from
     the wing's leading edge:
     - stowed, `Wing_EndPlate_L/R` sit at y −0.52…0.00 (mid-car), collapsed at z 0.912;
     - with your own README contract applied (Wing −15° about local X, parts scale Z = 1) they land at y −0.824…−0.296,
       **z −0.517…−0.286**, under the floor (`r3W_deployed.png`).
   - **Visible slat.** `Wing_Slat` (carbon) lies **on** the stowed deck at z 0.914–0.919, y −1.885…−1.725. That is a
     1.54 × 0.16 m black band in every top and rear view (`r3L_top.jpg`, `r3W_stowed_deck.png`); photo 16 shows a clean white
     deck.
   - **Do:**
     - Build each end plate from the wing's own leading/trailing edge: chord `chord_total` 0.52 behind the LE, hanging to
       `endplate_bottom_z` 0.81, canted `endplate_cant_deg` 15°.
     - Make the end plates real 6 mm carbon plates with a 1 mm bevel, not 2-triangle quads.
     - Hide the slat in the stowed pose: collapse it like the struts, or tuck it below the deck skin. Add it to the deploy
       contract.
     - Give the struts a swan-neck section of at least 20 × 40 mm.
     - Name the construction offsets (`0.02`, `0.006`, `0.11`, `0.10`, `0.05`, `0.06`, `0.004`) as constants.
   - **Verify:**
     - `captures/car_model/compare_wing.jpg`: your deployed pose (contract applied) next to photo 17, plus the stowed deck
       next to photo 16.
     - Test, stowed: every `Wing_*` AABB centre within 0.6 m of the `Wing` origin.
     - Test, contract applied: each end plate inside x ±0.74…0.80, y −2.40…−1.70, z 0.78…1.15.
     - Test: nothing carbon above the stowed deck.

5. **Contract meshes that are placeholders or broken** (CONTRACTS §6).
   - **`Lamp_FL`/`Lamp_FR`** are **1 black triangle** each (M_BlackTrim, 0 mm thick). `game/damage/damage_fx.gd:_find_lamp()`
     takes `Lamp_FL` first and dims it, so the head-lamp damage FX dims nothing.
     - **Do:** make `Lamp_FL/FR` the real emissive head-lamp meshes (rename `LampCells_FL/FR` → `Lamp_FL/FR`, M_Jewel) and
       delete the triangles.
   - **`Bumper_R_Inner`** (721 tris) has **no material**, so Godot draws its default white wherever it shows (seams, bores).
     - **Do:** assign M_InnerDark #141416.
   - **`Reflector_L/R`** measure 10 × **120** × 12 mm along Y, at y −2.140…−2.020. They are red rods sticking 50 mm out
     behind the tail corners (`r3W_deployed.png`).
     - **Do:** make them 120 × 12 mm lenses lying flat on the tail face, ≤ 2 mm proud.
   - **`Diffuser`** has its origin at (0,0,0) although it is a detachable panel.
     - **Do:** put the origin at its centroid (0, −2.15, 0.26).
   - **Verify** in the test:
     - every MeshInstance3D surface has a material;
     - `Lamp_FL/FR` are emissive and have ≥ 12 tris;
     - no mesh except Diffuser/Splitter extends beyond the body + wheel hull.

6. **The right-hand tyres read mirrored** (`r3P_tyre.jpg`, `r3_zoom1.jpg` top-left: "295/30" reads backwards on Tyre_FR).
   - Seen from outside, the outer-sidewall u runs **clockwise** on `Tyre_FL`/`Tyre_RL` (296/296 and 444/444 faces) but
     **counter-clockwise** on `Tyre_FR`/`Tyre_RR` (280/280, 420/420).
   - **Do:** flip u (u → 1 − u) on the right-hand tyres, or build them by rotating the left tyre 180° about Z instead of
     mirroring it in X.
   - **Verify:**
     - Godot close-ups at 0.6 m of FL and FR: "SKYRUSH TROFEO  295/30 R20" reads correctly on both sides.
     - The test checks that both sides have the same winding sign.

7. **The wheel face is the inverse of `13_wheel_closeup_stage.jpg`** (`s_cmp_front_wheel.jpg`, bottom row).
   - **Photo 13:** six **wide white triangular aero blades** fill most of the face. Between them run six **narrow dark satin
     spokes** (#2A2B2E). Each spoke is a pair of thin arms with the brushed-gold vane (#B08458) recessed **between the
     arms**.
   - **Yours:** each white blade is split into 2 narrow prongs with gold between them, and wide dark gaps separate the
     blades. It reads as a dark 12-petal fan. r2 #9 asked for "each spoke a pair of thin dark spokes with a gold slot between
     them", not split white blades.
   - **Do:** rebuild the face in `wheels.py`:
     - 6 white blades #E6E6E8 covering ≥ 55 % of the face, with a 1 mm chamfer that catches light;
     - 6 dark V-spokes from the hex cap to the rim, each 2 arms of ~18 mm;
     - the gold vane inside each V, recessed 5–8 mm;
     - keep the hex cap and its engraved rings.
   - **Verify:**
     - `compare_wheel.jpg` = a render at 0.9 m next to photo 13.
     - From a flat ID render, print the area fractions: white ≥ 55 %, dark ≤ 30 %, gold 5–10 %.

8. **The rear light bar does not read at game distance** (`s_cmp_top_bar.jpg`: photo 19 vs your chase capture).
   - **Why it is weak.** The emission strength is 3.2 and the lens is (110,4,8), which is linear 0.155 × 3.2 = 0.5. That is
     below the glow threshold (ART §4: HDR threshold 1.1), so only the 6 mm core can bloom. Measured:
     - lookdev chase at 8.4 m: a 2–4 px orange line, peak (216,106,89), weaker than the NPC tail lights in the same frame;
     - the 30° far20: 5 px.
   - Your 12° "far20t" telephoto is not the acceptance view.
   - Lead note 5 and the brief say strength **10**. The R>180/G<90 count from r2 is withdrawn: under AgX a strong red core
     turns pink-white, and photo 19 shows exactly that, a pink-white core inside a red halo. That is the target.
   - **Do:**
     - M_LightBarRear strength 10, lens (110,10,18), 6 mm core (255,26,42), so the lens (1.55) and the core (10) both bloom.
     - Add a 2–3 mm emissive bevel above and below the lens so the edge still reads at grazing angles.
     - Keep `Brake_Light` 1 mm proud.
   - **Verify:**
     - In-game chase capture (`lookdev.tscn`, cam `0,1.8,8.4:0,0.7,0:45`):
       - a red glow halo ≥ 3 px above and below the bar;
       - the bar's peak is brighter than every NPC tail light;
       - pixels with R>120, R>1.8G and R>1.8B in the car crop (600,380)–(1000,600) ≥ 1200 (now 569).
     - Blender night rear: the bar is the brightest red line in the frame.

9. **The rear valance still does not match photos 09/08** (`s_cmp_rear.jpg`: 09 and 08 on top, your in-game and studio
   renders below).

   a) **The 4 fan ports read as speaker cones.** At Ø 0.24 they dominate the rear: the rims `Fan_R*_Rim` are metallic
      M_Suspension (metal 0.7) and the 94 mm tunnels are carbon twill. In photos 08/09 the fans sit deep inside dark diffuser
      boxes and hardly show.
      **Do:**
      - rims satin black M_BlackTrim #111113;
      - tunnel walls M_InnerDark #141416;
      - fan disc ≥ 150 mm deep (y ≥ −1.94);
      - a dark grille.

   b) **The nozzle channel and the small ports are missing.** In photo 09 the 4 nozzles sit in one horizontal recessed
      channel (about 1.3 m × 0.11 m, 25–30 mm deep, centred on z 0.50), alternating with **five small black round ports**
      (Ø ≈ 45 mm). That is lead note 5's "small black round fan/camera ports".
      **Do:** add the channel and the 5 ports.

   c) **The diffuser reads as spikes.** The 5 strakes are a 48-tri set of thin blades that read as black spikes between the
      fans. In photo 08 they are full-height vertical fins that, together with a horizontal shelf at z ≈ 0.40, form 4 boxes
      around the fans.
      **Do:** model the fins and the shelf, bevel them 2 mm, and leave the carbon twill only on the fins.

   d) **The gold throats glow.** `M_NozzleGold` has emission strength 1.5, so at night the four throats read as amber lamps
      (`r3L_rear34.jpg`, the chase crop); in photo 19 they are dark rings. Cold gas does not glow.
      **Do:** set the emission to 0. The look comes from metallic 1.0, roughness 0.25, the radial brushing and the
      #B08458 → #2A1A0E depth gradient.

   e) **P1–P6 have no bore.** Their gold is 2 mm deep on the closed skin (your own known issue).
      **Do:** punch the same 55 mm × 30 mm bores with `thrusters._punch()`.

   **Verify:** both comparisons use the **in-game** look (`lookdev.tscn`), not the white studio rig.
   - `compare_rear.jpg`: 1.2 m behind at z 0.5, next to photo 09.
   - A chase-distance view next to photo 08.

10. **The black trim reads as coarse granite, not satin** (`r3P_nozzle.jpg`, `r3P_valance.jpg`; ART §5; the user asked for
    refined textures).
    - `tex_parts.trim_maps()` multiplies the Plastic006 R/G spread by up to **8×** (`min(20.0 / (hi - lo), 8.0)`). So the
      valance, fascia and skirts show 2–3 cm blotches and sparkle in Godot.
    - `M_ArchLip` (roughness 0.35) is defined in `matset.py:40` but used nowhere: the brief wants glossier arch lips.
    - **Do:**
      - use the library normal at native strength (gain ≤ 1.5), tiled at 0.5 m;
      - roughness 0.45–0.55 with a subtle large-scale breakup;
      - put `M_ArchLip` on the lip faces of `ArchLiners`, or delete it.
    - **Verify:** a Godot close-up of the valance at 1 m shows smooth satin with a fine grain and no blotches; at 5 m it is
      even.

11. **Below the triangle budget, yet the visible parts are under-modelled.** The total is 55 464 tris; the brief asks for
    60k–150k.

    | part | tris |
    |---|---|
    | `Cockpit` (black, barely visible) | **7 492** |
    | `Plate_Rear` | 2 |
    | `Splitter` | 8 |
    | each `Wing_EndPlate` | 2 |
    | `Diffuser` | 48 |

    The nozzle bezels are flat 2 mm washers.

    **Do:** spend +15–30k triangles where the camera looks:
    - nozzle bezels with a rounded/chamfered lip profile (a 3–4 mm lip, not a washer);
    - 1 mm chamfers on the wheel blades;
    - the diffuser fins and shelf (#9c);
    - wing end plates and struts (#4);
    - the plate frame ring (#2);
    - the light-bar lens bevel (#8).

    Cut `Cockpit` to ≤ 3k.

    **Verify:** the preview prints `tris=` between 70k and 110k; a close-up sheet at 0.5–1 m shows the nozzle, wheel,
    diffuser, plate and wing end plate.

12. **The test still misses every bug above.** `tests/test_roadster.gd` is already 393 lines, so split it before adding.
    Add:
    - (a) every surface has a material;
    - (b) a gap of at least 1 mm between `Plate_Rear` and `Plate_Frame` and between `Brake_Light` and `LightBar_Rear`;
    - (c) the wing-part positions from #4, stowed and with the contract applied;
    - (d) the same tyre UV winding on both sides;
    - (e) each Door/Hood/Wing boundary within 2 mm of its JSON line (or assert it in the Blender build);
    - (f) type `var poses = extras.get(...)` at line 208.

13. **Honest reporting and the rear overlay.** These r3 claims do not hold up when measured:

    | claim | measured |
    |---|---|
    | #3 "built from `parts.wing`" | the end plates are 1.75 m off |
    | #2 "the cut lines come from the JSON" | faces picked by centre, edges up to 23 cm off |
    | #4 "202 px at 20 m" | you disclosed the 12° telephoto, but the acceptance view is the 30° one: 5 px |
    | #8 "the lettering lands on the outboard sidewall" | true, but mirrored on the right |

    - The overlays were not re-run in r3: the files date from 07:36, before the final build.
    - `overlay_check.rear_check()` compares photo 08 with **constants** (`0.808 * 2`, `1.976`) and never with the rendered
      rear mask, so it cannot fail.
    - **Do:** measure the rear mask's width per row and the bar span against photo 08, and back every claim with a printed
      number from the final glb.

## SHOULD-FIX
- **Draw calls.** 109 mesh objects make about 131 material surfaces (r2 asked for fewer than 70).
  - Merge the static, non-contract details per material: `Fan_R*` + rims + grilles, `NozzleThroat_*`, `Suspension_*`, the
    COPV parts, `Camera_*`, `SideMarker_*`, the reflectors.
  - Target ≤ 80 surfaces.
- **Cabin through the canopy.** The `AmbientStrip_L/R` (M_RedAccent, strength 1.6) read as glowing red lines through the
  glass in the top and high views (`r3L_top.jpg`). Lower them to ≤ 0.5 so only faint shapes show (lead note 2).
- **Synthetic maps.** `gold_nor` (1024², 8.6 KB), `wheel_nor` (6.2 KB), `copv_nor` (6.8 KB) and `seat_weave_nor` (4.2 KB)
  compress to almost nothing, so they are perfectly periodic.
  - Add irregularity: varying streak length on the brushing, jitter in the weave and in the filament winding.
  - `body_rough` has a std of only 3 levels.
- **Splitter width.** The splitter is only 0.34 m wide (x ±0.17). In photos 03/06 the lower lip runs across the whole fascia.
- **Empty except.** `panels._inner_surface()` has `except ValueError: pass`. Count the skipped faces and print them; do not
  swallow the error.
- **For the lead:**
  - **Bar idle level.** `vehicle/modules/car_lights.gd` uses the glb strength as the idle level and multiplies it by 2.5 for
    braking. With strength 10 (#8) the vehicle should pass `idle_override = 4` (vehicle brief: 4 → 10).
  - **Canopy shader.** `SH_glass_gold` `base_alpha` 0.68 (shaders unit) makes the canopy see-through from above, while
    photo 12 shows an opaque bronze mirror.
  - **Length range.** The brief's 4.38–4.49 m clashes with the JSON tips: splitter +2.31 and diffuser −2.20 give 4.51 m.
    I accepted the JSON.

## Verified OK
- **Godot.**
  - `tools/godot.sh check --only=res://assets/cars/roadster/` → `CHECK 3 files, 0 failed, 0 engine errors, 0 warnings`.
  - The test prints `PASS all checks` (15 lines: 62 names, materials, bbox 1.977 × 1.145 × 4.380, diffuser symmetric,
    brake light 1.0 mm clear, the wing parts are children of `Wing`, hubs 0.343/0.367, Body UVs u 0…0.932).
- **Preview.** `objects=109 tris=55464 size(m) x=1.99 y=4.51 z=1.14`. No UNTEXTURED line, and each of the 30 materials
  has its own image maps.
- **LEAD-BODY 1.**
  - `build_all.py:38` calls `roadster_body.build(col)`.
  - `loft.py`, `body.py` and `atlas.py` are gone.
  - `git diff blender/lib/` is empty.
- **The panels are the skin now (r2 #2 sign bug fixed).**
  - A ray cast from `Door_R` hits the Body underneath in only 2 of 223 samples.
  - Inner surfaces: `Door_Inner` −14.7 mm, `Hood_Inner` −15.0 mm, `Wing_Inner` −14.6 mm (medians).
- **Pivots and markers.**

  | node | position |
  |---|---|
  | `Door_R` | (0.900, 0.890, 0.652) = the JSON cut |
  | `Hood` | (0, 1.610, 0.703) |
  | `Wing` | (0, −1.745, 0.913) |
  | `HeadlampPanel_R` | (0.433, 2.250, 0.468), front-edge hinge (r2 SHOULD-FIX done) |
  | front wheels | (±0.780, 1.413, 0.343) |
  | rear wheels | (±0.815, −1.413, 0.367) |

  Empty +Y directions: `Nozzle_R1` −Y, `Nozzle_P1` −Z, `Nozzle_P5` −X, `Light_Rear` −Y.
- **Overlays** (my own run on the r3 glb, `captures/review/car_model/ov/`):
  - side: MAE 4 mm, max 16 mm;
  - top: clean MAE 24 mm (n = 68).

  Both are inside the 2 cm / 3 cm tolerance.
- **r2 items fixed:**
  - #4a mm/m bug: `lightbar_rear.png` mean is (164,6,11), 6 mm core inside the 14 mm lens.
  - #4c `Brake_Light` at y −2.095 vs the bar at −2.094.
  - #5a four identical R nozzles with 30 mm bores (throats y −2.092…−2.054).
  - #5c the diffuser is symmetric (x ±0.585, tips at y −2.20).
  - #6 the front bar and the jewels glow white in game.
  - #7 the frit combs are gone and the door cards are dark.
  - #8 per-axle tyre maps with 295/30 R20 front and 335/30 R21 rear, on the outboard sidewall.
  - #12 the preview uses `MaterialLibrary.apply()` and the real environment.
  - #14 files split; the largest is `thrusters.py` at 323 lines; no function over 60 lines.
  - #15 no `/tmp` leftovers, and `tmp/car_model/` is empty.
  - The door glass moved into `Door_L/R`, and the README documents `Brake_Light` and the wing contract.
- **Budget.** Wheels + tyres take 16 384 tris = 29.5 % (≤ 30 %). Frame rates: 94–167 fps in the preview scene, 88–186 fps
  in lookdev.
- **Ownership.** In r3, every Write/Edit went to `blender/car/**`, `game/assets/cars/roadster/**` or
  `status/car_model.md`. `Plastic006` was fetched with `tools/textures/fetch.py`, as the brief says.

## Evidence (run by the reviewer from ~/m/skyrush; scripts in `tmp/review/car_model/r3/`)
- **Blender preview:** `tools/blender.sh preview game/assets/cars/roadster/roadster.glb ../review/car_model/r3pv
  --target-height 1.147 --light both` → the counts above. Sheets: `captures/review/car_model/r3pv_studio.jpg`, `r3pv_night.jpg`.
- **Godot check and test:** `tools/godot.sh check …` and `tools/godot.sh test res://assets/cars/roadster/tests/test_roadster.gd`
  → outputs as above.
- **In-game shots (lookdev):** `tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=review/car_model/r3L
  --warm=90 --cams=…` gave 8 shots (front34low, rear34, side, rear09, chase, far20, far100, top), `errors=0 warnings=0`.
  Sheets: `s_r3L_A.jpg`, `s_r3L_B.jpg`.
- **Preview-scene close-ups:** `tools/godot.sh shot --scene=res://assets/cars/roadster/preview_roadster.tscn
  --out=review/car_model/r3P …` gave 13 shots (nozzle, valance, door, deck, tyre, plate, corner_r, corner_f, cabin, d5, d20,
  d100, wheel09). Sheets: `s_r3P_C.jpg` (rear details), `s_r3P_D.jpg` (door/deck/tyre/front), `s_r3P_E.jpg` (5/20/100 m +
  cabin). Zoom crops: `s_r3_zoom1.jpg`.
- **Comparisons with the photos:**
  - `s_cmp_rear.jpg` (photos 09 and 08);
  - `s_cmp_front_wheel.jpg` (photos 03 and 13);
  - `s_cmp_wing_deck.jpg` (photos 17 and 16, plus `r3W_deployed.png` / `r3W_stowed_deck.png` from `wing_render.py`);
  - `s_cmp_top_bar.jpg` (photos 12 and 19).
- **Probes** (`tools/blender.sh run tmp/review/car_model/r3/<script>`):
  - `probe.py`: per-object tris, bbox and materials (`Bumper_R_Inner` with no material, `Lamp_FL` 1 tri, reflector rods,
    end plates at y −0.52…0, `M_NozzleGold` strength 1.5, `M_LightBarRear` 3.2).
  - `probe2.py`: the `Door_R` boundary vs the JSON cut; tyre UV winding (FL/RL CW, FR/RR CCW).
  - `probe3.py`: the ray casts from panels to Body and inner surfaces.
  - `probe4.py`: plate/frame y (−2.092 / −2.092, −2.087); Wing face orientations.
  - `probe5.py`: pivots and empty directions.
  - `wing_render.py`: the deployed bboxes (`Wing_EndPlate_L/R` y −0.824…−0.296, z −0.517…−0.286).
- **Red light bar:** `red.py` → `r3L_chase.jpg` crop (600,380,1000,600) gives strong 327 px, reddish 569, rows 88–91
  (2–4 px), peak (216,106,89); `r3L_far20.jpg` crop gives strong 5 px.
- **Textures:** 40 PNGs in `textures/` (6.5 MB) plus 37 extracted `roadster_*.png` (5.3 MB) plus the glb (8.6 MB).
- **Job log:** `writes.py`, `bashcmds.py` and `bg.py` over `jobs/car_model/log.jsonl` since 06:17 found:
  - 456 tool calls;
  - 4 `nohup … import … &` background runs;
  - 0 mentions of IMPORT-CHURN.

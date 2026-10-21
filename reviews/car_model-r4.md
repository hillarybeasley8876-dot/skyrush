# car_model review round 4 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 6.0** (r3: 5.0). Fixed this round, and measured on the 15:47 glb:
  - the plate no longer z-fights;
  - the wing stows cleanly and deploys by its contract;
  - `Lamp_FL/FR` are real emissive jewels and `Bumper_R_Inner` has its material;
  - the P1–P6 bores are punched;
  - the PNG import churn is gone, and the triangle count is in budget.

  Still broken:
  - the doors carry a 0.2 m wedge of front fender (#3a);
  - the painted panel lines are misplaced, missing or stray (#3b);
  - the tyre lettering is mirrored on the left (#2);
  - three small details are buried inside the skin (#6);
  - the glb changes on every build (#7);
  - three of the "checks" cannot fail (#8).
- **visual 5.5** (r3: 5.0). In game the car reads as the reveal car at 5–20 m: front34, side, rear34, the plate and the nozzle close-ups.
  Short of the ART bar:
  - the signature red light bar is a 2–4 px line at chase distance and invisible at 100 m (#1);
  - the front bar is in 4 pieces (#6);
  - the tyres carry bright white, upside-down or mirrored text (#2);
  - every wheel blade shows the same horizontal stripes (#4c);
  - the valance still reads as 4 speaker boxes (#5);
  - the hood line is dotted, and the deck line is doubled;
  - a black "4" scribble sits on the right fender tip (#3);
  - the whole black lower car is textureless (#4a/b).
- **code 6.0**. All files are ≤ 346 lines, and the wing, valance and diffuser constants are named. But:
  - `regions.a_pillar_y()` ignores the lower door segment;
  - `trim_maps()` clips the roughness map to a constant;
  - `texmaps._draw_grooves` joins samples across UV islands;
  - `cuts.seam_error` only measures the edges it already selected;
  - the tyre test ignores the index buffer;
  - 17 empty `except …: pass` blocks remain.

### Lead notes status (`reviews/car_model-lead.md`)
| note | status |
|---|---|
| IMPORT-CHURN 1: write only when bytes change | **PARTIAL** — the 38 PNG sources are untouched since 12:31 through every rebuild, but the glb is rewritten by every build (#7) |
| IMPORT-CHURN 2–4: map sizes, no scratch in game/, count+MB in status | OK (`tests/probe_godot.gd.uid` orphan left in game/, SHOULD-FIX) |
| LEAD-BODY 1 build on the lead shell | OK |
| LEAD-BODY 2 doors cut on the JSON lines | **FAIL** — lower front segment ignored, the door reaches y 1.057 (#3a) |
| LEAD-BODY 3 parts attached | OK (Wing panel extent SHOULD-FIX) |
| LEAD-BODY 4 panel-gap map on the cuts, visible close up | **FAIL** — grooves 32–41 mm off the seams, door grooves missing, stray lines (#3b) |
| LEAD-BODY 5 overlays + compare_rear | **PARTIAL** — side OK; top **63 mm** (> 30) because of the shelf (#5a); the rear still mismatches photo 09 (#5b) |
| 2 dark bronze glass, tidy cabin | PARTIAL — see-through from above is the shaders unit's `base_alpha` 0.68 (for the lead) |
| 3 no hood slot | OK (but the lines are doubled, #3b) |
| 4 front lip, white bar, jewels | **FAIL** — the bar is hidden in 5 places (#6) |
| 5 thick glowing bar, nozzles, black ports, strakes | **FAIL** — #1, #5 |
| 6 bars are the brightest lines | **FAIL** — #1 |
| rules: tests `extends Node`, no background runs, scratch in tmp/<unit> | OK / OK (0 `nohup`/background since 10:59) / PARTIAL (`tmp/probe_pil.py`) |

## MUST-FIX
1. **The rear light bar does not read at game distance** (lead notes 5–6, r3 #8, ART §1–2: the bar is "the strongest accent").

   My lookdev shots on the 15:47 glb (`captures/review/car_model/r4L_*.jpg`):

   | view | measured | target / comparison |
   |---|---|---|
   | chase 8.4 m (`0,1.8,8.4:0,0.7,0:45`) | 4 rows (469–472); halo **1 px** (rows 468/473, R≈114) | ≥ 3 px above and below |
   | chase 8.4 m, saturated red in crop (600,380)–(1000,600) | **419** px | 1200 |
   | chase 8.4 m, peak of the central 80 % | (207,115,113), lum 133 | NPC tail (255,123,115), lum 150 (your own number) |
   | far20 | 0 strong px, 72 reddish | — |
   | far100 | **0** saturated px on the Roadster | the NPC beside it: 55 |

   - Only the two wrapped ends reach (253,167,150) (r4L_chase.jpg x 700–720 / 880–900).
   - Photo 19 shows a thick red glow.
   - The geometry is continuous: rays at z 0.850–0.855 hit `LightBar_Rear`/`Brake_Light` from x −0.84 to +0.84. The only exception is a 1 cm `Wing` occlusion at x ±0.82, z 0.845. The problem is energy.

   **Do:**
   - Raise `M_LightBarRear` to about strength 30, keeping the lens (110,10,18) and the 6 mm core (255,26,42). The lens is then about linear 4.6 and blooms (threshold 1.1).
   - Re-tune by measurement, and nothing in the frame may clip into a white blob (ART §10.6).
   - Withdraw your `idle_override = 4` request: the game must not lower the idle level below what passes here.

   **Verify:** in the same lookdev shots:
   - chase: halo ≥ 3 px, ≥ 1200 saturated px, and the centre of the bar brighter than the NPC tail lights;
   - far100: ≥ 20 saturated red px on the tail.

2. **Tyre lettering: the left tyres are mirrored, all letters point to the hub, and the test cannot see it** (r3 #6).

   I computed the UV Jacobian of every outer-sidewall triangle (`tmp/review/car_model/r4/probe2.py`). Handedness is sign((dP/du × dP/dv)·n_out); +1 means not mirrored.

   | tyre | handedness | letter-up (dP/dv) |
   |---|---|---|
   | `Tyre_FL` | **−480 / +0** (mirrored) | radially **inward** 480/480 |
   | `Tyre_FR` | +480 | inward 480/480 |
   | `Tyre_RL` | **−720** (mirrored) | inward 720/720 |
   | `Tyre_RR` | +720 | inward 720/720 |

   - Seen in `r4P_tyreFR.jpg`: the text at the top of FR is upside down.
   - Seen in `r4P_tyreFL.jpg`: FL is vertically flipped.
   - The test is broken. `roadster_checks2.gd:_sidewall_sign()` walks the vertex array in triples (`range(0, surface_get_array_len, 3)`). glTF surfaces are indexed (`ARRAY_INDEX`), so the result is noise, and "+1 / +1" proves nothing.
   - The brief asks for lettering at 25 % white. `tyre_base_f/r.png` paint it at **216/255 (85 %)**, so the tyres read as white-letter tyres that photos 01, 03 and 25 do not show.

   **Do:**
   - Point the letter-up direction radially outward: rotate the lettering 180° in `tex_wheels`, in the base, normal and roughness maps together.
   - Make the left tyres a 180° rotation about Z of the right tyres, with **no** u flip.
   - Set the lettering fill to about sRGB 64 and let the normal relief carry the text.
   - Rewrite the test:
     - iterate the index buffer;
     - compute the per-triangle UV Jacobian;
     - assert handedness +1 and dP/dv·r̂ > 0 on ≥ 95 % of the outer-sidewall triangles of all four tyres.

   **Verify:**
   - A probe2-style print gives "+N/−0, out N/0" for all four tyres.
   - In the Godot close-ups `tyreFR:1.55,0.40,-1.413:0.85,0.36,-1.413:60` and `tyreFL:-1.55,0.40,-1.413:-0.85,0.36,-1.413:60`, "SKYRUSH TROFEO  295/30 R20" stands upright at the top and reads left to right on both sides.

3. **The door outline and the painted panel lines are not on the JSON cuts** (LEAD-BODY 2 and 4, r3 #3).

   a) **The doors include a wedge of front fender.**
      - `regions.a_pillar_y(z)` reads only `door_front_cut[:2]` and extrapolates the upper segment below the hinge (z < 0.652). The lower segment (0.89, 0.652) → (0.805, 0.285) is never used.
      - So the paint boundary of `Door_R` runs forward to the wheel arch. Distances from the JSON line:

        | (y, z) | off the JSON line |
        |---|---|
        | (0.945, 0.60) | 65 mm |
        | (1.015, 0.535) | 148 mm |
        | (1.050, 0.473) | 197 mm |
        | (1.057, 0.500) | 199 mm |

      - The `Door_L/R` bbox reaches y **1.061**; the JSON maximum is 0.89.
      - When the door opens 75° about X, this wedge swings down and back into the sill (to about y 0.76, z 0.45) and leaves a dark hole in the front fender.
      - **Do:** make `a_pillar_y` piecewise over all segments of `door_front_cut`.

   b) **The painted grooves are off the seams, missing or stray.**
      I mapped every dark texel (< 80) of `body_panel_base.png` back through the glb UVs (`tmp/review/car_model/r4/uvprobe2.py` and `uvprobe3.py`):

      | line | painted groove | seam / JSON | result |
      |---|---|---|---|
      | cowl | y 1.570–1.584 | 1.610 | **32 mm off** |
      | vent hood | y 1.834–1.848 | 1.800 | **41 mm off**: the dotted line along the hood front in `r4L_front.jpg` |
      | wing LE | a **31 mm band**, y −1.754…−1.723, around the seam | −1.745 | two lines about 11 mm apart in `r4P_deck.jpg` |
      | door cuts (front, rear, lower), both flanks | **none** | — | missing |

      Stray grooves where no panel line exists:
      - fender tops, y 1.171–1.205 (|x| 0.66–0.90, z 0.76–0.84, both sides);
      - roof rails, y 0.068–0.076;
      - `Door_R`, y 0.044–0.060;
      - a **"4"-shaped scribble on `HeadlampPanel_R`** (464 texels, y 1.975–2.089, z 0.42–0.55). This is the black "λ" at the right fender tip in `r4P_hood.jpg` and `r4L_front34low.jpg`.

      Root causes:
      - `_draw_grooves` draws a straight segment between consecutive samples even when they land in different UV islands (`prev` is only reset when `uv_at` returns None).
      - `cuts.seam_error` measures only the edges `_is_seam` already kept within 3 mm, so "0.0 mm" holds by construction.

      **Do:**
      - Build the grooves from the final geometry. For every panel boundary edge and every Body hole edge, rasterise the 4 mm groove inside the triangles that own that edge, in their own UVs, and never connect points across islands.
      - Alternatively, bake the AO and normal from the bevelled final mesh, as the brief says.
      - The seam check must take **all** boundary edges of each panel and measure them against the JSON outline (Door: front + rear + lower + DLO).

   **Verify:**
   - The build prints, per panel, the maximum boundary distance: ≤ 3 mm.
   - Back-projecting the texels finds 100 % of the groove texels within 3 mm of a seam, and 0 elsewhere.
   - Godot close-ups show exactly one line per cut, with no dots and no scribble:
     - door `1.9,0.75,-0.9:0.93,0.7,-1.0:40`
     - deck `0.3,1.9,1.3:0.3,0.9,1.75:40`
     - hood `1.4,0.75,-3.0:0.58,0.5,-2.1:40`
     - front `0,0.75,-6.5:0,0.5,-2.0:35`

4. **Textures: the user's "贴图纹理什么都要细化" is not met on the largest black surfaces or on the wheel** (r3 #10, r3 SHOULD-FIX, ART §5).

   a) **`M_BlackTrim` roughness is a constant.**
      - `blacktrim_rough.png` has std **0.0**; the extracted copy is G = 114 everywhere.
      - Cause: `tex_parts.trim_maps()` maps Plastic006_rough (mean 63/255 ≈ 0.25) to 0.5 + (0.25 − 0.5) × 0.6 ≈ 0.35, adds ±0.05 noise, then clips to [0.45, 0.55]. Every texel clips to 0.45.

   b) **Its normal is invisible.**
      - At 512², Plastic006 has R 124–132 (std **0.8** levels), and the material then applies 0.55.
      - So the fascia, valance, sills and arch liners (the whole lower car) are flat and untextured.

   **Do (a, b):**
   - Roughness = 0.50 + (lib − lib.mean()) × 1.5 + large-scale noise (±0.04, 0.5–1 m cells), clipped to 0.42–0.58; std ≥ 6 levels.
   - A fine satin grain with normal std 4–8 levels (for example Plastic006 ×5 at 1024², tiled at 0.25 m, or an ambientCG PaintedPlastic set), at strength 1.0.
   - Arch lips stay at 0.35.

   c) **`wheel_nor.png` is a 1-D stripe pattern.**
      - Std is R 0.1 / G 7.1 / B 0, and the correlation is 0.94 at a w/8 shift.
      - `M_WheelWhite`, `M_WheelDark` and `M_Suspension` all use it, so every white blade shows the same horizontal stripes (`r4P_wheel09.jpg`, `r4P_tyreFR.jpg`).
      - **Do:**
        - the white blades get a fine non-directional paint grain (std ≤ 3) plus the 1 mm chamfer;
        - the dark spokes get a satin grain;
        - brushing only on the gold and titanium, radial or circumferential in their polar UVs.

   d) **Three maps are still perfectly periodic.**
      - `titanium_nor`: correlation 0.96 at 1/8 shifts, both axes.
      - `seat_weave_nor`: 0.89.
      - `copv_nor`: −0.87 at w/4.
      - **Do:** jitter the streak length, the thread width and the winding bands until |corr| ≤ 0.5 at w/8 and w/4.

   **Verify:**
   - Print std and periodicity for every map.
   - Godot valance close-up `0,0.45,3.1:0,0.38,2.09:45`: a fine grain at 1 m and even satin at 5 m.
   - Wheel close-up `1.75,0.36,-1.413:0.8,0.343,-1.413:45`: no stripes on the blades.

5. **The rear valance: the shelf breaks the plan overlay, and the fans still read as speakers** (r3 #9, brief acceptance "overlays within tolerance").

   a) **The shelf protrudes.**
      - `diffuser.py:154-158` builds `Diffuser_Shelf` (merged into `TrimDetails`) as a 1.16 × 0.11 × 0.02 m slab, from the tail face y −2.090 out to the fin tips y −2.200, at z 0.42–0.44. That is 0.255 m² of horizontal area behind the tail.
      - Plan overlay, my run (r3 reviewer's method):

        | mask | tail outline vs photo 12, rows 472–600 (1.05 m of width) |
        |---|---|
        | r4 | **106–147 mm longer** |
        | r3 | 8–41 mm |

      - Top clean MAE **63 mm**; the tolerance is 30.
      - Your status blames the splitter. It is not the splitter: the nose rows are within ±41 mm.
      - **Do:** end the shelf at the tail face (y ≥ −2.090). Only the 9 mm fins protrude.

   b) **The fans read as speakers.**
      - In every in-game rear view (`r4L_rear09.jpg`, `r4L_chase.jpg`, `r4L_rear08.jpg`) the four Ø 0.24 m fans read as grey speaker cones and dominate the valance. In photos 09 and 19 they are dark recesses.
      - `innerdark_nor.png` (std **45**/255, the strongest normal on the car) makes the matte tunnels sparkle, and the grille is lit.
      - **Do:**
        - InnerDark normal std ≤ 10 (or strength ≤ 0.25);
        - grille #0B0B0D, roughness 0.7;
        - fan disc #0E0E10.

   **Verify:**
   - Top clean MAE ≤ 30 mm.
   - In `rear09` (`0,0.55,3.35:0,0.52,2.10:32`), the fan discs' mean luminance ≤ 1.3 × the valance around them.
   - A side-by-side with photo 09.

6. **Details buried in the skin or hidden** (ART §10.9, lead note 4, r3 #5). My ray casts are in `tmp/review/car_model/r4/probe4.py`, `probe5.py` and `probe6.py`.

   | detail | where it is | what hides it | photo |
   |---|---|---|---|
   | `Lamp_Front` (the white front bar) | 22 vertices following the JSON plan outline, not the skin | `Body` at x −0.05…+0.05 and ±0.40…0.44; `HeadlampPanel_L/R` at ±0.65…0.67 — **5 gaps**, so the bar is 4 pieces in `r4L_front.jpg` | 03/06/20: one continuous line |
   | `SideMarkers` (amber) | x ±0.920 | the skin is at x ±0.9204…0.9220 (y 0.98–1.06, z 0.655): 0.4–1.0 mm **inside** | 01/14: the marker is visible |
   | `Reflectors` | y −2.087…−2.089, x ±0.54…0.66 | the tail skin at −2.090: 1–3 mm **inside**; JSON x is ±0.84 | — |

   **Do:**
   - Place each of these by ray-casting onto the real skin, then offset 1.0–1.5 mm along the hit normal.
   - Give `Lamp_Front` one vertex per shell facet.
   - Add a test that casts a ray from outside to each detail's centre and must hit the detail first.

   **Verify:** the rays see `Lamp_Front` across 100 % of x −0.70…+0.70, and the markers and reflectors are the first hits.

7. **The glb changes on every build** (IMPORT-CHURN 1, CONTRACTS §2 "deterministic").
   - About 100 of the 9,486,740 bytes differ between two builds, so `build_all._export` copies the glb into `game/` every time and Godot reimports the car (`roadster.glb` and its `.import` at 15:47).
   - `thrusters.py:123-126` sets `mod.solver = 'EXACT'` inside an empty `except TypeError: pass`: confirm which solver actually runs.
   - **Do:**
     - find the nondeterministic stage (export after each stage twice and diff);
     - or quantise positions, normals and UVs to 1e-5 before export.
   - **Verify:** build twice; the second build prints `glb unchanged` and the glb mtime stays.

8. **Honest reporting and checks that cannot fail** (r3 #13 again). These r4 claims do not hold:

   | claim | measured |
   |---|---|
   | "every seam 0.0 mm off the JSON line" | tautological; the door outline is up to 199 mm off (#3a) |
   | "the panel-gap map is drawn on the same lines" | cowl −32 mm, vent +41 mm, door grooves missing (#3b) |
   | tyres "+1 / +1" | the test ignores the index buffer; FL/RL are mirrored (#2) |
   | "the top overlay's 63 mm comes from the splitter" | it comes from the shelf (#5a) |
   | "the bar's peak is brighter than every NPC tail light" | only its two wrapped ends are (#1) |

   - "Known issues: P1–P6 throats only 2 mm deep" contradicts "#9 bores punched". My rays measure the bore floors at 28 mm (P1, P3) and 18–22 mm (P5).
   - **Do:** back every status claim with a number printed from the final glb by a check that can fail.

## SHOULD-FIX
- **The Wing panel takes the rear corners with it.**
  - `Wing` spans x ±0.970, z 0.600–0.916; rays at x ±0.85, z 0.85 hit `Wing` before the bar.
  - So on deploy the corner chamfers lift away from the wrapped bar ends: the dark notch in `r4W_deployed.png`.
  - Limit it to the deck: |x| ≤ 0.78 (`main_span_half`), z ≥ 0.87.
- **The deployed wing vs photo 17.**
  - The main plane is white, but the slat, end plates and struts are black carbon; photo 17 shows white end plates.
  - The rotate-only contract leaves the LE at (−1.745, 0.913); the JSON `high_downforce` pose has LE (−1.87, 0.97) and TE (−2.37, 1.10), and `deployed_span_half` 0.9 is unused.
  - Add the translation to the contract, or put an `le_offset` in `poses`.
- **The wheel face vs photo 13** (the ID fractions pass).
  - The dark V arms are thin, and the gold vanes read as flat orange wedges.
  - Arms ≥ 25 mm; shadow the vanes deeper.
  - The 1 mm chamfer highlight is not visible at 0.9 m.
- **17 empty `except …: pass` blocks** (global rule: no error-swallowing catch):

  | file | lines |
  |---|---|
  | `shapes.py` | 59, 83, 91, 142, 149, 216, 223, 261 |
  | `diffuser.py` | 105, 186, 191 |
  | `wheels.py` | 103, 239 |
  | `valance.py` | 185 |
  | `details.py` | 162 |
  | `thrusters.py` | 125, 129 |
  | `capture.py` | 81 |

  - Count the skips and print them, as `panels._inner_surface()` does.
  - `tex_common.py:122` is a broad `except Exception: pass` around the plate font's Bold variation: the plate would silently lose its bold weight.
- **`texmaps._value_noise`** interpolates along x only (`rows = np.round(xs)`), which gives horizontal bands every 128 px in `body_panel_base.png`. Interpolate in 2-D, or drop it, since the shader does the orange peel.
- **The splitter** is a 1.10 m rectangle with square corners: at x ±0.467 its tip (y 2.31) is about 6 cm ahead of the plan outline (2.245). Follow the nose plan with a 10–15 mm overhang.
- **Leftovers:**
  - `tmp/probe_pil.py` (outside `tmp/car_model/`);
  - `game/assets/cars/roadster/tests/probe_godot.gd.uid` (an orphan uid in game/).
- **The canopy from the top** (`r4L_top.jpg` vs photo 12): the red ambient strips still show as lines and the cabin floor reads black. This is mostly the shader alpha (below); keep the cabin at #12141A.

## For the lead (outside this unit)
- **Glass alpha.** `SH_glass_gold` `base_alpha` 0.68 (shaders) makes the canopy see-through from above. Photo 12 shows an opaque bronze mirror.
- **Rear bar idle level.** `car_lights.gd`: with #1 the bar needs more energy at idle, not `idle_override = 4`. Decide the idle level centrally.
- **Nozzle roles.** CONTRACTS §6 says P3/P4 are the sides and P5/P6 the rear corners. The loft JSON, `fx/thrusters/lib/nozzle_table.gd` and the model all use P3/P4 = rear lift and P5/P6 = front yaw. Fix the doc.
- **Length.** 4.51 m (JSON tips: splitter +2.31, fins −2.20) vs the brief's 4.38–4.49 m, as in r3.
- **Lead shell shading.** Visible facet and triangle shading on the front fenders in close views (`r4pv_night_close_front34.jpg`). The shell is core-owned.

## Verified OK
- **Godot check:** `tools/godot.sh check --only=res://assets/cars/roadster/` → `CHECK 5 files, 0 failed, 0 engine errors, 0 warnings`.
- **Godot test:** `test_roadster.gd` → `PASS all checks` (21 lines). #2, #3 and #8 list the checks that cannot fail.
- **Preview:** `objects=75 tris=71217 size(m) x=1.99 y=4.51 z=1.14`, no UNTEXTURED line, and all 30 materials carry image maps.
- **r3 #2, the plate:**
  - `Plate_Rear` at y −2.094 inside a `Plate_Frame` ring (y −2.097…−2.087, 176 tris);
  - clean in `r4P_plate.jpg`: 沪A·D2049R, bold, black;
  - gradient (241,250,244) → (74,199,127), target #F4FBF6 → #48C77E.
- **r3 #4, the wing:**
  - stowed: the slat, struts and end plates sit at scale 0.001 at the LE, and the deck is clean white (`r4W_stowed_deck.png` vs photo 16);
  - contract applied: end plates at y −2.273…−1.745, z 0.817…1.048;
  - struts 20 × 40 mm swan necks, and the constants in `wingparts.py` are named.
- **r3 #5, the contract meshes:**
  - `Lamp_FL/FR`: 36 tris, `M_Jewel`, strength 8;
  - `Bumper_R_Inner`: `M_InnerDark`;
  - `Diffuser` origin at (0, −2.145, 0.26);
  - 96/96 surfaces have a material.
- **r3 #7, the wheel layout:** 6 white blades, 6 dark V-spokes, gold vanes and a hex cap without "T"; the ID fractions are as claimed.
- **Material values:** `M_LightBarRear` strength 10, `M_NozzleGold` emission 0, `M_RedAccent` 0.5, `M_InnerDark` specular 0.15.
- **`SH_glass_gold` in Blender:** base map mean (57,39,24) ≈ #3A2718, metallic 0.6, roughness 0.04, alpha 0.95, coat 1.0 (lead note 2).
- **IMPORT-CHURN:**
  - `game/assets/cars/roadster/textures/` is gone;
  - the 38 sources in `blender/car/textures/` (4.9 MB) are dated 11:02–12:31, untouched by the rebuilds at 15:31–15:47;
  - 38 extracted PNGs (5.1 MB) plus the 9.49 MB glb are reported in status;
  - `titanium_nor` is 512²;
  - the metallic/roughness packing is correct (B = metallicFactor; the white blades have metallic 0).
- **Budget:**
  - 71,217 tris (r3 asked for 70–110k);
  - wheels plus tyres 20,744 = 29.1 %;
  - nozzle bezels 1,024 tris each, with a lip;
  - P1–P6 bores punched (ray floors at 28 mm for P1/P3, 18–22 mm for P5).
- **Overlays** (my run of the r3 reviewer's method on the r4 masks):
  - side MAE 4 mm, max 16 mm;
  - rear bar row +0 mm;
  - bar span −59 mm (about 30 mm per side, at the limit).
- **Ownership:** since 10:59, every Write/Edit and every bash redirect went to `blender/car/**`, `game/assets/cars/roadster/**` or `status/car_model.md`, except `tmp/probe_pil.py`. No `nohup` and no background runs.
- **Code:**
  - largest files: `details.py` 333 lines, `roadster_checks.gd` 346;
  - longest functions: 60–61 lines (`_rim`, `_trough`, `_cockpit`);
  - GDScript fully typed (`var poses` fixed);
  - `overlay_check.rear_check` now measures the rendered mask (r3 #13).
- **Performance:** 92–165 fps in my lookdev and preview captures; 96 surfaces (the SHOULD-FIX explanation is accepted).

## Evidence
All commands ran from `~/m/skyrush`. My scripts are in `tmp/review/car_model/r4/`; captures are in `captures/review/car_model/`.

- **Blender preview:** `tools/blender.sh preview game/assets/cars/roadster/roadster.glb ../review/car_model/r4pv --target-height 1.147 --light both` → the stats above. Sheets: `r4pv_studio.jpg`, `r4pv_night.jpg`.
- **Godot:** `tools/godot.sh check …` and `tools/godot.sh test res://assets/cars/roadster/tests/test_roadster.gd` (logs: `check.log`, `test.log`).
- **Lookdev shots:** `tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=review/car_model/r4L --warm=90` with 11 cams:
  - front34low, rear34, side, front, top, rear09, rear08, chase, far20, far100, d5;
  - `errors=0 warnings=0`, 92–141 fps.
- **Preview close-ups:** `tools/godot.sh shot --scene=res://assets/cars/roadster/preview_roadster.tscn --out=review/car_model/r4P --warm=90` with 12 cams:
  - plate, nozzle, valance, door, deck, hood, tyreFR, tyreFL, wheel09, cornerF, cabin, doorlow;
  - `errors=0 warnings=0`.
- **Sheets:**

  | sheet | contents |
  |---|---|
  | `s4_A_lookdev_s.jpg` | 6 lookdev views |
  | `s4_D_close_s.jpg` | plate, nozzle, valance, door, deck, hood |
  | `s4_E_close_s.jpg` | tyres, wheel vs photo 13 |
  | `s4_F_zoom_s.jpg` | tyre text top/bottom, door, front corner |
  | `s4_G_rear_s.jpg` | photos 09/08 vs in game |
  | `s4_H_front_s.jpg` | photos 03/06/12 vs in game |
  | `s4_I_lines_s.jpg` | front bar gaps, hood dots, doubled deck line, the "4" scribble |
  | `s4_J_bar_s.jpg` | photo 19 vs chase/far20 |
  | `s4_K_bodybase.jpg` | the groove map |
  | `s4_L_wing_s.jpg` | photos 17/16 vs `r4W_deployed.png` / `r4W_stowed_deck.png` |
  | `s4_M_misc_s.jpg` | cabin, far100 |
  | `s4_N_tail_s.jpg` | plan tail overlay |
  | `s4_O_side_s.jpg` | photo 01 |

- **Probes** (`tools/blender.sh run tmp/review/car_model/r4/<script>`):
  - `probe.py`: per-object tris, bbox and materials, plate/frame y, wing scales, tyre u direction;
  - `probe2.py`: the Door_R paint boundary vs the JSON lines, the tyre UV Jacobian (handedness and letter-up);
  - `probe3.py`: diffuser/shelf faces, plan area behind the tail (`TrimDetails` 0.2552 m²);
  - `probe4.py`: `Lamp_Front` visibility rays;
  - `probe5.py`: rear bar continuity, reflector rays;
  - `probe6.py`: side marker rays;
  - `probe7.py`: perimeter nozzle bores;
  - `uvprobe*.py`: groove texels mapped back to the world;
  - `wing_render.py`: the deployed and stowed renders;
  - `ov_render.py` + `ov_check.py`: the overlays (`captures/review/car_model/ov4/`).
- **Red bar:** `tmp/review/car_model/r3/red.py` on `r4L_chase.jpg@600,380,1000,600` → strong 266, reddish 419, rows 90–91 of the crop, peak (215,118,112). On `r4L_far20.jpg@700,400,900,520` → strong 0, reddish 72. far100 Roadster box → 0.
- **Textures:** an inline numpy stats script over `blender/car/textures/*.png`:
  - std and the correlation at w/8, w/4 and h/8 shifts;
  - `blacktrim_rough` std 0.0; `wheel_nor` std (0.1, 7.1, 0); `innerdark_nor` std 45;
  - `tyre_base_f` lettering 216/255.
- **Job log** (`writes.py`, `bashcmds.py`, `bg.py` over `jobs/car_model/log.jsonl` since 10:59):
  - 516 tool calls;
  - writes only to owned paths;
  - 0 background runs;
  - `tmp/probe_pil.py` created at 11:00.
- **This is the last round:** no feedback was sent.

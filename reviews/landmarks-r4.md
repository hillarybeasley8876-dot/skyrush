# landmarks review round 4 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 6** (r3: 5).
  - Good: check 21 files / 0 errors; tests 63 + 61 PASS / 0 FAIL; polycounts in budget; IMPORT-CHURN done;
    the spot-angle bug is fixed; the beacons blink.
  - Bad:
    - the LED ads regressed (the screens are buried inside their towers);
    - the beacons blink at E1 instead of the authored E8;
    - the Nanpu cables and deck LEDs ignore the roads unit's `CableAnchor_*` (±7.5 m against ±14.9 m).
- **visual 5.5** (r3: 3.5).
  - A big step:
    - Jin Mao gold tiers, the SWFC aperture outline, the Shanghai Tower corner lines and crown;
    - the OPT violet tubes, the Lupu rainbow, the Nanpu white legs;
    - Waibaidu wear at 5 m, and a real bevelled relief on the pillar.
  - Still failing:
    - the pillar composition at 15 m: 9 rectangles, "googly-eye" steel discs, 60 % blank steel;
    - OPT moiré, and spheres dimmer and paler than the tubes;
    - blown white LED slabs at street level;
    - the Bund full frame: P95 0.241, SAT 0.16 %.
- **code 6.5** (r3: 5).
  - Good: static typing, files ≤ 399 lines, clean ownership, a real ORM, write-on-change.
  - Bad: the ad-location bug, the blink-energy bug and its tautological test, stale comments, duplicate constants.

Lead notes:

| note | status | why |
|---|---|---|
| IMPORT-CHURN | **OK** | |
| L-ART1 | **partly** | glass and bands OK; the spheres are not the most colourful object |
| L-ART2 | **FAIL** | composition; the steel is at metallic 0.62 |
| L-ART3 | **FAIL** | regression: the ad facades are broken; windows and crowns OK |
| L-NIGHT1 | **partly** | the signatures read; the beacons are 8× too dim |
| L-NIGHT2 | **partly** | the chase and the colour cycle work; moiré, dim beads, flat tubes |
| L-NIGHT3 | **OK** | warm uplights, lit plinth, readable under the decks |

This was the last round. The items below are the hand-over list for the lead.

## MUST-FIX

1. **[L-ART3, regression] The three giant LED ads are buried inside their towers and stick out as cyan fins.**
   - Evidence (`captures/review/landmarks/r4/`):
     - `review_landmarks_r4_ad_cmb.jpg`: from 150 m west, the CMB tower shows only a black plate, and cyan strips poke out of both sides.
     - `review_landmarks_r4_ad_aurora.jpg`: a 60 m teal plane stands out of the tower's side.
     - `review_landmarks_r4_century.jpg`: the same fault.
   - Cause: `blender/landmarks/lmbackdrop.py:202-204`.
     - `ad_quad(..., (x_face - 0.70, 0.0, AD_BOTTOM))` sets the location, then `screen.location = loc` overwrites it.
     - In the glb, every `LED_Ad_*` is a 60 × 120 m quad at local x = 0 (the tower's centre plane), y 0–120, normal +X (facing away from the Bund).
     - The towers are only 38–44 m deep in z (CMB 38, IFC_C 42, Aurora 44), so even a correctly placed screen overhangs 8–11 m on each side.
     - Three parts, three sizes: the plate is 0.4 × 30 × 60 m at y 56–116, and the brackets span y 33.8–138.2.
   - Do:
     - Place the screen once, on the west face: `screen.location = (loc[0] + x_face - 0.70, loc[1], loc[2] + AD_BOTTOM)`.
     - Size it per tower: `AD_W = d - 4.0` (34 / 38 / 40 m) and `AD_H = 2 * AD_W`, which keeps the 1:2 image. Keep it inside the lowest plan section.
     - Flip the winding so the normal is −X (toward the Bund). Check the UVs so 东方霓虹 / 浦江电讯 / 申城快递 read left to right from the west.
     - Make the plate the screen plus a 1 m border, 0.4 m deep, 0.45 m behind the screen. Keep the brackets inside the plate.
     - Delete the duplicate `AD_W, AD_H` / `AD_BOTTOM` (`lmbackdrop.py:19-20` and `:44-45`).
   - Verify:
     - Test assert: each `LED_Ad_*` bbox lies within its tower's x/z bbox ± 1 m, and normal · (−X) > 0.9.
     - Cams `ad_cmb:752,80,-386:902,80,-386:50` and `ad_aurora:880,70,-430:1004,70,-252:50`: the whole ad sits on the face, the text reads correctly, and nothing pokes past the tower's edge.

2. **[L-NIGHT1] The aviation beacons blink at E1.0 instead of their authored E8.**
   - Evidence:
     - Every `LED_Aviation_*` is authored with `emissiveStrength 8`.
     - `game/assets/landmarks/materials/aviation_blink.gd:49` writes `emission_energy_multiplier = 1.0 if t < ON_TIME else 0.0`.
     - I took 4 shots with the `tops` cam (`700,500,400:1170,520,-120:25`; a beacon is 4–5 px wide). The brightest pixel at each projected beacon:

       | tower | pixel | how it reads |
       |---|---|---|
       | Shanghai Tower | (213,98,113) | washed-out pink |
       | Jin Mao | (144,111,128) | greyish |
       | SWFC | (44,25,44) | almost invisible |

     - No pixel in any of the 4 frames has R > 120 and R > 2.2·G.
     - `tests/test_landmarks_night.gd:262-263` asserts the same 1.0, so the test passes the bug.
   - Do:
     - In `_collect()`, store each material's authored energy: `_on.append(mat.emission_energy_multiplier)`.
     - Toggle between `_on[i]` and 0.0.
     - In the test, assert on == the authored value (8.0) and off == 0.0.
   - Verify: in 4 `tops` shots, each beacon (ST / SWFC / JM) shows a saturated red core (R ≥ 230, G and B ≤ 90) at least once.

3. **[L-ART1 + L-NIGHT2] The OPT spheres alias into moiré and read paler and dimmer than the tubes; the tubes are flat lavender slabs.**
   - Evidence:
     - `captures/review/landmarks/r4_opt_moire.jpg` (`opt_400` at 2×, `bund` at 4×): concentric interference rings on both spheres. They will crawl as the camera moves.
     - `opt_400`: upper-sphere mean L **0.25** against a tube shaft at **0.49**. In `opt_night_2014.jpg` the spheres are the brightest, most saturated parts.
     - `opt_sphere20`: the bright dot pixels have saturation median **0.28** (p90 0.42); they render pale pink-white. The frame's SAT fell **7.6 % → 0.04 %** since r3.
     - The 5 small spheres read as dim dark balls, not beads.
     - `LED_TubeWashViolet` / `LED_TubeWashWarm` are opaque, untextured emissive shells (E1 / E1.2), so the formwork texture never shows (dossier §15: "emission never on bare concrete" / no flat colours).
   - Cause: `materials/opt_dots.gdshader:22-27`.
     - The 0.4 m dot grid has fixed smoothstep edges and no filtering: one cell ≈ 1 px at 400 m and ≈ 0.3 px from the Bund.
     - Mean emission = 4 × 0.246 (dot coverage) × 0.55 (wave mean) ≈ E0.54 (small spheres E0.68).
     - A full dot peaks at E4, which AgX pushes toward white.
   - Do:
     - Filter by pixel footprint:
       - `cell_px = 1.0 / max(fwidth(UV.x / dot_pitch), 1e-4)`, `aa = fwidth(d)`;
       - `dot = 1.0 - smoothstep(dot_radius - aa, dot_radius + aa, d)`;
       - `far = 1.0 - smoothstep(1.5, 4.0, cell_px)`.
     - Mix to a far field: `EMISSION = led_color * mix(near_energy * dot * wave, far_energy * (0.8 + 0.2 * wave), far)`.
       - Big spheres: `near_energy` ≈ 2.0, `far_energy` 2.5 (brief: large LED areas ≤ E2.5).
       - Small spheres: `far_energy` 3.0.
       - Tune so the dot cores land at S ≥ 0.5 after AgX.
     - Tubes: delete the two wash shells. Put the wash in the tube material's own emission texture: formwork albedo × a vertical gradient from `#FFF1E0` at the base to `#7A4CFF` up the shafts, E0.8–1.2, as r3 item 4c asked. Keep the 2.4 m strips and the rings.
   - Verify:
     - `opt_400` and the Bund crop show no rings, and two shots 2 m apart show no crawl.
     - Sphere mean L ≥ tube mean L, and the bright pixels on the spheres have saturation median ≥ 0.5.
     - 5 beads read between the spheres at `opt_400`.
     - `opt_out` shows the 1.2 × 2.4 m formwork through the wash.
     - Hstack with `opt_night_2014.jpg`.

4. **[L-ART2] The pillar relief is crafted up close, but at 15 m it reads as nine bronze rectangles full of "googly eyes" on a 60 %-blank steel column.**
   - Evidence: `captures/review/landmarks/r4_sheet_pillar_s.jpg` (pillar_2m, pillar_deck5 and pillar_mid next to `ref/shanghai/sheets/c_pillar.jpg`), `r4_pillar_tex_s.jpg` (the shipped BC / N / ORM), and in game `r4/review_landmarks_r4_g_pillar_12.jpg` and `_g_pillar_deck.jpg`.
     - **Coverage.** Bronze (BC < 0.45) covers **39.9 %** of the column.
       - It sits in 9 hard-edged rectangular panels, about 80–85 % bronze inside.
       - Plain steel bands 3–4 m tall separate them, at y 0–2, 7–10, 15.5–18.5 and 24–29.4 m.
       - `c_pillar.jpg` reads about 55–65 % dark relief, continuous between the decks, with irregular edges.
     - **Steel islands.** Each panel holds 8–10 bare-steel discs, Ø 0.5–0.8 m, with a hook inside. Under the lights they are the brightest spots, and at 15–18 m they read as eyes or holes.
     - **雷纹.** The fret is a square-wave meander laid in rows. At 1:1 it reads as brick courses, not as square spirals.
     - **The top 5 m** (24.5–29.4 m) carry only a clip-art spiky sun and a crescent.
     - **Steel.** It is metallic 0.62, a deviation from the lead's 1.0, and its brushing cannot be seen at 2 m: the ORM G channel is visually flat.
     - **Deck levels.** The tiers ignore the dossier §1.3 soffits.
       - The plain bands sit at `PANEL_Y = (8.4, 17.0, 25.3)` (`tex_pillar.py:50-51`).
       - The soffits are at 7.2–9.0, 14.9–16.5 and 22.4–24.0 m.
   - Do (`blender/landmarks/tex_pillar*.py`):
     - (a) **Bands.**
       - Make four continuous relief bands that wrap the whole circumference, between the soffits: 0.6–7.2, 9.0–14.9, 16.5–22.4 and 24.0–29.4 m.
       - Keep plain steel only at the deck levels (7.2–9.0, 14.9–16.5, 22.4–24.0 m) and from 0 to 0.6 m.
       - No vertical steel seams.
       - The top and bottom edges of each band follow the dragon and cloud outlines (± 0.3 m), never a ruler line.
       - Spread the 9 dragons over the 4 bands, with the spiral continuing from band to band.
       - Target: bronze covers 55–65 % of the column.
     - (b) **雷纹.** Make it true square spirals: 2.5–3 turns per cell, cells 0.15–0.20 m, alternating hand, linked into chains.
     - (c) **No steel discs.**
       - Remove the round steel islands. Cloud hooks become raised bronze C/S scrolls, 0.04 m proud, with a 2–3 cm worn edge `#8A6A3E` → `#C9A66B`.
       - Bare steel inside a band: ≤ 10 %, in irregular slivers.
     - (d) **Sun and moon.** Make them archaic relief roundels, Ø 1.2 m (§1.2), with a raised rim and hooked rays, set in the top band. Not icon shapes.
     - (e) **Steel.**
       - Metallic 1.0, as §1.2 and L-ART2 require.
       - To stop it reading as a black mirror at night, give `dragon_pillar.tscn` its own ReflectionProbe (12 × 32 × 12 m, UPDATE_ONCE, warm interior ambient `#3A2E22`). Or put the deviation to the lead with an A/B capture pair.
       - Brushing in the roughness: streaks 1–3 mm wide and 5–40 cm long, amplitude ± 0.05.
   - Verify:
     - Hstack `pillar_mid` and `g_pillar_12` with `c_pillar.jpg`. At 15 m:
       - dark ornament dominates;
       - the dragons read (head, eye, claws);
       - there are no bright round spots and no rectangle edges.
     - Bronze coverage per metre (method in Evidence) is ≥ 70 % inside every band.
     - A 1:1 crop of the BC shows square spirals.

5. **The LED lines run down to the ground as solid white slabs, 2.4–3.6 m wide (ART §5 flat untextured surface, §10.6 blown-out).**
   - Evidence (`r4_sheet_tex1_s.jpg`):
     - `st_5m` P95 0.963: at street level a 3.6 m white plane fills a third of the frame.
     - `swfc_20m` P95 0.942.
     - `LED_Tower_CornerLines` spans y 0.0–579.6 and `LED_SWFC_Edges` spans y 0.0–492.
     - The corner strips are ±1.8 m (`build_shanghai_tower.py:128`), but the docstring at `:115` says 1.6 m.
   - Do:
     - Start the lines above the podium, as on the real towers: Shanghai Tower ≥ 40 m, SWFC ≥ 30 m.
     - Give the line material an emission texture: a dark backing `#15171C`, a bright 0.4 m LED core, and luminaire joints every 1.5 m (or a 0.3 m dot-pixel row), so at 5–20 m the line reads as a fixture.
     - The 1.3 km read stays, through the strip's width.
     - Fix the docstring.
   - Verify:
     - Cams `st_5m:1168,4,-40:1150,22,-42.5:62` and `swfc_20m:1312,200,-136:1262.2,210,-136:62`: ≤ 2 % of pixels above 0.95.
     - The Bund crop keeps P99 ≥ 0.55.

6. **[brief item 7] The Nanpu cables and deck LEDs do not meet the roads unit's `CableAnchor_*`.**
   - Evidence:
     - `game/world/data/road_furniture.json` (12:08) lists 156 `cable_anchors` for `road == "nanpu_bridge"`. In the bridge's local frame they sit at lateral ±7.5 m, y 42.85–45.85, every 9.6 m from −355.6 to 382.7.
     - The glb's cable deck ends are at |x| 14.8–15.0 (`NP_CABLE_DECK_X = 14.9`, `build_bridges.py:37`).
     - `LED_Nanpu_DeckEdge` (|x| 14.8) and `LED_Nanpu_UnderStrip` (|x| 14.0) follow the same 30.35 m width.
     - The roads lanes on the bridge are 2 + 2 × 3.75 m (offsets −2.88 and −6.62). So the cable feet and the blue and orange lines hang about 7 m outside the roads unit's edge girder.
     - The brief says: "read `road_furniture.json` when it exists". Nothing in `blender/landmarks/` reads it.
   - Do:
     - Read the anchors in `build_bridges.py` and convert them to bridge-local (anchor (1330, 1430), rotation_y −2.0203).
     - End each cable at its anchor, and run the deck LEDs along the anchor lines.
     - The two units disagree on the width (the dossier's 30.35 m against the roads unit's ≈ 15 m deck). Raise it in status → Requests to the roads unit and the lead, but ship geometry that matches the anchors.
   - Verify:
     - Test assert: every cable deck end lies within 0.3 m of an anchor.
     - In game (`g_spiral`, plus a deck-level cam on the main span): the cables land on the girder and the blue line sits on the deck edge.

## SHOULD-FIX
- **Jin Mao crown.** The spire is still the lattice "power pylon" from the r3 SHOULD-FIX; the real spire is a slim stepped needle (`swfc_jinmao_night_2009.jpg`). Every face of the crown glows at E3.5, so it blooms into one gold blob (`jinmao_crown` P95 0.822). Light the tier edges and the lattice lines, not whole faces.
- **The skyline from the Bund is still dark** (full frame P95 0.241 / SAT 0.16 %; crop SAT 0.97 % against the 1.5 % target; `trio_air` P95 0.263).
  - The facades are fogged by the env unit: `env_recipe.gd` `FOG_DENSITY 0.0035` against ART §4's 0.0012, about 99 % fog at 1.3 km.
  - Keep the request to the env unit and the lead open. The fixed ads (MUST-FIX 1) will add the saturated area.
- **The pillar light rig.**
  - One pillar takes 17 of the ≤ 48 real lights: 4 base, 12 wash and 1 under-deck.
  - The 12 wash spots aim horizontally at the column, so they flatten the relief and spill onto the decks.
  - In game `g_pillar_deck` ran at 38–41 fps; the other game views ran at 64–104.
  - Replace them with grazing spots under the soffits: 2 per deck level, 12.5°, range 10 m. That gives ≤ 10 lights.
  - Profile with `tools/godot.sh perf --skip-menu --spawn=<deck at the junction>`.
- **Stale evidence.**
  - The per-asset Blender night + studio previews in `captures/blender/` are from r1–r3 (22:38–07:27).
  - `captures/landmarks/side_*.jpg` are from 09:44, before this round's rebuilds, and `sheets.py` still pairs the `r3_skyline_*` captures.
  - Re-render all of them after the fixes.
- **Code.**
  - `landmark_lights.gd`: the header says the light "is turned to point along the empty's +Y"; `_aim()` says the light inherits the empty's transform.
  - `_aim()` aims nothing: the z basis vector of an orthonormal transform always has length 1, so its warning can never fire. Delete it or rename it.
  - Python-style `"""docstrings"""` in GDScript (3 in `landmark_lights.gd`, 12 in the tests) should become `##` comments.
  - `LED_Crown_Backdrop` duplicates `LED_Backdrop_Crown`.
- **Unused embedded images.** Twelve `facade_night_*` / `glass_bands_*` images (jin_mao, shanghai_tower, swfc, backdrop) are overridden at runtime by `apply_facade.gd`. Drop them from the glbs: fewer imports.
- **Duplicates.** 18 byte-identical extracted images remain, waiting on the lead's answer about `.gltf` with shared textures.
- **Lupu.** The arch's bright pixels have saturation median ≈ 0.41 at the `lupu` cam (r3 target 0.45). Raise the band saturation, or drop E to about 1.2 so AgX keeps the hue.
- **Scratch.** Scratch is left in `tmp/landmarks/` (`diag_blink.gd`, `diag_lights.gd`, `export/`, `pillar_look.py`). Delete it when done (lead rule). If `frame_stats.py` is a tool, move it into `blender/landmarks/`.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://assets/landmarks/` → `CHECK 21 files, 0 failed, 0 engine errors, 0 warnings`.
- **Tests:**
  - `test_landmarks.gd` → 63 PASS / 0 FAIL (`landmark_lights: 39 lights spawned`).
  - `test_landmarks_night.gd` → 61 PASS / 0 FAIL, rc 0.
- **Polycounts** (Blender import), all within budget, the pillar ≤ 60k:

  | asset | tris |
  |---|---|
  | OPT | 61,876 |
  | pillar | 59,902 |
  | Shanghai Tower | 58,148 |
  | Nanpu | 17,924 |
  | Jin Mao | 17,188 |
  | Lupu | 9,128 |
  | Waibaidu | 7,344 |
  | Pearl Ring | 5,216 |
  | backdrop | 3,660 |
  | SWFC | 1,952 |

  Only `LED_*` emitters and colliders are untextured.
- **r3 item 2 (spot-angle bug) is fixed:**
  - `spot_angle` is passed in degrees;
  - the uplights stand on the plinth rim, with housings and a plinth line;
  - in game the pillar reads under the decks (`g_pillar_12` P95 0.754);
  - ≤ 1.5 % of pixels are above 0.95 in every pillar frame.
  - **L-NIGHT3 OK.**
- **LED unfog:** all 10 wrappers (test 10/10); Bund crop P99 **0.880** (r3 target ≥ 0.55).
- **Pillar maps:**
  - wiring: `LM_PILLAR_Steel` BC 2048×4096 + MR/AO 2048×4096 + N 4096×8192;
  - real bevels, chevron scales and a deep fret at 2 m;
  - 9 different dragons climbing diagonally;
  - no emission on the relief (dossier DON'T respected).
- **OPT:**
  - the 0.4 m dot shell chases at 0.75 Hz and cycles pink → violet → blue over 40 s;
  - at 20 m (`opt_sphere20`) the glass, the silver band with its lit edge and the dot skin look right;
  - the dimensions match §6.1.
- **The trio from 300 m** (`r4_sheet_crowns_s.jpg`): the Jin Mao gold-white crown and setback bands, the SWFC aperture outline, and the Shanghai Tower corner lines with the crown ring all read.
- **Facades:** the facade shader (`lit_ratio 0.42`, cool / neutral / warm interiors, fins, mullions) reads at 5–100 m (`r4_sheet_tex1_s.jpg`, `tower100`).
- **Nanpu:**
  - H-towers with splayed legs (leg axis 21.0 m from the centreline at the footing, 17.2 m above the deck);
  - the red 南浦大桥 sign;
  - the legs reach P95 **0.806** at the spiral cam (r3 target ≥ 0.6);
  - in game, white legs from the spiral.
- **Lupu:** the seven-colour arch reads at 2.2 km.
- **Waibaidu:** rivets, chipping and rust streaks at 5 m, warm LED lines, and in game the truss sits on the roads unit's deck (`g_wb`).
- **IMPORT-CHURN:**
  - the worker's double build (`find -newer stamp`) changed 0 files;
  - the glb mtimes are staggered (jin_mao / swfc / tower 11:50, untouched by the 12:28 build);
  - only the hero pillar maps exceed 1024²;
  - the reported 83 images / 52 MB are confirmed, and `textures/` holds 356 KB.
- **Rules and ownership:**
  - every Write/Edit since the r3 review is under `blender/landmarks/**`, `game/assets/landmarks/**`, `status/landmarks.md`, `jobs/landmarks/` or `tmp/landmarks/`;
  - the temporary `tests/zz_diag_*.gd` were removed, and `/tmp/gd_sample.txt` is gone;
  - the tests extend Node, the GDScript is fully typed, and the largest file is `lmlib.py` at 399 lines.
- **Acceptance (a):** OPT front-left, the trio behind, the Shanghai Tower tallest and rightmost. (b), (c) and (d) are captured.

## Evidence
- **Commands** (from `~/m/skyrush`):
  - **Check and tests:** `tools/godot.sh check --only=res://assets/landmarks/`, then `tools/godot.sh test res://assets/landmarks/tests/test_landmarks{,_night}.gd`. The night output is in `tmp/review/lm_r4_test_night.txt`.
  - **glb audit:**
    - `tools/blender.sh run tmp/review/lm_stats.py` → `tmp/review/lm_r4_stats.txt` (tris, untextured materials);
    - `python3 tmp/review/lm_glbjson.py game/assets/landmarks/*.glb` → `tmp/review/lm_r4_glbjson.txt` (wiring, `es=8` on the beacons);
    - `python3 tmp/review/lm_r4_bbox.py <glb>` (node bboxes: the ads, the Nanpu, the OPT spheres).
  - **Blender preview:** `tools/blender.sh preview game/assets/landmarks/dragon_pillar.glb ../review/landmarks/bp_r4_pillar --views close_front34,front34 --light night` → `PREVIEW objects=6 tris=59902`. The only untextured materials are the 2 LED materials and the collider.
  - **Preview shots:** `tools/godot.sh shot --scene=res://assets/landmarks/preview_skyline.tscn --out=review_landmarks_r4 --env-only --warm=40 --cams="<29 cams>"` → `CAPTURE errors=0 warnings=0`, fps 51–154. These overwrote the worker's same-named `captures/review_landmarks_r4_<cam>.jpg`; copies are in `captures/review/landmarks/r4/`.
  - **Game shots:** `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --warm=120 --out=review_landmarks_r4 --cams="<8 cams>"` → fps 41–104.
    - 127 `uniform_set is null` render errors, not from this unit.
    - The first attempt hit a parse error in the world unit's `furniture_filter.gd`, which was being edited at the time; I retook the shots.
    - Some road and block glbs were "not imported yet" (other units' churn).
  - **Measurements:**
    - `python3 -I ref/art/lookdev/tools/screenshot_stats.py` on every shot (table below);
    - a PIL beacon probe at the projected beacon positions in `tops_a..d`;
    - bronze coverage per metre: `dragon_pillar_pillar_bc.jpg` luminance < 0.45, per 1/29.4 of the height;
    - the road anchors against the glb cable ends: `road_furniture.json` `cable_anchors` moved into the bridge frame, against the `LED_Nanpu_Cables` vertices with y < 47.5.
  - **Ownership:** `python3 tmp/review/lm_r4_logpaths.py jobs/landmarks/log.jsonl 2026-10-20T02:28`.
- **New cams** (`name:pos:look:fov`; the r3 list is reused for the rest):

  | cam | spec |
  |---|---|
  | pillar_deck5 | `-1292.5,10,682.5:-1299,11,687:60` |
  | wb_deck | `-139,5.6,-925:-141,7.5,-1005:70` |
  | st_5m | `1168,4,-40:1150,22,-42.5:62` |
  | st_20m | `1175,300,-42.5:1122.8,300,-42.5:62` |
  | swfc_20m | `1312,200,-136:1262.2,210,-136:62` |
  | ad_cmb | `752,80,-386:902,80,-386:50` |
  | ad_aurora | `880,70,-430:1004,70,-252:50` |
  | tops_a..d | `700,500,400:1170,520,-120:25` |
  | g_pillar_deck | `-1312,10.8,693:-1299,13,687:62` |
  | g_wb | `-150,6,-905:-141,7,-990:62` |
  | g_lujiazui | `400,30,-900:1100,250,-200:60` |

- **Frame stats** (dossier tool; targets P95 0.40–0.78, P99 0.55–0.97, SAT 2–15 %):

  | frame | P50 | P95 | P99 | SAT % |
  |---|---|---|---|---|
  | bund | .115 | .241 | .459 | 0.16 |
  | bund crop 250/150/1050/650 (full res) | — | .382 | .880 | 0.97 |
  | century | .103 | .394 | .778 | 0.02 |
  | spiral | .116 | .240 | .330 | 0.00 |
  | spiral, tower region 700/400/900/780 | .124 | .806 | .820 | — |
  | trio_air | .121 | .263 | .622 | 0.00 |
  | opt_400 | .121 | .392 | .673 | 0.99 |
  | opt_sphere20 | .131 | .468 | .818 | 0.04 (r3: 7.56) |
  | opt_out | .101 | .526 | .817 | 0.84 |
  | pillar_2m | .239 | .804 | .911 | 13.82 |
  | pillar_deck5 | .193 | .765 | .966 | 7.14 |
  | pillar_mid | .113 | .540 | .785 | 1.66 |
  | st_5m | .238 | .963 | .963 | 0.10 |
  | st_20m | .131 | .810 | .948 | 0.00 |
  | swfc_20m | .096 | .942 | .949 | 0.00 |
  | jinmao_base | .098 | .644 | .819 | 0.24 |
  | tower100 | .144 | .639 | .923 | 0.61 |
  | jinmao_crown | .145 | .822 | .937 | 0.30 |
  | swfc_ap | .150 | .556 | .912 | 0.28 |
  | st_crown | .125 | .365 | .786 | 0.08 |
  | nanpu_w_main | .094 | .395 | .703 | 0.03 |
  | lupu | .146 | .273 | .658 | 0.25 |
  | wb_side | .145 | .343 | .734 | 1.50 |
  | ring_street | .102 | .399 | .546 | 0.00 |
  | tops_a..d | .158 | .330 | .743 | 0.00 |
  | g_bund | .135 | .573 | .917 | 0.04 |
  | g_pillar_2m | .372 | .777 | .892 | 25.43 |
  | g_pillar_12 | .138 | .754 | .762 | 11.10 |
  | g_pillar_deck | .170 | .651 | .833 | 9.63 |
  | g_opt | .158 | .564 | .694 | 0.25 |
  | g_spiral | .141 | .264 | .421 | 0.00 |
  | g_wb | .170 | .337 | .527 | 0.19 |

- **Captures:**
  - shots: `captures/review/landmarks/r4/review_landmarks_r4_*.jpg` (29 preview, 8 game);
  - sheets: `captures/review/landmarks/r4_sheet_{accept,pillar,tex1,tex2,ref,crowns,game,misc}.jpg` (with `_s` 1280 px versions);
  - maps: `r4_pillar_tex.jpg`;
  - moiré crops: `r4_opt_moire.jpg`;
  - Blender: `bp_r4_pillar_night{,_close_front34,_front34}.jpg`.

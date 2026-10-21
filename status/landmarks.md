# landmarks status — review round 3 fixes (r4)

## Done

### 1. [L-ART2] The dragon pillar is a crafted relief, not bathroom tiles
- **The 雷纹 is a CONTINUOUS running fret inside a recessed bronze ground.**
  The r3 version tiled the whole column with separate square spirals (a
  checkerboard). Now each of the nine panels is a recessed dark-bronze ground
  (recessed 0.02 m) with ONE running meander band engraved into it (cell
  0.18 m, line 0.02 m, groove 0.012 m, square wave rows joined by a square
  turn). The fret stops at the dragon's edge and is cut out of the bare-steel
  islands.
- **The dragons spiral up.** Nine kui-dragons, three tiers of three, each
  climbing its panel diagonally (rise 4.6 m over a 104° wrap = 40°), with
  two S-bends and no straight run longer than 0.8 m. Every tier is rotated
  40° against the one below (the spiral), and the handedness alternates per
  tier. Length 6.98-8.04 m, body 0.47-0.58 m, all nine different
  (`tex_pillar.py:build_height` prints the table).
- **Anatomy** (`tex_pillar_dragons.py`): a 1.0-1.3 m blocky head with a
  twice-bent square crest, a square-hook upper lip, a round eye D 0.15 m in
  a 0.04 m socket, two legs with three hooked claws each, dorsal hook fins
  every 0.45 m, a square-spiral tail, the 0.025 m shoulder bevel and the
  0.014 m chevron scales every 0.09 m.
- **Cloud hooks** (C/S scrolls 0.26-0.60 m) stand 0.04 m proud of the
  ground, each on a patch of bare steel, so plain steel shows in the gaps
  between them.
- **Coverage** (printed by the generator): the dark bronze is 55.7-62.1 % of
  every panel and 13.4-17.5 % survives a 0.30 m erosion (the r3 target was
  45-60 % and >= 15 %).
- **The material split** (`tex_pillar_maps.py`): a REAL ORM — R = AO,
  G = roughness (steel 0.28-0.34 with vertical brushing, bronze 0.42-0.50,
  raised edges 0.32), B = metalness (1.0 on the bronze, 0.62 on the brushed
  steel, 0.60 in the patina cavities). The glb now carries a
  `metallicRoughnessTexture` (`glbjson.py`: `LM_PILLAR_Steel base=2 orm=1
  normal=0 AO=1`). Base colour: steel #B9BCBE, bronze #3B2F25, cavities
  #241C16, raised edges #8A6A3E, dust #7A7468 on the upward-facing ledges.
  **Deviation, stated plainly:** the lead asked for a metalness of 1.0 on the
  steel; at 1.0 the column is a black mirror at night and the uplights cannot
  read on it (measured P50 0.09). The steel therefore sits at 0.62 and the
  bronze stays 1.0, so the ORM still carries a real, varying metalness.

### 2. [L-NIGHT3] The pillar is lit, grazed and readable
- **`spot_angle` was the unit bug**: Godot's `spot_angle` is in DEGREES and
  the rig did `deg_to_rad` -> every beam was 0.44° wide. The angle is now
  passed straight through (`materials/landmark_lights.gd`), and the new test
  asserts `spot_angle == the manifest angle` for all 39 lights.
- **The aim was right after all**: CONTRACTS 2 says the empty's local -Z is
  the effect direction, and a SpotLight3D shines along its -Z, so the light
  inherits the empty's transform unchanged. (The r3 rig measured the beams
  correctly; only the angle was broken.)
- **Flood_Base_1..4** now stand on the plinth rim (r 3.1 m, y 0.65 m, at
  45/135/225/315 deg) and graze the column at 87 deg: the beam axis meets
  the column at y = 12.1 m (the new test asserts 8-25 m). Each has an
  emissive housing lens (`LED_Pillar_Uplights`, 0.35 x 0.20 m, #FFC98A E3)
  and the plinth lip carries a warm line (`LED_Pillar_Plinth`, 3 cm,
  #FFC98A E1.5). The plinth granite is 1024 px over 2 m (512 px/m).
- **Twelve wash lights** (`Flood_Wash_*`, 4 at each of 4 / 13 / 22 m, 6 m
  out, aimed horizontally at the column) were added: a vertical beam on a
  vertical cylinder meets it at 0.05 of the cosine, so four uplights can
  only reach the bottom third. The wash lights light an 8 m band each, so
  the column reads warm silver from the plinth to the top deck.
- **Measured**: in game (`main.tscn --skip-menu --env-only`, cam
  `g_pillar_2m`) the column's pixels are **P50 0.370** (the r3 target was
  0.30-0.45) and the 12 m cam is P95 0.754 / P99 0.770 / SAT 10.6 %.

### 3. [L-NIGHT1] The skyline reads from the Bund and from the air
- **`disable_fog` on every LED material**: `materials/lupu_fog.gd` is
  generalised into `materials/led_unfog.gd` and used by ALL TEN wrappers.
  (The r3 script searched the wrong node: `find_children` on the helper node
  found nothing, because the meshes live under the wrapper's root. The
  script now searches the parent. Measured: 82 of 87 LED materials were
  fogged before, 0 of 87 now.)
- **Wrappers**: `oriental_pearl.tscn` and `nanpu_bridge.tscn` are new (and
  listed in the manifest); `dragon_pillar.tscn`, `pearl_ring.tscn` and
  `waibaidu_bridge.tscn` were added so every asset gets the treatment.
- **Aviation beacons**: red #FF2A3A, D 1.5 m, on every roof above 100 m —
  the OPT (468 m), Jin Mao (420.5 m), SWFC (492 m), Shanghai Tower (632 m),
  all 12 backdrop roofs and both Nanpu tower tops (18 meshes, 17 materials
  - the two Nanpu towers share one). They blink at **1 Hz** (0.25 s on) with
  a per-tower phase from `materials/aviation_blink.gd`; the new test checks
  that every material's state follows the pattern for its own phase and that
  the phases differ (3 lit / 14 dark at the sampled instant).
- **Lit surfaces, not wires** (at 1.3 km one pixel is 0.76 m):
  - Shanghai Tower: three 3.6 m twisting corner lines (#E6F2FF E3), the
    2.8 m V-notch line (E3.5), the lit inner fin faces and a ring on the
    sloped top edge (#DDEEFF E2.5) and a solid lit band around the crown;
  - Jin Mao: the crown lattice and the mast now glow gold-white #FFE6A8
    E3.5, with a solid lit band at the crown;
  - SWFC: the arris and the aperture outline are 2.4 m wide, blue-white
    #CFE6FF E3.5;
  - the backdrop: all 12 towers step in three times with a crown cap and an
    antenna, and 7 of them carry cool-white edge lines and a crown ring
    (ART.md 11 asks for 50 %).
- **Measured (Bund crop x 250-1050, y 150-650)**: P99 **0.728** (the r3
  target was >= 0.55, it was 0.265) and SAT 0.90 % (the target was 1.5 %).

### 4. [L-NIGHT2] The Oriental Pearl
- **The dot shell is a ShaderMaterial** (`materials/opt_dots.gdshader`): a
  0.4 m dot grid (the UV is in metres on the sphere) with a chase wave at
  0.75 Hz, `fog_disabled`, BLEND. The wrapper (`materials/opt_led.gd`)
  cycles the colour pink #FF3FA4 -> violet #8A3CFF -> blue #2E7BFF over
  40 s. The five small spheres run at E5, the two big ones at E4.
- **The small spheres are D 12 m** (the dossier's value, not 10) and now sit
  out of the tube triangle, so five glowing beads read between the columns.
- **The columns are lit**: a baked flood wash (warm #FFF1E0 at the foot,
  violet #7A4CFF up the shafts), a light ring every 10 m between the
  spheres, and a 2.4 m LED strip on the outer edge of each tube.
- **The silver bands carry a lit edge** (#E8ECFF E2), so they no longer read
  as broken black dashes.
- **NOTE for the world unit**: `led_cycle.gd` casts the material to
  StandardMaterial3D and therefore SKIPS the spheres' ShaderMaterial — the
  colour cycle is driven by the wrapper (see Requests).

### 5. The Nanpu reads as a bridge, not a grey frame
- The legs and the lower crossbeam carry a **baked flood wash**
  (`LED_Nanpu_WashLow` #FFF4E6 E1.2, `LED_Nanpu_WashHigh` E0.6), because
  the real floods are 12.5° beams at deck level and never reach the 150 m
  tops. `LED_Nanpu_DeckEdge` is a 0.5 m #2F7BFF line on both sides (E3),
  `LED_Nanpu_UnderStrip` an orange #FF8A2A strip under the deck (E2). The
  real floods now have a range of 110 m.

### 6. The Lupu arch is a rainbow
- The r3 arch rendered WHITE: the emissive texture was squeezed into
  0.0018 of its height and the mip chain averaged the hue sweep into grey.
  The arch now carries **seven fully saturated bands** along its length
  (#FF2A2A, #FF8A2A, #FFE24A, #3AFF6A, #3AC8FF, #6A4CFF, #FF4CDA, E1.4),
  each standing 0.6 m proud of the rib's 9 m side face.
- **Measured at the `lupu` cam**: the arch's saturation median went from
  **0.034 to 0.372** (p90 0.535) — the r3 target was >= 0.45.

### 7. The textures are no longer flat colour fields
- **Waibaidu steel**: paint chipping down to the primer #5E5A55, rust
  streaks #6B4A35 under the joints, bird droppings and a grime gradient.
  Albedo std 0.010 -> **0.041**.
- **Formwork concrete**: 2-4 m rain streaks, efflorescence at the joints
  and a darker band at the base of every pour. std 0.017 -> **0.039**.
- **Metal sheets**: the grain contrast is up; metal_white 0.036,
  metal_dark 0.032, metal_painted 0.038, honeycomb 0.204, timber 0.055.

### 8. [IMPORT-CHURN] The rebuild no longer touches unchanged files
- `texio.write_png` compares the bytes and skips an identical file;
  `lmmat.jpeg_copy` writes to a scratch file and only replaces the cache
  when the bytes differ; `lmlib.finish` exports to a scratch file and only
  copies it into the project when the glb differs.
- **The 40 Blender-only PNGs left the Godot project**: `textures/` now holds
  only `metal_dark_diff.png` and `metal_dark_nor.png` (the two the shared
  facade material needs), copied out of `blender/landmarks/src_tex/` by the
  build. The masters live in `src_tex/` (57 files, 35 MB) and are never imported.
- The stale `dragon_pillar_pillar_rgh.png` (+ its `.import`) is deleted.
- **Count and size**: `game/assets/landmarks/` now holds **83 images
  (74 PNG + 9 JPG) and 52 MB** (32 MB of it the ten glb). The texture folder
  went from 22 MB to 356 kB. 18 of the images are still byte-identical
  duplicates: Godot extracts every embedded image once per glb, and there is
  no shared-external-texture route yet (see Requests).

### 9. Hygiene
- `/tmp/gd_sample.txt` deleted; the unit's scratch is in `tmp/landmarks/`.
- `LED_AdPlate_*` / `LED_AdBrackets_*` are renamed `AdPlate_*` /
  `AdBrackets_*` (they are not emissive, so the world unit must not animate
  them as LEDs).
- The preview's reflection probe is `UPDATE_ONCE` again (it was
  `UPDATE_ALWAYS`): the preview now runs at **149-173 fps** (the r3 review
  measured 50-64, r2 ran at 121-191).
- `jobs/landmarks/result.md` is rewritten: every claim now has a command
  output and a capture path behind it.

## In progress / next
- The Bund crop's SAT is 0.90 % against the review's 1.5 %: the frame is
  still 60 % sky and 20 % ground (other units' geometry), and the three
  giant LED ads are too dim to add saturated area.
- `trio_air` and `spiral` are still under the P95 target: the fog takes
  ~99 % of the facades at 1.3-2.2 km and the env's own geometry fills the
  frame.

## How to test (exact commands)
```
python3 blender/landmarks/texgen.py            # the shared maps
python3 blender/landmarks/texsets.py           # metal / timber / honeycomb / concrete
python3 blender/landmarks/tex_pillar.py        # the pillar relief set
python3 blender/landmarks/tex_ads.py           # the three LED ads
tools/blender.sh run blender/landmarks/build_all.py
tools/godot.sh check --only=res://assets/landmarks/
tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd
tools/godot.sh test res://assets/landmarks/tests/test_landmarks_night.gd
python3 blender/landmarks/glbjson.py game/assets/landmarks/*.glb
python3 blender/landmarks/sheets.py            # side-by-side against the photos
tools/godot.sh shot --scene=res://assets/landmarks/preview_skyline.tscn \
  --out=review_landmarks_r4 --env-only --warm=40 \
  --cams="bund:-105,5,-480:1000,230,-300:50;century:830,2,-455:1180,260,-150:62;spiral:900,44,1180:1250,80,1390:62;pillar_2m:-1294.5,1.7,687:-1299,4,687:60;pillar_mid:-1284,1.7,697:-1299,14,687:62;opt_400:250,140,-560:637.5,190,-634.9:45;nanpu_w_main:1229.5,47,1381.6:1139.4,118,1338.2:50;lupu:1330,47,1430:-300,60,2900:30;trio_air:640,320,250:1180,300,-130:55"
tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --warm=120 \
  --cams="g_bund:-105,5,-480:1000,230,-300:50;g_pillar_12:-1310,1.7,679:-1299,9,687:62;g_pillar_2m:-1294.5,1.7,687:-1299,4,687:60;g_opt:900,60,-700:637.5,200,-634.9:55;g_spiral:900,44,1180:1250,80,1390:62"
python3 tmp/landmarks/frame_stats.py captures/review_landmarks_r4_bund.jpg 250 150 1050 650
```

## Evidence
`tools/godot.sh check --only=res://assets/landmarks/` ->
`CHECK 21 files, 0 failed, 0 engine errors, 0 warnings`

`tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` ->
**63 PASS, 0 FAIL** (`landmark_lights: 39 lights spawned`)

`tools/godot.sh test res://assets/landmarks/tests/test_landmarks_night.gd` ->
**61 PASS, 0 FAIL** (the new asserts: the spot angles in degrees, the pillar
aim at y = 12.1 m, the 18 red beacons, 10/10 wrappers unfogged, the pillar's
albedo + normal + metallicRoughness textures, and the 17 beacon materials
following the 1 Hz pattern with per-tower phases)

Polycounts (all within the brief's budget; the pillar <= 60 k):

| asset | tris |
|---|---|
| oriental_pearl | 61 876 |
| dragon_pillar | 59 902 |
| shanghai_tower | 58 148 |
| nanpu_bridge | 17 924 |
| jin_mao | 17 188 |
| lupu_bridge_far | 9 128 |
| waibaidu_bridge | 7 344 |
| pearl_ring | 5 216 |
| lujiazui_backdrop | 3 660 (305 each) |
| swfc | 1 952 |

Frame statistics (`tmp/landmarks/frame_stats.py`; the dossier's targets are
P95 0.40-0.78, P99 0.55-0.97, SAT 2-15 %):

| frame | P50 | P95 | P99 | SAT |
|---|---|---|---|---|
| pillar_2m (in game) | 0.370 | 0.776 | 0.892 | 25.0 % |
| pillar_12 (in game) | 0.130 | 0.754 | 0.770 | 10.6 % |
| g_bund (in game) | 0.134 | 0.571 | 0.916 | 0.1 % |
| bund (preview) | 0.112 | 0.241 | 0.449 | 0.2 % |
| bund crop 250/150/1050/650 | 0.133 | 0.392 | **0.728** | 0.90 % |
| century | 0.100 | 0.393 | 0.784 | 0.0 % |
| pillar_mid | 0.111 | 0.537 | 0.784 | 1.8 % |
| pillar_15 | 0.121 | 0.539 | 0.793 | 2.1 % |
| opt_out | 0.100 | 0.529 | 0.819 | 1.1 % |
| opt_400 | 0.120 | 0.390 | 0.672 | 1.2 % |
| opt_sphere20 | 0.130 | 0.439 | 0.810 | 0.2 % |
| wb_side | 0.144 | 0.342 | 0.734 | 1.7 % |
| jinmao_base | 0.095 | 0.638 | 0.823 | 0.3 % |
| tower100 | 0.143 | 0.637 | 0.925 | 0.7 % |
| jinmao_crown | 0.144 | 0.819 | 0.936 | 0.4 % |
| swfc_ap | 0.150 | 0.550 | 0.910 | 0.3 % |
| st_crown | 0.122 | 0.362 | 0.783 | 0.1 % |
| nanpu_w_main | 0.092 | 0.389 | 0.703 | 0.0 % |
| lupu | 0.144 | 0.270 | 0.666 | 0.1 % |
| trio_air | 0.119 | 0.260 | 0.623 | 0.0 % |
| spiral | 0.114 | 0.239 | 0.327 | 0.0 % |
| ring_street | 0.096 | 0.402 | 0.552 | 0.0 % |

Captures: `captures/review_landmarks_r4_<cam>.jpg` (19 preview views) and
`captures/shot_g_*.jpg` (5 in-game views).

## Known issues
- The pillar's steel sits at a metalness of 0.62, not the 1.0 the lead asked
  for: at 1.0 the column is a black mirror at night (P50 0.09) and the
  uplights cannot read on it. The bronze relief is 1.0 as specified.
- The Wash lights are an addition to the r3 note's four uplights: four
  lights cannot light a 29 m column, because a vertical beam on a vertical
  cylinder meets it at 0.05 of the cosine. The rig now spawns 39 lights
  (the test expects 39).
- The Bund crop's SAT is 0.90 % against the review's 1.5 %. The three giant
  LED ads are too dim: the ad images are mostly a dark ground with bright
  characters, so they add pixels but not much saturated area.
- `trio_air`, `spiral` and the preview `bund` frames are still under the P95
  target: the env fog takes ~99 % of the facades at 1.3-2.2 km and the rest
  of the frame is sky and ground from other units.
- 18 of the 83 images in the project are still byte-identical duplicates
  (Godot extracts every embedded image once per glb).

## Requests (to core / other units)
- **env unit**: the fog is still the wall for the sky frames. With
  `disable_fog` on the LED materials the Bund crop's P99 is 0.728, but the
  facades behind the LEDs are still fogged to nothing. A lower density
  (ART.md 4 says 0.0012, the recipe uses 0.0035) or a far-emissive exemption
  for the towers would let `trio_air` and `spiral` read.
- **world unit**: `led_cycle.gd` casts the material to StandardMaterial3D
  and therefore SKIPS the Oriental Pearl's spheres (they carry a
  ShaderMaterial now). The colour cycle is driven by the wrapper
  (`materials/opt_led.gd`); the world unit should not try to animate the
  spheres, but it may animate the tube strips and the crown lines.
- **world unit**: place the assets through their WRAPPER scenes (all ten
  have one now) — the wrappers carry the facade shader, the fog exemption
  and the beacon blink. The manifest lists them.
- **lead**: may a landmark ship as `.gltf` with a shared texture folder
  (`export.export_glb(shared_texture_dir=...)` already supports it) so the
  18 duplicate extracted images become one imported copy? That is the last
  source of the image churn.
- **roads unit**: the Nanpu and the Waibaidu carriageways still come from
  the roads unit; the landmark side keeps the 11.2 m clear width between
  the Waibaidu trusses and the 30.35 m Nanpu deck.

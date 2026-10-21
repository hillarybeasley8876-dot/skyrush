# bund review round 3 — VERDICT: FAIL

Reviewer: lead / art director, 2026-10-20 13:10. Judged against briefs/bund.md, reviews/bund-lead.md (IMPORT-CHURN and
B-ART1..4 are mandatory), reviews/bund-r2.md, SPEC/ART/CONTRACTS, SHANGHAI_DOSSIER §5.3/§5.4, art DOSSIER §3.4/§3.7,
the reference photos and my own 23 preview captures (captures/review/bund/r3/). The user asked "贴图纹理什么都要细化".
Real progress: the row is warm at last (photo-angle facade #835F49 vs r2 #36353D), the granite is a real scan with
grain and V-grooved rustication, the domes are closed, every mesh has a material, the bull stands on the deck, the
dials have numerals. But the far-field fix painted every facade with a comb of vertical light spikes, the gradient is
upside down (dark crown, dim base), half the side/rear glass faces inwards, the HSBC has 4 lopsided portico columns
and a drum whose 16 columns are buried, street-level glass is black, and the trim sheet is ~85 % blank.

## Scores (0-10)
- function: 6 — loads, check 0 errors, test 51/0, 25 nodes at dossier z/heights, sidecar sane, 873,575 tris,
  119–189 fps; BUT glass culled on one flank of every building and ~80 % of rear panes, Broadway Mansions stage
  walls misplaced, HSBC portico bug, buried drum columns, a dead bull check, no road in the preview.
- visual: 4 — warm row, good granite at 2–5 m, real grooves and pediments; but the picket-fence wash on every facade
  at 20–400 m, inverted base/crown gradient, HSBC dome unreadable with a halo, Customs shaft grey, pyramid and BoC
  roof dark from the river, flood wall a thin line in the classic view, black shopfronts, void foreground.
- code: 4.5 — clean modules, deterministic, typed GDScript; but 2 files > 400 lines, 21 unused imports/locals, dead
  constants and test helpers, the winding bug, unconditional texture writes (lead note), scratch in game/tmp/, and
  false status claims for the third round.

## Lead notes
| note | status | evidence |
|---|---|---|
| IMPORT-CHURN (1) write only when bytes change | FAIL | `texbase.save` always writes (MF8) |
| IMPORT-CHURN (2)(3)(4) sizes, shared maps, no scratch in game/, report count+MB | FAIL | 168 imported maps (89 source + 79 glb copies), granite_0 imported 3×, 4096² blank trim ×3, game/tmp/bund/probe*.gd, status counts 89 (MF7, MF8, MF10) |
| B-ART1 gold from light; base + crown brightest; dark lines under cornices | FAIL | stripes, inverted gradient (MF1) |
| B-ART2 relief | PARTIAL | grooves 0.15/0.09 ✓, pediments ✓, cornices ✓, front recess 0.30 ✓; HSBC 4 columns lopsided ✗ (MF3a), BM stage recess 0.05 m ✗ (MF2) |
| B-ART3 cascades reflected; dials backlit; pyramid teal | PARTIAL | dials ✓; cascades near ✓ but 0.37 % of the classic view (MF5); pyramid luma 57 vs 126 (MF3c) |
| B-ART4 dark reflective glass, ≈ 25 % amber, never black holes | FAIL | shopfronts #07080C (MF4); culled panes show the grey core (MF2) |

## MUST-FIX

1. **The facade light reads as a comb of vertical spikes, the gradient is upside down, the wash paints over the
   windows (B-ART1; brief acceptance "the row must read warm gold").**
   - Evidence: `wash_cone.png` is a V whose lit width grows from 0 % at the bottom to 100 % at 42 % from the top, and
     `wash._card` maps v 0→1 from the ground to cornice + 1 m, so the dark wedges between neighbouring uplights reach
     ≈ 19 m on the HSBC (33 m card) and ≈ 40 m on the Bank of China (69 m card). Every facade in `photo_hsbc`,
     `photo_peace`, `river_mid`, `far100`, `mid20` and your own compare_12/13/20/23/0 is a picket fence of spikes;
     hsbc_customs_night_2026.jpg and peace_hotel_boc_night_2026.jpg show a continuous gold wash. The cone is also
     zero at its apex and flat with height (0.72–0.87), so nothing makes the base or the crown brightest. Measured on
     `hsbc_front` (x 1180–1400): attic/crown band rows 260–335 luma 58–65, R−B −5…12 (cold grey); upper floors
     158–163; lower floors and base 83–122 — the reverse of the reference (base and crown brightest, dossier §5.4).
     The cards sit 0.06 m in front of the wall and span the openings, so orange shafts stand inside the black
     shopfronts and every pane under a cone is tinted (`crops_wash_dome.jpg` left = `mid20` ground floor).
   - Physics to follow (art dossier §3.4): a 45° uplight 1 m off the wall aimed 80° up hits the wall from 1.6 m;
     its axis lands at 5.7 m where the pool is ≈ 4.8 m wide, so with 5 m spacing the scallops close ≈ 6 m above the
     lamps and above that the wash is continuous, falling off with distance.
   - Do: (a) one wash card per facade (or per bay) whose emission map is a light map baked in metres (numpy,
     0.25 m/px): accumulate every `Uplight_*` of the building (E = cos(incidence)/d² × smooth 45° cone) so scallops
     exist only in the first ≈ 6 m, ≈ 35 % of the base level at 25 m; add a cornice-grazer band (the 2.5 m under the
     main cornice + the attic) at ≥ 1.3× the mid-facade; multiply by a window mask (0 inside every window/shopfront
     rect — reuse the edge lists of `facade.front_wall`) and a cornice-shadow mask (0.4 in the 0.8 m under every
     cornice/string course). Per-bay cards built around the openings with `walls._columns/_subtract` and a cone
     authored in metres are acceptable if they pass the verify. (b) Colour: lit stone reads #835F49 in `photo_hsbc`
     vs #936E34 in the photo (R−B 55 vs 75, p95 178 vs 234): use the dossier §5.4 floodlight #FFC873 for the facade
     wash and #FFE2A8 at the crown so the stone reads gold, not salmon. (c) Keep the real spots in the near field.
   - Verify: `tools/godot.sh shot --scene=res://assets/bund/preview_bund.tscn --out=review_bund_r4 --warm=45
     --cams="photo_hsbc:300,3,-305:-135,30,-300:20;photo_peace:290,3,-585:-155,42,-585:20;hsbc_front:-88,10,-268:-130,22,-268:62;mid20:-112,1.7,-300:-133,9,-300:62;far100:-60,6,-520:-157,35,-569:55"`
     → no dark wedge between bays higher than 6 m on any facade; on `hsbc_front` the crown/attic band ≥ 1.3× and the
     first 6 m ≥ 1.2× the mid-facade luma, R−B ≥ 60 on all lit stone; `photo_hsbc` band x 384–1274, y 417–604:
     median within ±15 % of the reference band (#936E34, luma p50 114, R−B 75) and p95 ≥ 210; unlit panes under the
     wash ≤ luma 40 in `mid20`; no light shaft inside any opening.

2. **Half the side glass and ~80 % of the rear glass face into the building (invisible), the Broadway Mansions
   stages have their back wall on the front, the side mullions are off-centre (r2 MF3 not done; B-ART4).**
   - Evidence: `walls.opening_wall` emits every pane in the same vertex order whatever `sign` is (axis "X" panes
     always face +X, axis "Y" panes always face −Y) and `_bar` ignores `sign` too; `recalc_face_normals` cannot
     orient a lone quad. Counted on the Bund_Window_* triangles of bund_buildings.glb
     (`python3 tmp/review/bund/glasswall.py`): rear walls 2,592 facing in / 622 out; side walls 3,312 in / 3,052 out.
     Back-face culling hides them: the HSBC rear (`rear_hsbc`, `crops_cull.jpg` left) shows the grey core in almost
     every opening. `buildings._ziggurat` builds the "back" wall of each stage at plane 0.0 with sign −1, i.e. a second
     wall 0.35 m proud ON the front (stage glass at x +0.30 and −0.30, recess 0.05 m), while the stage backs
     (x −28 / −20.8 / −14.4) are blank boxes; its side walls pass sign +1 at −hw and −1 at +hw (inverted).
     Mullions: `u = uc - uh + uh * f` puts both bars in the left half of every side/rear/BM opening.
   - Do: wind panes and bars from `sign` (reverse the vertex order for sign < 0 on X and sign > 0 on Y, or build
     the quad from the wanted normal); `_ziggurat`: back wall at x = −hd with sign −1, the y = −hw wall with sign −1,
     the y = +hw wall with sign +1; mullions at `uc - uh + 2 * uh * f`; add a build-time assert in build.py: for
     every Bund_Window_* face, normal · (face centre − core centre) > 0 in plan, else raise.
   - Verify: glasswall.py prints 0 "in" for side and rear; `rear_hsbc` (-232,3,-238 → -195,18,-268, 62), `sidest`
     (-112,1.7,-221 → -160,9,-226, 66), `nanjing` (-138,1.7,-541 → -200,10,-541, 66) and `bm_back`
     (-250,62,-1125 → -178,52,-1051, 55) show glass (dark or amber) in every opening, `bm_front` 0.30 m recesses.

3. **The three landmarks the lead judges are still not unmistakable (brief acceptance).**
   - (a) HSBC: `trim._portico_bays` returns 4 positions for n = 6 (one entry per gap): y −15.5, −5.5, 0.0, +5.5 —
     four columns, lopsided under the centred pediment (`hsbc_front`). Do: 6 columns single-double-double-single,
     symmetric, pairs ≈ 1.8 m on centre (e.g. −15.5, −6.3, −4.5, +4.5, +6.3, +15.5 for the 31 m span). The 16 drum
     columns of `roofs.dome_drum` stand at r 5.58 inside the solid drum of r 6.0 — invisible (status says "16 paired
     Ionic columns"): put them at r + 0.45 in front of the drum wall (or shrink the drum to r − 1.0). The dome is
     pale grey with a flat crown card that floats outside its silhouette as a halo (`crops_wash_dome.jpg` right);
     hsbc_customs_night_2026.jpg: a gold ribbed dome on a colonnaded drum, the brightest part of the HSBC.
   - (b) Customs House: the shaft below the clock stage is grey (`customs_close` x 700–840, y 600–700: median
     #39373D, luma 56, R−B −5); the photo has the whole tower gold. Do: crown floods on the main roof aimed up all
     four shaft faces + the clock stage brightest.
   - (c) Peace Hotel pyramid from the river (`photo_peace`, cam 290,3,-585 → -155,42,-585, fov 20): teal pixels
     median #1B423F, luma 57 vs #0A9D75, luma 126 in peace_hotel_boc_night_2026.jpg (near, `peace_close`: #2C7F63).
     Do: emission E ≥ 4 at the eaves → 1.5 at the apex, hue #21C08B, and keep it readable through the fog (like the
     wash) or brighter.
   - (d) Bank of China: the teal hip roof (152 tris, y 69.8–79.2) is a dark flat cap in `boc_river` and
     `photo_peace`. Do: lit eaves/ridges in green-teal + a gold flood on the Deco crown below, readable from the river.
   - (e) Crown wash: replace the flat crown cards (ghost outlines when the camera moves) by 1.02× shells of the crown
     meshes (dome, drum, cupolas, clock stage, BM setbacks) with the additive wash shader and a base→top gradient,
     so the glow follows the form from every side.
   - Verify: `photo_hsbc` and compare_12: gold dome on a visible colonnade, 6 paired columns; compare_13: Customs tower
     gold from the main roof to the mast; `photo_peace`: pyramid teal median luma ≥ 100; `boc_river`
     (-40,10,-625 → -154,60,-600, 50): the BoC eaves read against the sky; no halo outside any crown silhouette.

4. **Street-level glass is black (B-ART4 "never black holes").** `stone2m` (-130.7,1.6,-290 → -133.2,1.4,-290.4,
   60): 38 % of the frame is below luma 12, the shopfront glass is #07080C; the unlit upper panes in `mid20` are
   near-black too. The Bund's ground floors are banks, hotels and shops with lit lobbies (zhongshan_e1_road_2015.jpg,
   bund_walkway_hsbc_2019.jpg).
   - Do: ground-floor shopfronts and doors lit (warm #FF9F40 interiors, ≥ 60 % of the ground-floor openings, a
     lobby/door cell in the interior atlas); unlit glass: albedo ≥ 0.12 linear, roughness 0.08, a faint interior
     (atlas emission ≈ 0.05) so frames and curtains read.
   - Verify: `stone2m`/`close5`: no area > 2 % of the frame below luma 12; `mid20`: unlit panes p50 ≥ 18.

5. **The flood-wall curtains vanish in the classic view (B-ART3).** In `photo_hsbc` blue pixels are 0.37 % of the
   frame, the band 15 rows tall, p90 luma 110; hsbc_customs_night_2026.jpg: 7.5 %, p90 151, separate curtains from
   the coping to the water plus long reflections. Near (`flood`, -45,1.6,-340 → -79,1,-330) the modules read; from
   the Pudong bank only the top ≈ 2.5 m glows.
   - Do: every 6 m module lit from the lip (y 2.5) down to the water (y −3), #29D3FF at the top → #1E8BFF at the
     foot, dark gap ≥ 1.5 m between modules, E ≥ 4, readable through the fog; the preview water must streak them.
   - Verify: `photo_hsbc` blue ≥ 1.5 % of the frame, band ≥ 30 px tall, p90 ≥ 140; compare_floodwall shows separate
     curtains and their reflections at the photo angle.

6. **The preview cannot show the driver's view (brief evidence: "from the road, heading north and south").**
   `road_n` (-101,1.3,-230 → -126,5,-330, 70) and `road_s` (-139,1.3,-640 → -150,10,-545, 70): the lower half is a
   featureless void; `PreviewWater` (x −100…680) shows as a canal 5.5 m below the road between the carriageway and
   the deck wall, with a white specular blob; in `photo_hsbc`/`river_mid` the river carries big white blobs (the
   deck OmniLights' specular on the water) instead of gold streaks.
   - Do: a road under the camera — instance the roads unit's tiles under the Bund read-only (roads_*.glb covering
     x −190…−40, z −1080…0) or a 20 m asphalt ribbon along `data.ROAD_PATH_EXT` with the shared `asphalt_02` maps,
     plus the 6 m sidewalk; start the water at the flood-wall face; deck lamps `light_specular = 0` (or range ≤ 8 m).
   - Verify: `road_n`/`road_s` show asphalt and lane lines, no canal; no white blob > 20 px on the water in
     `photo_hsbc`; the facades reflect as warm streaks.

7. **Textures: the hero granite is fixed, everything around it is still flat ("贴图纹理什么都要细化").**
   - Evidence (numpy on game/assets/bund/textures, `textures.jpg`): `trim_sheet` 4096² ×3 maps is ≈ 85 % blank
     #ACAAA0, high-pass grain 2.4/255, normal tilt mean 1.1° (median 0.7°) — no egg-and-dart, dentils, bead-and-reel,
     acanthus (r2 MF6c still open) while costing ≈ 270 MB VRAM; `bronze` olive camouflage blotches #68613F, grain 2.0,
     tilt 0.6° (the bull renders black); `iron_dark` tilt 0.8°; `roof_tar` grain 2.0, tilt 0.7°; `tile_coffee` (the
     whole Broadway Mansions) grain 3.6, a flat orange grid; `grass` grain 3.0; `paving` has a dark strip down the
     tile that repeats as black rectangles across the deck (`prom_along`, `bull`). Good: granite_0/1/2 grain 26–30
     (scan 37), tilt 4.4°; brick 9.8°; paving 3.8°; wall 5.8°.
   - Do: trim sheet (2048², or 4096² only when filled) with ≥ 10 carved bands (egg-and-dart, dentil, bead-and-reel,
     acanthus, guilloche, flute, Greek key, rope, console/keystone, volute) as height → normal (tilt ≥ 3°), the
     granite grain multiplied in (std ≥ 15) and AO in the crevices; bronze: patina #3A3226/#4C5A3E with polished
     #B58B4F horns/nose/hooves via roughness 0.25 vs 0.6, normal ≥ 2°; cast iron with paint chips and rust streaks
     (≥ 2°); roof felt with seams and gravel (≥ 2°); Broadway Mansions brick/tile with per-unit hue ±8 %, recessed
     joints, soot (≥ 3°); paving without the strip (random slab tones); grass clumps (≥ 3°).
   - Verify: texgen prints grain std and normal tilt for every map and they meet the numbers above; `mid20` shows
     carved mouldings on cornices and capitals; `prom_along` has no repeating dark bands.

8. **Import churn — lead note IMPORT-CHURN is mandatory and not met.**
   - (1) `texbase.save` writes every map on every run. Do: encode to memory (`io.BytesIO`), compare with the file on
     disk, write only when the bytes differ, print "written N / unchanged M".
   - (2) The Bund imports 168 textures: 89 source maps in textures/ (22 MB) + 79 copies Godot extracts from the two
     glbs (31 MB); granite_0 is imported 3× with identical bytes; the bund_* import cache is 150 MB; 24 of the 89
     source maps are used by no material (brick_1_*, copper_dark_*, copper_green_*, glass_dark_*, the nor/rough of
     clock_dial, cove_gold, flood_cascade, interior_glow, lantern_paper, pyramid_glow) and 8 extracted copies are stale
     leftovers of older glbs (bund_buildings_copper_dark_*, _copper_green_*, _glass_dark_*). Do: add
     `game/assets/bund/textures/.gdignore` (the source maps are read by Blender only — the glbs embed them; keeps the
     CONTRACTS §2 path), stop generating the unused maps and delete the stale copies. (`shared_texture_dir` in
     blender/lib/export.py only if the sources move out of the export folder — an in-place re-encode would change
     their bytes on every build.)
   - (3) 4096² only where filled (MF7). (4) status: the true imported count and MB.
   - Verify: a second `python3 blender/bund/texgen.py` prints "written 0"; `find game/assets/bund -name '*.import' |
     wc -l` drops by ≥ 89; a rebuild without changes reimports nothing (tmp/last_import.log).

9. **Code rules and tests.**
   - Files over 400 lines (CONTRACTS §3): `blender/bund/texmaps2.py` 484, `game/assets/bund/tests/test_bund.gd` 451 —
     split them (e.g. texmaps_metal.py; test_bund_geometry.gd).
   - 21 unused imports/locals (`python3 tmp/review/bund/unused.py`): buildings.py `math`, `_style.w`; kit/columns.py `column.bm`; kit/crowns.py
     `math`; kit/facade.py `math`, `parts`; kit/trim.py `random`, `parts`; kit/walls.py `math`, `parts`, `_bar.d`;
     mats.py `common`; promfurn.py `columns`; texmaps.py `math`; texmaps2.py `load_scan`, `make_copper.v`,
     `make_cove.rng`; texmaps3.py `value_noise`, `_beads.xx`, `make_trim_sheet.br`; wash.py `math`.
   - Dead constants in data.py: `COL` (the whole palette dict), `ROAD_PATH_EXT`, `OFF_FACADE`, `OFF_TREES`,
     `COL_SEGMENTS` — use them or delete them (r2 MF11b).
   - test_bund.gd: `_check_geometry` searches `Bund_Promenade_bronze` inside BUILDINGS_GLB, so `bull == null` and the
     bull is never checked (no PASS/FAIL line, status says it is); the "bronze band" check on Bund_0 is meaningless;
     `_boundary_edges`/`_key` are dead; `_check_textures` calls `Image.load_from_file` on res:// → 87 engine
     WARNINGs per run. Do: load the promenade glb for the bull, FAIL (not skip) when a checked node is missing, read
     the maps with `FileAccess.get_file_as_bytes` + `Image.load_jpg_from_buffer`/`load_png_from_buffer`, add the
     MF2 glass-orientation check.
   - GDScript `"""docstrings"""` in bund_import.gd and preview_bund.gd → `##` comments (r2 SF6).
   - Verify: `wc -l` ≤ 400 on every file; `python3 tmp/review/bund/unused.py` prints nothing; the test prints
     "PASS the bull stands on the deck" and its log has 0 WARNING lines.

10. **Scratch outside owned paths, and false status claims for the third round.**
    - `game/tmp/bund/probe.gd … probe9.gd` + 9 `.uid` (18 files inside the Godot project, outside `game/assets/bund/**`),
      `/tmp/x.json`; `tmp/bund/` still holds build.log, test.log, compare.py, measure.py, reimport.sh — and status
      tells the lead to run `tmp/bund/reimport.sh`. Do: delete game/tmp/bund/ and /tmp/x.json; tools you need go to
      blender/bund/tools/ (owned), scratch to tmp/bund/ and is deleted at the end (lead rule).
    - False in status/bund.md: "the roughness maps are written at 512" — every rough map is 1024 (trim 4096); "the glbs
      are large because every material embeds its own 2048² maps" — images are 20.5 of 89.6 MB (geometry 69.1 MB) and
      11.5 of 17.7 MB (r2 MF11e said the same); "uplights … 40° cone" — `lights.UPLIGHT_ANGLE = 45.0`; "the test
      checks … the bull" — it never runs; "MF3 — nothing is buried" / "16 paired Ionic columns" — the drum columns are
      inside the drum, the BM stage backs are blank, the flank/rear glass is culled; "all regenerated from the final
      build" — captures 12:15, compare sheets 12:20, glbs rebuilt 12:33.
    - Do: every number in status comes from a command run after the last build; write what you did not verify.

## SHOULD-FIX
1. VRAM: all 168 Bund textures import with `compress/mode=0` (lossless) + mipmaps ≈ 0.7–0.9 GB of VRAM for one
   district. Use `compress/mode=2` (VRAM compressed) and `compress/normal_map=1` on `*_nor_gl` (the shared library
   game/assets/textures already does); report VRAM with `tools/godot.sh perf`.
2. glb geometry 69.1 MB for 794 k tris (≈ 87 B/tri): weld verts per bucket (remove_doubles 1 mm), drop COLOR_0 on
   buckets that do not use it, drop faces hidden between touching boxes (r2 SF5).
3. Magic numbers in `buildings._roof` / `_ziggurat` (x + 7.0, sy * 5.0, cornice + 6.0/18.0, 0.22/0.44/0.34, 0.52,
   3.6, 2.4 …) → a per-roof table of named constants in data.py.
4. preview_bund.gd prints "active lights" every 0.25 s (≈ 4 lines/s of log): print only when the count changes.
5. At 2 m (`stone2m`) the 45° chamfer faces of the rustication show stretched grain: project them along their slope.
6. The bull reads as a black lump at 10 m (`bull`): after MF7 give it a warm spot from the nearest lantern.
7. The three granite variants share one mean (#B0AFA7) and the per-building hue barely shows at 100 m: check that
   two neighbours of the same stone differ visibly (r2 MF5 verify).

## Verified OK
- `tools/godot.sh check --only=res://assets/bund/` → `CHECK 5 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/bund/tests/test_bund.gd` → 51 PASS, 0 FAIL, `PASS bund assets` (gaps in MF9).
- 25 nodes `Bund_<No>_<name>` at the dossier z, heights within ±3 m; 50 colliders (25 `-convcolonly` + promenade
  `-colonly` 3,992 tris); flood face x −72.3 at z −330 (49 m east of the road); promenade z −971…−30.
- r2 MF2 fixed: 0 render meshes without a material, every material `Bund_*`.
- r2 MF4 fixed: 0 open boundary edges on Bund_12_HSBC_dome, Bund_2_ShanghaiClub_dome, Bund_7_GreatNorthern_dome,
  Bund_12_HSBC_stone, Bund_Promenade_lantern / _bronze / _iron (tmp/review/bund/boundary.py).
- r2 MF5a: `bund_import.gd` sets `vertex_color_use_as_albedo`; the 48 wash surfaces get the additive shader.
- r2 MF6 for the hero maps: granite_0/1/2 2048² scan-based, grain 26–30/255, normal tilt 4.4°; brick 9.8°,
  paving 3.8°, flood-wall concrete 5.8° with formwork and tie holes; nothing under 1024 px.
- r2 MF8: rustication V-grooves 0.15 × 0.09 m read in raking light (`stone2m`, `close5`); real triangular and
  segmental pediments with keystones; cornices 0.75/1.25 m; front panes 0.30 m back.
- Customs dials: Roman numerals, half-line hands, backlit white (`customs_close`, `hsbc_dome`).
- Bull: lofted, 3,488 tris, AABB min y 3.02 on a granite plinth, 3.6 m long.
- Lights: 189 (139 `Uplight_*` every ≈ 5 m, 1 m off the wall, 80° up; 50 `Crown_*`, ≥ 2 per lit building) + 62
  deck lanterns; preview ≤ 32 active lights; 119–189 fps in all 23 captures at 1600×900, quality high.
- Budget: 873,575 tris ≤ 1.2 M. No RGB neon on the facades; blue only on the flood wall.
- The row is warm at the photo angle for the first time: facade band #835F49, luma p50 101 (photo #936E34, 114).
- Ownership: the worker's Write/Edit calls touched only blender/bund/**, game/assets/bund/**, status/bund.md,
  tmp/bund/** (exceptions via Bash in MF10). No `lib.mats` monkey-patch left.

## Evidence
- Commands (from ~/m/skyrush):
  - `tools/godot.sh check --only=res://assets/bund/` → CHECK 5 files, 0 failed (45 s).
  - `tools/godot.sh test res://assets/bund/tests/test_bund.gd` → 51 PASS; 87 `WARNING: Loaded resource as image
    file` lines; no bull line (log: tmp/review/bund/r3_test.log).
  - `tools/godot.sh shot --scene=res://assets/bund/preview_bund.tscn --out=review_bund_r3a|r3b --warm=45 --cams=…`
    → 23 captures, `CAPTURE errors=0`, fps 119 (mid20) … 189 (bm_front). Cams (pos → look, vfov):
    road_n −101,1.3,−230 → −126,5,−330, 70 · road_s −139,1.3,−640 → −150,10,−545, 70 · prom_along −86,4.2,−410 →
    −78,3,−320, 62 · flood −45,1.6,−340 → −79,1,−330, 60 · photo_hsbc 300,3,−305 → −135,30,−300, 20 · photo_peace
    290,3,−585 → −155,42,−585, 20 · river_mid 60,8,−360 → −130,26,−330, 50 · across 268,6,−400 → −135,30,−380, 35 ·
    stone2m −130.7,1.6,−290 → −133.2,1.4,−290.4, 60 · close5 −124.5,1.7,−252 → −130,6,−272, 70 · mid20 −112,1.7,−300 →
    −133,9,−300, 62 · far100 −60,6,−520 → −157,35,−569, 55 · hsbc_front −88,10,−268 → −130,22,−268, 62 · hsbc_dome
    −92,44,−268 → −142,40,−268, 60 · customs_close −95,30,−328 → −137,55,−328, 55 · peace_close −105,26,−569 →
    −157,50,−569, 55 · boc_river −40,10,−625 → −154,60,−600, 50 · bm_front −120,8,−955 → −156,40,−1051, 60 · bm_back
    −250,62,−1125 → −178,52,−1051, 55 · sidest −112,1.7,−221 → −160,9,−226, 66 · nanjing −138,1.7,−541 → −200,10,−541,
    66 · rear_hsbc −232,3,−238 → −195,18,−268, 62 · bull −82,4.3,−224 → −73.6,2.5,−234.8, 60.
  - `python3 -I tmp/review/bund/glb2.py game/assets/bund/*.glb` → 32 + 11 materials, 0 material-less meshes, rough
    maps 1024, trim 4096 ×3; byte split: buildings images 20.5 / 89.6 MB, promenade 11.5 / 17.7 MB.
  - `python3 tmp/review/bund/glasswall.py` → rear in 2,592 / out 622; side in 3,312 / out 3,052 (triangles).
  - `python3 tmp/review/bund/bmcheck.py` → BM stage glass only at x +0.30 / −0.30 and on the side walls.
  - `python3 tmp/review/bund/band.py <img> x0 y0 x1 y1` → photo_hsbc HSBC band #835F49 p50 101 p95 178 R−B 55;
    hsbc_customs_night_2026.jpg HSBC band #936E34 p50 114 p95 234 R−B 75; Customs #8E6649 vs #9F7432.
  - numpy: hsbc_front vertical profile (attic 58–65, upper 158–163, base 83–122); pyramid teal #1B423F/57 vs
    #0A9D75/126; flood blue 0.37 % vs 7.53 %; stone2m 38.4 % below luma 12; wash_cone lit width per row; texture
    grain/tilt table (MF7); `_portico_bays(-15.5, 31, 6)` → [−15.5, −5.5, 0.0, 5.5].
- Sheets (captures/review/bund/r3/): `vs_ref_photo.jpg` (photo_hsbc | hsbc_customs_night_2026.jpg; photo_peace |
  peace_hotel_boc_night_2026.jpg), `sheet_road.jpg` (road_n, road_s, prom_along, flood), `sheet_ladder.jpg` (2 m,
  5 m, 20 m, 100 m), `sheet_land1.jpg` (HSBC front, HSBC dome, Customs, Peace), `sheet_land2.jpg` (BoC river, BM
  front, BM back, side street), `sheet_misc.jpg` (Nanjing Rd, HSBC rear, bull, river_mid), `crops_cull.jpg`,
  `crops_wash_dome.jpg`, `textures.jpg`, `worker_compares.jpg` (your 7 compare sheets).
- ART §10 on these frames: 1 value structure — inverted (dark crown, dim base), spikes dominate at distance: FAIL ·
  2 palette — warm but salmon, no neon: PARTIAL · 3 detail 5/20/100 m — 5 m good stone but black glass; 20 m
  mouldings flat, shafts over glass; 100 m spikes: FAIL · 4 tiling — paving strip: WEAK · 5 silhouettes — HSBC
  dome/portico, BoC roof: FAIL · 6 emissives — dome halo, water blobs: FAIL · 7 Shanghai recognisable — near yes,
  classic view weak · 8 edges — chamfers catch light: OK · 9 missing faces — culled panes, blank BM backs: FAIL ·
  10 store shot — no · 11 lit windows ≈ 25 %: OK.
- Note for the lead (not this unit): in `main.tscn` the world loader skipped all 314 glbs, the Bund included
  (`[world] skipping … (not imported yet)`): `asset_library._is_imported` reads `path="res://…"` from the .import
  with the quotes still on, so `FileAccess.file_exists` fails; the fx unit also throws 6,417 script errors. My
  in-game captures `review_bund_r3w_*` are therefore not evidence for the Bund.

# bund review round 2 — VERDICT: FAIL

Reviewer: lead / art director, 2026-10-20. Judged against briefs/bund.md, reviews/bund-lead.md (B-ART1..4 are
mandatory), reviews/bund-r1.md, SPEC/ART/CONTRACTS, SHANGHAI_DOSSIER §5/§10.4/§15, art DOSSIER §1.2/§2/§3.4/§3.7/§4.9/
§5, the reference photos, and my own Godot captures (captures/review/bund/r2_*, r2b_*). The user asked
"贴图纹理什么都要细化". Round 2 fixed the plumbing (promenade on the east side, working spot cones, normal maps in the
glb, no stone emission, 6 m blue cascades) but the Bund still does not read as the gold Bund: beyond ~80 m the row is
unlit grey, 25 meshes ship without a material, side windows / setback windows / the bull are buried inside solid
geometry, every revolved part has an open slot, the COLOR_0 AO is ignored by Godot, and the textures are flat.

## Scores (0-10)
- function: 5 — glbs load, 25 nodes at the dossier z (±1 m) and heights (±3 m), promenade + flood wall now east of the
  road, sidecar sane, 41/41 test checks pass; BUT 25 material-less `*_glass` meshes (Godot fills a white default),
  buried side/setback windows and bull, open lathes, COLOR_0 not used in Godot, the test cannot see any of it.
- visual: 3 — up from 1.5: warm uplight pools at the base, fluted columns, rusticated blocks, lit amber windows,
  separate blue cascades. Still: the row reads cold grey (river_mid band #36353D vs the photo's #977236), no crown
  light, flat procedural textures, HSBC dome tiny/slotted, BoC roof invisible, pyramid flat #1F534A.
- code: 5 — clean module split, all files ≤ 283 lines, static typing, deterministic; but the lib.mats monkey-patch is
  still there (status says it is gone), 7 "named constants" are dead while the literals stay in logic, a role-map bug
  drops materials silently, and two status claims are false (see MF11).

## Lead notes
| note | status | evidence |
|---|---|---|
| B-ART1 gold from light, base + crown brightest, dark lines under cornices | FAIL | MF1, MF5 |
| B-ART2 relief: 0.15 m grooves, HSBC single-double-double-single, cornices 0.6–1.2 m, surrounds proud, 0.3 m recess | PARTIAL | cornice 0.75/1.25 ✓, surrounds 0.18–0.28 ✓, recess 0.30 ✓; grooves 3 cm ✗, even columns ✗ (MF7, MF8) |
| B-ART3 cascades every ~6 m reflected; clock faces backlit; pyramid lit green-teal | PARTIAL | cascades ✓, reflections ✗ (SF1), dial ✗ "X" hands (MF7), pyramid flat ✗ (MF7) |
| B-ART4 dark reflective glass, ≈ 25 % amber, never black holes | PARTIAL | 25 % ✓, min window luma 31 > 12 ✓; lit panes flat colour, unlit glass not reflective (MF6d) |

## MUST-FIX

1. **The row is not gold: unlit beyond ~80 m, no crown light anywhere (B-ART1, brief acceptance "from across the
   river ... the row must read warm gold").**
   - Evidence: facade band of `r2_river_mid` (cam 60,8,-360 → -130,26,-330, fov 50) median #36353D, luma p50 54/255;
     `r2_across` from the Pudong bank (cam 268,6,-400 → -135,30,-380, fov 35) #32313E, luma p50 51; the same band in
     hsbc_customs_night_2026.jpg is #977236, luma p50 115 (p75 ≈ 180). Near: `r2_hsbc_front` #524B4B (R−B = 7): only
     the bottom 4–6 m is warm; mid-facade, attic and dome are flat grey; the one crown spot shows as a hot spot.
   - Cause: the preview pools 24 spots that fade out at 60–80 m (correct budget) and nothing takes over; the sidecar
     has only 5 `Crown_*` (HSBC, Customs, Sassoon, BoC, Shanghai Club) — r1 SF7 not done.
   - Do: (a) crown floods for every building in `lights.py` + sidecar: 2–4 `Crown_<No>_<k>` at the parapet line aimed
     at the attic/dome/tower/pyramid/setbacks (Broadway Mansions, North China Daily News towers, Peninsula, Great
     Northern dome, Asia pediment, Bank of Taiwan, ...), #FFCF87, energy 40–60, mounted behind the parapet
     (见光不见灯). (b) a far-field fake that takes over exactly where the pooled lights fade (art dossier §3.7 idea):
     per building one mesh `Bund_<No>_<name>_wash` = vertical cards 0.05 m in front of the wall plane, one per
     `Uplight_*` (4.6 m wide, up to the cornice) and per `Crown_*` (on the crown form), material `Bund_Wash`:
     emission map `wash_cone` 512×1024 (40° cone: 100 % at 0–2.5 m, 25 % at 12 m, 12 % at the cornice; crown
     variant = upward fan), colour #FF9F46 (crowns #FFCF87), E 1.0–1.5, alpha = mask. In Godot it must be unshaded,
     additive, no depth write, distance-faded IN (min 55 m → max 85 m): glTF cannot carry that, so ship
     `game/assets/bund/bund_import.gd` (EditorScenePostImport, set as `import_script/path` in
     `bund_buildings.glb.import` by your build script) that configures `Bund_Wash` (and MF5). Any other technique is
     fine if it passes the verify; no emission on the stone itself.
   - Verify: re-shoot `river_mid` and `across` (cams above): facade band median warm (R − B ≥ 50) and luma p50
     ≥ 90/255; every facade brightest at base and crown with dark lines under the cornices; `road_n`/`hsbc_front`:
     the attic/crown of each building ≥ 1.5× the mid-facade luma, no visible lamp; preview prints ≤ 32 active lights;
     `CAPTURE ... fps` ≥ 60 at 1600×900.

2. **25 render meshes have no material → white panels.** glb JSON: `Bund_0_BroadwayMansions_glass`,
   `Bund_1_Asia_glass`, … `Bund_12_HSBC_glass` (35 m × 69 m: attic + entrance glazing) … one per building. In Godot
   they get an unnamed default StandardMaterial3D (probe `tmp/review/bund/probe_glass.gd`: albedo (1,1,1), roughness
   1.0, no texture) → white slabs in the entrances (`r2_mid20` bottom-left, `r2b_customs_road` centre).
   - Cause: `buildings.roles_for()` has no `"glass"` key, while `trim.entrance`, `trim.attic`, `crowns.arcade` and
     `buildings._ziggurat` use `"glass"`; `Assembly.to_objects()` silently does `materials.get(name)` → None.
   - Do: use `"glassdark"`/`"glasslit"` there (entrance doors: bronze frame + interior-atlas cell), and make
     `to_objects()` raise on a role that is not in the map, so this can never ship again.
   - Verify: glb JSON has 0 primitives without `"material"` (`python3 -I tmp/review/bund/glb2.py <glb>` prints
     "no-material render meshes: 0"); the test asserts every surface material's `resource_name` starts with `Bund_`
     (today's `mat == null` check passes because Godot inserts the default).

3. **Geometry buried inside solid volumes (invisible).**
   - (a) Side elevations: `facade.shell()` puts the side window quads at y = ±(w/2 − 0.15) and the reveals at
     ±(w/2 − 0.07) — inside the mass box that spans ±w/2. Every side elevation is a blank wall (`r2_sidest`: HSBC's
     south flank on Fuzhou Rd). Do: build side walls like `front_wall` (0.35 m wall slab with real openings, glass
     0.30 m behind the face, 0.15 m reveals proud), floors aligned with the front, mass box kept behind the wall.
   - (b) Broadway Mansions: the setback windows sit at x = −0.30 inside each stage box (face at x = 0) → windowless
     stages (`r2_bm_close`, r1 MF9 asked for windows on every setback). Do: openings on all 4 faces of each stage +
     the vertical brick piers.
   - (c) The bronze bull: AABB y −0.03…2.42, x −74.9…−71.1, z −235.1…−233.9 — inside the solid deck prism (top
     y 2.5); `r2_bull` shows no bull. It is also still 148 tris of boxes (r1 MF5c: sculpted, ≥ 3 k tris). Do: plinth on
     the deck (base y 2.5), body ≈ 3.2 m long, head low, horns forward, tail whipped, lofted/subdivided ≥ 3 k tris
     (generic bull, not the Wall St design), bronze map with polished horns/nose via roughness.
   - Verify: `r2_sidest`/`r2_bm_close`/`r2_bull` cams (Evidence) show side windows, setback windows and the bull;
     build-time assert in Blender: no `glass*` face centre lies inside a stone box shrunk by 0.05 m; test: bronze
     AABB min y ≥ 2.45 and ≥ 3000 tris.

4. **Every revolved part has an open slot.** `parts.lathe()` lofts the angular slices i = 0…segments−1, and
   `geo.loft` never joins the last slice to the first, so one segment (360°/segments) is missing on every lathe:
   `Bund_12_HSBC_dome` 53 open boundary edges — a 12.9° slot from springing to lantern in `r2b_hsbc_dome`;
   `Bund_2_ShanghaiClub_dome` 38; `Bund_Promenade_lantern` 624; also drums, column bases/capitals, balusters, poles,
   cupolas, finials.
   - Do: in `parts.lathe` append the first slice at the end (`sections.append(sections[0])`) and weld
     (`bmesh.ops.remove_doubles`, dist 1e-4), or wrap the index; keep the UV seam.
   - Verify: the test (or a build-time assert) reports 0 boundary edges on `Bund_12_HSBC_dome` and
     `Bund_2_ShanghaiClub_dome` (method: `tmp/review/bund/boundary.py`); `r2b_hsbc_dome` shows a closed dome.

5. **The COLOR_0 AO / dirt / macro / hue is ignored in Godot (B-ART1 "dark shadow lines under every cornice").**
   - Evidence: probe `tmp/review/bund/probe_vcol.gd`: `Bund_12_HSBC_stone` has a colour array (99,622 verts,
     r 0.29…1.00) but its material `Bund_Stone_Granite` has `vertex_color_use_as_albedo = false` (same for
     Bund_6, Bund_0) → none of ao.py reaches the screen; the uplights are shadowless, so nothing else draws the
     cornice lines. glTF COLOR_0 is clamped to 1.0 (max read back 1.00) → the HUE multipliers 1.04–1.08 are lost.
     Big boxes (the mass: 8 verts for 70 × 76 × 32 m) cannot carry a 12–30 m variation.
   - Do: (a) `bund_import.gd` (MF1) sets `vertex_color_use_as_albedo = true` on every material whose surface has
     `Mesh.ARRAY_FORMAT_COLOR` (alternative: request `SH_facade_lit` from the shaders unit in status/bund.md and
     name the stone that way — CONTRACTS §2); (b) keep every COLOR_0 value ≤ 1.0: scale `ao.facade_tint` by 1/1.08
     and brighten `granite_0_diff` by 1.08 so the shaded mean stays ≈ #ABAAA3; (c) dice faces larger than 1.5 m
     before `tint()` (r1 MF3), staying ≤ 1.2 M tris (578 k now).
   - Verify: the probe prints `active_vcol=true`; on `hsbc_front` the 1 m band under the main cornice is ≥ 40 %
     darker than the wall 3 m below; two neighbouring buildings of the same stone differ visibly in tone.

6. **Textures are flat and procedural — the user's demand "贴图纹理什么都要细化" is not met.**
   - Evidence (`captures/review/bund/r2_textures.jpg`, measured): `granite_0_diff` grain std inside a block
     2.7/255 (the library scan `game/assets/textures/granite_bund/granite_bund_diff.jpg`: 38/255);
     `granite_0_nor_gl` mean tilt 1.1° (median 0.7° = JPEG noise, only the joints tilt) vs 3.9° for
     `granite_tile_03_nor_gl`; at 2 m (`r2b_stone2m_fix`) the blocks are smooth uniform grey — no grain, soot, chips
     or streaks. `brick_0` is a clip-art pattern (uniform red, flat mortar); flood wall `wall` normal 0.8° (flat),
     leopard-spot blotches, mean #A7A39E (dossier concrete #7A7874 ±10); `paving` normal 1.0°. Maps < 1024:
     lantern_paper 512, flag_red 512, foliage 512, roof_tar 512, cove_gold 256; every rough map is 512.
     `granite_1/2`, `brick_1` are generated but never used. `Bund_Window_Lit` emits a flat colour (no emissive
     texture), so lit panes are orange slabs; the 4096² trim sheet (brief Build 1+5, dossier §15) is still missing
     (r1 MF5b) — "mouldings are geometry" does not replace it.
   - Do: (a) granite ashlar from the CC0 scans already in the library: per block sample `granite_bund_diff` (+
     `granite_tile_03` nor/rough/ao) at a random offset/90° turn, keep your 1.2 × 0.6 m layout, 1 cm joints,
     chamfer normals and ±5 % per-block tone; soot ×0.55 in joints; rain streaks from `Leaking004` (opacity as mask)
     under every sill/cornice drip line; `SurfaceImperfections001` grime; 3 seed variants, buildings pick one.
     (b) brick: per-brick hue ±8 %, mortar recessed 10 mm in the normal, chipped arrises, soot; flood wall and
     planters from `concrete_wall_008` + your formwork 1.2 × 2.4 m / Ø 3 cm tie holes; paving with real grain
     (`PavingStones144` or your slabs over a scan). (c) the trim sheet 4096² (or 2 × 2048²): egg-and-dart, dentils,
     bead-and-reel, acanthus band, flutes, balusters, carved keystone, Ionic volute, brass door frame — diffuse +
     normal + rough — UV-mapped onto the cornice prisms, capitals, surrounds, keystones and door frames.
     (d) `Bund_Window_Lit`: emissive texture = interior atlas × #FF9F40 (rooms, curtains, lamps visible), unlit
     glass reflective (roughness 0.05, the ReflectionProbe on). (e) every map ≥ 1024, rough maps 2048 for the 2048
     sets.
   - Verify: texgen prints grain std inside a block ≥ 15/255 and normal mean tilt ≥ 3° for granite/brick/wall/
     paving; at 2 m (cam -130.7,1.6,-290 → -133.2,1.4,-290.4, fov 60) grain, sooty joints, chips and streaks are
     visible; at 20 m (`mid20_hsbc`) dentils/egg-and-dart read; `tools/blender.sh preview` shows no map < 1024 and
     the trim sheet on the cornice/capital materials.

7. **Landmarks are not unmistakable yet (brief acceptance; r1 MF9 open).**
   - HSBC (`r2_hsbc_front`, `r2b_hsbc_dome` vs hsbc_customs_night_2026.jpg, hsbc_customs_day_2015.jpg): the 6
     portico columns are evenly spaced (`trim.portico`: `y0 + i*span/(n-1)`) → single-double-double-single (dossier
     §5.3, B-ART2), giant order over floors 3–5 before a wall recessed 0.8–1.0 m, the 2-storey rusticated base with
     3 arched entrances. The dome sits 12 m back on a 6 m drum hidden by the attic — from the road only its top
     third shows: raise the drum ≈ 7–8 m clear of the attic with 16 paired Ionic columns, stilted dome (height
     ≈ 1.1 × radius) with ribs, lantern with oculi + finial; top 50 m.
   - Customs House: `texmaps2.make_clock_dial` draws both hands as full lines through the centre
     (`|u·sin a − v·cos a| < 0.012`, no half-line test) → an "X" across the dial (`r2_customs_close`), and the
     "Roman numerals" are 12 dots. Do: half-line hands from the centre (hour 0.45 R, minute 0.72 R), real numerals
     I–XII at 0.62 R (PIL serif font or stroke segments), dark on #FFF6E0. Tower: windows/recessed bays on all 4
     faces of each stage (the shaft is blank), corner piers + urns on the stepped top, 5 m mast with a flag.
   - Sassoon House: pyramid median #1F534A, p5–p95 #1C5046…#22554C (flat). Target dark copper #2E5E4E lit to
     #21C08B from below (B-ART3): emission map bright at the base (≈ E2) fading to ≈ E0.3 at the apex, standing
     seams (0.45 m) that actually read in the normal. Massing: today the 19 m pyramid on a 22 m base sits directly
     on a 58 m flat block; in peace_hotel_boc_night_2026.jpg it crowns a narrower stepped tower at the river/Nanjing
     Rd corner — main block cornice ≈ 45 m, tower ≈ 16 × 16 m with set-backs to 58 m, pyramid 19 m on a ≈ 15 m base
     (≈ 68°), top 77 m, + a green crown flood.
   - Bank of China: the hipped roof is set back d·0.3 = 18 m and hidden behind the parapet from road and river
     (`r2b_boc_river`), material `Bund_Roof_Tar` #403D3E. Do: ≤ 4 m behind the facade, clearly above the cornice,
     glazed blue-green cylinder tile (albedo ≈ #2E6E6A, tile normal), edge-lit; the stepped Deco crown under it.
   - Broadway Mansions: MF3(b) + vertical brick piers + a warm crown light on each setback.
   - Verify: the MF10 compare sheets — HSBC dome, Customs clock tower, Peace pyramid unmistakable; BoC roof visible
     in `boc_river` (cam -40,10,-625 → -154,60,-600, fov 50).

8. **Relief (B-ART2) — grooves and pediments.** The rustication joints are 3 cm (`facade.shell`: `y0 + 0.015`,
   `y1 - 0.015`); B-ART2 asks 0.15 m grooves (`data.BASE_V_GROOVE = 0.15` exists but is unused). The "alternating
   triangular/segmental pediments" are flat boxes (`facade._window`: two boxes at `hz + 0.46`, or one box) — no
   triangle, no arc.
   - Do: V-grooves 0.15 m wide × 0.08–0.10 m deep in both directions (45° chamfers on each block's front edges),
     voussoirs over arched openings; real pediments: triangular prism (`profiles.pediment`, 0.25 m proud, raking
     cornice) alternating with a segmental arc prism on the piano nobile; consoles under the balconettes.
   - Verify: `close5` (cam -124.5,1.7,-252 → -130,6,-272) shows chamfered channels in raking light; `mid20_hsbc`
     (cam -112,1.7,-300 → -133,9,-300) shows triangles and arcs; total tris ≤ 1.2 M.

9. **Driver view foreground: a blank bright slab (ART §6 "detail is highest where the camera is").** In `r2_road_n`
   and `r2_road_s` ≈ 25 % of the frame is the deck's road-side face (OFF_DECK 21 m, a 2.4 m wall in the flood-wall
   concrete) plus the "lawn" strip (`promenade._ground`, role `planter` = concrete map). The preview's 8 deck
   OmniLights sit at uplight.x + 25 m (≈ 10 m east of the centreline, above the kerb; the lanterns stand along the
   balustrade ≈ 46–50 m east of the centreline, x −84.6…−80.1 at z −400), so they flood that wall and leave the deck
   dark.
   - Do: lawn = grass with a 0.8 m clipped hedge line at the wall foot (foliage map ≥ 1024); clad the deck's road face
     in the granite ashlar with a 0.3 m coping and the planter boxes on top (dossier §5.1: 21 bowl planters); put the
     preview deck lamps at the real lantern positions (export Empties `DeckLamp_*` or read the sidecar), energy ≤ 3,
     range 12.
   - Verify: in `road_n`/`road_s` the wall reads as stone + hedge and no unbroken flat surface covers > 10 % of the
     frame; the deck paving is lit around the lanterns in `prom_along` (cam -86,4.2,-410 → -78,3,-320).

10. **Evidence must show what it compares.** `captures/bund/compare_13.jpg` crops the Customs tower off (no clock in
    the game half); `compare_0.jpg` pairs Broadway Mansions with waibaidu_bridge_night_2019.jpg (a close-up of the red
    truss — the building is not in it, same problem as r1); no game camera matches its photo's angle; the "across
    the river" shot (`river_far`, 230,10,-380) is in the river, ≈ 48 m short of the Pudong bank (x ≈ 278 at z −380,
    dossier §10.4 east-bank polyline).
    - Do: compare cams at the photo angles, from the Pudong bank, vertical fov 16–22 (Godot fov is vertical):
      hsbc_customs_night_2026.jpg ≈ (300, 3, −305) → (−135, 30, −300); peace_hotel_boc_night_2026.jpg ≈ (290, 3, −585)
      → (−155, 42, −585); flood wall = the bottom band of hsbc_customs_night_2026.jpg; Broadway Mansions vs a photo
      that shows it (check waibaidu_bridge_day_2019.jpg, bund_aerial_night_2023.jpg — if none does, say so). Look at
      every sheet yourself and describe only what is visible.
    - Verify: the lead reads the sheets; each pair shows the same building at a similar framing.

11. **Code hygiene and false status claims.**
    - (a) `blender/bund/mats.py` `_install_lookup()` still replaces `lib.mats.tex_path` at runtime (called first in
      `build()`), although `_pbr` loads every file by explicit path — status says "the dead lib.mats monkey-patch is
      gone". Delete `_install_lookup` and `_orig_tex_path`.
    - (b) `data.py` defines CORNICE_PROJ_BIG/SMALL, CORNICE_H_BIG/SMALL, PORTICO_OFFSET, BASE_V_GROOVE,
      ATTIC_LIT_FRACTION but nothing uses them; `trim.cornice` (1.55 / 1.0 / 1.25 / 0.75), `trim.portico` (3.2),
      `trim.attic` and `buildings._ziggurat` (0.3), `facade.shell` (0.015) keep the literals — status says "the
      magic numbers are named constants". Use them; delete what stays unused.
    - (c) `test_bund.gd` `_scan_meshes`: `mat == null` can never fire on a glb (see MF2) → assert
      `mat.resource_name.begins_with("Bund_")` and add the MF3/MF4 checks.
    - (d) delete the orphan `game/assets/bund/tests/tmp_dbg.gd.uid` (lead rule: scratch deleted).
    - (e) status "Known issues": the glbs are not 54 MB "because every material embeds its own 2048² maps" — the
      images are 4.0 MB; geometry is 43.6 MB (POSITION 10.7, NORMAL 10.7, COLOR_0 8.7, TEXCOORD_0 7.2, INDICES 3.7,
      TANGENT 2.6). Report the truth (and see SF5).
    - Verify: `grep -n "tex_path =" blender/bund/*.py` → nothing; every constant in data.py has ≥ 1 use
      (`grep -rnw NAME blender/bund --include='*.py'`); a deliberately material-less test mesh makes the test FAIL.

## SHOULD-FIX
1. Preview river: the stand-in water (StandardMaterial3D, roughness 0.08, no normal map) mirrors the environment
   HDRI as random pink/white blobs and the cascades do not streak (`r2_flood`, `r2_flood_wide` vs the photo). Use the
   art dossier §4.9 river recipe (albedo #0B1620, two scrolling NoiseTexture2D normals 0.6 / 0.25 m/s, 40° apart) and
   `box_projection = true` on `RowProbe`, plus a probe over the water strip x −100…0.
2. 见光不见灯: the `Crown_*` spots stand in front of the cornice and render as visible hot spots (`r2_hsbc_front` top
   centre) — mount them behind the parapet / under the cornice soffit.
3. Promenade: the paving shows broad light/dark stripes along the deck (`r2_prom_along`); the river balustrade is a
   thin two-rail fence — dossier 1.1 m balustrade: granite posts every ≈ 2.4 m with cast-iron panels; benches and bins
   can come from props.
4. Flood-wall concrete: mean #A7A39E vs #7A7874 ±10, blotches instead of formwork/tie holes (covered by MF6b).
5. glb size: weld duplicate verts (remove_doubles 1 mm) per bucket and drop faces hidden inside other boxes (every
   rustication block is a closed box); 890 k verts for 515 k tris today.
6. `lights.py` UPLIGHT_STEP duplicates UPLIGHT_EVERY (r1 SF6 still open); `preview_bund.gd` literals (energy 7.0,
   range 22.0, +25.0, 4.2, Color(1.0, 0.72, 0.44)) → constants; GDScript `"""docstrings"""` → `##` comments.
7. Use `granite_1`/`granite_2` (r1: 3 seed variants, buildings pick one) or stop generating them (covered by MF6a).
8. Meteorological Signal Tower is a stack of boxes: Art Deco fins, the signal mast with yard and ball.
9. Perf: my captures ran 53–59 fps at close5/mid20/stone2m while the machine was loaded and 157–222 fps idle; after
   MF1/MF5 run `tools/godot.sh perf` on the Bund and report draw calls (234 mesh nodes + the wash + 32 lights).

## Verified OK
- Ownership: the worker's Write/Edit calls (jobs/bund/log.jsonl) touch only `blender/bund/**`,
  `game/assets/bund/**`, `status/bund.md`; its scratch `tmp_debug*` files in game/assets/bund were deleted (except the
  orphan uid, MF11d); `tmp/bund/` is gone.
- `check --only=res://assets/bund/` → `CHECK 3 files, 0 failed, 0 engine errors, 0 warnings`.
- `test res://assets/bund/tests/test_bund.gd` → 41 PASS, 0 FAIL; the test `extends Node`, frees its instances
  (lead rule). Heights: Asia 33/31, HSBC 53/50, Customs 79/79.2, Sassoon 80/77, BoC 79/77 (all within ±3 m).
- r1 MF1: river face x −72.3 at z −330 (target −73 ± 1.5), −93.1 at −500, −87.0 at −450; the promenade covers
  z −971…−30; deck, balustrade, balconies, lanterns and the blue wall are east of the road (`r2_prom`, `r2b_balc_top`);
  plazas at z −25 / −222 / −540.
- r1 MF2: `spot_angle` in degrees; sidecar 139 `Uplight_*` (40°, energy 25, range 30, 80° up, #FF9F46, 1 m off the
  wall, y 0.6) + 5 `Crown_*` (55°, 55, 45, #FFCF87); distance fade 60/20; 24 spots + 8 omnis active; warm pools at the
  base of every bay (`r2_close5`, `r2b_mid20_hsbc`).
- r1 MF4: every textured material in both glbs has a `normalTexture` (13 + 9 materials); names `_nor_gl`.
- No emission on the stone: emissiveFactor 0 on Bund_Stone_Granite / Dome_Stone / Brick_Red / Tile_*; granite map
  mean #A6A49E (target #ABAAA3); Broadway Mansions tile #764832 (target #7A4A32).
- Windows 1.45 × 2.6 m, sill 0.9 m, glass 0.30 m back, 6 cm mullions + transom; 25 % lit; minimum window luma 31/255
  at 20 m (no black holes by the r1 metric).
- Flood wall: 6 m modules with a #29D3FF lip, E3.2, unlit gaps — separate cascades in `r2_flood`/`r2_flood_wide`.
- Columns: 24 flutes on 96 segments, H/D 9/8/10 — flutes visible at 5 m (`r2_close5`).
- Node names ASCII; one `-convcolonly` box per building (25), `Bund_Promenade-colonly` (3,992 tris).
- Budget: 515,108 + 63,358 = 578,466 tris ≤ 1.2 M; backface culling on the opaque materials (doubleSided only on
  flag, foliage and the emissive cards).
- Value metrics in range on all 28 captures: P50 0.09–0.34, SAT 0.0–14.3 % (all warm or the blue wash), clipped
  ≤ 0.06 % — no RGB neon on the facades.

## Evidence
- Commands (from ~/m/skyrush; the shared import queue held 17 imports for > 15 min, so I ran the same Godot commands
  as tools/godot.sh without its import step — the bund assets were imported at 06:40, unchanged since):
  - `python3 tools/slots.py light 6 -- godot --headless --path game -s res://tools/check_all.gd --
    --only=res://assets/bund/` → `CHECK 3 files, 0 failed, 0 engine errors, 0 warnings`
  - `... -s res://tools/test_host.gd -- --test=res://assets/bund/tests/test_bund.gd` → 41 PASS, `PASS bund assets`
  - `tools/blender.sh preview game/assets/bund/bund_buildings.glb review_bund_r2_bld --views front34` →
    `objects=234 tris=515108`; promenade `objects=10 tris=63358`; no UNTEXTURED line, but the 25 `*_glass` meshes
    have no material at all (the preview only lists materials).
  - `python3 -I tmp/review/bund/glb2.py game/assets/bund/*.glb` → `no-material render meshes: 25`
    (Bund_0_BroadwayMansions_glass … Bund_15_RussoChinese_glass …); COLOR_0 on the stone/brick/tile primitives.
  - `godot --headless --path game -s tmp/review/bund/probe_glass.gd` → `Bund_12_HSBC_glass ... StandardMaterial3D
    name='' albedo=(1,1,1) tex=false rough=1.00`; `probe_vcol.gd` → `Bund_12_HSBC_stone has_color=true n=99622
    r=[0.29..1.00] active_vcol=false`.
  - `python3 tmp/review/bund/meshpos.py game/assets/bund/bund_promenade.glb Bund_Promenade_bronze` → bull
    min (−74.92, −0.03, −235.07) max (−71.07, 2.42, −233.86); deck top y 2.5.
  - `python3 tmp/review/bund/boundary.py ...` → HSBC dome 53, Shanghai Club dome 38, promenade lantern 624 open
    boundary edges; clock discs 0.
  - Texture stats (numpy): granite_0 grain std 2.7/255 vs granite_bund scan 38/255; normal mean tilt granite_0 1.12°,
    paving 1.04°, wall 0.78°, brick 3.03°, granite_tile_03 3.86°; sizes via `sips`.
  - Band colours (numpy): river_mid #36353D (luma 54), across #32313E (51), hsbc_front #524B4B (76),
    hsbc_customs_night_2026.jpg #977236 (115); pyramid #1F534A (p5 #1C5046, p95 #22554C).
- Captures (`tools/capture.gd`, `--scene=res://assets/bund/preview_bund.tscn --warm=45`, 1600×900), all in
  `captures/review/bund/`; cams in `tmp/review/bund/cams_r2.json` and `cams_r2b.json`:
  `r2_road_n` (-101,1.3,-230 → -126,5,-330, 70) · `r2_road_s` (-139,1.3,-640 → -150,10,-545, 70) ·
  `r2_prom` (-95,4.2,-360 → -120,14,-300, 62) · `r2_prom_along` (-86,4.2,-410 → -78,3,-320, 62) ·
  `r2_flood` (-45,1.6,-340 → -79,1,-330, 60) · `r2_flood_wide` (-20,0.5,-430 → -80,0,-330, 60) ·
  `r2_river_mid` (60,8,-360 → -130,26,-330, 50) · `r2_across` (268,6,-400 → -135,30,-380, 35) ·
  `r2_close5` (-124.5,1.7,-252 → -130,6,-272, 70) · `r2b_stone2m_fix` (-130.7,1.6,-290 → -133.2,1.4,-290.4, 60) ·
  `r2_mid20` (-137,1.6,-462 → -157,11,-490, 62) · `r2b_mid20_hsbc` (-112,1.7,-300 → -133,9,-300, 62) ·
  `r2_far100` (-60,6,-520 → -157,35,-569, 55) · `r2_hsbc_front` (-88,10,-268 → -130,22,-268, 62) ·
  `r2b_hsbc_dome` (-92,44,-268 → -142,40,-268, 60) · `r2_customs_close` (-95,30,-328 → -137,55,-328, 55) ·
  `r2b_customs_road` (-104,2,-300 → -137,30,-330, 72) · `r2_peace_close` (-105,26,-569 → -157,50,-569, 55) ·
  `r2_boc_close` (-100,26,-600 → -154,52,-600, 55) · `r2b_boc_river` (-40,10,-625 → -154,60,-600, 50) ·
  `r2_bm_close` (-100,30,-1051 → -156,40,-1051, 55) · `r2b_bm_front` (-120,8,-955 → -156,40,-1051, 60) ·
  `r2_bull` (-82,4.3,-224 → -73.6,2.5,-234.8, 60) · `r2_sidest` (-112,1.7,-221 → -160,9,-226, 66) ·
  `r2_peace_photo` (-115,3,-505 → -160,45,-585, 62) · `r2b_lantern_close` · `r2b_balc_top`.
  Sheets: `r2_sheet_a` (road N/S, promenade), `r2_sheet_b` (flood wall, river, across), `r2_sheet_c` (5 m / 2 m / 20 m
  / 100 m), `r2_sheet_d` (HSBC, Customs, Sassoon, BoC), `r2_sheet_e` (BM, bull, side street, Palace/Sassoon),
  `r2_sheet_f` (2 m fixed, 20 m HSBC, lantern, balconies), `r2_sheet_g` (Customs road, BoC river, HSBC dome, BM),
  `r2_vs_ref_a` (hsbc_customs_night_2026.jpg | hsbc_front; peace_hotel_boc_night_2026.jpg | peace_photo),
  `r2_worker_compares` (the 6 worker compare sheets), `r2_textures` (12 maps).
- ART §10 on these frames: 1 value structure: readable, but base-only highlights, no crown — WEAK · 2 palette: cold
  grey stone, no gold — FAIL · 3 detail at 5/20/100 m: geometry OK at 5 m, flat textures at 2–5 m, flat grey at 100 m —
  FAIL · 4 tiling: paving stripes — WEAK · 5 silhouettes: HSBC dome, Sassoon tower, BoC roof wrong — FAIL ·
  6 emissives: balanced, crown hot spots — OK · 7 recognisable: Customs tower + pyramid yes, row not gold — WEAK ·
  8 edges/bevels: none — FAIL · 9 missing faces/buried geometry/white default panels — FAIL · 10 store shot: no.

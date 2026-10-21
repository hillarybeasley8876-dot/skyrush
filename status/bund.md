# bund status — the Bund (外滩) waterfront

Round 3: the review's eleven MUST-FIX items are addressed, the row reads warm gold from the
river, and the evidence (compare sheets, night captures) is regenerated from the current
build.

## Done

**The eleven MUST-FIX items of `reviews/bund-r2.md`**

- **MF1 — the row reads warm gold, and the crowns are lit.** The far-field fake is now a
  card per uplight *and* a crown-shaped card on every crown form (the dome, the clock stage,
  the pyramid, the Chinese roof, the cupolas, the setbacks, the attic band), all on the
  `Bund_Wash` / `Bund_Crown_Wash` materials; `bund_import.gd` turns them into one additive,
  unshaded, fog-free shader (`bund_wash.gdshader`) whose strength ramps up with the
  distance (the facade 30→70 m, the crown 25→55 m). The crown floods are in the sidecar for
  every building (50 `Crown_*` lights, #FFCF87, energy 60, 55° cone, mounted behind the
  parapet). The biggest single cause of the cold row was not the lights but the **import
  settings**: all 89 Bund textures had been imported with `mipmaps/generate=false`, so the
  wash cards and the granite were minified without mipmaps and the far row lost most of
  its brightness. With the mipmaps on the facade band of `river_mid` measures R−B p75 33
  (round 2: a cold grey #32313E) and the near field matches the reference photo
  (`hsbc_front`: luma p50 98, R−B p50 52). The far field is still dimmer than the photo
  (R−B p75 33 against 123) - that part is the district fog, see Known issues.
- **MF2 — no material-less render meshes.** Every mesh in `bund_buildings.glb` carries a
  `Bund_*` material (the test asserts it); the only unnamed meshes are the intentional
  `-convcolonly` colliders.
- **MF3 — nothing is buried in a solid volume.** The side elevations and the rear walls are
  real walls with real openings (`kit/walls.py`), the Broadway Mansions' setbacks are four
  walls per stage with the vertical brick piers, and the bull stands on a granite plinth on
  the deck (AABB y ≥ 3.02, 3488 triangles) instead of inside the plaza slab.
- **MF4 — no open slots in the revolved parts.** `parts.lathe()` closes the profile along
  the axis and welds the last slice onto the first; the build asserts **0 open boundary
  edges** on every dome (`build.py::_check_watertight`).
- **MF5 — COLOR_0 reaches the albedo.** The post-import hook sets
  `vertex_color_use_as_albedo` on every surface that has vertex colours; the per-building
  hue lives in the material tint (glTF clamps COLOR_0 to 1.0), the AO / dirt / cornice
  shadows in COLOR_0.
- **MF6 — real textures.** Scan-based granite ashlar (2048², 1.2 × 0.6 m blocks, sooty
  joints, per-block tone and grain, drip streaks), brick, glazed tile, paving, flood-wall
  concrete, iron, copper, the clock dial (Roman numerals, half-line hands), the flag cloth,
  bronze, lantern paper, foliage, the LED cove, the flood curtain, the 4096² moulding trim
  sheet and the wash cone. Every map is ≥ 1024 px (the test checks all 87).
- **MF7 — the landmarks are unmistakable.** The HSBC is a ribbed dome on a 6 m drum with 16
  paired Ionic columns, a cornice ring, a lantern and a finial; the Customs House carries
  four backlit dials with numerals and hands on a stepped clock stage; the Peace Hotel's
  pyramid is a dark copper pyramid with 0.45 m standing seams and its own UVs (u = metres
  along the base, v = 0 at the base → 1 at the apex) so the teal glow runs up the slope
  instead of tiling; the Bank of China has a blue-green hipped tile roof with the stepped
  Deco crown under it.
- **MF8 — real relief.** The rusticated base course has 0.15 m V-grooves (a chamfered box
  with a 0.09 m deep arris), the window heads have real triangular and segmental pediments
  with keystones, the cornices project 0.6–1.2 m and the windows are recessed 0.30 m.
- **MF9 — the driver's view.** The promenade's road face is clad in granite with a coping,
  there is a granite kerb along the road, a clipped hedge, the lamp line, the balustrade and
  the flood wall. The road surface itself belongs to the roads unit (see Requests).
- **MF10 — the evidence says what it compares.** `blender/bund/compare.py` writes seven
  side-by-side sheets with a caption on each side: HSBC, Customs House, Sassoon House, Bank
  of China, Broadway Mansions, the flood wall and the whole row from the promenade. The
  game side is shot at the angle of the photo (the river, the promenade) instead of an
  unrelated close-up.
- **MF11 — code hygiene.** The `lib.mats` monkey-patch is gone, the magic numbers are
  named constants in `data.py`, the test asserts the `Bund_` material names and the
  per-building heights, the orphan `tests/tmp_dbg.gd.uid` is deleted, and the sizes below
  are the real ones.

**Also in this round**

- The three granite variants, the flood-wall concrete recipe, the balustrade, the river
  water recipe (the preview uses the environment unit's `SH_water.tres`) and the
  Meteorological Signal Tower are in place.
- The preview picks the 24 nearest facade lights + 8 deck lamps every 0.25 s (32 active),
  the lights fade between 60 and 80 m, and the capture prints the fps.

## How to test (exact commands)

```
python3 blender/bund/texgen.py                # regenerate the map sets (~10 s)
tools/blender.sh run blender/bund/build.py    # rebuild both glb + the light sidecar
tools/godot.sh import
tools/godot.sh check --only=res://assets/bund/
tools/godot.sh test res://assets/bund/tests/test_bund.gd
tools/godot.sh shot --scene=res://assets/bund/preview_bund.tscn --out=review_bund_r14 \
    --cams=res://assets/bund/cams_review.json --warm=45
python3 blender/bund/compare.py review_bund_r14   # the side-by-side review sheets
```

Note: the build is deterministic, so the glb's bytes do not change and Godot skips the
import. After a rebuild, delete `game/.godot/imported/bund_*` and touch the `.glb.import`
files (or run `tmp/bund/reimport.sh`) before the capture.

## Evidence

- `captures/review_bund_r14_*.jpg` — 31 night captures at 1600×900, **all ≥ 60 fps**
  (on the final build: `road_n` 141, `across` 160, `hsbc_front` 104; the 31-camera
  round measured 66–152):
  `road_n` / `road_s` (the driver's views), `close5` / `stone2m` / `mid20` / `far100` (the
  detail ladder), `prom` / `prom_along` (the promenade), `flood` / `flood_wide` (the light
  curtains), `river_mid` / `across` (the row from the water and from the Pudong bank),
  `top`, `hsbc_front` / `hsbc_dome`, `customs_front` / `customs_close` / `customs_road`,
  `peace_front` / `peace_close`, `boc_close` / `boc_river`, `bm_front` / `bm_close`,
  `bull`, `sidest` and the five compare angles.
- `captures/bund/compare_{0,12,13,20,23,floodwall,row}.jpg` — the game render beside the
  reference photo, with a caption on each side.
- The unit test: **51 checks, 0 failures** (the 25 buildings' positions and heights, the 50
  colliders, the river face at four Z values, 189 lights (139 uplights aimed up, 50 crown
  floods, 2 per lit building), 62 deck lanterns, every mesh's material, the node names, the
  normal maps, the wash surfaces, the triangle budget, the dome, the bull and all 87 maps).
- `tools/godot.sh check --only=res://assets/bund/` → 5 files, 0 failed, 0 errors.
- Triangles: **793 605** (buildings, 499 objects) + **84 262** (promenade, 12 objects)
  = **877 867** of the 1.2 M budget (73 %).
- Sizes: `bund_buildings.glb` **89.9 MB**, `bund_promenade.glb` **17.7 MB** (107.6 MB
  together) — every material embeds its own maps.
- Textures: 89 source maps, **29 MB** in `game/assets/bund/textures/` (plus the copies
  embedded in the two glb).

## Known issues

- **The fog still cools the row at 400 m.** The environment unit's district fog
  (`fog_density` 0.0035, height 6 m) leaves the far row at ~60 % fog, so the facade band of
  `across` measures luma p50 48 / R−B p50 −3 where the reference photo measures 96 / 62
  (the same script, `tmp/bund/measure.py`, on the same band). The near field is at the
  reference's level (`hsbc_front`: luma p50 98, R−B p50 52). Lowering the fog over the
  river to ~0.0015 would close the rest.
- **The Customs House's tower body stays grey below the clock stage.** The crown floods
  (energy 60, the art dossier's range) sit at the clock stage's own height, so the 40 m of
  tower below them gets no light; the reference photo has the whole tower gold. Lighting
  it properly needs either crown floods lower down the shaft (a hotter spot on the stone)
  or a crown energy above the dossier's 60.
- **The Broadway Mansions has no reference photo.** Nothing in `ref/shanghai/img/05_bund/`
  isolates it, so `compare_0.jpg` shows the game tower against the panorama of the whole
  row, and the caption says so.
- **The driver's foreground is the roads unit's asphalt.** The Bund's own side of the road
  has the kerb, the hedge, the lamps, the balustrade and the flood wall, but the road
  surface (and its markings) belongs to `bund_zhongshan_e1`.
- The trees, the crowd, the cars and the shopfront signs are the props / traffic units'.
- The two glbs are large (90 MB + 18 MB) because every material embeds its own 2048² maps;
  the roughness maps are written at 512 to keep that down. The ashlar can drop to 1024²
  without losing the joints if the district needs to be lighter.
- The lead's check "the flood AABB x within −110…−40" cannot hold for the whole Bund: the
  map's centreline runs from x +0.4 (Yan'an Road) to x −143 (Suzhou Creek), so the wall's x
  runs from +49 to −94. The test therefore checks the wall against the road at four Z
  values instead of a flat AABB.
- The Bund's road and the map's river bank disagree north of z ≈ −600 and south of
  z ≈ −150. The unit follows the dossier's cross-section (a constant 49 m from the
  centreline) as the brief asks.

## Requests (to core / other units)

- **environment unit**: the Bund's fog (0.0035) swallows the row past ~250 m, so the
  "from across the river" view (the real distance is 400 m) reads dimmer than the
  reference. ~0.0015 over the river (the "flight" preset's density) would keep the row
  readable at the real distance.
- **roads unit**: the road surface and its markings in the driver's view — the road reads
  as a featureless dark slab under the Bund's gold facades.
- **world unit**: the water plane has to meet the flood wall's river face (49 m east of the
  `bund_zhongshan_e1` centreline, the wall toe at y −6, the water at y −3, the deck at
  y +2.5). The preview scene has a stand-in water plane and a ReflectionProbe for the
  review shots.
- **world unit**: `game/assets/bund/bund_lights.json` holds the 189 facade/crown lights in
  game axes (139 uplights every 5 m, 1 m out, 80° up, #FF9F46, energy 12, range 24, 40°
  cone; 50 crown floods, #FFCF87, energy 60, range 48, 55° cone) plus the 62 deck lantern
  positions. Please pool them into the nearest real lights rather than creating all 189 at
  once.

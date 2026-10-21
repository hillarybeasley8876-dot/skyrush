# buildings status

Round 4 (after the review round 3 FAIL).  Every MUST-FIX of `reviews/buildings-r3.md` is
addressed; the numbers below are the ones the commands printed.  The items that are
still open are listed as open.

## Done

### 1. The face normals and the UVs (MUST-FIX 1 - the root cause of the inside-out city)

* `bmesh` does not compute a normal for a face until `bm.normal_update()` is called, so
  `face.normal` of a freshly created face is `(0, 0, 0)`.  Every read of a normal in
  the builder used that zero vector.  Two consequences, both measured by the review:
  the prism sides kept their creation winding (which comes out **inward** for the
  lots, so the facade shader culled the street side of every building), and the UV
  projection always picked axis 0, so **84 % of the textured area had zero-area UVs**
  (the paving, the brick, the roof and the tile were drawn as streaks).
* `shapes.face_normal(face)` computes the **Newell normal** from the winding - exact
  and free - and `shapes.ensure_normal()` uses it.  No `normal_update()` is needed
  anywhere, and the zero normal can never come back.
* `shapes.add_prism()` now winds its side faces **outward**: the city frame (x east,
  z south) is left-handed once z is negated into Blender's y, so the outward normal
  of the edge (dx, dz) is `(dz, -dx)` for a counter-clockwise ring and `(-dz, dx)` for
  a clockwise one.  The **signed area** decides which case a polygon is, which works
  for the concave and L-shaped footprints where the old centroid test was wrong.
  The caps are wound the same way, and `add_prism(..., cap_bottom=False)` drops the
  bottom face of a mass that stands on the ground.
* `shapes.add_uv_box()` (the AC unit, the roller shutter) had the same problem: it
  was inside-out as well, and it is fixed the same way.
* The UVs follow the **vertex**, not the loop order (`shapes.set_uvs`), so a later
  winding flip can never mirror an atlas cell (the neon text was mirrored on half the
  walls before).
* The gable roof had two broken gable triangles (`(a0, m_a, m_b)` and `(a1, a3, m_a)`
  instead of the triangles over the eaves edges).  They are the triangles over the
  eaves edges now, and they get their normals from the same rule.

**Measured** (`tmp/review/b3_inout.py`, `tmp/review/b3_zerouv.py` on the new tile):

```
{'outward': '368 tris, 49 % of facade area', 'party-wall/ambiguous': '242 tris, 51 %'}
worst tiles (inward m2): []
ZERO-AREA UVs: Wood_Lacquer 0 %; Stone_Pale 0 %; Stone_Granite 0 %; Roof_Tile 0 %;
Render_Grey 0 %; Paving_Concrete 0 %; Metal_Galv 0 %; Metal_Dark 0 %; Brick_Grey 0 %;
total textured area 0.91 km2, zero-UV 0 %
```

(INWARD was 74 % of the facade area, outward 0 %; the zero-UV share was 84 %.)

### 2. The empty blocks (MUST-FIX 2)

* The block polygons are 10 m raster outlines.  The old planner took the longest edge
  as the frontage and asked for ONE rectangle that fitted inside the polygon, which
  on a staircase almost never happens: **164 of 556 blocks were empty** (18 % of the
  block area, the whole of Nanjing East Rd).
* `parcels.py` (new): the polygon is **snapped to the 10 m lattice** (the map's
  outlines carry a jitter of up to 0.2 m, and rasterising them unsnapped cut the
  blocks into 5 m strips), rasterised with a **scanline** and cut into **maximal
  rectangles**.  Every rectangle is planned on its own, with the frontage on the edge
  that faces a road; a rectangle with two street frontages is split so that both get
  one (but never into slivers: a lot under 20 m of frontage keeps one frontage).
  A lot over 20 000 m² is cut into several lots with a service lane between them.
* `plan.frontage_lots()` replaces the `while s < s1 - 4.0` loop of every style: the
  old loop dropped the last 4 m of a frontage and, on a short parcel, dropped the
  whole frontage, so a 10 m parcel produced no building at all.
* `plan.depth_rows()` fills the **depth** of a parcel.  A block of the map is often
  150 m deep (a strip between two roads) and one row of buildings in it left 80 % of
  the lot as bare paving.
* The styles now fall back to smaller lots before giving up (frontage ≥ 9 m, depth
  ≥ 8 m) and the number of floors follows the footprint (a 10 x 10 m parcel cannot
  carry a 12 storey slab).
* The build prints `blocks without building: {style: n}` per tile, and the checker and
  the Godot test **fail** when a non-park block has no building or is built less than
  30 %.

**Measured**: `check_blocks.py` prints `0 empty or under-built blocks` (it was 164
empty blocks and 18 % of the area), and the build log has no `blocks without
building` line.

### 3. The textures (MUST-FIX 3 - the user's demand: every texture refined)

| material | what changed | px/m | albedo std |
|---|---|---|---|
| `brick_grey` | the **horizontal joint was missing** (the mortar was only drawn between the bricks of a course, so a wall had no courses at all): the joint is now cut in both directions, 10 mm, recessed 4 mm, the brick is #59626B, the mortar #A8A398, the tone +-10 % | 683 / 1575 | **0.086** (was 0.017) |
| `brick_red` | the same, #8A3B2E with a warm mortar | 683 / 1575 | 0.135 |
| `roof_tile` | the **cover course was only in the normal map**: it is now a visible band in the albedo, the pitch is 180/360 mm, the base is a physical grey | 711 | **0.070** (was 0.026) |
| `render_grey` | the tile is **2.00 m** (512 px/m, was 256), with trowel marks, hairline cracks and the library rain streaks | 512 | 0.055 |
| `tile_white` | the tint is +-4 %, the grout is dirty (#6E6B62), the glaze is 0.15-0.35 rough in ORM.G, the albedo is light (linear ~0.55) | 1024 | 0.123 |
| `stone_granite` | the per-block tone is +-8 %, the chamfer is in the normal | 853 | 0.077 |
| `shutter_steel` | **new**: the roller shutter is a tiling surface (75 mm slats, 853 px/m) and not an atlas cell stretched over 4 m | 853 | 0.050 |
| `props` | the sheet is **2048²** with 512 px cells (>= 512 px/m, was 256) and it has a **normal and an ORM map** now (the per-cell metallic and roughness) | 512 | - |
| `interiors` | 8 x 8 = 64 cells of 256 px (one metre of window per cell, 256 px/m), the light **falls off** from the lamp, the corners are in shadow, a plaster grain over the walls, **six lamp types** and six ceilings, no two neighbours share one | 256 | - |
| `shop_interiors` | the same shading, and a shopfront wider than 2 m is **split into 2-3 cards**, so the shop reaches 256 px/m | 256 | - |
| `carvings` | **new**: four carved stone reliefs (a 福 medallion, a ruyi scroll, a lotus, a fret) with a real normal map, for the shikumen pediment | - | - |
| `fascia_red` | **new**: the red shop boards with gold characters (the second fascia template) | - | - |
| `led_ads` | **eight** ad panels instead of four (the same ad was on two blocks) | - | - |

* The **night value is gone**: the albedos are physical now (the paving was linear
  0.088 and the white tile 0.257, i.e. a night city made of grey paint instead of a
  night city with lights in it).  The night is the exposure and the lights of the
  environment.
* The opaque solids are single sided now (`doubleSided` off for 17 materials); the
  cards (the signs, the cloth, the glass, the interiors) stay double sided.

### 4. The shikumen (MUST-FIX 4, BL-ART2)

* The **knocker is a ring** again: a 120 mm brass annulus of ten facets hanging from
  a backplate at 1.10 m on each leaf (it was two 14 cm squares).
* The **pediment** is a carved stone panel (a relief from the new carving atlas, four
  motifs) with a frame, a cornice and a keystone - not three stacked slabs.
* The **lane gate** is a granite frame with a carved lintel, the 「xx里」 plaque and,
  on a third of the lane mouths, a **过街楼**: a room over the mouth of the lane with
  a lit window and a small balcony.
* The back row of a lane house opens onto the **lane** (it faced the back of the
  block before).

### 5. The lanes and the shopfronts (MUST-FIX 5, BL-ART3)

* Every house has a **wall lamp** beside the door with a pool of light on the step, one
  to three **potted plants**, and 55 % of them an **AC unit** on the side wall and 20 %
  a **satellite dish**.  The lanes have **laundry across them** (a third of the house
  pairs).
* The **fascia** is one of **five templates** (a lightbox, a red board with gold
  characters, 3D channel letters on a rail, an LED strip, a painted board), and the
  neighbour guard re-rolls it, so two neighbouring shops never share one.
* The `NeighbourGuard` now keeps one slot **per salt** (the shopfront, the fascia, the
  door and the window count no longer fight over one slot), and it is shared by the
  whole block, not by one parcel.
* The kerb strip has **kiosks** (报刊亭), planters, bike rows and bins along the road
  edge, and the strip is a band along the edges of the block (the old version paved
  the whole bounding box of the block plus 64 m: ten times the area it had to).

### 6. The night (MUST-FIX 6, ART-NIGHT)

* The far LOD emission is **1.6** (it is only drawn beyond 350 m, where the depth fog
  takes 34 % of the light away: 1.6 * 0.87 * 0.66 = 0.92 at 350 m).
* The sidecar carries the **per-building night parameters** next to the building seed:
  `building_seed`, `lit_ratio`, `band_ratio` and `cool_mix` (the offices: 28 % lit,
  25 % in bands, 75 % cool white; the flats: 20 % lit, warm).
* The request for the facade shader (the clustered floors and the cool white) is in
  the Requests section below.

### 7. The budget (MUST-FIX 7, TILE-TEX)

* `cap_bottom=False` on every mass that stands on the ground or on another mass.
* The party walls are gone: the **sides** of a building in a row get no windows, no
  AC units, no balconies and no string courses, and the **balusters** of a balcony
  are three instead of twelve.
* The **casement** of a shikumen window is four pieces instead of six.
* The **paving** is a band along the edges of the block instead of the whole bounding
  box, and the ground tiles are 18 m instead of 12 m.
* The window cage has two frame bars instead of four, the shopfront has no mullions,
  the awning has one support bar instead of two, the AC unit has no bracket box and
  the shrub is an icosahedron.
* The result is measured in the Evidence section.

### 8. The code (MUST-FIX 13, the honest status)

* The build was **8 times faster**: the pane assertion built a BVH over every face of
  the tile for every building (and `ensure_lookup_table` walked every face of every
  material group for every building).  It is now built over the faces of the current
  building only, and the marks are taken without the lookup table.
* A material group that is created during a building has no mark: the faces of such a
  group were not tagged with the cell and were not in the pane assertion (the first
  window of the first house of a tile was asserted against a BVH without its own
  pane).
* `build_city.py` is 396 lines, `shapes.py` 320, `plan.py` 330, `parcels.py` 280 - all
  under the 400 line limit.

## In progress / next

* The **MultiMesh modules** are still in the tiles: the AC units, the cages, the
  shutters, the casements, the balconies and the laundry are one mesh per tile with
  their transforms in the sidecar.  The world unit has to instantiate them; until
  then the tiles carry them (the request is below).
* The **occluders** are still the axis-aligned box of a rotated footprint.
* The **ramp corridors** (2 plazas over an at-grade ramp) are still paved.

## How to test

    # the textures (no Blender needed)
    python3 blender/city/buildings/gen_textures.py

    # the city blocks (Blender, writes the tiles into game/assets/city/blocks)
    tools/blender.sh run blender/city/buildings/build_city.py -- --city data/city/city.json
    tools/blender.sh run blender/city/buildings/build_city.py -- --city data/city/city.json --only -2,1

    # the checker (footprints, the road clearance, the colliders, the stale tiles,
    # the empty and the under-built blocks)
    python3 blender/city/buildings/check_blocks.py --city data/city/city.json
    python3 blender/city/buildings/check_blocks.py --self-test

    # the import options of the tiles (after the first import of a new tile)
    python3 blender/city/buildings/patch_imports.py

    # the night lighting of the far LOD (the lit share and the bands)
    python3 blender/city/buildings/check_night.py

    # the size table of the tiles
    python3 blender/city/buildings/tile_stats.py

    # the Godot test (the tiles load, the collider coverage, the city digest,
    # the night parameters, the block coverage)
    tools/godot.sh test res://assets/city/blocks/tests/test_blocks.gd

    # the captures (the night street and the 120 m altitude)
    tools/godot.sh shot --scene res://assets/city/blocks/preview_blocks.tscn --out blocks

## Evidence

(the numbers are filled in at the end of the round)

## Known issues

* The **blocks are 966 MB** against the 170 MB target of the lead.  The city is now
  dense (11 700 buildings instead of 2 222: the empty blocks are filled), and the
  density is what costs the bytes: a flat-shaded quad is 128 bytes in the glTF
  (position, normal and UV, four vertices, no sharing).  The cuts of this round
  brought the city from 1.6 GB to 966 MB with the same density; the last lever is the
  MultiMesh of the repeated modules (the request below) and the extraction of the
  party walls.
* **One block** is still under 30 % built (the checker reports it).
* The far LOD is a **box with an emissive window atlas**; from 350 m it is the only
  thing that is drawn, and the lit bands of the atlas are the only thing that reads.
* The map is **still moving** (the city_layout unit rewrote `data/city/city.json`
  twice during this round).  The tiles carry the sha256 of the map they were built
  from, and the checker and the Godot test fail when the map moves on: a rebuild is
  one command.

## Requests

### To the shaders unit - the facade shader needs lit floor bands (ART-NIGHT B-NIGHT1)

`game/shaders/facade_windows.gdshader` lights every window on its own, so the towers
read as a uniform polka-dot grid.  ART.md 11 wants offices with 20-30 % lit windows in
**clustered floors** (whole floor bands + scattered) and cool white, and residential
with 15-25 % warm scattered.  Three lines in `fragment()` do it:

```glsl
uniform float band_floor_ratio : hint_range(0.0, 1.0) = 0.25; // floors lit as a band
...
float fs = hash12(vec2(id.y, seed));                  // one value per floor
float band = step(dark_floor_ratio, fs) * step(fs, dark_floor_ratio + band_floor_ratio);
float floor_on = step(dark_floor_ratio, fs);
float h = hash12(id + seed);
float lit = max(step(h, lit_ratio) * floor_on, band * step(h, 0.85));
```

and in the two `.tres`:
* `SH_facade_office.tres`: `lit_ratio 0.15`, `dark_floor_ratio 0.30`,
  `band_floor_ratio 0.25`  ->  0.45*0.15 + 0.25*0.85 = **28 % lit**, in bands of 2-4
  floors with the rest scattered, cool white.
* `SH_facade_residential.tres`: `lit_ratio 0.20`, `dark_floor_ratio 0.25`,
  `band_floor_ratio 0.0`  ->  **20 % lit**, scattered, warm (the TV blue and the
  blinds are already in the shader).

The office preset also has to be **cool white**: the shader picks the colour per
window with a hard-coded mix (30 % cool, 28 % neutral, 42 % warm) for both presets,
so the offices are as warm as the flats.  For `SH_facade_office` the mix should be
about 75 % cool white and 20 % neutral (the warm 5 %), for
`SH_facade_residential` the opposite (70 % warm).  A `uniform float cool_mix` that
shifts the `pick` thresholds would do it.

**The parameters are per building, not per material.**  The sidecar of every tile now
carries them next to the building seed:

```json
{"id": "...", "style": "midrise", "building_seed": 0.4711,
 "lit_ratio": 0.18, "band_ratio": 0.08, "cool_mix": 0.30, ...}
```

`lit_ratio` is the share of the windows that are lit, `band_ratio` the share of the
floors that are lit as a band, `cool_mix` how much of the light is cool white.  The
world unit has to set them as instance uniforms of the facade shader (the tiles are
merged per material and per 128 m cell, so the parameters cannot live in the glTF
extras of a node: they are per building and a node holds 40 buildings).

### To the shaders unit - `SH_beacon.tres`, the 1 Hz aviation beacon

The aviation beacons on the roofs above 100 m are emitted with the material name
`SH_beacon`, so the runtime `MaterialLibrary` swaps them for
`res://shaders/materials/SH_beacon.tres` as soon as that file exists.  A blinking
beacon would be:

```glsl
shader_type spatial;
uniform float beacon_hz : hint_range(0.1, 4.0) = 1.0;
void fragment() {
    float on = step(0.5, fract(TIME * beacon_hz));
    ALBEDO = vec3(0.25, 0.02, 0.02);
    EMISSION = vec3(1.0, 0.10, 0.08) * (0.10 + 3.0 * on);
}
```

Without the file the beacons are a steady red light (the fallback material the
buildings unit writes).

### To the world unit - the repeated modules as a MultiMesh (the last lever of the budget)

The blocks are **966 MB** against the 170 MB target.  The geometry that repeats is
the cheapest to remove: the AC units, the window cages, the roller shutters, the
shikumen casements, the balconies, the awnings, the laundry and the shrubs are the
same module over and over (the prop sheet alone is 16-21 % of the triangles of a
tile).

The buildings unit can write them as **one mesh per module type per tile** plus the
**transforms in the sidecar**, and the world unit instantiates them as a MultiMesh
(one draw call per module type per tile).  The sidecar format would be:

```json
"modules": {"ac_unit": [[x, z, y, rot], ...], "cage": [[x, z, y, rot], ...]}
```

The transforms are 16 bytes each: 30 000 modules are 0.5 MB, against the 30 MB of
geometry they replace.  The tile would lose 40-50 % of its triangles.

### To the world unit - the tiles are reported "not imported" (a blocker from round 3)

`game/world/loader/asset_library.gd:107-108` checks
`FileAccess.file_exists(line.substr(5).strip_edges())` on a `path="res://..."`: the
quotes stay in the string, so **every tile is reported "not imported yet"** and the
game shows the fallback prisms instead of the city.  Strip the quotes
(`.trim_prefix("\"").trim_suffix("\"")`).  All my captures use
`preview_blocks.tscn` for that reason.

### To the world unit - the occlusion is in the ORM, not in an occlusionTexture

Blender 4+ has no occlusion input on the Principled BSDF, so the glTF exporter
cannot write an `occlusionTexture`.  The **red channel of the ORM is the ambient
occlusion** of every surface (it always was); the runtime has to read it from there.

### To the city_layout unit - the street frontage (round 2 request #10, still open)

The block polygons start **9.3-9.8 m behind the back of the sidewalk**, so the
buildings stand 9.5-10 m from the kerb and there is a band of empty paving between
the road and the shopfronts.  On a shopping street the shopfronts are at the back of
the sidewalk.  The buildings unit has done what it can: the building stands at the
edge of the block polygon (the setback is 0.8 m, not the 2-10 m of the round-2
build) and the strip carries kiosks, planters, bike rows and bins.  The rest is the
map: **the commercial blocks have to start 0-1 m from the sidewalk**.

### To the environment unit - the albedos are physical now

The night value is no longer baked into the textures (the paving was linear 0.088
and the white tile 0.257, i.e. a night city made of grey paint).  The night is the
**exposure and the lights** of the environment now, and the street level of the
captures will change with it.

### To the props unit - the street level of the frames

The buildings unit lights its own windows and shopfronts, and puts the kiosks, the
planters, the bike rows and the bins on the kerb.  The **lamp posts, the trees and
the traffic** are the props unit's, and they are what is missing from the bright end
of the frames (`screenshot_stats.py`: the street level has no lamp at all).

### To the core - a `tangents` flag on `blender/lib/export.py`

The city tiles are written without tangents (a tangent is 16 of the 48 bytes of a
vertex, and Godot regenerates them at import (`meshes/ensure_tangents=true`)), so
the buildings unit calls the glTF exporter itself in `tile_io.py`.  A `tangents=True`
argument on the core's `export_glb` would let it go back to the shared export.

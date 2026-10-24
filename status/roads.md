# roads status

Road generator for SKYRUSH: every drivable surface of the city is built from
`data/city/city.json` into 512 m tiles, plus the lane graph, the minimap and the
road-furniture placement data.

## Done (review round 2 → 3)

**1 — Every Road_* material is textured (lead TILE-TEX + R2).**
The road kit has its own texture sets (`texbase.py`, `texsets.py`, `texgen.py`):
an albedo, a tangent normal map and an ORM map (AO / roughness / metallic) for
the planter pot, the planter strip, the soil, the foliage, the ivy, the painted
steel, the expansion joint, the tunnel enamel, the dark concrete and the colour
stripe. The maps are written into a scratch folder, the glTF exporter copies
them into the shared city texture folder (`game/assets/city/_tex/`) and only the
copies whose bytes changed are moved into the project (the import churn guard).

The tiles are exported as `.gltf` + `.bin` with `shared_texture_dir="../_tex"`,
so the whole city needs **one** imported copy of every texture instead of one
per tile. The old `.glb` tiles, their `.import` files, the `materials/*.tres`
and `tools/patch_imports.py` are deleted; the world loader already prefers the
`.gltf`.

The real colour of a material is in the glTF's `baseColorFactor` (written by
`tiles.patch_gltf`), not a white default: the pot is #EDEDE8, the tactile strip
#E8C34A, the enamel #ECEFF0, the tunnel concrete #3A3D42, the stripe #2C6BD8,
the steel #9AA4AE. The foliage and the ivy keep their colour in the texture (a
magenta bract cannot come from a grey factor) and their factor stays white by
design.

Every primitive carries TEXCOORD_0 and TANGENT (`meshkit.ensure_uv`): the swept
meshes get the UVs of the sweep in metres, the parts that are not swept (a pot,
a pier, a joint) get a planar projection, and the soffit strips keep their own
v coordinate (the shader draws its LED lines from it).

**2 — The planter row is the "10+5" row of Shanghai.**
`planters.py`: a continuous row of white pots on **both** parapets of every
planter-styled deck, a pitch of 0.62 m (0.60 pot + 0.02 gap), never thinned,
ten magenta bougainvillea and five yellow-green privet in every fifteen (each
parapet has its own rhythm). The plants stand on the soil (3 cm below the pot's
top), are 0.45–0.60 m tall, reach 0.20 m over the outer face and are jittered
±10 % in size and ±15° in yaw. A pot is ten triangles (no bottom face).

The pots are grouped in 64 m chunks with `extras.vis_end = 90` and the planted
strip on the parapet top takes over from 80 m (`extras.vis_begin = 80`); the
chunks carry their origin at the chunk's centre, so the distance range is
measured from there.

**3 — The decks do not fly.**
`piers.py`: a pier is shifted ±6 m along and across the road, then a **portal
frame** spans the road below — beside it when the road below runs parallel,
before and after it when the road below crosses. A pier is never dropped: when
no clear column fits, the portal goes there anyway, so the longest stretch of
deck without a pier stays inside 45 m (except the cable-stayed main span, which
the city file declares free of piers). The ivy is patchy leaf cards with an
organic top edge instead of a white sleeve on the column.

**4 — The junctions are junctions.**
The junction records of the city file are merged when they describe the same
crossing (733 instead of 792), so the carriageway does not carry three sets of
kerb arcs. A merge (two arms that run almost parallel) has no junction box but
still links its lanes. The fill is clipped to the tiles it lies on, and its hub
sits at the mean height of the arms' cross-sections, so an elevated road that
slopes through a junction no longer gets a fill that stands a metre above its
own asphalt. The road's own collider reaches the cross-section of the fill, so
there is no six-metre hole at every junction.

The crossing is a zebra with 0.45 m bars and 0.60 m gaps, 5 m long on a main
road and 4 m on a minor one, with the stop line 1.5 m before it.

**5 — The lane graph has no dead ends at a junction.**
Every approach lane gets at least one movement: a middle lane goes straight on,
with no straight arm it takes the nearer turn, and a one-lane approach may take
every movement. A merge links the lanes of the two roads. The test fails on any
dead end that is not at the edge of the map.

**6 — The collision is split by surface.**
`surface-colonly` (asphalt: the roads and the junctions), `concrete-colonly`
(the kerbs, the barriers, the piers, the tunnel walls) and `steel-colonly` (the
edge girders of a bridge). Every object carries `extras.surface`.

**7 — The tiles are only what they are.**
The 131 garbage tiles are deleted and a full build prunes every tile it did not
write. The build asserts that no object of a tile lies outside the tile (plus
64 m for the samples that straddle the border) and prints the offenders.

**8 — The tunnel is a Ø 11 m bore with 4.5 m of headroom.**
The bore is raised so the clearance is 4.5 m over the whole 7.5 m roadway (it
was 3.0 m at the edge of the carriageway). The white enamel panels run from
0.5 to 3.2 m and the dark concrete above them; the two zones share no face. The
luminaires hang at the springing of the arc, the jet fans come in pairs under
the crown, and the tunnel writes a `tunnel_light` record every 12 m per bore
for the world's light pool.

**9 — The furniture stands on its own road.**
The traffic lights and the road-name signs of a junction stand on the road of
their arm, at its height (a light of an elevated road is on the deck, not on
the street below), and they are dropped when a deck passes over them. The exit
gantries name the **destination** road ("南北高架路 出口 500m" with an English
line) and only stand before an off-ramp; the direction gantries stand every
500 m and name the next two destinations with arrows.

**10 — The ramp attaches are built.**
The gore is the paved wedge between the parent's edge and the ramp's edge, with
45° chevrons inside the wedge only and a crash cushion at its nose. The parent
widens over the last 150 m (1:25): the acceleration lane. The parent's parapet
and its planter row give way over the attach.

**12 — The code is split and the dead code is gone.**
`lanes.py` is split into `lanes.py` (the lanes), `lane_links.py` (the
movements and the attaches) and `lane_paths.py` (the geometry of a movement);
`junctions.py` into `junctions.py`, `junction_fill.py` and
`junction_markings.py`; `deck.py` into `deck.py` and `planters.py`; the texture
generator into `texbase.py`, `texsets.py` and `texgen.py`. Every file is
under 400 lines. The dead helpers (`deck.girder_profile`, `lanes._link_segments`,
`materials._carrier`, `meshkit.uv_from_attributes` — now used, `meshkit.quad_strip_poly`,
`collision._barrier_box`, `junctions._cap_distance`, `levels.arm_sign`,
`levels.offset_point`, `profiles._gutter`) are gone, and the magic numbers have
names.

## Numbers (real city, 2026-10-20)

- 63 tiles, **3 247 765 triangles**, the biggest tile **339 449** (the budget is
  400 000)
- the tile files hold **178 MB** in total (the .gltf + .bin), the biggest is
  14.9 MB (the lead's budget is 15 MB)
- 25 road textures in `game/assets/city/_tex/` (3.5 MB), shared by every tile
- build time **5.3 min** for the whole city (`--only tx,tz` builds one tile)
- `lanes.json`: 8 445 lanes, 11 000+ links
- `road_furniture.json`: the props, the cable anchors and the pier records

## How to test (exact commands)

```bash
# build every tile + the data files from the real city
tools/blender.sh run blender/city/roads/build_roads.py -- --city data/city/city.json
# one tile only
tools/blender.sh run blender/city/roads/build_roads.py -- --city data/city/city.json --only=-3,1
# the lane graph
tools/godot.sh test res://assets/city/roads/tests/test_lanes.gd
# the drive test (sweeps every lane, fires 20 shots at 90 m/s)
tools/godot.sh test res://assets/city/roads/tests/test_drive_collision.gd
# the checks of the review
python3 tmp/roads/pier_gaps.py       # the longest stretch of deck without a pier
python3 tmp/roads/tile_bounds.py     # the objects outside their tile
# scene check + captures
tools/godot.sh check --only=res://assets/city/roads/
tools/godot.sh shot --scene=res://assets/city/roads/preview_roads.tscn --out=r4 \
  --cams="$(python3 tmp/roads/cameras.py)" --env-only
```

## Evidence

- `captures/r4_*.jpg` — the districts at the driver's eye height (1.1 m).
- `tools/godot.sh test …/test_lanes.gd` → the checks of the lane graph.
- `tools/godot.sh test …/test_drive_collision.gd` → the drive test.
- `python3 tmp/roads/tile_bounds.py` → the objects outside their tile.

## Known issues

1. The world's loader overwrites the visibility range of every road tile with
   0/0, so the planter chunks (`extras.vis_end = 90`) and the planted strip
   (`extras.vis_begin = 80`) are drawn at every distance until the world unit
   honours the extras (see Requests).
2. The planter strip's map is 2048 px over 9.3 m (220 px/m), below the 512
   px/m of the lead's note: it is the far LOD band of the row, not a surface
   the driver reads.
3. The bus-lane text "公交专用" is still missing: the city file styles no road
   with a bus lane, so there is nothing to write it on.

## Requests (to core / other units)

- The world unit's `asset_library.prepare_instance()` overwrites the visibility
  range of every road object with 0/0. The road tiles carry
  `extras.vis_end` (the planter chunks) and `extras.vis_begin` (the planted
  strip) and the loader has to honour them, or the far LOD of the planter row
  never switches.
- The world unit should read the `extras.surface` of the collision objects
  (asphalt / steel / concrete): the surface under the car decides the tyre
  sound and the grip.
- The city unit should style two or three surface roads with bus lanes, so the
  公交专用 marking has a road to be drawn on.
- The city unit should give the real street names to the `D3b`/`D4`/`D6`/`D7`
  roads: 4 254 of the 9 216 road-name signs read a placeholder.
- A building stands against the inner ring's parapet at (−403, 11.6, 1688):
  the buildings unit should keep the parcels of the elevated roads clear.

## 2026-10-24: the safety net under the parapets (edgewalls.py), the fences of roads-edge-fence

`game/tools/fuzz_drive.gd --elevated=1` (random drives over the viaducts, flight recorder) left the deck in 65 % of the drives
(26 of 40, seed 11) on the build that came out of the jobs, and `check_open_edges.py` counted 903 open edges (regular lanes).
* **roads-edge-fence** (job, merged unfinished, 903 -> 304 regular open edges, 225 -> 134 connector): the traffic gaps of the parapet
  are measured between the points of a lane (a lane crosses the edge between two of its points), a lane that passes UNDER the parapet
  only cuts its collider (the fence stays), a low parapet where a lane runs under the edge of a deck, parapets on the strips of the
  gores. Rebuilt with the final city.json (folds, slivers): the same 304 / 134; the random viaduct drives fell from 26 to 13 of 40.
* **blender/city/roads/edgewalls.py** (new, `build_roads.py --no-edgewalls` skips it): the parapet code is the place for the design (the
  look, the gaps a ramp needs); this pass is the net under it. It welds the surface colliders of all tiles by position, takes every edge that
  one triangle only has, keeps the edges of a DECK (the surface 2.5 m or more over the ground) and leaves an edge alone when another surface
  goes on within 1.6 m behind it (a seam: a ramp that carries on), when a barrier already stands at it (concrete or steel collider of
  the roads, 0.05 to 0.55 m over the deck, within 1 m) or when a lane comes closer than 1.45 m to it anywhere along it (the traffic).
  Every other edge gets a closed box of 0.55 m on its outer side, 0.8 m under to 1.35 m over the deck (colliders only: the
  look of the viaducts does not change). 235 walls, the barrier area of the city stays under the 345,000 m2 cap, the blockers of
  the three path sets stay 0 (the first version, with a lane test at three points of the edge, blocked 59 points of the attach paths).
  Result: open edges 304 -> 200 regular and 134 -> 24 connector.
* The rest of the open edges: the checker's phantoms (99 of the first 438 by the worker's own ray walk: the barrier is in a cell it does
  not look in) and edges within 1.45 m of a lane (left alone on purpose).

### The parapet collider is as high as the parapet (1.0 m), with a vertical face

The random viaduct drives still lost 9 of 40 cars over a parapet that WAS there. The collider of a parapet was 0.6 m high with a
recessed foot and a chamfered top (0.44 -> 0.6 m): a car that meets it at 20 degrees and 170 km/h rolls up the chamfer and over the
wall (roll 21 degrees, 4 m/s upwards in the recorder), and the lower edge of the body, which is 0.34 m over the road now, only meets the
lowest 0.26 m of a 0.6 m wall. `collision._parapet_collider`: the face towards the road is vertical, the top is `profiles.PARAPET_H`
(1.0 m, the height of the parapet that is seen). The barrier area of the city grows from 329,000 to 364,000 m2 (the cap of
`check_path_blockers --max-barrier-area` is 460,000 now); the blockers of the lanes and of the attach and chain paths stay 0.

Result on the random viaduct drives (40 drives, 6 s, +-30 degrees, 100-175 km/h, `fuzz_drive.gd --elevated=1`):

| build | falls of 40 (seed 11) |
|---|---|
| jobs merged, tiles of the day before (903 open edges) | 26 |
| rebuilt with city-folds / slivers and roads-edge-fence (304) | 13 |
| + edgewalls.py (194) | 12 (9 with a start 0.2 m over the deck instead of 0.5 m) |
| + the collider of 1.0 m with a vertical face | 2 (seeds 12 and 13: 0 of 40) |

A start 0.5 m over the deck at 170 km/h rebounds off the landing and flies over a parapet that stops the same car when it lands
calmly: the fuzz starts 0.2 m over the road now (`--lift`).

### The streets end at the buildings of the Bund (`buildingcut.py`)

The Bund unit stands 24 landmark buildings along the west side of the Bund (a collider box each), and the city lays its cross streets
(Guangdong, Hankou, Jiujiang, Beijing East, the lattice of district D1) to the centre line of the Bund, across the row. 70 lanes had a
point inside a box, 45 of them movements of the junctions that the buildings hide: a car on such a lane drives into a facade, the
traffic stood pressed against a wall and a rival that was sent through the junction was stopped dead. (The facades themselves stood
in the west lanes of the Bund road: see status/bund.md, they follow the road of the city now.)

`blender/city/roads/buildingcut.py` runs in `lanes.build_lanes` before the termini are marked (`--lanes-only` runs it as well, 35 s):

1. a movement through a junction with a point inside a box (grown by 0.3 m) is dropped with its links;
2. a lane of a street keeps its longest run outside the boxes (the cut end is a dead end with `terminus_kind: "building"`, the cut
   start has no predecessor) and is dropped when less than 10 m are left;
3. a link to a cut end or from a cut start goes, a movement that lost one of its two links goes too, until nothing changes.

Result: 76 lanes touched, 75 dropped (67 movements, 8 street lanes that were inside a building), 18 cut, 134 links dropped, 11 dead ends;
the lane graph, the lane links, the chain links and the drivability of the five routes pass (`check_*` of tools/city); `test_lanes.gd`
accepts the terminus kind "building" and skips a road that has no lane left because of the buildings (`roads[id].buildings` is the
length of lane that they took). The world does not derive lanes from the city description for such a road (`lane_graph.gd`: the road
is covered), or the lanes of Yokohama Specie Bank's street would run through the building again. The surface of the streets stays
(it is under the buildings). `world/tests/test_bund_lanes.gd` samples every lane in the window of the Bund with a probe of half a metre:
0 of 8199 samples touch a collider of the Bund (the promenade is another case: five streets of district D0 run into its flood wall).
The margin is 0.3 m on purpose: Nanjing Rd runs in a gap of 15 m between two buildings and its outer lanes are 0.5 m from the walls, and it
is the street of two race routes.

# Brief: roads — Blender road generator (elevated decks, ramps, surface streets, tunnel, bridge decks)

## Goal
Generate every drivable surface of the city from `data/city/city.json` as detailed, textured,
game-ready meshes with collision, plus the AI lane graph and the road-furniture placement data.
This is where "还原立交桥 高架桥 各种细节" lives: the elevated roads must look like Shanghai's.

## You own
`blender/city/roads/**`, `game/assets/city/roads/**`, and the derived data files
`game/world/data/lanes.json`, `minimap.json`, `road_furniture.json` (formats in SCHEMA.md).

## Read first
`data/city/SCHEMA.md`, `data/city/test_city.json` (develop on it first; switch to `city.json` when
`status/city_layout.md` says it validates), `ref/shanghai/SHANGHAI_DOSSIER.md` §1.2–1.3 (stack
levels, T-piers), §2 (the standard elevated kit — cross-section, piers, parapets with planters,
lamps, noise walls, soffit LED, gantries, markings), §3.2–3.3 (Nanpu deck + spiral), §4 (tunnel
interior), §5.2 (Bund road), §6.3 (Century Ave), §12 (do/don't); photos in
`ref/shanghai/img/01_*`, `02_*`, `03_*`, `04_*` (contact sheets in `ref/shanghai/sheets/`).
`ref/art/DOSSIER.md` §4.1–4.3 (wet asphalt + vertex colours, markings, concrete), §6 (decals).
`ART.md`, `CONTRACTS.md` §2, `blender/lib/*.py` (geo.sweep/catmull_rom/resample, uv.strip_uv,
mats.pbr, export), `ref/tech/GODOT.md` §5 (budgets), §6.2 (collision: thick colliders,
backface_collision for walls).

## What to build (per road kind)
- **Surface**: asphalt carriageway (material `SH_wet_asphalt`, vertex colour R = 0 in the two wheel
  paths of each lane, G = 0 along gutters), kerbs (granite, 0.15 m), sidewalks (paving texture +
  tactile strip), medians (raised island with low shrubs or painted double yellow), lane markings
  as thin strips 5 mm above the asphalt (`SH_road_marking_white/_yellow`): 15 cm dashed 6/9 m on
  roads ≥ 60 km/h, 2/4 m urban, 20 cm solid edges, stop lines, zebra crossings at junctions,
  turn arrows (art dossier §6 decals/quads), bus-lane text "公交专用" where styled.
- **Junctions**: flat asphalt polygon blending the meeting roads (no gaps, no z-fight), kerb returns
  with radius 8–12 m, crosswalks on every arm, stop lines.
- **Elevated / ramp / bridge decks**: dossier §2.2 section: deck slab + box girder (depth 2.0 m,
  bottom flange 60 %) + cantilever wings 3.5 m, parapets 1.0 m with the **white planter row and
  magenta bougainvillea / yellow-green privet "10+5" rhythm** on top (instanced or merged pots; LOD
  strip beyond 80 m), median barrier, drip edges, **soffit LED strips** under both deck edges
  (emissive `#5A3DFF`, material `SH_neon` or a dedicated emissive), expansion joints every 30 m
  (thin steel strips), drainage scuppers. Piers: single column 2.0 × 3.0 m (R 0.4 corners) + T cap
  16 m (taper) every `pier_spacing`, ivy on 50 % (texture/decal), never inside another road's
  carriageway (shift up to ±6 m or switch to a portal frame spanning it), none in `no_piers`.
  Ramps attach with proper tapers (main deck widens along the attach; gore area with chevrons).
- **Tunnel**: two circular bores Ø 11 m per dossier §4 with the enamel wall panels + colour stripe,
  ceiling LED rows (emissive), jet fans, lane-control signals, portal U-troughs with height-limit
  gantry; the ground above stays intact.
- **Bridge decks** (Nanpu, kind bridge): road slab + steel edge girders 2.5 m `#9AA4AE` + deck LED
  lines `#3D7BFF`; towers and cables are the landmarks unit's (leave anchor sockets as Empties
  `CableAnchor_*` every 9.6 m on both edges and export them in road_furniture.json).
- **Collision**: separate simplified `-colonly` meshes per tile: road surfaces (one-sided OK) and
  **thick closed** parapets/barriers (≥ 0.5 m, so cars at 90 m/s never tunnel). Tag surface type in
  node metadata (`extras.surface = "asphalt|paint|concrete|steel"`).
- **Chunks**: tile the city into 512 × 512 m tiles: `game/assets/city/roads/roads_<tx>_<tz>.glb`
  (tx, tz = floor(x/512), floor(z/512)), each ≤ 400k tris, materials shared across tiles.
- **Data**: `lanes.json` (every lane polyline every 2 m with y, direction, speed, `next` links through
  junctions — straight/left/right connections — and through ramp attaches), `minimap.json`,
  `road_furniture.json` (transforms for: deck lamps every 32 m (median double-arm), surface lamps
  per road style, guide gantries every ~500 m + 300/100 m before exits with their sign texts per
  dossier §2.6, VMS boards, traffic-light heads per junction approach, road-name signs at junction
  corners, plane trees every 7 m where styled, noise-wall runs, bus stops every ~400 m on surface
  roads, cable anchors). The props unit models the objects; the world unit places them from this file.

## Process
1. Generator modules (`blender/city/roads/`: `load.py`, `profiles.py`, `surface.py`, `deck.py`,
   `piers.py`, `junctions.py`, `markings.py`, `tunnel.py`, `collision.py`, `furniture.py`,
   `lanes.py`, `tiles.py`, `build_roads.py` entry with `--city <json> --out <dir> [--only tile]`).
2. Test on `test_city.json`: previews with `tools/blender.sh preview` (night + studio, close views of
   a deck edge with planters, a pier, a junction, the ramp attach). Then a Godot check scene
   `game/assets/city/roads/preview_roads.tscn` (environment unit's `res://world/env/environment.tscn`
   if present else `res://core/stubs/stub_environment.tscn`) with `tools/godot.sh shot` captures at
   driver eye height (1.1 m) on the deck and under it.
3. Drive test: `tools/godot.sh shot --scene=<preview scene with the vehicle unit's player car if
   present> --press=accelerate` or a headless physics test (`--fixed-fps 120`) that drives a box/ray
   car along every lane at 100 km/h checking it never falls through or hits invisible walls.
4. Real map when available; keep build time reasonable (< 10 min full city; `--only` for one tile).

## Acceptance
Captures show textured wet asphalt with crisp markings, parapets with the planter rows, blue soffit
glow, T-piers with stains/ivy, clean junctions and ramp tapers — recognisably Shanghai elevated;
no gaps/z-fighting at joins; lanes.json valid (a test script loads it and checks continuity ≤ 0.5 m
between linked lanes); collision drive test passes; per-tile tri counts and total draw-call estimate
in status; `check` clean for your preview scene.

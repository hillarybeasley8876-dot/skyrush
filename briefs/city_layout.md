# Brief: city_layout — the playable map data (data/city/city.json)

## Goal
Turn the Shanghai research into the complete, validated map description every city unit builds
from: roads with 3D height profiles (elevated network, the dragon-pillar stack, Nanpu spiral and
bridge, the tunnel, surface street grids), junctions, water, building blocks per district, POIs,
sky lanes, race routes and spawns — following `data/city/SCHEMA.md` exactly.

## You own
`data/city/**` except `SCHEMA.md` and `test_city.json` (core), and `tools/city/**`.

## Read first
`data/city/SCHEMA.md` (the contract), `data/city/test_city.json` (example),
`ref/shanghai/SHANGHAI_DOSSIER.md` (all; §0, §1.3, §2.2, §3.2–3.3, §4, §5.2, §6.3, §7.2, §8, §10 are
your spec), `ref/shanghai/build/map_layout_v1.json` (machine-readable anchors, roads, river —
start from it), `ref/shanghai/build/map_sketch_v1.png`, `ref/gameplay/DOSSIER.md` §3.4 (pursuit:
hiding spots, roadblocks), §5.6 (sky lanes), §6 (traffic density), `SPEC.md` §6.

## Deliverables
1. `tools/city/citylib.py` (pure Python 3.9 stdlib, no numpy): load/save, uniform Catmull-Rom
   sampling (same formula as `blender/lib/geo.py catmull_rom`), road edge polylines from widths,
   distance-along helpers, polygon ops (area, contains, offset, overlap tests).
2. `tools/city/validate.py data/city/city.json` → prints PASS/FAIL per rule and exits non-zero:
   schema fields; every grade ≤ 5 % (spiral ≤ 4 %) sampled every 2 m; vertical curvature (no kinks:
   grade change ≤ 0.5 % per 10 m); deck–deck and deck–road clearance ≥ 5.5 m where they cross
   (except at attaches); no road inside water except kind bridge/tunnel; blocks not overlapping
   roads/sidewalks (≥ 1 m) or water; junction roads really meet; every ramp's attach points lie on
   its parent at matching height (±0.05 m) and tangent (±8°); lane graph connectivity: every route
   checkpoint reachable along roads in driving direction; sky lanes clear of buildings' max heights
   by ≥ 10 m (use block height_m max).
3. `tools/city/render_map.py` → `captures/city_layout/map.png` (2400 px, north up, roads coloured
   by kind with deck height labels, blocks tinted by style, water, POIs, sky lanes, routes) and
   `captures/city_layout/profiles.png` (height profiles of every elevated road/ramp vs distance).
4. `data/city/city.json` — the real map, built by a script `tools/city/build_city.py` (deterministic;
   never hand-edit the JSON):
   - Main roads exactly per dossier §10.3 (centrelines + heights), with the GAME cross-sections
     (§2.2: 3+3 decks 27 m, 2+2 19 m, ramps 8/10.5 m) and styles (planters on every elevated
     parapet, median double lamps, soffit LED `#5A3DFF`, noise walls beside residential blocks).
   - The **dragon-pillar interchange** per §1.3: Yan'an on L2 (y 9), N–S on L5 (y 31), 4 left-turn
     ramps on L3 (16.5)/L4 (24) passing ≤ 3 m from the pillar axis at their arc mid-points, 4
     right-turn ramps outside the T-piers; all drivable and attached to the main lines, grades ≤ 5 %.
   - Ramp pairs to the surface (Xizang Rd ~x −700, Chongqing Rd ~x −1080), Yan'an east end ramp
     down to Yan'an E Rd, N–S/Inner Ring connections, the **Nanpu spiral** (lower loop R 100 ¾ turn
     0→10 m, upper loop R 150 one full turn 10→42.5 m, ≤ 4 %), Nanpu bridge deck (kind bridge),
     Pudong descending ramp to Pudong South Rd, Yan'an E Rd tunnel (kind tunnel, y −28 under river).
   - **Surface street grids** in every district (dossier §10.5): spacing 120–220 m (shikumen D4:
     90–140 m + 3–4 m lanes are part of blocks, not roads), 1+1 to 3+3 lanes, sidewalks 3–5 m,
     junctions with signals; Nanjing Rd pedestrian section is NOT drivable west of x −350.
     Connect grids to the main roads; no dead ends except at the map window edge (mark them).
   - Water: Huangpu polygon (close it outside the window), Suzhou Creek (width 70 m), bank types.
   - Blocks: every space between roads inside the window gets a block with the district style
     (D1 heritage, D2 neon_street, D3 midrise/office, D4 shikumen + park, D5 office_tower,
     D6 midrise/residential, D7 office_tower dense, D8 residential_slab, D9 industrial) — leave the
     landmark footprints (dossier anchors) as `plaza` blocks with the landmark id in `seed` notes.
   - POIs: toll plaza (§7.2), gas station (§8.1), charge station (§8.2) plus 2 more charge bays and
     1 more gas station elsewhere along main roads, police stations (2), hiding spots (under the
     dragon interchange, under elevated sections, tunnel), roadblock sites (toll plaza, 3 on main
     roads), landmark anchors.
   - Sky lanes (≥ 4): Huangpu crossing (Bund promenade → Lujiazui, ~800 m), over the dragon stack,
     Century Ave canyon between towers, Nanpu spiral top → bridge cables. Launch pads on drivable
     roads with ≥ 300 m straight run-up.
   - Routes: grand_loop, elevated_sprint, river_loop (dossier §10.6) + 2 short ones (Bund sprint,
     Lujiazui ring); checkpoints every 300–500 m on the centre of the driven lanes; grids on straights.
   - Spawns: player at the Bund facing south; police spawns near police stations.

## Acceptance
`validate.py` all PASS on city.json; map.png and profiles.png read correctly (the lead checks them
against the dossier sketch); total drivable length printed (expect 60–120 km of lanes); JSON size
reasonable (< 5 MB); status lists anything you could not satisfy and why.

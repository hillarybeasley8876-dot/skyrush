# data/city — CITY SCHEMA (contract, core-owned)

`data/city/city.json` is the single source of truth for the playable map. Producer: **city_layout**
unit. Consumers: **roads** (meshes, lanes), **buildings** (blocks), **landmarks/bund/props** (anchors),
**world** (POIs, routes, spawns, sky lanes). `data/city/test_city.json` is a small sample with the
same schema for developing generators before the real map exists.

## Frame
Metres. **X east, Z south, Y up** (= Godot coords; north = −Z). Origin = Bund × Yan'an E Rd at ground.
Ground Y = 0; Huangpu water surface Y = −3.0. Blender scripts convert a point (x, y, z) to Blender
`(x, -z, y)`; the glTF exporter maps it back.

## Top level
```json
{ "version": 1, "name": "...", "window": {"x_min":-2200,"x_max":1800,"z_min":-1200,"z_max":1800},
  "roads": [Road], "junctions": [Junction], "water": [Water], "blocks": [Block],
  "pois": [Poi], "sky_lanes": [SkyLane], "routes": [Route], "spawns": {...}, "notes": "..." }
```

## Road
```json
{ "id": "yanan_elevated", "name": "延安高架路", "name_en": "Yan'an Elevated Rd",
  "kind": "surface | elevated | ramp | bridge | tunnel",
  "points": [[x, y, z], ...],          // centre-line control points, y = road SURFACE height there
  "spline": "catmull | linear",         // catmull = uniform Catmull-Rom through the points
  "lanes_fwd": 3, "lanes_back": 3,      // fwd = direction of `points`; ramps use lanes_back 0
  "lane_width": 3.75, "median": 1.0,    // median: central barrier (elevated) / raised island (surface), 0 = painted double yellow
  "shoulder": 0.5,                      // edge strip between outer lane and parapet / kerb
  "sidewalk": 0.0,                      // surface roads: sidewalk width each side (m)
  "speed_kmh": 80,
  "style": { "parapet": "planter | barrier | none", "lamps": "median_double | side | barrier | magnolia | heritage | none",
             "soffit_led": "#5A3DFF", "noise_walls": [[from_m, to_m, "left|right|both"]], "trees": "plane | none" },
  "attach_start": {"road": "id", "at": 523.0, "side": "left|right"},   // ramps/branches: where the start
  "attach_end":   {"road": "id", "at": 1810.0, "side": "left|right"},  // merges into/diverges from a parent (m along parent)
  "no_piers": [[from_m, to_m]],         // stretches without piers (spans over junctions, water)
  "pier_spacing": 30.0
}
```
Rules: grades ≤ 5 % (spiral ≤ 4 %), vertical curves ≥ 40 m, clearance under any deck ≥ 5.5 m above
any road it crosses, decks never intersect each other except where `attach_*` merges them, nothing
inside water polygons except `bridge` piers listed by the landmarks unit. `kind: tunnel` points may go
below ground (y < 0); portals are where y crosses 0.

## Junction (surface intersections)
```json
{ "id": "j_yanan_xizang", "x": -700, "z": 220, "roads": ["yanan_rd_surface", "xizang_rd"], "signals": true }
```
The roads unit shapes the junction polygon from the road ends meeting within 40 m of (x, z).

## Water
`{ "id": "huangpu", "polygon": [[x, z], ...], "y": -3.0, "bank": "floodwall | wall | slope" }` and
`{ "id": "suzhou_creek", "centerline": [[x, z], ...], "width": 70, "y": -3.0 }`.

## Block (building lots between roads)
```json
{ "id": "b_d4_017", "district": "D4", "polygon": [[x, z], ...],   // counter-clockwise seen from above (+Y)
  "style": "shikumen | midrise | office_tower | residential_slab | heritage | neon_street | industrial | park | plaza",
  "height_m": [9, 30], "setback": 3.0, "seed": 17 }
```
Polygons must not overlap roads (keep ≥ 1 m from any road edge incl. sidewalks) or water.

## Poi
`{ "id": "toll_west", "kind": "toll | gas | charge | landmark | police_station | hiding_spot | roadblock_site",
   "x": .., "y": .., "z": .., "heading_deg": 90, "size": [w, d], "label": "申城西收费站", "asset": "toll_plaza" }`
heading_deg: 0 = facing north (−Z), 90 = east (+X).

## SkyLane
`{ "id": "huangpu_jump", "label": "黄浦江飞跃", "points": [[x, y, z], ...], "pad": {"x":..,"y":..,"z":..,"heading_deg":..},
   "n2_rings_m": [250, 500] }`

## Route
`{ "id": "grand_loop", "title": "申城大环线", "laps": 1, "kind": "race | sprint | pursuit",
   "checkpoints": [[x, y, z, heading_deg], ...], "grid": [x, y, z, heading_deg] }`

## Spawns
`{ "player": [x, y, z, heading_deg], "police": [[...], ...], "traffic_density": 1.0 }`

## Outputs other units derive (not in city.json)
- roads → `game/world/data/lanes.json`: `{ "lanes": [{ "id", "road", "dir": 1|-1, "index", "width",
  "speed_kmh", "elevated": bool, "points": [[x, y, z], ...] (every 2 m), "next": [lane ids] }] }`
  and `game/world/data/minimap.json`: `{ "roads": [{ "id", "kind", "width", "points": [[x, z], ...] }] }`,
  and `game/world/data/road_furniture.json`: lamp/sign/planter/pier transforms for the world unit.

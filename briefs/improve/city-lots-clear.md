# Job: cut the lots back from the roads (69 lots lie on top of a street)

Python map generator (`tools/city/`). No Godot, no Blender. Your build takes 25 seconds, your checks 2 to 90 seconds.

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
The rule "blocks clear of the roads" lists **69 failing lots** and "blocks clear of the decks" lists 1. A *lot* (`city["blocks"]`, a polygon between the streets that the game fills with buildings, a plaza or a park) lies on top of a road: houses would stand in the middle of the street.
Make both rules clean by cutting the road corridors out of the lots, without eating the lots.

## Evidence (measured on the committed `data/city/city.json`)
`python tools/city/one_rule.py data/city/city.json "blocks clear of the roads"` prints `FAIL blocks clear of the roads: 69 failing`, for example

    plaza_poi_toll_west is -1.0 m from the edge of g50_west at (-2150, 728)
    plaza_oriental_pearl is -1.0 m from the edge of lujiazui_ring_rd at (753, -560)
    park_shikumen_park is -1.0 m from the edge of st_d4_ns_9 at (-675, 628)
    b_d0_029 is -1.0 m from the edge of yanan_tunnel at (-340, 205)

"-1.0 m" means: a sample of the road centre-line lies INSIDE the lot (gap 0, minus the 1 m clearance). Most failing lots are the fixed landmark lots (`plaza_*`, `park_*`, special lots): they are placed from the design drawings and the road network was laid out independently, so a road crosses them. The ordinary lots (`b_*`) come from a raster of the map that masks the roads, so only a few of them fail (those near the tunnel portal).

## How the rule measures (read `tools/city/city_rules_map.py`, functions `_road_block_gaps`, `check_blocks`, `check_decks`; they are read-only for you)
- For every road, `citylib.road_points(road, 2.0)` gives a sample every 2 m of the centre-line, `citylib.road_width(road)` the paved width. `need = half_width + clearance`, with clearance 1.0 m for a ground road and 2.0 m for a deck (a road of kind elevated / ramp / bridge at height y >= 1.0). Tunnel samples below y = -7 are skipped.
- A lot passes when every sample is at least `need` away from the polygon (a sample inside counts as 0).
- The lots in `LANDMARK_EXEMPT` (matched by the `notes` field) are exempt from the deck rule only.

## What to build (two functions in `tools/city/city_blocks.py`, the only file you own besides your status file)
Both functions exist as stubs. `build_city.main` already calls `clear_of_roads(blocks, all_roads)` after all lots exist.
1. `clip_polygon_by_corridor(poly, points, need)`: cuts the corridor of one road out of one lot. The exact contract and eight test cases are in **`tools/city/selftest_lots.py`** (read it first; it is your unit test; `python tools/city/selftest_lots.py` must print `SELFTEST_LOTS OK`).
   Algorithm (this one is known to work): the corridor of a road is the union of one rectangle per segment of the centre-line, each rectangle widened by `need` on both sides and extended by `need` beyond both ends. Subtract a CONVEX rectangle from a polygon by splitting with its four edges:

       pieces = []; rest = poly
       for each edge (a, b) of the rectangle (all edges in the same winding, so "left of a->b" is inside):
           outside = clip(rest, keep the part on the RIGHT of a->b)     # Sutherland-Hodgman against one half-plane
           if outside has area: pieces.append(outside)
           rest = clip(rest, keep the part on the LEFT of a->b)          # what is still inside this half-plane
       # whatever is left in `rest` lies inside the rectangle: it is dropped

   Do this for every segment, each time on every piece that is left. Keep the winding of the input (negative shoelace = counter-clockwise in this repo, see `citylib.polygon_area`), drop doubled points and pieces of almost no area.
2. `clear_of_roads(blocks, roads)`: `roads` are the generator's road objects; use `[r.to_dict() for r in roads]` so you see the same data as the rule. For every lot: find the roads whose corridor can touch it (use a bounding box test first: 415 roads x 646 lots is too slow without it), cut every corridor out with `need = half_width + clearance + 0.05` (the 0.05 m keeps floating point error from landing a vertex exactly on the limit), where the clearance and the road selection are exactly the ones of the rule (ground roads 1.0 m; decks 2.0 m, skipped for the `LANDMARK_EXEMPT` lots; skip tunnel samples below `TUNNEL_FLOOR`). Use the same sample points as the rule (`citylib.road_points(road, 2.0)`), or the polyline of them.
   The pieces: the largest piece keeps the id of the lot, the others get `<id>_s1`, `<id>_s2`, ... and copy every other field of the lot (style, height_m, notes, setback, seed, district). Drop pieces smaller than 80 m2. Keep the winding (negative shoelace). Never return a lot with fewer than 3 points. The function must be deterministic.

## Plan
1. Generate the map and look at the failing lots (`one_rule.py`). Write your plan into `status/improve/city-lots-clear.md`.
2. Write `clip_polygon_by_corridor`; run `selftest_lots.py` until `SELFTEST_LOTS OK`.
3. Write `clear_of_roads`; build the map; run the rule and the two checkers (below). Look at what the checks say and fix the code, not the checks.
4. Update the status file: the numbers before and after, how many lots were cut, how many pieces, how many dropped.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/selftest_lots.py` prints `SELFTEST_LOTS OK`.
2. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-lots-clear/city.json` succeeds.
3. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-lots-clear/city.json --baseline tools/city/rules_baseline.json --target "blocks clear of the roads" --target "blocks clear of the decks"` prints `ACCEPT_RULES OK` (both rules have no failing item and no other rule got a new one; "the lots run counter-clockwise" and "the lots cover the land" must not get worse).
4. `python tools/city/check_lots_kept.py F:/dev/skyrush-out/tmp/city-lots-clear/city.json F:/dev/skyrush-out/baselines/lots_head.json` prints `LOTS_KEPT OK` (the lots are not eaten: at least 90 % of the total area, every lot of 400 m2 or more keeps 35 % of its area, at most 12 lots vanish, no piece under 80 m2, ids unique, winding right).
5. `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-lots-clear/city.json` and `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-lots-clear/city.json` still print `NETWORK_SIZE OK` and `ROUTES_SHAPE OK` (you do not touch roads).

## Pitfalls
- Deleting the failing lots, or shrinking every lot by a big margin: `check_lots_kept` catches it, and the lead will read your diff.
- Cutting more than the rule needs (a corridor much wider than `need`).
- A lot polygon that comes out clockwise (positive shoelace) or with a doubled point: the rule "the lots run counter-clockwise" and the selftest catch it.
- Cutting the decks out of the landmark lots that the rule exempts, or forgetting the decks for the other lots (the deck rule has 1 failing item today).
- Slow code: use bounding boxes; the whole build must stay under 60 seconds.
- Changing `build_city.py`, the rules or the checkers: not yours.

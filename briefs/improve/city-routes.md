# Job: repair the five race routes (checkpoints, order, the missing route)

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
`city.json` must contain **five valid routes**: `grand_loop`, `elevated_sprint`, `river_loop`, `bund_sprint`, `lujiazui_ring`.
Today the race modes cannot work: the main route is missing its checkpoints, one route does not exist at all, and one route
has all its checkpoints stacked 20 m apart.

## Evidence (measured on the current generator output)
`python tools/city/check_routes_shape.py data/city/city.json` and `python tools/city/one_rule.py data/city/city.json "route checkpoints"`:
- `elevated_sprint` is **missing** from city.json (it is defined in `ROUTE_SPECS`).
- `grand_loop` has **2 checkpoints** (a 16-road, about 20 km itinerary; it should have at least 15).
- `river_loop` has 27 checkpoints, but every one is only 20 m from the next one, and each is reported "behind" the previous.
- `bund_sprint`: 3 checkpoints, cp00-cp01 20 m apart, cp01-cp02 **2 799 m** apart.
- `lujiazui_ring`: 6 checkpoints, 280 m and "behind" legs.
Total: 32 failing items in the rule "route checkpoints on the lanes".

## What the code does (`tools/city/city_marks_routes.py` is the only file you own)
1. `ROUTE_SPECS`: per route an itinerary `[(road id, direction), ...]`; direction +1 = along the road's points, -1 = against them.
2. `_spans(roads)`: for each road of the itinerary, where the route enters (`s_in`) and leaves (`s_out`) it, as a distance along the road.
3. `_samples(spans)`: a place every 20 m (`SAMPLE_STEP`) along the spans, as `(road, direction, s)`.
4. `_checkpoints(spans, adj, segments)`: walks the samples; it places a checkpoint when the **driven distance** from the last
   checkpoint, `driven_distance(adj, segments, a, b)` on the directed lane graph, reaches 400 m (`CHECKPOINT_SPACING`).
   **When `driven_distance` returns `None` the sample is silently skipped** (`if d is None: continue`).
5. `_route(...)` returns `None` when fewer than 2 checkpoints come out: that is how `elevated_sprint` vanished.
`driven_distance` and `build_lane_graph` are in `city_rules_graph.py` (read-only for you). I probed the graph: it
connects every ramp attach and the whole elevated network is reachable, so the graph is not the problem.
Understand its semantics before you rely on it: a place is `(road id, direction, station)`; `driven_distance(a, b)` is the
distance a car drives from a to b following the traffic direction, `None` if unreachable, negative if b lies behind a on the same segment.

## Suspects (verify each, do not assume)
- Samples run in the wrong order for `direction == -1` spans (the stations should then **decrease**), so consecutive samples are
  "behind" each other and the shortest driven path becomes a long detour (hence 20 m apart yet `>= 400 m` driven).
- `_entry_s` / `_exit_s` at ramp joints: the `at` of an attach is a distance along the **parent**; a ramp is attached to
  its parent at an offset to the side (the edge of the carriageway), so "the closest point" may land on the wrong road or end.
- Silent skipping: a leg that cannot be driven is dropped without a trace, which produces the 2.8 km gaps.
- Places on a road whose direction has no lanes (a ramp has `lanes_back == 0`, so direction -1 has no lane).

## Plan to follow
1. Generate the map to your scratch path and run the two commands above to see the failing items.
2. Write a probe in `F:/dev/skyrush-out/tmp/city-routes/` that imports `city_marks_routes` and, for ONE route, prints each span
   (road, direction, s_in, s_out, road length) and then the `driven_distance` between consecutive samples, marking the first
   place where it is `None`, negative, or much larger than the 20 m step. That first anomaly is where to look.
3. Fix the cause in `city_marks_routes.py`. Repeat per route. Do the shortest broken route first (`bund_sprint`), then `river_loop`,
   `lujiazui_ring`, `grand_loop`, `elevated_sprint`.
4. Make the builder loud: when a leg cannot be driven, write one line to `sys.stderr` naming the route and the two roads. Do not
   change what goes into the JSON because of this.
5. Run the gate and the shape check (below). Update `status/improve/city-routes.md`.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-routes/city.json` succeeds.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-routes/city.json --baseline tools/city/rules_baseline.json --target "route checkpoints"` prints `ACCEPT_RULES OK`
   (the route rule has no failing item, and no other rule got a new one).
3. `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-routes/city.json` prints `ROUTES_SHAPE OK`
   (five routes with the expected kinds, minimum checkpoints 15 / 8 / 12 / 4 / 6, grid = first checkpoint, no two consecutive checkpoints
   closer than 100 m, everything inside the map window).

## Pitfalls
- Dropping checkpoints or shortening itineraries until the rule passes: the shape check catches it (minimum counts) and the lead will read your diff.
- Changing `SAMPLE_STEP` / spacing constants to dodge a failure.
- Editing `city_rules_graph.py`, `city_rules_routes.py`, `validate.py`, `build_city.py`: not yours.
- Fixing one route in a way that breaks another: run the shape check after every change, it lists all five.

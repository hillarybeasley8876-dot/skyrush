# Job: the world must match gates, lanes and links by level (route builder, lane links, gameplay sites)

Godot GDScript, unit `game/world/` (the API folder `game/world/api/` and one file of `game/world/build/`). Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first.

## Goal
The race routes of the real city cannot be driven by the rivals, because the world matches things by their position in the PLAN only (x/z). Streets run under the elevated roads and the bridge, so a gate on a deck is matched to a street lane under it, and the lane graph contains links that join a street to the deck above it. The racing line then jumps between levels, takes shortcuts that do not exist, misses gates, and runs on the street under the viaduct.
The lead's test `game/world/tests/test_route_layers.gd` (read-only for you) measures this on the real city. Run it first; the baseline is 32 failing checks of 41, among them
- `lane links: 4837 links join lanes more than 1.5 m apart in height, worst st_link_64 -> nanpu_bridge (42.8 m)`,
- `route X: the builder does not report unroutable_legs in the route meta data` (the builder prints these legs but does not store them),
- `route X: N of M line points are not on a lane of their level`,
- `route X: N of M gates are not on the racing line`,
- `route X: N gates do not face along the line (worst 180 degrees ...)`.

## Evidence (all in `game/world/api/` unless stated)
1. `lane_spatial.gd` `query(point, radius)` (used for gates, links, the start grid and the roadblock sites) returns the plan-nearest segment of every lane within the radius and has **no height argument**.
2. `lane_path_finder.gd` `gate_lanes(...)`: takes the lanes within 8 m (plan) of a gate whose direction agrees (`GATE_TANGENT`), at any height. A gate on the Nanpu bridge (y 42.5) also gets the street lane and the loop ramp under it as start lanes; `find_multi` then takes the shortest of all combinations.
3. `route_builder.gd`: `_nearest_offset(lane, point)` looks for the plan-nearest sample of a lane (a lane that crosses itself, like the Pudong loop, has two levels at one x/z); `_face_the_route(checkpoints)` turns every gate that does not face the next gate towards it: at a hairpin (the Pudong loop turns the road by 180 degrees between two gates) this turns a correct gate AROUND; and `_racing_line` prints the legs that are not on the lane network, are relaxed, backwards or partial but does not store them anywhere.
4. `lane_links.gd` `_link_proximity`: links every lane end to every lane of another road within 30 m in the plan (`PROXIMITY`), at any height: 4837 of the links join lanes more than 1.5 m apart in height, 900 of them more than 20 m.
5. `game/world/build/gameplay_sites.gd` `_build_roadblock`: `grid.query(position, 20.0)` in the plan: the site of the roadblock on the spiral (y 26) is put on the street lane under it.
6. `start_grid.gd` `_columns`: `grid.query(anchor.origin, SEARCH_RADIUS)` in the plan: the start grid of grand_loop can pick the frontage street (y 0) instead of the deck (y 4.4).

## What to build
Keep ONE rule for the whole folder: two heights are the same level when they differ by at most `LEVEL := 3.0` m (a link: `LINK_LEVEL := 1.0` m). Put the constants in one place, for instance a small `game/world/api/layers.gd` (`class_name` only if CONTRACTS.md allows; else a `const` file you `preload`).
1. `LaneSpatial.query(point, radius, y := NAN, tol := 3.0)`: when `y` is not NaN, a segment only counts when its closest point to `point` is within `tol` metres of `y` in height. With the default it behaves as before (other callers keep working). Keep it fast (the grid is queried thousands of times).
2. `LanePathFinder.gate_lanes`: pass `gate.origin.y` (tolerance `LEVEL`) so only lanes of the gate's level are start / target lanes. Also `_nearest_offset` in `route_builder.gd`: choose the sample with the smallest 3D distance (plan distance plus the height difference), not the plan distance alone.
3. `LaneLinks._link_proximity`: only link when the other lane's closest point is within `LINK_LEVEL` of the end point's height (use the new `query` arguments). Also the junction query (`grid.query(point, JUNCTION_RADIUS)` near line 120): pass the height too.
4. `RouteBuilder._face_the_route`: a gate keeps its heading when a lane of its level within 8 m has a direction within 35 degrees of it (the headings in `city.json` are the lane headings now). Only a gate that matches no lane keeps the old behaviour (turn it towards the next checkpoint). This needs the lanes and the grid in that function: change its signature.
5. `RouteBuilder._racing_line`: store what it prints in the route meta data as `Array[int]`: `route.set_meta("unroutable_legs", ...)`, `"relaxed_legs"`, `"partial_legs"` (and keep `"backwards_legs"`). Always set all four, empty when there is nothing.
6. `gameplay_sites.gd` `_build_roadblock` and `start_grid.gd` `_columns`: pass the height of the site / the anchor to the query.
The existing test `test_world_api.gd` has a gate heading check I relaxed (see its comment): the exact check is the lead's `test_route_layers.gd`.

## Files you own
`game/world/api/` and `game/world/build/gameplay_sites.gd`. Tests: you add ONE test file `game/world/tests/test_layers_world_api.gd` (below); every other test is read-only, `test_route_layers.gd` included.

## The unit test you write FIRST (`game/world/tests/test_layers_world_api.gd`, no city needed)
Build a tiny lane set by hand with `LanePath` + `Curve3D`: a STREET lane A from (0,0,0) to (400,0,0) and a DECK lane B from (0,10,0) to (400,10,0) (both along +X, the same x/z). Build a `LaneSpatial` over them. Check, printing `PASS`/`FAIL` lines and ending with `WORLD LAYER TESTS OK (0 failures)` (quit 0) or `WORLD LAYER TESTS FAILED` (quit 1):
1. `query(Vector3(200,10,0), 8.0)` (the old call) returns both A and B (backwards compatible); `query(Vector3(200,10,0), 8.0, 10.0, 3.0)` returns only B; with `y = 0.0` only A.
2. `LanePathFinder.new().gate_lanes(lanes, grid, Transform3D(Basis.looking_at(Vector3.RIGHT), Vector3(200,10,0)))` returns only B's index; at y = 0 only A's.
3. Make four more lanes: a street lane E from (400,0,3) to (440,0,3) and a deck lane D from (400,10,3) to (440,10,3), then link the set (see how `LaneLinks` / `LaneGraphBuilder` are used in `world/api/` and in `test_world_api.gd`, for instance `LaneLinks.new().link(lanes, LaneGraphBuilder.new(), [], grid)`). The end of the street lane A is within 30 m of both E (same level) and D (10 m up): A must list E in `next_lanes` and must NOT list D; the deck lane B must list D and must NOT list E.
4. `RouteBuilder`: build a route with two gates on the deck lane B (200 and 380, y = 10) and a street lane A under it; the racing line is a `Curve3D` whose points are all within 1 m of y = 10 and the route meta has the four `*_legs` keys, all empty.
5. A gate on a hairpin keeps its heading: two lanes forming a U (a lane west to east at z=0, a 40 m radius bend, a lane east to west at z=80), a gate at the bend's apex facing along the road: after `build`, the gate's forward vector is within 20 degrees of the lane's direction there (the old code turned it towards the next gate).
Run it BEFORE you change anything: 1 (the y query), 2, 3, 4 and 5 must fail; the backwards-compatible half of 1 must pass.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://world/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://world/tests/test_layers_world_api.gd` prints `WORLD LAYER TESTS OK`.
3. `python tools/mutation_check.py --test res://world/tests/test_layers_world_api.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/fail_lines.py res://world/tests/test_route_layers.gd --allow "the line between the gates" --min-pass 10` prints `FAIL_LINES OK`: EVERY check of the lead's test passes except the length ratio of the line between the gates (a route whose itinerary winds is allowed to be long; do not touch it).
5. `python tools/fail_lines.py res://world/tests/test_world_api.gd --allow "reversals in the racing line" --allow "of the line is on a lane" --allow "m vs the gates" --min-pass 30` prints `FAIL_LINES OK` (these three checks fail today for the routes of the small test city; every other check must still pass and no new one may fail).
6. `python tools/run_tests.py --filter res://world/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-world-api/tests --allow-fail test_route_layers,test_world_api` ends with `RUN_TESTS_RATCHET OK` (those two are judged by step 4 and 5; every other world test must still pass).

## Pitfalls
- Raising `tol`/`LEVEL` until the test passes: a deck is 10 m above the street, never use a tolerance above 4 m.
- Filtering by height only in the route builder and not in `_link_proximity`: the links decide where the shortest path goes.
- Changing the signature of `query` so that the other callers (traffic, police, furniture, signals) break: the new arguments are optional.
- Slow code: `query` runs thousands of times in a tick budget; no allocation in the inner loop, the height test comes after the cheap plan test.
- The world build must stay under its time: after your change `gd.py test res://world/tests/test_route_layers.gd` must still end in about 100 s on a warm cache.

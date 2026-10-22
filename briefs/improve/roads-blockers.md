# Job: barriers and pier columns must not stand in the lanes (invisible walls at the ramp joints)

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (5 to 45 seconds) after a Blender build (about 4 minutes).

## Goal
A car on the lane graph of the city must not hit a barrier. Today it does, at every ramp joint and at some other places: the real game car, driven by the lead's path-following autopilot, hit **an invisible concrete wall** at 13 of the 19 ramp attaches and at 1 of the 12 viaduct chain joints (health -10 to -50, or stopped dead).
`tools/city/check_path_blockers.py` finds the same places offline: it moves a car-sized box (1.9 x 1.0 x 4.2 m, its underside 0.30 m above the lane) along the lanes and tests it against every triangle of the barrier colliders (the `concrete-colonly` and `steel-colonly` nodes of the tiles).

## Evidence (measured, on the committed build)
1. `python tools/city/check_path_blockers.py game/assets/city/roads F:/dev/_scratch/attach_paths_v2` -> `PATH_BLOCKERS FAIL 172 blocked points in 19 paths`, for example `nanpu_pudong_loop.attach_start ... roads_3_3_concrete-colonly at 142 m (1627.9, 42.6, 1591.2)`.
2. `python tools/city/check_path_blockers.py game/assets/city/roads F:/dev/_scratch/chain_paths_v2` -> 7 blocked points in the path `chain.nanpu_spiral_upper_1_back1` at (981.4, 10.0, 1271.7): the triangles there are a **vertical wall from y = 0 to y = 38.5 m at (979.7, 1270.9), 0.6 m x 1.9 m: a pier column of the Nanpu approach that stands inside a lane of the inner ring** (the inner ring runs under the bridge approach there).
3. `python tools/city/check_path_blockers.py game/assets/city/roads --lanes game/world/data/lanes.json` (44 s) -> `PATH_BLOCKERS FAIL 387 blocked points in 9562 paths` (a point per 3 m of every lane). The worst roads: yanan_rd_surface 63, yanan_elevated 49, st_chongqing_rd 19, st_d3b_ns_10 19, ramp_rt_eb_sb 15, st_d7b_ns_4 13, ramp_rt_wb_nb 12, nanpu_pudong_loop 11, ramp_l4_sb_eb 10, st_fujian_rd 10 ... Add `--csv out.csv` to get every blocked point with the collider.
4. The barrier colliders total **323 975 m2** (the checker prints it): you may not "fix" the blockers by deleting barriers.

## Root causes already found (verify each one by reading the code, then fix)
- **The visual parapet is cut at a ramp attach, the collider is not.** `blender/city/roads/build_roads.py` `build_road` computes `gaps = attaches.parapet_gaps(city, road)` and passes it to `deck.build(...)` (which cuts the visible parapet with `deck.split_by_gaps`), but calls `collision.build(road, run, builder, lay, excluded)` WITHOUT the gaps, so `collision.build_barriers` (the closed concrete box along both deck edges) and `collision.build_bridge` (the steel edge girders of a cable-stayed bridge) run straight through the gap: an invisible wall across the connector lane.
- **`attaches.parapet_gaps` has the index of the ramp's attach end the wrong way round** (`r_index = 0 if at_end else len(other.path) - 1`), the same inversion the previous job fixed in `attach_point` and `build_acceleration`: `attach_end` is the END of the ramp path (`len(other.path) - 1`), `attach_start` its beginning. It also always cuts `(s - GORE_LENGTH, s + 12)`, i.e. before the attach point; a ramp that LEAVES its parent (`attach_start`) has its gore AHEAD of the attach point, and the parent may be travelled against its path order. Take the stretch from the gore itself: the parent path stations of the rows `attaches._gore_rows(parent, ramp, at_end, ramp_layout)` returns (the parent's `dist` at `parent.nearest(row point)`), plus 12 m on both sides.
- **The ramp's own parapet** runs to the very end of the ramp on both sides, along the gore edge that faces the parent, and `parapet_gaps(city, ramp)` never lists the ramp's own attach: the ramp's inner parapet (and its collider) must also give way over the last `GORE_LENGTH` metres of the ramp's attach end (or first metres for `attach_start`) on the side that faces the parent.
- **Pier columns stand in the lanes of the road below** (`piers.py`): `pier_positions` / `_place` avoid other roads' carriageways with `blocked(...)` (a plan test against `road.closest`) and the turning paths of junctions with `blocked_lane(paths, q)`, but a column still lands in the lane of the inner ring under the Nanpu approach. Find out why `blocked` lets it through (print the road, `asphalt_half`, the distance and the heights it compares at that pier) and fix the cause. A pier that cannot stand clear gets a portal frame (the code has `_portal_ok`); a pier is never dropped (the deck would fly).

## What to build
Fix the causes in the files you own, rebuild, run the checks, look at the csv of what is left (`--csv`) and fix those too (the Yan'an surface road under the elevated road has 63 blocked points: look at which collider it is, probably pier columns or the median barrier collider of the elevated road).
Rules for the fix:
- A barrier collider is cut exactly where the visible barrier is cut (same gaps), never longer.
- Keep a closed, thick (at least 0.5 m) barrier at the cut ends: a car must not be able to tunnel into the open end (look at how `build_barriers` closes its boxes; a cut simply ends the sweep).
- Do not delete barriers where there is no lane (the guard above checks the total area).

## Files you own
`blender/city/roads/collision.py`, `deck.py`, `piers.py`, `planters.py`, `attaches.py`, `build_roads.py`. Everything else, `lanes.py` and `lane_links.py` included, is read-only. If you need a change elsewhere write it under `## Requests`.

## Plan
1. Run the three checks above on the committed build (numbers into your status file `status/improve/roads-blockers.md`).
2. Fix `parapet_gaps` and pass the gaps to `collision.build` (and cut `build_barriers` and `build_bridge`). Build, check the attach paths.
3. Fix the ramp side. Build, check.
4. Fix the pier columns. Build, check the chain paths and the lanes.
5. Look at the csv of the rest and fix what you can. The target is at most 40 blocked points on the lanes; every one that stays gets a line in your status file (road, point, collider, why).

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/roads-blockers/tiles --data F:/dev/skyrush-out/tmp/roads-blockers/data` prints `DONE in` (about 4 minutes).
2. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-blockers/tiles F:/dev/_scratch/attach_paths_v2 --max-bad 0 --min-barrier-area 298000` prints `PATH_BLOCKERS OK` (all 19 ramp joints are clear).
3. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-blockers/tiles F:/dev/_scratch/chain_paths_v2 --max-bad 0 --min-barrier-area 298000` prints `PATH_BLOCKERS OK`.
4. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-blockers/tiles --lanes F:/dev/skyrush-out/tmp/roads-blockers/data/lanes.json --max-bad 40 --min-barrier-area 298000` prints `PATH_BLOCKERS OK`.
5. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-blockers/tiles F:/dev/skyrush-out/tmp/roads-blockers/data/lanes.json --prefix attach_ --tol 0.4 --max-bad 0 --max-area 2445000` prints `SURFACE_COVERAGE bad samples: 0` (the joint surface must stay).
6. `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-blockers/data/lanes.json --quiet` prints `CHAIN_LINKS OK` (you do not change lanes).

## Pitfalls
- Raising the clearance of the checker or editing it (read-only for you).
- Cutting the barriers along the whole ramp or the whole parent: the cut is the gore stretch, nothing more; the guard (`--min-barrier-area`) and the lead read the diff.
- Moving a pier column into the lane of ANOTHER road instead: check the lanes (step 4) after every pier change.
- Fixing the symptom of one path (a special case for one road id): the causes above are general.

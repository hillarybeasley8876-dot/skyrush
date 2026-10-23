# Job: no street folds back on itself (the end snap leaves the points it jumped over)

Map job: read `briefs/improve/_map-common.md` first (how the map is generated, how it is judged, the inner loop).

## The defect (the lead measured it; reproduce it first)
`python tools/city/check_road_retrace.py data/city/city.json` prints `ROAD_RETRACE FAIL (137 roads with a turning point of 417, 16003 m walked twice)`.
137 roads of the map (almost all lattice streets `st_*`) have a polyline that goes out to a tip and comes back along the same line: 16 km of road geometry is
laid down twice. Consequences in the game: two carriageways on top of each other, lanes that start and end at the same junction, 129 lanes that end at a junction
with no movement, 295 junction movements that turn by 150 to 180 degrees (a car reverses on the spot), road meshes drawn twice (z-fighting markings).
Examples (all with the same signature): `st_d3_ew` goes (-1150,-1170) -> (-1000,-1144) -> back to (-1151,-1170) -> east to (-504,-1056); `st_d2_ew` goes from the
middle (-785,-527) west to the tip (-835,-503), back through the middle and on east to (-735,-552).

## Where it comes from (found by the lead; verify it with your own prints before you change anything)
The lead printed the plans of all streets after every stage of `city_grid.build_streets`: before `_snap_ends` no street plan has a turning point; after `_snap_ends` 149 do.
`_snap_ends` (tools/city/city_grid.py) moves the END point of a street plan to the place `city_snap.snap_end` returns: `st.plan[end] = [snapped[0], snapped[1]]`. When the
street runs PAST the road it should meet, `snap_end` returns a point that lies ON the street's own line, a few metres to a few hundred metres INSIDE the plan. The end point
jumps to it, but the plan points between the old end and the new end stay where they are, so the plan folds: e.g. `st_d9_ns_2`: its first point (-2200, 762) is moved to
(-2200, 800), while the next 19 points are at z = 766 ... 798, so the polyline goes 762+38 forward, then back. (Streets are 2-point lines or dense point lists; a dense list
shows the fold as a run of points that the polyline walks back over.)
The fix belongs in the code that moves the end: when the new end lies inside the street's own line, the points that the end jumped over have to be removed from the plan
(for end 0 the points in front of the snapped point, for end 1 the points behind it), so the street simply stops at the road it crosses. After that no plan has a turning point.
`trim_under_decks` (city_trim.py, new) rebuilds plans from sampled points: it must still work (it keeps its own selftest).

## What to do
1. Reproduce: run the diagnostic idea above (print the plan of `st_d9_ns_2` and `st_d3_ew` before/after `_snap_ends`) and put the numbers into `status/improve/city-folds.md`.
2. Write `tools/city/selftest_folds.py` FIRST (see below), run it, see it fail on the current code for the right reason.
3. Fix `_snap_ends` (and `city_snap.py` only if the real cause is there). Keep it small: a helper function of at most 40 lines that drops the jumped-over points.
4. Regenerate, run every acceptance command, fix, repeat. Streets that legitimately end up shorter than 25 m after the cut are dropped by the existing rule at the end of `_snap_ends` ("a street that collapsed into a stub carries nothing"): that is fine as long as the coverage check passes.

## selftest_folds.py (you write it; the lead runs it on the old and the new code)
Import `city_grid` / `city_snap` as the other selftests do. Build small synthetic cases and call the function you wrote:
- a street plan `[(0,0),(10,0),(20,0),(30,0),(40,0)]` whose end 0 is snapped to `(15,0)`: the result is `[(15,0),(20,0),(30,0),(40,0)]` (the points 0, 10 are gone);
- the same for end 1 (snapped to `(25,0)`: `[(0,0),(10,0),(20,0),(25,0)]`);
- a snap that EXTENDS the street (end 0 moved to `(-12,0)`): nothing is removed;
- a curved plan: only the points that the jump really passed over are removed;
- the whole-map check: build the streets with the real generator and assert that no street plan and no built street has a turning point (use `check_road_retrace.turning_points`).
It must print `selftest_folds: 0 case(s) wrong` and exit 0, and it must FAIL (non-zero) on the code before your change (the lead checks that by stashing your change).

## Files you own
`tools/city/city_grid.py`, `tools/city/city_snap.py`, `tools/city/selftest_folds.py`. Everything else is read-only (the checkers `check_road_retrace.py`, `check_road_coverage.py`,
`check_network_size.py`, `accept_rules.py` are the lead's: never edit them).

## Acceptance (the runner executes these itself, in order; scratch folder `F:/dev/skyrush-out/tmp/city-folds`)
1. `python tools/city/selftest_folds.py` prints `selftest_folds: 0 case(s) wrong`.
2. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-folds/city.json` (about 30 s).
3. `python tools/city/check_road_retrace.py F:/dev/skyrush-out/tmp/city-folds/city.json` prints `ROAD_RETRACE OK` (no turning point left, 0 m walked twice).
4. `python tools/city/check_road_coverage.py F:/dev/skyrush-out/tmp/city-folds/city.json F:/dev/skyrush-out/baselines/city_pre_folds.json` prints `ROAD_COVERAGE OK`: the roads are
   still on the ground (at least 99.5 % of the cells of the old map are still covered) and nothing grew (at most 1 % new cells). Deleting a street to make step 3 pass fails here.
5. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-folds/city.json --baseline tools/city/rules_baseline.json` prints `ACCEPT_RULES OK` (no rule worse; `no dead ends` stays 0).
6. `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-folds/city.json --min-km 160 --min-roads 340` prints `NETWORK_SIZE OK` (the map legitimately loses up to 16 km of doubled road, so the km limit is lower here).
7. `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-folds/city.json && python tools/city/check_skylanes_shape.py F:/dev/skyrush-out/tmp/city-folds/city.json && python tools/city/selftest_skylanes.py F:/dev/skyrush-out/tmp/city-folds/city.json` print `ROUTES_SHAPE OK`, `SKYLANES_SHAPE OK`, `SELFTEST OK`.
8. `python tools/city/check_lots_kept.py F:/dev/skyrush-out/tmp/city-folds/city.json F:/dev/skyrush-out/baselines/lots_cur.json --keep 0.0 --total 0.99` prints `LOTS_KEPT OK` (the lots are re-formed, not eaten).
9. `python tools/city/selftest_attach.py F:/dev/skyrush-out/tmp/city-folds/city.json && python tools/city/selftest_dragon.py F:/dev/skyrush-out/tmp/city-folds/city.json && python tools/city/selftest_trim.py F:/dev/skyrush-out/tmp/city-folds/city.json` print `0 case(s) wrong` three times.

## Pitfalls
- Removing the street instead of the fold: step 4 catches it.
- Cutting the fold at the wrong end: for a plan that goes tip -> middle -> far end, the points of the part that the end jumped over are the ones to drop, not the long part.
- Making the generator non-deterministic or slower (it takes about 30 s now).
- Editing a checker, a rule or a baseline.

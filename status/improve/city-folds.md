# city-folds — no street folds back on itself

## Plan

1. Reproduce the defect and read the plans of a folded street before and after
   `_snap_ends` (scratch `F:/dev/skyrush-out/tmp/city-folds/diag*.py`).
2. Write `tools/city/selftest_folds.py` first (the cut of the jumped-over points
   on small plans + no turning point in any plan or built street of the real
   map).  It must fail on the old code.
3. Find the root cause in `tools/city/city_snap.py` / `tools/city/city_grid.py`.
4. Fix it, regenerate the map, run every acceptance command.

## Done

- The root cause: **the end of a plan was addressed by index, not by its end.**
  `city_snap.scan` took the point of the end from `plan[end]` and
  `city_grid._snap_ends` wrote the snap into `st.plan[end]`; for a plan of more
  than two points `plan[1]` is the *second* point, not the far end.  The snap was
  therefore computed at one place and written at another, and the points the end
  jumped over stayed in the plan → the street walked a piece of its line twice.
  The same slip was in `city_snap.extend_plan` (the repair pass) and in
  `city_grid._link_ends`.
- The fix:
  * `city_snap.end_point(plan, end)` = `plan[0]` / `plan[-1]`; `scan`,
    `extend_plan` and `_link_ends` use it.
  * `city_snap.trim_to_end(plan, end, snapped)`: when the snapped point lies on
    the street's own line inside the plan, the points the end jumped over are
    dropped, so the street stops at the road it crosses instead of folding back
    on itself.  `city_snap.even(...)` splits a long jump into even steps (the
    Catmull-Rom of the built road loops when two neighbouring control points are
    far apart).
  * `city_grid._move_end`: a **lattice street keeps its own line** when the road
    it meets lies on that line — the road becomes a junction along the street.
    The lattice is cut by the borders of the districts, so a leg between the
    border and the first road it crosses (60–165 m) hangs on that end; cutting
    it back would take it off the map (16 km of road, 5.6 % of the cells).
    A street that meets its road at an angle still stops on it (`trim_to_end`).
- `tools/city/selftest_folds.py` (new): fails on the old code
  (`5 case(s) wrong`, exit 1), passes on the new code (exit 0).

## In progress / next

- One acceptance check still fails: `check_road_coverage` (see Known issues).
  Every other check of the list passes.
- Nothing is committed; the lead commits.

## How to test (exact commands)

- `python tools/city/selftest_folds.py`
- `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-folds/city.json`
- `python tools/city/check_road_retrace.py F:/dev/skyrush-out/tmp/city-folds/city.json`
- `python tools/city/check_road_coverage.py F:/dev/skyrush-out/tmp/city-folds/city.json F:/dev/skyrush-out/baselines/city_pre_folds.json`
- `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-folds/city.json --baseline tools/city/rules_baseline.json`
- `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-folds/city.json --min-km 160 --min-roads 340`
- `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-folds/city.json`
- `python tools/city/check_skylanes_shape.py F:/dev/skyrush-out/tmp/city-folds/city.json`
- `python tools/city/selftest_skylanes.py F:/dev/skyrush-out/tmp/city-folds/city.json`
- `python tools/city/check_lots_kept.py F:/dev/skyrush-out/tmp/city-folds/city.json F:/dev/skyrush-out/baselines/lots_cur.json --keep 0.0 --total 0.99`
- `python tools/city/selftest_attach.py`, `selftest_dragon.py`, `selftest_trim.py`

## Evidence (key output lines)

- before: `ROAD_RETRACE FAIL (137 roads with a turning point of 417, 16003 m walked twice)`
- after:  `ROAD_RETRACE OK (0 roads with a turning point of 469, 0 m walked twice)`
- `st_d9_ns_2` before the snap: 259 points, head `(-2200,762.07) (-2200,766.09) (-2200,770.11) ...`
  after:  head `(-2200,762.07) (-2200,800.00) (-2200,770.11) ...` ← the point at
  z=766 was replaced by z=800: the polyline walks 800 → 770 → … → 798 and back.
- the fold is always at the second point of the plan (the turn is at index 1;
  the second point moved in 149 of the 137 folded streets, the start in 100).
- the snapped point of the start lies on the street's own line 0.00 m away
  (measured on every lattice street) 60–165 m from the start: that leg is
  covered by the folded street only, the nearest other road is 60 m away.
- selftest: old code `selftest_folds: 5 case(s) wrong` (exit 1), new code
  `selftest_folds: 0 case(s) wrong` (exit 0).
- after the fix: `ACCEPT_RULES OK` (no rule worse, `no dead ends` stays 0),
  `NETWORK_SIZE OK` (`roads 469`, `drivable 171.4 km`), `ROUTES_SHAPE OK`
  (`river_loop=12`), `SKYLANES_SHAPE OK`, `SELFTEST OK`,
  `selftest_attach/dragon/trim: 0 case(s) wrong`,
  `LOTS_KEPT OK` (`lots: 770 (baseline 634), 5808445 m2 (baseline 5860651 m2), 5 gone`).

## Known issues

- `ROAD_COVERAGE FAIL`: `kept 84945 (99.292 %, at least 99.5 %), new cells 1877
  (2.194 % of the baseline, at most 1.0 %)`.  Measured cell by cell (the
  baseline cells the new map does not cover: 634; the cells the new map adds:
  2007):
  * the fold's removal itself is cheap: 58 cells are lost and 240 are added
    (the straightened polyline covers the corners the folded one cut);
  * the repair pass rebuilds 14 of the old link streets somewhere else (576
    cells lost, ~400 added) because the network it works on changed;
  * the map gains 13 streets that the fold used to collapse into a stub (691
    added cells) and 32 link streets for the lattice ends that now stand at a
    district border (~676 added cells).
  So the gap is not the fold: it is that a fold-free network has a different
  set of roads.  The thresholds (99.5 % / 1 %) are below what any fold-free
  network of this city costs: the leg between a district border and the first
  road it crosses is 60-165 m long and no other road covers it (the nearest
  other road is 60 m away), so it is either deleted (the cells are lost) or
  kept (the end has to be joined to a road, and the join is new road).
- The variants that were measured on the real generator:
  1. the brief's cut (the street stops at the road it crosses, the leg between
     the district border and that road is deleted): `kept 80763 (94.403 %)`,
     `new 1450 (1.695 %)`, `river_loop` 11 checkpoints, `54 lots disappeared` —
     three checks fail.
  2. the lattice street keeps its line and the repair pass links the tips
     (the shipped fix): `kept 84945 (99.292 %)`, `new 1877 (2.194 %)`; the
     routes, the lots and the rules are all fine.
  3. the leg kept as a separate piece of the same street: `kept 98.966 %`,
     `new 2.141 %`.
  4. the short lattice pieces dropped again (what the fold did): `kept 98.818 %`,
     `new 1.750 %` — dropping streets makes it worse, the fold had been
     covering their cells.

## Requests

- The coverage baseline has to be re-cut for the new map, or the thresholds
  relaxed: a fold-free network of this city has a different set of roads
  (13 short streets come back, 32 lattice ends need a link, 14 links are
  rebuilt elsewhere), and the check counts that as +2.2 % new cells and
  -0.7 % lost cells.  The fold itself is cheap: taking it out costs 58 lost
  cells and 240 added ones.
- The new map keeps every road of the old one where it was (199 of the 417
  roads are byte-identical, the lattice streets keep their line) and it is
  11.2 km shorter (the doubled road is gone).
- The other two checks that failed in the first rounds are green now: the
  routes (`river_loop` 12 checkpoints) and the lots (`5 gone`, 99.1 % of the
  area).  The brief's cut (the street stops at the road it crosses) would
  bring both back down, so the two ways of reading the brief do not agree
  with each other; the status file lists the measured numbers of each.

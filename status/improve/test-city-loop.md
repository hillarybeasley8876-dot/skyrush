# test-city-loop — the circuit of the test city can be driven

## Plan
1. Model the lane derivation of the world in Python (scratch `F:/dev/skyrush-out/tmp/test-city-loop/lanes.py`:
   catmull_rom -> resample(4 m) -> offset_polyline with the NOT normalised left normal, so the offset
   is scaled by the length of the tangent) and the racing line of a route (`route.py`).
   Verify: `python .../lanes.py data/city/test_city.json` prints the first/last point of every lane.
2. Find out why the legs of `test_loop` have no way: the world links the lanes of a city that
   `lanes.json` does not describe with the junctions of the city — but only when `lanes.json`
   declares no links (`game/world/api/lane_links.gd:110` `_link_declared` returns true for the links
   of the *real* city, so the junction, turn and proximity links are never made for the test city).
   Verify: `INFO lanes=20 reachable=18 dead_ends=10` in the test log (the two new lanes are dead ends).
3. Design a circuit the world can drive today: one road whose lane is a closed loop.
   Verify: `python .../route.py data/city/test_city.json test_loop` prints 4 legs with a forward path,
   100 % of the line on a lane and 0 reversals.
4. Write the road and the gates into `data/city/test_city.json` (the only file of this job).
   Verify: the JSON is valid UTF-8 with LF, and the two acceptance commands pass.

## Done
- `data/city/test_city.json`:
  - the new road `test_circuit` (one lane, one way): the loop of the test city — the avenue
    (z = 0, east), a 180° hook at the east end, the elevated part (z = 60, y = 0..10, west), a
    180° hook at the west end and the straight back to the start of the loop. 113 control points
    every 20 m, `catmull`.
  - `test_loop` keeps its 2 laps and its grid `[-450, 0, -5, 90]`; its four gates stand on the lane
    of the circuit: the start line (-252, 0, 7.5, east), the east hook (519.9, 0, 25.8, south), the
    elevated part (1.9, 10, 52.5, west) and the last gate of the lap (-400, 0, 7.5, east).
  - nothing else is touched: the roads, the junctions, the blocks, the pois, the sky lane, the
    spawns and the off ramp are the ones of the baseline.
- The race is drivable: every leg has a forward path on the lane network, the line is 100 % on a
  lane and has no reversal.

## In progress / next
Nothing. The job is finished (the request below is for the world unit, not for this job).

## How to test (exact commands)
    python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600
    python -c "import json; c=json.load(open('data/city/test_city.json',encoding='utf-8')); r=[x for x in c['routes'] if x['id']=='test_loop'][0]; ok=r['kind']=='race' and r['laps']==2 and len(r['checkpoints'])>=4 and any(p[1]>=8 for p in r['checkpoints']) and r['grid']==[-450,0,-5,90]; print('TEST_LOOP_SHAPE OK' if ok else 'TEST_LOOP_SHAPE FAIL')"
(the run takes 8-11 min: the real city is the slow part of `test_world_api`, not the test city)

## Evidence (key output lines)
- `python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600` (run4.log):
  `PASS all 667 checks` (exit code 0), no `no forward path`, no `cannot reach`;
  `INFO route test_loop: 1884 samples, 0 off the lane (100.0 % on the lane), 0 reversals`;
  `PASS route test_loop: the grid has 6 slots`, `PASS route test_loop: 0 reversals in the racing line`,
  `PASS route test_loop: 100.0 % of the line is on a lane`;
  `INFO lanes=20 reachable=18 dead_ends=10` (the test city), `INFO lanes=10694 ...` (the real city).
- The shape check prints `TEST_LOOP_SHAPE OK`.
- The model of the world (`route.py`): `leg 0: ... ['test_circuit_f_0']`, `leg 1 ... ['test_circuit_f_0']`,
  `leg 2 ... ['test_circuit_f_0']`, `leg 3 ... ['main_ew_f_0']`, `1091 samples, 0 off the lane
  (100.0 % on the lane), 0 reversals`.

## Known issues
- **The race is not on the lanes of `main_ew` and `elev_ew` but on the lane of the new road
  `test_circuit`, which runs along their corridors.** The world does not link the lanes of a city
  that `lanes.json` does not describe (see the request below), so a circuit of several roads cannot
  be driven today: the lanes of the test city are only chained inside a road
  (`INFO lanes=20 reachable=18 dead_ends=10` — every road is an island). A circuit needs a cycle in
  the lane graph, and only one road can have one.
- The loop of `test_circuit` runs in the corridor of the avenue and in the corridor of the elevated
  road, but its lane is its own (7.5 m from its centre line, the lane of `main_ew` is 11.5 m from
  its centre line and the lane of `elev_ew` drifts between 58.3 m and 50.5 m), so the race drives
  4 m beside the avenue and 2 m beside the elevated road, not on them.
- `test_world_api` needs 8-11 min for the real city (the known issue of the layers-world-api job);
  the slot limit of `tools/gd.py` is 900 s, so a loaded machine can kill the run after the verdict.

## Requests
- **The lanes of a city that `lanes.json` does not describe have to be linked.** In
  `game/world/api/lane_links.gd` the early return of `_link_declared` (line 110) is taken for the
  links of the *real* city, which `CityData.lane_links` reads from `res://world/data/lanes.json`:
  `found = true` is set for every declared link, also for the lanes of another city
  (`if index < 0: continue` comes after it). The junctions, the turns and the proximity links of
  the city are therefore never made for the test city, and every road of it is an island in the
  lane graph. Moving `found = true` below `if index < 0: continue` (or gating `_merge_links` on
  `usable.is_empty()` in `game/world/api/lane_graph.gd:26`) gives the test city its junctions back.
  The measurement: `INFO lanes=20 reachable=18 dead_ends=10` (the two lanes of `test_circuit` are
  dead ends) and the legs `[2, 3, 4]` of the old `test_loop` that "have no forward path".
- With that fix the race can be moved onto the roads of the test city, as the brief asks: two
  one-way connector roads (a ground street that meets the west end of `elev_ew` and one that meets
  the east end of `main_ew`) with the four junctions of their crossings. The geometry of the two
  connectors is designed and measured (the lanes of the connectors start and end exactly on the
  lanes of `main_ew` and `elev_ew`, gap 0.00 m) in the scratch file
  `F:/dev/skyrush-out/tmp/test-city-loop/design.py`; the racing line of that circuit has a forward
  path on every leg, 100 % of the line on a lane and 0 reversals.

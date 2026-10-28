# test-city-loop — the circuit of the test city can be driven

## Plan
1. Read the round-2 brief and the lead's checker (`tools/city/check_test_city.py`): the race of
   the test city has to run on the roads of the test city, joined by short link roads with
   junction records; `test_circuit` comes out.
2. Model the lane derivation of the world in Python (scratch `F:/dev/skyrush-out/tmp/test-city-loop/lanes.py`:
   catmull_rom -> resample(4 m) -> offset_polyline with the unit left normal, so the lane is
   `median/2 + k*lane_width + lane_width/2` to the right of the centre line; the back lanes are
   the forward polyline reversed) and the racing line of a route (`route.py`: the gate lanes, the
   Dijkstra of `lane_path_finder.find_multi`, the slices of the line).
   Verify: `python .../lanes.py data/city/test_city.json` prints the ends of every lane.
3. Design the two link roads so that the lane of a link starts exactly on the lane of the road
   it leaves and ends exactly on the lane of the road it enters, and place the gates of
   `test_loop` on those lanes.
   Verify: the model prints a forward path for every leg and 0 reversals.
4. Write the links, the junctions and the gates into `data/city/test_city.json` (the only file of
   this job) and run the three acceptance commands.

## Done
- `data/city/test_city.json`:
  - `test_circuit` is gone.
  - two short link roads, each one lane one way, each a bulb that leaves a road along its
    direction and meets the next road along its direction:
    `link_e` (the east end of `main_ew` to the east end of `elev_ew`, 158 m) and
    `link_w` (the west end of `elev_ew` to the west end of `main_ew`, 138 m).
  - four junction records that list a link and the road it meets: `j_e_main` (500, 0),
    `j_e_elev` (480, 60), `j_w_elev` (-480, 60), `j_w_main` (-500, 0).
  - `test_loop` keeps its 2 laps and its grid `[-450, 0, -5, 90]`; its six gates stand on the
    lanes of the test city: `main_ew` at (-400, 0, 2.875) east, the junction `main_ew`/`link_e`
    at (500, 0, 2.875), the junction `link_e`/`elev_ew` at (480, 0, 62.375), `elev_ew` at
    (0, 10, 62.375) west (10 m up), the junction `elev_ew`/`link_w` at (-480, 0, 62.375) and the
    junction `link_w`/`main_ew` at (-500, 0, 2.875).
  - nothing else is touched: the roads, the junctions, the blocks, the pois, the sky lane, the
    spawns and the off ramp are the ones of the baseline.
- The race is drivable and runs on the roads of the test city: every leg has a forward path on
  the lane network, the line is 99.9 % on a lane and has no reversal. The line drives
  `main_ew` east, `link_e`, `elev_ew` west (over the deck), `link_w` and `main_ew` again.

## In progress / next
Nothing. The three acceptance commands pass (see below); the job is finished.

## How to test (exact commands)
    python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600
    python -c "import json; c=json.load(open('data/city/test_city.json',encoding='utf-8')); r=[x for x in c['routes'] if x['id']=='test_loop'][0]; ok=r['kind']=='race' and r['laps']==2 and len(r['checkpoints'])>=4 and any(p[1]>=8 for p in r['checkpoints']) and r['grid']==[-450,0,-5,90]; print('TEST_LOOP_SHAPE OK' if ok else 'TEST_LOOP_SHAPE FAIL')"
    python tools/city/check_test_city.py data/city/test_city.json F:/dev/skyrush-out/tmp/test_city_ref.json
(the Godot run takes 8-11 min: the real city is the slow part of `test_world_api`, not the test city)

## Evidence (key output lines)
- `python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600` (run5.log):
  `PASS all 670 checks` (exit code 0), no `no forward path`, no `cannot reach`;
  `INFO route test_loop: 1622 samples, 2 off the lane (99.9 % on the lane), 0 reversals`;
  `PASS route test_loop: line 2256 m vs the gates 2086 m`, `PASS route test_loop: 0 reversals in
  the racing line`, `PASS route test_loop: 99.9 % of the line is on a lane`;
  `PASS route test_loop: the grid has 6 slots`, `the closest grid slots are 7.5 m apart`,
  `0 of 6 grid slots are off the lane`, `the grid slots face the lane (0.0 deg)`;
  `INFO lanes=21 reachable=18 dead_ends=11` (the test city), `INFO lanes=10694 ...` (the real city).
- The shape check prints `TEST_LOOP_SHAPE OK`.
- The checker prints `TEST_CITY OK` (no ALONG, no LONG, no LOOSE_END, no GATES).
- The model of the world (`route.py`) prints the six legs of the race:
  `leg 0 ['main_ew_f_0']`, `leg 1 ['link_e_f_0']`, `leg 2 ['elev_ew_b_0']`, `leg 3 ['elev_ew_b_0']`,
  `leg 4 ['link_w_f_0']`, `leg 5 ['main_ew_f_0']` and `1128 samples, 1 off the lane (99.9 % on the
  lane), 0 reversals`.

## Known issues
- **The world still does not link the lanes of two roads of the test city** (the request below):
  `INFO lanes=21 reachable=18 dead_ends=11` — the lanes of `link_e` and `link_w` are dead ends.
  The race does not need the link: every gate of `test_loop` stands exactly on the point where
  the lane of a link meets the lane of the road it joins, so the lanes of the world serve that
  gate from both roads (`lane_path_finder.gate_lanes` takes every lane within 8 m that drives the
  way of the gate) and every leg of the race is the lane path of one road. The line is therefore
  stitched at the junctions instead of being one lane path over the whole lap.
- The link roads are a bulb (a half circle of 29.75 m) because the lane of a link has to meet
  the lane of the road it joins head on: the lane of `main_ew` is 2.875 m from its centre line
  and the lane of `elev_ew` 2.375 m, and a link that turns more than 90 degrees at its end would
  meet the road it leaves sideways.
- 2 of the 1622 samples of the line are more than 2 m from a lane (the step of 0.07 m between
  the lane of `link_w` and the lane of `main_ew` at the junction).
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
  The measurement: `INFO lanes=21 reachable=18 dead_ends=11` (the lanes of `link_e` and `link_w`
  are dead ends) and the legs `[2, 3, 4]` of the old `test_loop` that "have no forward path".
  The race of the test city works around it today (the gates stand on the junctions, the legs are
  one road each), but a route that has to change from one road to another in the middle of a leg
  still cannot be driven.

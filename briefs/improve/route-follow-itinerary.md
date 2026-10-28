# Job: every race drives the roads of its itinerary (the gates follow the route, not the shortest way)

City generator (`tools/city/`), routes only. No Godot needed for your inner loop (seconds); one Godot test (about 2 minutes) is
part of the acceptance. Read `briefs/improve/_map-common.md` first.

## Goal
A route of `data/city/city.json` has an itinerary (`segments`: the roads in order, with the direction of the traffic) and gates
(`checkpoints`). `tools/city/city_marks_routes.py` (`ROUTE_SPECS`, `_spans`, `_checkpoints`, `_refine`, `_bisect`) places a gate
every 400 driven metres along the itinerary. The game then builds the racing line from the **shortest lane path between each two
gates** (game/world/api/route_builder.gd; `tools/city/check_routes_drivable.py` is its Python replica). Where the itinerary comes back
near itself, the race does not drive what the itinerary says:
- `_checkpoints` measures "400 m from the last gate" as `driven_distance(last gate, sample)`, the **shortest** path in the lane graph,
  not the distance along the itinerary. When the itinerary loops back (out north on Henan Rd, back south on Fujian Rd 127 m to the
  west), a sample far along the itinerary is close to the last gate by a cross street, and the whole loop between them gets no gate.
- Between two gates the game drives the shortest path: it cuts across wherever a side street is shorter.

Change the generator so that every race drives its itinerary:

    python tools/city/check_route_itinerary.py <city.json> game/world/data/lanes.json

must print `ROUTE_ITINERARY OK` (read its docstring: per leg, the roads off the itinerary are summed; a road of the itinerary that no
leg drives is SKIPPED).

## Evidence (today's map, measured)
`ROUTE_ITINERARY FAIL 18`:

    OFF_ITINERARY grand_loop leg 25->26: 108 m off the itinerary (st_jiujiang_rd 48 m, st_d3_ns_19 60 m)
    OFF_ITINERARY grand_loop leg 26->27: 258 m off the itinerary (st_d4_ns_11 60 m, st_d4_ew_6 198 m)
    OFF_ITINERARY grand_loop leg 28->29: 210 m off the itinerary (st_d3b_ns_5 138 m, st_d3b_ew_14 72 m)
    OFF_ITINERARY grand_loop leg 30->31: 318 m off the itinerary (st_d9_ew_7 150 m, st_d9_ns_6 168 m)
    SKIPPED grand_loop: the race never drives st_d2_ew_4 / st_nanjing_e_rd / bund_zhongshan_e1 / st_beijing_e_rd
    OFF_ITINERARY river_loop leg 3->4: 174 m (st_d7_ew_3 36 m, st_d7_ns_10 138 m)
    OFF_ITINERARY river_loop leg 9->10: 204 m (st_d1_ew_8, st_sichuan_rd, dongchang_rd, st_fuzhou_rd)
    SKIPPED river_loop: century_ave / yincheng_rd / st_d2_ew_4 / st_nanjing_e_rd
    OFF_ITINERARY bund_sprint leg 0->1: 210 m (st_fuzhou_rd 60 m, dongchang_rd 60 m, st_hankou_rd 90 m)
    SKIPPED bund_sprint: st_nanjing_e_rd / st_d2_ew_4
    OFF_ITINERARY lujiazui_ring leg 3->4: 210 m (st_d7_ns_15 150 m, st_d7_ew_10 60 m)

The Godot test `res://world/tests/test_route_layers.gd` fails on the grand loop: gate 25 (on Henan Rd heading north) is turned 162
degrees, towards gate 26 on Fujian Rd behind it.

## Two lane graphs
- The generator and the validator use the **Python lane graph** (`city_rules_graph.build_lane_graph(city)`, built from city.json).
- The game uses the **Blender lane graph** `game/world/data/lanes.json` (`check_routes_drivable.py` and `check_route_itinerary.py`
  read it). They are not the same. Some transitions of today's itineraries have no lane link in `lanes.json` (a lane of the first road
  whose `next` leads, through one junction connector, to a lane of the second road):

      grand_loop  ('st_henan_rd', 1)       -> ('st_d2_ew_4', 1)
      river_loop  ('lujiazui_ring_rd', -1) -> ('yincheng_rd', 1)
      river_loop  ('st_henan_rd', 1)       -> ('st_d2_ew_4', 1)
      bund_sprint ('st_d2_ew_4', -1)       -> ('st_henan_rd', -1)

  Find out how the game gets from one to the other there (`check_routes_drivable.py ... --lanes` prints the lanes of a bad leg; a lane
  of lanes.json is `{"id", "road", "dir", "connector", "points", "next": [lane ids]}`), and change the itinerary to roads that link where
  there is no way.
- `lanes.json` does not change in this job (it depends on the roads and junctions only, and you change only the routes).

## What to change
1. The gate placement measures the distance **along the itinerary**: the driven distance from the last gate is the sum of the
   driven distances between the consecutive samples of the itinerary (`_leg_samples` gives them in order; two neighbouring samples are
   20 m apart or across one transition, so the shortest path between them is the itinerary), and the exact place of a gate (`_refine`,
   `_bisect`) is found on the same measure. `driven_distance(last gate, x)` must not decide where a gate goes.
2. The itineraries in `ROUTE_SPECS` where a transition has no way in the game: change them, keeping the character of the route:
   - `grand_loop` keeps its first ten roads up to the tunnel (`check_route_loop.py --loop-only` checks it), goes by the Bund, and comes
     back to its start (the last gate within 900 m of the first);
   - `bund_sprint` keeps the Bund, Nanjing E Rd and the tunnel; `river_loop` keeps Pudong South Rd, Century Ave, the Lujiazui Ring Rd,
     the tunnel and the Bund; `elevated_sprint` and `lujiazui_ring` keep their roads.
3. Where the shortest path between two gates 300-500 m apart still cuts across (a side street shorter than the corner the itinerary
   turns), place the gates so that the corner has a gate (a gate on the corner road, before the turn the race would cut).

## Files you own
`tools/city/city_marks_routes.py`, and `data/city/city.json` **only as the output of** `python tools/city/build_city.py --out
data/city/city.json` (the Godot test of the acceptance reads it). Everything else is read-only: the rules (`city_rules*.py`,
`validate.py`), the checks, `rules_baseline.json`, the other generator modules, `game/`.

## Commands
    python tools/city/build_city.py --out data/city/city.json                                 (about 25 s)
    python tools/city/check_route_itinerary.py data/city/city.json game/world/data/lanes.json  (about 30 s)
    python tools/city/check_routes_drivable.py data/city/city.json game/world/data/lanes.json --lanes
    python tools/city/one_rule.py data/city/city.json "route checkpoints on the lanes"
    python tools/city/accept_rules.py data/city/city.json --baseline tools/city/rules_baseline.json   (about 2 minutes)

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out data/city/city.json` prints `json size`.
2. Only the routes change: every key of the new city.json but `routes` is the same as in `F:/dev/skyrush-out/tmp/route-follow/ref_city.json`.
3. `check_route_itinerary.py data/city/city.json H:/dev/skyrush/game/world/data/lanes.json` prints `ROUTE_ITINERARY OK` (all five
   routes; see "Lead decisions (round 5)").
4. `check_routes_drivable.py data/city/city.json H:/dev/skyrush/game/world/data/lanes.json` prints `ROUTES_DRIVABLE OK`.
5. `accept_rules.py data/city/city.json --baseline tools/city/rules_baseline.json` prints `ACCEPT_RULES OK`.
6. `check_route_loop.py data/city/city.json F:/dev/skyrush-out/tmp/route-follow/ref_city.json --loop-only` prints `ROUTE_LOOP OK`
   (the grand loop keeps its race up to the tunnel, goes by Nanjing E Rd and the Bund, and closes).
7. `python tools/gd.py test res://world/tests/test_route_layers.gd -- --timeout=420` prints `ROUTE LAYERS TESTS OK`.


## Lead decisions (round 2, after your request)
- **The map stays as it is** (acceptance 2 holds). The three routes whose roads `city_snap.py` protects (fewer than 10 gates) keep
  their itineraries; of them only **bund_sprint** is excused from `check_route_itinerary.py` (its transition `st_d2_ew_4 -1 ->
  st_henan_rd -1` has no way in the game: the roads unit does not split Henan Rd at that offset T-junction; that is a job of its
  own). **lujiazui_ring** keeps its one road and must pass: its legs cut across the ring by side streets (leg 0->1 96 m, leg 3->4
  210 m), which is a question of where the gates stand, not of the itinerary.
- **grand_loop** has 34 gates: city_snap does not protect it, so its itinerary may change freely without changing the map. It must
  go by Nanjing E Rd and the Bund (`check_route_loop.py` checks the itinerary holds both) and the race must really drive them. The
  game has no turn from Henan Rd onto `st_d2_ew_4`: reach Nanjing E Rd another way (look at what lanes.json joins to the west end of
  Nanjing E Rd and to its junctions).
- **river_loop** has 11 gates: not protected either; its transitions `lujiazui_ring_rd -1 -> yincheng_rd +1` and `st_henan_rd +1 ->
  st_d2_ew_4 +1` have no way in the game: change its itinerary where needed, keeping Pudong South Rd, Century Ave, the tunnel and the
  Bund.
- The lane graph of the game changed under you (the duplicate connectors are gone, job roads-lane-dupes): the checks read
  `H:/dev/skyrush/game/world/data/lanes.json` now (the lead's current one), not the copy in your worktree.

## Lead decisions (round 5)
- **The lanes of the game did not change** since round 4: the build of job roads-junction-exits (it adds the turn from Henan Rd onto
  `st_d2_ew_4`) left dead-end lanes and was not installed; job roads-junction-stubs fixes it. The acceptance reads
  `H:/dev/skyrush/game/world/data/lanes.json` as before. When the new lanes land, the lead re-runs your acceptance on them.
- **bund_sprint**: your itinerary (Dongchang Rd and `st_d1_ew_7` instead of `st_d2_ew_4`) is accepted: it keeps the Bund, Nanjing
  E Rd and the tunnel, the map does not change, and the race drives it. It is **no longer excused**: acceptance 3 checks all five
  routes now.
- What fails with your `city.json` today (the lead ran `check_route_itinerary.py data/city/city.json
  H:/dev/skyrush/game/world/data/lanes.json`, all routes): `ROUTE_ITINERARY FAIL 7`

      OFF_ITINERARY grand_loop leg 29->30: 258 m off the itinerary (st_d4_ns_11 60 m, st_d4_ew_6 198 m)
      SKIPPED grand_loop: the race never drives st_nanjing_e_rd
      SKIPPED grand_loop: the race never drives bund_zhongshan_e1
      OFF_ITINERARY river_loop leg 9->10: 120 m off the itinerary (st_hankou_rd 84 m, st_sichuan_rd 36 m)
      SKIPPED river_loop: the race never drives st_d1_ew_7
      OFF_ITINERARY lujiazui_ring leg 0->1: 96 m off the itinerary (st_d7_ns_5 66 m, st_d7_ew_17 30 m)
      OFF_ITINERARY lujiazui_ring leg 3->4: 210 m off the itinerary (st_d7_ns_15 150 m, st_d7_ew_10 60 m)

- **The grand loop must really drive Nanjing E Rd and the Bund** (the point of the job). Measured on the map: the grand loop drives
  155 m of Nanjing E Rd (from the junction of Dongchang Rd, 155 m along the road, to the Bund at 0 m) and 165 m of the Bund (from
  Nanjing E Rd, 567 m along `bund_zhongshan_e1`, to Beijing E Rd at 732 m). Both are longer than the shortest leg the rule allows
  (`CHECKPOINT_MIN` = 150 m since commit ae67d94): a gate on each of them is allowed, and without one the shortest way between the
  gates before and after does not take them. Do not change the constants or the rule.
- `maxRounds` is 7: you have up to three more rounds.

## Lead decisions (round 6)
- **The lanes of the game are new** (jobs roads-junction-exits, roads-junction-stubs and roads-connector-curves are merged): a road
  is cut where a side street meets it beside its centre line (Henan Rd now turns into `st_d2_ew_4`, the Bund into Nanjing E Rd),
  two junctions close together share one cut, the connectors are smooth curves. `H:/dev/skyrush/game/world/data/lanes.json` is
  the new graph, and your worktree has the new lanes and road tiles too (the lead merged them: `test_route_layers.gd` imports
  the new tiles on its first run, a few minutes). The acceptance reads them.
- Your `city.json` of the end of round 5 on the new lanes: `ROUTES_DRIVABLE OK` (0 bad legs, 0 reversals on every route) and
  `ROUTE_ITINERARY FAIL 1`: `SKIPPED river_loop: the race never drives bund_zhongshan_e1`. The rules gate of round 5:
  `route river_loop: # m between cp08 and cp09` and `cp11 cannot be reached from cp10` (the Python graph).
- Round 5 ran out of turns (300 tool calls). `maxRounds` is 9 now. Keep your status file short and current: write the state
  of the five routes into it before you run long experiments.

## Pitfalls
- The rule "route checkpoints on the lanes" wants 300-500 m of driving between two gates, measured with the shortest path of the
  Python graph. A leg whose shortest path is under 300 m while it is 400 m along the itinerary is a place where the race would cut:
  that is a place for step 3, not a reason to change the rule.
- Do not delete a route, do not make a route a sprint to get rid of its closing leg, do not change the spacing constants.
- The gate boards of the game (`game/modes/textures`) depend on the number of gates: leave them, the lead regenerates them.
- `build_city.py` writes the whole map: only `routes` may change (acceptance 2). If anything else changes, you changed something
  that the rest of the map reads.

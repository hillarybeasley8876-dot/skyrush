# roads-dead-end-uturns — no lane ends at a junction without a way on

## Plan
1. Baseline: build the lanes and the tiles into the scratch dir, run every acceptance check, keep the output.
2. Measure: which approach lanes have no movement, and why (the arms, the exits and the options of their junction).
   `python tools/gd.py blender run F:/dev/skyrush-out/tmp/roads-dead-end-uturns/dbg_junctions.py`
3. New module `blender/city/roads/lane_turnround.py`: the turn round of a road that ends at a crossing.
   - the U-turn: an approach lane with no movement at its junction turns into a lane of its own road that leaves the same
     junction in the other direction; the two ends of the connector are at least 12 m apart (a car turns on a radius of 6 m),
     so a lane that is too near the other side turns into an outer lane of the other side;
   - the curve: a cubic Bezier with the arms of the arc of that radius (4R/3), on the height of the junction's fill;
   - the road that ends and has no room to turn round: the stretch of the road between the crossing and the end of the road
     gets its lane back and the traffic carries on into it.
4. `lane_links.py`: call the new module after the attaches and the chains (a lane that already has a way on is left alone).
5. Verify offline: `check_lane_graph --max-junction-termini 0`, `check_lane_stubs --ref`, `check_connector_shape --max 100`,
   `check_junction_exits --max 5`, `check_lane_dupes`, `check_chain_links`, `check_routes_drivable`, `check_path_blockers`,
   `check_new_uturns --min-chord 12 --max 12`.
6. Install the lanes into the game and run the test: `python tools/gd.py test res://assets/city/roads/tests/test_lanes.gd -- --timeout=600`.

## Done
- `blender/city/roads/lane_turnround.py` (new): the turn round of a road that ends at a crossing.
  - the U-turn (case 1): the approach lane of Pudong South Rd (3 lanes) that has no movement at the junction of the ramp
    `nanpu_pudong_loop` turns into the lane of the other carriageway that is at least 12 m away: fwd0 -> back2, fwd1 -> back1,
    fwd2 -> back0 (the chords are 12.24 m, the radius 6.12 m).  The connector is a cubic Bezier with the arms of the arc of
    that radius (4R/3), on the height of the fill of the junction; its kind is "uturn".
  - the road end (case 2): the approach lane of st_d4_ew_12 that has no movement (the junction j_st_d4_ew_12_st_link_69_1 has
    two arms of one road only, so there is no room for a turn round: the other carriageway is 3.5 m away) carries on into the
    lane of the stretch of the road between the crossing and the end of the road (36 m, the lane `end_st_d4_ew_12_1_back0`).
    It ends at the end of the road: the traffic stops at the end of the network, not in the middle of a crossing.
- `blender/city/roads/lane_links.py`: `link_chains` calls `lane_turnround.turn_arounds` at the end (after the junctions, the
  attaches and the chains, so a lane that already has a way on is left alone).
- `game/world/data/lanes.json`: the lanes of the build (10693 lanes, 4 more than before).

## In progress / next
Nothing: the work is done and every acceptance command passes (see the evidence).

## How to test (exact commands)
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-dead-end-uturns/tiles --data F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full
    python tools/city/check_lane_graph.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --max-junction-termini 0
    python tools/city/check_lane_stubs.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --ref F:/dev/skyrush-out/tmp/roads-dead-end-uturns/ref_lanes.json
    python tools/city/check_connector_shape.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --max 100 --quiet
    python tools/city/check_junction_exits.py data/city/city.json F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --max 5 --quiet
    python tools/city/check_lane_dupes.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --quiet
    python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --quiet
    python tools/city/check_routes_drivable.py data/city/city.json F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json
    python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/tiles --lanes F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --max-bad 25 --max-barrier-area 395000
    python tools/city/check_new_uturns.py F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json --ref F:/dev/skyrush-out/tmp/roads-dead-end-uturns/ref_lanes.json --min-chord 12 --max 12
    python -c "import shutil; shutil.copyfile('F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full/lanes.json', 'game/world/data/lanes.json'); print('INSTALLED')"
    python tools/gd.py test res://assets/city/roads/tests/test_lanes.gd -- --timeout=600

## Evidence (key output lines)
- the build: `DONE in 305.7 s`, `LANES 4 lanes that end at a junction got a way on`
- `LANE_GRAPH OK (giants 0 of at most 0, junction termini 0 of at most 0)` (before: 4 junction termini)
- `LANE_STUBS OK` (0 new dead ends at a junction, 0 new lanes without a predecessor, 92 lanes shorter than 10 m)
- `CONNECTOR_SHAPE OK` (94 connectors with a defect, the same 94 as before: the U-turns add none)
- `JUNCTION_EXITS OK` (4 two-way roads run through a junction, one less than before), `LANE_DUPES OK`, `CHAIN_LINKS OK`
- `ROUTES_DRIVABLE OK`
- `PATH_BLOCKERS OK` (the same 25 blocked points as before, on the roads of the baseline: the new lanes add none)
- `UTURNS OK` (3 new U-turns, 0 narrower than 12 m: the ends 12.2 m apart)
- `test_lanes.gd`: `PASS no lane dead-ends at a junction (0 dead ends: ; 176 map edges)`, `TEST lanes: 10 checks, 0 failures`
- the Godot tests of the world: `test_drive_lanes` (18 checks), `test_junction_mouths`, `test_lane_surfaces_world`,
  `test_route_layers`, `test_world_api`: all PASS.

## Known issues
- `check_lanes_regression.py` (not part of the acceptance of this job) reports 2 problems, both about st_d4_ew_12: its lanes
  changed and they cover 1380 m instead of 1344 m.  That check is written for the jobs that change the linking of the ramp
  attaches ("the roads that have nothing to do with an attach must be identical to the baseline"); this job changes the lane
  graph of two roads on purpose, and the road of case 2 gets the 36 m of lane that the phantom junction had cut away.
- `test_bund_lanes.gd` fails (2 checks) with the new lanes and with the reference lanes alike: the world holds 10791 lanes
  (the check wants 11000) and 9 samples of st_nanjing_e_rd run through a building of the Bund.  Both are the state of the
  reference build, not of this change.
- The three U-turns of Pudong South Rd cross each other (their ends are 12.24 m apart and their radius is 6.12 m, so the three
  arcs of the same radius cross): the traffic code reads the crossing lanes and slows for them.

## Requests
- none

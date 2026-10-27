# Job: two junctions close together leave no lane that a car cannot leave or cannot enter (the stubs of roads-junction-exits)

Blender road builder (`blender/city/roads/`), the lane graph. No Godot needed: your checks are offline Python scripts after a
Blender build (lanes only: about 30 s; the full build at the end: about 6 minutes).

## Goal
Job roads-junction-exits cut a road where a junction stands on it (`junction_holes.road_holes`) and let the cuts of two junctions
of the same road share the road between them ("the earlier cut stops two samples before the next one starts"). Where two junctions
stand close together, that leaves a few metres of road between the two cuts, and the lanes of that stretch are broken:

    python tools/city/check_lane_stubs.py <lanes.json> --ref F:/dev/skyrush-out/tmp/roads-junction-stubs/ref_lanes.json

(read its docstring; the reference is the build before roads-junction-exits) prints today:

    6 new dead ends at a junction, 26 new lanes without a predecessor, 144 lanes shorter than 10 m (96 in the reference, at most 96)
    DEAD_END lujiazui_ring_rd_10_back0: 6.0 m long, ends at (1299.8, 0.0, -478.7)      (and _back1, _back2)
    DEAD_END st_d3b_ns_2_1_back0 / st_d5_ew_5_4_back0 / st_d6_ew_7_10_back0: 6.0 m long
    ORPHAN bund_zhongshan_e1_8_back0: 5.9 m long ...        (the Bund: 6 m of road between two junctions)
    ORPHAN century_ave_4_fwd3: 147.2 m long ...             (a long lane of Century Ave that nothing leads into)
    ORPHAN lujiazui_ring_rd_11_back0: 12.0 m long ...
    LANE_STUBS FAIL 80

A dead end: the traffic that drives into it stops there for good (`test_lanes.gd` of the game: "no lane dead-ends at a junction",
5 before the job, 10 now). An orphan: no car can drive onto it. A stub (a road lane shorter than 10 m): shorter than a car and its
gap; two junctions with 6 m of road between them are one crossing for the traffic. Make `LANE_STUBS OK` while the junctions keep
their exits (`check_junction_exits.py ... --max 8`: the 8 cases that are left are explained and are not this job).

## The case measured first (Lujiazui Ring Rd, southbound, x about 1300, z -415 to -490)
Four junctions stand within 40 m on the ring: `j_lujiazui_ring_rd_st_d7_ew_9`, `j_lujiazui_ring_rd_st_d7_ew_8` (13.9 m from the
end of the stub), `j_lujiazui_ring_rd_st_d7_ns_8` (24.3 m), `j_lujiazui_ring_rd_st_d7_ns_7` (37 m). The southbound lanes now are:

    lujiazui_ring_rd_12_back1 -> connector j_lujiazui_ring_rd_st_d7_ew_9_..._12_back1_straight_lujiazui_ring_rd_10_back1
                                 (60 m long: (1320.0, -415.6) to (1305.0, -473.9); it jumps over lujiazui_ring_rd_11_back1)
    lujiazui_ring_rd_11_back0/1  (1311, -438) -> (1308, -450), 12 m: no lane leads into them
    lujiazui_ring_rd_10_back0/1/2 (1305, -474) -> (1303, -480), 6 m: no successor (the dead ends)
    lujiazui_ring_rd_9_back0/1/2 (1296..1304, -490) -> (1224, -648)

Before the job the cuts of these junctions met and the lanes went from `_11`/`_12` straight into `_9`. The movements of a junction
come from `lane_links._arm_lanes`: a lane is an exit of an arm when it travels along the arm and its START is within
`reach = max(road_radius, 40) + CROSS_TOLERANCE` of the centre and nearer than its end; an approach when its END is. With four
junctions within 40 m, a short stretch is within the reach of all of them: it can be an exit of a junction two cuts away (the 60 m
straight connector of st_d7_ew_9 into `_10`), and an approach that no junction gives a movement. Measure this yourself first
(print `_arm_lanes` and `movements` of these four junctions for the lanes of lujiazui_ring_rd), then the other cases.

## What to build (your choice of how; these are the conditions)
- No road lane shorter than 10 m between two cuts of the same road that the reference does not have: where the stretch between two
  holes would be shorter, the holes meet (the road is cut once, from the first junction to the last), and the movements of both
  junctions start and end at the lanes before and after that one cut (an approach of the first junction can turn into the side
  streets of the second one, and the other way round), so no road runs through either junction (`check_junction_exits`).
- A movement goes from a lane end to the lane start of the same cut: never across another lane of its own road (the 60 m connector).
- Every road lane keeps a successor and a predecessor unless the reference has the same dead end or start at that place.

## Files you own
`blender/city/roads/junction_holes.py`, `blender/city/roads/junctions.py`, `blender/city/roads/lanes.py`,
`blender/city/roads/lane_links.py`, and `blender/city/roads/lane_stubs.py` (a new module, if you need one). Everything else is
read-only (`load.py`, `collision.py`, `levels.py`, `buildingcut.py`, `tools/`, `data/`, `game/`).

`lane_links.py` has 703 lines today: do not shorten its docstrings or comments to meet the 400-line rule; put new code into a new
module and keep the text of the existing files.

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-junction-stubs/data
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-junction-stubs/tiles --data F:/dev/skyrush-out/tmp/roads-junction-stubs/full

## Plan
1. Lanes-only build on the current code; `check_lane_stubs.py` and `check_junction_exits.py` on it (the baseline: FAIL 80, 8).
2. Measure the Lujiazui Ring Rd case (above) and one more case; write the numbers into `status/improve/roads-junction-stubs.md`.
3. Implement; rebuild the lanes; re-run both checks; repeat for the cases that are left.
4. The full build and every acceptance command; numbers before / after into the status file.

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `python tools/city/check_lane_stubs.py F:/dev/skyrush-out/tmp/roads-junction-stubs/full/lanes.json --ref F:/dev/skyrush-out/tmp/roads-junction-stubs/ref_lanes.json` prints `LANE_STUBS OK`.
3. `python tools/city/check_lane_graph.py .../full/lanes.json --max-junction-termini 4` prints `LANE_GRAPH OK` (the 4 dead ends of the reference that are left: Pudong South Rd at the Nanpu loop, st_d4_ew_12).
4. `python tools/city/check_junction_exits.py data/city/city.json .../full/lanes.json --max 8` prints `JUNCTION_EXITS OK`.
5. `check_lane_dupes.py .../full/lanes.json --quiet` prints `LANE_DUPES OK`; `check_chain_links.py .../full/lanes.json --quiet` prints `CHAIN_LINKS OK`.
6. `python tools/city/check_routes_drivable.py data/city/city.json .../full/lanes.json` prints `ROUTES_DRIVABLE OK`.
7. `python tools/city/check_surface_coverage.py .../tiles .../full/lanes.json --max-bad 3895` exits 0.
8. `python tools/city/check_path_blockers.py .../tiles --lanes .../full/lanes.json --max-bad 25 --max-barrier-area 395000` prints `PATH_BLOCKERS OK`.
9. `python tools/city/check_open_edges.py .../tiles .../full/lanes.json --max-regular 181 --max-connector 14 --top 0` prints `OPEN_EDGES OK`.

## Pitfalls
- A hole moved along a road moves the end of the road's surface and kerbs there too (`build_road` uses the same
  `junctions.trim_indices`): the surface coverage (7) and the blockers (8) catch a road that loses its surface or gets a kerb
  across a lane.
- `lane_links.MOVEMENTS` / `DROPPED` (job roads-lane-dupes): a movement (from, to) is built once, by the first junction that builds
  it; keep that (acceptance 5).
- Do not change how the junction records are merged (`load.py`) or raise a limit of a check.

# Job: no two connectors for the same movement (two junctions close together each built it)

Blender road builder (`blender/city/roads/`), the lane graph. No Godot needed: your checks are offline Python scripts (seconds)
after a Blender build (lanes only: about 30 s; the full build at the end: about 4.5 minutes).

## Goal
A connector lane of a junction joins the lane a car leaves from (the lane whose `next` holds the connector) to the lane it drives
into (the connector's own `next`). `lane_links.link_junctions` builds the connectors junction by junction. Where two junctions lie
close together (a staggered crossing: on Chongqing Rd a street comes in from the west at (-1094, -366) and another leaves to the east
at (-1066, -361), two T-junctions 28 m apart), the lane that passes between them is an approach of both, and both build the same
movement: **two connectors in the same place for the same pair of lanes**. Two traffic cars on them do not see each other (a car
keeps its distance to the cars of its own lane): they drive into each other and stop. `game/tools/soak_traffic.gd` found it: a car
stood 39 s on `st_chongqing_rd_7_fwd0`, 8 m before the end of the lane, touching another car, nothing in front of it.

    python tools/city/check_lane_dupes.py game/world/data/lanes.json

    11261 lanes, ..., 610 pairs joined by more than one connector (665 extra connectors)
    DUPLICATE bund_zhongshan_e1_7_fwd0 -> bund_zhongshan_e1_8_fwd0: j_bund_zhongshan_e1_st_beijing_e_rd_..., j_bund_zhongshan_e1_st_link_36_...
    LANE_DUPES FAIL 610

Make every movement have one connector: `check_lane_dupes.py` must print `LANE_DUPES OK` with `--ref` (no movement may be lost or
added: the set of (from lane, to lane) pairs stays exactly the same; only the extra connectors go).

## What to change
`_add_movement` (or `link_junctions`) in `blender/city/roads/lane_links.py`: remember the (src id, dst id) pairs already joined by a
connector, and do not build a second connector for a pair (the first junction that builds it keeps it; the junctions are visited in
the order of `city.junctions`, so the result is the same on every build). Keep the ids of the connectors that stay exactly as they
are (the id is `junction_src_kind_dst`). Read `link_junctions`, `_add_movement`, `link_attaches`, `link_chains` first: a movement may
also be built by `link_attaches` or `link_chains` — find out whether those can build a duplicate too (the checker counts any two
connectors for one pair) and handle them the same way.

## Files you own
`blender/city/roads/lane_links.py`. Everything else is read-only (`lanes.py`, `lane_paths.py`, `junctions.py`, `collision.py`,
`tools/`, `data/`, `game/`).

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-lane-dupes/data
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-lane-dupes/tiles --data F:/dev/skyrush-out/tmp/roads-lane-dupes/full

The first is the inner loop (lanes.json only, about 30 s); the second builds the tiles too (the connectors carry a strip of road
surface collision, `collision.build_connectors`), about 4.5 minutes: run it once at the end.

## Plan
1. Run the lanes-only build on the current code and `check_lane_dupes.py` on it: it must show the 610 pairs (the baseline).
2. Write your plan into `status/improve/roads-lane-dupes.md`.
3. Implement, rebuild the lanes, run `check_lane_dupes.py ... --ref F:/dev/skyrush-out/tmp/roads-lane-dupes/ref_lanes.json`.
4. Run the full build and all the acceptance commands; put the numbers before / after into the status file.

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `python tools/city/check_lane_dupes.py F:/dev/skyrush-out/tmp/roads-lane-dupes/full/lanes.json --ref F:/dev/skyrush-out/tmp/roads-lane-dupes/ref_lanes.json`
   prints `LANE_DUPES OK` (no duplicate, no movement lost, none added).
3. `check_lane_graph.py .../full/lanes.json --quiet` prints `LANE_GRAPH OK` and `check_chain_links.py .../full/lanes.json --quiet` prints `CHAIN_LINKS OK`.
4. Every race route is drivable on the new lanes: `python tools/city/check_routes_drivable.py data/city/city.json F:/dev/skyrush-out/tmp/roads-lane-dupes/full/lanes.json` prints `ROUTES_DRIVABLE OK`.
5. The road surface does not lose coverage: `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-lane-dupes/tiles F:/dev/skyrush-out/tmp/roads-lane-dupes/full/lanes.json --max-bad 4175` exits 0.
6. No lane is walled off: `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lane-dupes/tiles --lanes F:/dev/skyrush-out/tmp/roads-lane-dupes/full/lanes.json --max-bad 25 --max-barrier-area 395000` prints `PATH_BLOCKERS OK`.

## Pitfalls
- A pair of lanes may be joined directly (no connector: the end of one lane within 0.5 m of the start of the next, `DIRECT_LINK`);
  that is not a duplicate and must stay.
- Do not drop a connector whose pair has no other connector: acceptance 2 compares every pair with the reference.
- Do not change the shape of the connectors that stay, nor the junction merging (`load.City._merge_junctions`).

# Job: link the elevated roads that meet end to end (the lane graph has holes in the viaduct chain)

Blender road builder (`blender/city/roads/`). No Godot needed. Your build is the lanes-only build (about 25 seconds) and your checks are offline Python scripts (about 2 seconds).

## Goal
Four main roads are laid end to end, one after the other, with no junction between them:

    ns_elevated  ->  inner_ring  ->  nanpu_spiral_upper  ->  nanpu_bridge          (and back the same way)

The lane graph (`lanes.json`) has **no links across these three joints**. A car that drives up the N-S elevated road reaches the end of
`ns_elevated` and the lane just stops (`next` is an empty list), 0.5 m away from the start of `inner_ring`. The same at the other two joints.
Traffic, rivals, police and the race routes cannot cross them. Make every lane that arrives at such a joint continue into the lanes of the next road.

## Evidence (measured on the current builder)
1. `python tools/city/check_chain_links.py <lanes.json>` prints `CHAIN_LINKS FAIL 40` with lines like

       FAIL A  ns_elevated_0_fwd0 ends at a joint with inner_ring_0_fwd0 but has no successor
       FAIL B  inner_ring_0_fwd0 starts at a joint but has no predecessor

   (14 lanes without a successor, 16 lanes without a predecessor, 20 lanes in all that meet a lane of another road within 6 m.)
2. The numbers behind it, from the same build:
   `ns_elevated_0_fwd0` ends at (-1124.4, 10.0, 1511.5) with `next = []`; `inner_ring_0_fwd0` starts at (-1124.1, 10.0, 1511.9), 0.5 m away, with no predecessor.
   `ns_elevated` has 3 lanes per direction, `inner_ring` has 2: the third lane (`ns_elevated_0_fwd2`, 4.0 m beside the nearest start) must merge into the nearest lane of the ring.
   The same holds for `inner_ring` -> `nanpu_spiral_upper` (2 lanes, 2 lanes) and `nanpu_spiral_upper` -> `nanpu_bridge` (2 lanes, 3 lanes: here one bridge lane has no feeder, a split).
3. Cause in the code: `lane_links.link_attaches` only links **ramps** (`attach_stations` starts with `if ramp.kind != "ramp": continue`), `link_junctions` only links junction records.
   In `city.json` these four roads are joined by `attach_start` / `attach_end` records that are not ramps (for instance `ns_elevated.attach_end = {road: inner_ring, at: 0.0}`); nothing reads them.

## How the lane builder works (read this before you touch it)
`blender/city/roads/lanes.py` -> `build_lanes(city)`:
- builds one lane per road, segment, direction and index: `lane["road"]`, `lane["segment"]`, `lane["dir"]` (+1 = "fwd", along the road's path; -1 = "back", against it), `lane["index"]`;
- `lane["points"]` are in **travel order**: a "back" lane starts at the road's path END and runs to its path start;
- links are collected in the list `links` (`{"from", "to", "turn"}`); at the end `build_lanes` copies them into each lane's `next`;
- `_link_cuts` links the segments of one road, `lane_links.link_junctions` the junction movements, `lane_links.link_attaches` the ramps.

`blender/city/roads/lane_links.py` has the helpers you need: `_end_segment(segs, road, at_end)` (the segment that holds a road's last or first path point), `_of(by_road, road, seg, direction)` (the lanes of one segment and direction, sorted by index),
`_link_attach(first, second, road, lanes, links)` (a direct link when the two ends are within 0.5 m, otherwise a smooth connector lane built by `_connector`: a cubic Bezier that keeps both headings).
A connector lane is a normal lane with `"connector": True` and its own `next`.

## What to build
A new function `link_chains(city, lanes, segments, links)` in `lane_links.py`, called in `lanes.build_lanes` right after `lane_links.link_attaches(...)`:
1. Find the joints. For every road A of `city.roads` that is **not** a ramp and has `attach_start` or `attach_end` in `A.data`: the parent is `city.by_id[att["road"]]`. A joint is real when the point of A (`A.path[0]` for attach_start, `A.path[-1]` for attach_end) is within 20 m of the first or the last path point of the parent; then the joint is (A, that end of A, parent, that end of the parent). Every joint appears twice (once from each road): handle it once.
2. At a joint there are two flows. For the end of a road `R` at path end (`at_end` true): the lanes that ARRIVE are its "fwd" lanes (dir +1) of the last segment, the lanes that DEPART from there are its "back" lanes (dir -1) of the last segment. For the path start it is the other way round (arrive: dir -1, depart: dir +1, segment of the first path point).
   Flow 1: arrivals of A -> departures of the parent. Flow 2: arrivals of the parent -> departures of A.
3. Match by distance: every arriving lane that has **no outgoing link yet** gets linked to the nearest departing lane of the other road (end point to start point, plan distance at most 6 m, height difference at most 1.5 m). Every departing lane that has **no incoming link yet** gets fed from the nearest arriving lane. (So a 3 -> 2 joint merges the third lane into the second, a 2 -> 3 joint splits one lane into two. Never more than 2 successors per lane.)
   "No outgoing / incoming link yet" is read from the `links` list, so the function never doubles a link a junction already made.
4. Make the link with a copy of `_link_attach` that names the connector `chain_<from>_<to>` (not `attach_...`: the attach checkers must not see it).
5. Only the lanes of the touched roads change. Do not change a lane id, a point, a junction movement or a ramp link.

## Plan
1. Run the lanes-only build and the checks (commands below) to see the baseline. Print the joints your code finds (road, end, number of arriving/departing lanes) and compare with the list above: you must find exactly the three Nanpu-corridor joints that fail, and no others.
2. Write your plan into `status/improve/roads-chain-links.md`.
3. Implement `link_chains`, rebuild (25 s), run the checks. Fix, repeat.
4. Update the status file with the numbers before and after, and the list of lanes you linked.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --lanes-only --data F:/dev/skyrush-out/tmp/roads-chain-links/data` prints `DONE in`.
2. `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-chain-links/data/lanes.json --quiet` prints `CHAIN_LINKS OK`
   (A: no lane ends in the air at a joint, B: no lane starts without feeder, C: lanes with the same index are linked, D: every link is a direct link of at most 1.6 m or one connector of at most 60 m and turns at most 30 degrees, E: at most 2 successors).
3. `python tools/city/check_lane_links.py F:/dev/skyrush-out/tmp/roads-chain-links/data/lanes.json data/city/city.json --quiet` prints `LANE_LINKS OK` and
   `python tools/city/check_attach_geometry.py F:/dev/skyrush-out/tmp/roads-chain-links/data/lanes.json data/city/city.json --quiet` prints `ATTACH_GEOMETRY OK` (the ramp links stay as they are).
4. `python tools/city/check_lanes_regression.py F:/dev/skyrush-out/tmp/roads-chain-links/data/lanes.json F:/dev/skyrush-out/baselines/lanes_head.json data/city/city.json` prints `LANES_REGRESSION OK`.
5. `python tools/city/selftest_chain_links.py game/world/data/lanes.json` prints `SELFTEST OK` (it runs the checker on the committed, still broken lane graph and on three broken repairs of it: this proves the checker itself still works; you do not own it and you must not change `game/world/data/lanes.json`).

## Pitfalls
- Linking every arriving lane to every departing lane (rule E), or linking lanes across a joint with a straight 3 m jump (rule D wants a connector).
- Editing the checkers or the baseline: they are read-only for you.
- Writing links for joints that are already linked by a junction (g50_west -> yanan_elevated, the Bund, the tunnel portals): the function must read the `links` list and skip lanes that already have links.
- Mixing up the directions: a "back" lane starts at the path end of its road. If a car would drive against the traffic through your link, `check_chain_links` rule D (heading) and the selftest will show it; also check by hand that a "fwd" lane of `ns_elevated` feeds a "fwd" lane of `inner_ring`.
- A connector over 60 m or a joint 20 m away that is really a ramp (those are already linked by `link_attaches`).

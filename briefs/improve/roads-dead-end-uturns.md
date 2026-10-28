# Job: no lane ends at a junction without a way on (a road that ends at a junction where it cannot go on turns round)

Blender road builder, the lane graph (`blender/city/roads/lane_links.py`). Offline checks after a Blender build (lanes only:
about 40 s; the full build at the end: about 6 minutes), then one Godot test. Read `briefs/improve/_map-common.md` first.

## Goal
`game/assets/city/roads/tests/test_lanes.gd` fails on one check: "no lane dead-ends at a junction (4 dead ends:
pudong_south_rd_14_fwd0, pudong_south_rd_14_fwd1, pudong_south_rd_14_fwd2, st_d4_ew_12_1_back0)". Offline:

    python tools/city/check_lane_graph.py game/world/data/lanes.json
    ... junction termini by road: pudong_south_rd:3, st_d4_ew_12:1
    LANE_GRAPH OK (giants 0 of at most 0, junction termini 4 of at most any)

A car of the traffic (or of a race) that drives into one of these lanes has nowhere to go. Make it 0.

## The two cases (measured by the lead)
1. Pudong South Rd (3+3 lanes, two-way) ends at (1690, 0, 1280), where the spiral ramp `nanpu_pudong_loop` (2+0, one-way, down
   from the Nanpu bridge) ends too: junction `j_nanpu_pudong_loop_pudong_south_rd`. The ramp's traffic comes down and drives on
   into the southbound lanes of Pudong South Rd; the three northbound lanes arrive at the junction and the only other arm is the
   ramp, which cannot be driven up. `lane_links.link_junctions`: `_options` leaves out the arm of the approach itself (no U-turn),
   the ramp arm has no exits (`_nearest_lanes` finds none of a one-way road that arrives), so `movements` gets no option.
2. `st_d4_ew_12_1_back0` ends at (-1115.2, 0, 905.8): `st_d4_ew_12` and `st_link_69` both start at (-1150, 0, 915) and three
   junction records lie within 36 m (`j_st_d4_ew_12_st_link_69_1` 19 m from the lane end, `j_st_d4_ew_12_st_d4_ns_st_link_69`,
   `j_st_d4_ew_12_st_link_69`). Find out why that lane gets no movement (print `_arm_lanes` / `movements` for those junctions).

## What to build
- An approach that has no movement at its junction (no other arm it can drive into) turns round: a U-turn into the lanes of its
  own road that leave the same junction in the other direction. Every lane of the approach gets one (no lane may end there).
- A U-turn needs room: a car turns on a radius of 6 m or more. A lane that is too close to the lanes of the other direction for
  that (the inner lane of Pudong South Rd: 4.5 m from the inner lane of the other side) turns into an outer lane of the other
  side: the two ends of a U-turn connector are at least 12 m apart. The connector curve is `lane_paths.connector_points` (it keeps
  a curve on the fill of the junction): check its shape with `check_connector_shape.py`.
- Only where there is no other way: a junction where an approach can drive on into another road gets no U-turn (the rule "no
  U-turns" of `_options` stays for every other approach).
- For case 2: fix what the measurement shows (a lane end that belongs to another junction of the three, a movement that is
  dropped as a duplicate, ...) in your file.

## Files you own
`blender/city/roads/lane_links.py`, and `blender/city/roads/lane_turnround.py` (a new module, if you need one; `lane_links.py`
has over 700 lines: do not shorten its comments, put new code into the new module). Everything else is read-only.

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-dead-end-uturns/data
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-dead-end-uturns/tiles --data F:/dev/skyrush-out/tmp/roads-dead-end-uturns/full

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `check_lane_graph.py .../full/lanes.json --max-junction-termini 0` prints `LANE_GRAPH OK`.
3. `check_lane_stubs.py .../full/lanes.json --ref F:/dev/skyrush-out/tmp/roads-dead-end-uturns/ref_lanes.json` prints `LANE_STUBS OK`
   (no new dead end, no new orphan: the reference is the lanes.json of the game today).
4. `check_connector_shape.py .../full/lanes.json --max 100` prints `CONNECTOR_SHAPE OK` (94 today: the U-turns are smooth).
5. `check_junction_exits.py data/city/city.json .../full/lanes.json --max 5` prints `JUNCTION_EXITS OK`;
   `check_lane_dupes.py ... --quiet` `LANE_DUPES OK`; `check_chain_links.py ... --quiet` `CHAIN_LINKS OK`.
6. `check_routes_drivable.py data/city/city.json .../full/lanes.json` prints `ROUTES_DRIVABLE OK`.
7. `check_path_blockers.py .../tiles --lanes .../full/lanes.json --max-bad 25 --max-barrier-area 395000` prints `PATH_BLOCKERS OK`.
8. `python tools/city/check_new_uturns.py .../full/lanes.json --ref .../ref_lanes.json --min-chord 12 --max 12` prints `UTURNS OK`
   (a new connector that turns 150 degrees or more is a U-turn: its ends at least 12 m apart, at most 12 new U-turns).
9. The lanes go into the game and `test_lanes.gd` passes: the build's `lanes.json` is copied to `game/world/data/lanes.json`, then
   `python tools/gd.py test res://assets/city/roads/tests/test_lanes.gd -- --timeout=600` prints no `FAIL`.

## Pitfalls
- Do not delete the lanes that dead-end, do not mark them as map edges, do not raise a limit of a check.
- A U-turn is the last resort: if an approach has any other arm to drive into, it does not turn round.
- The connector of a U-turn has `"turn": "uturn"` (the game reads the kind of a turn: look for `turn` in `game/world/` to see what
  a new kind means there before you add it; if the game has no use for it, `"left"` with the U-turn geometry is the other way).

# Job: the junction connectors are smooth curves (no loops, no back-ups, no corners)

Blender road builder (`blender/city/roads/`), the lane graph. No Godot needed: offline Python checks after a Blender build
(lanes only: about 30 s; the full build at the end: about 6 minutes).

## Goal
A connector (a lane of `lanes.json` with `"connector": true` and a `"junction"`) is the path a car follows through a junction:
the traffic drives along it, the racing line of a race is made of them, the speed of a rival comes from its curvature. Today
1093 of the 7261 connectors loop, back up or have a corner:

    python tools/city/check_connector_shape.py <lanes.json>          (read its docstring)
    1093 connectors with a defect (KINK 199, LOOP 894) ...
    LOOP j_st_d7b_ew_17_st_d7b_ns_11_st_d8_ew_17_st_link_92_st_d7b_ew_17_0_fwd0_right_st_link_92_0_back0: 85.6 m for a chord of
         58.5 m, net turn +22 deg, turning 650 deg, worst step 133 deg
    LOOP j_lujiazui_ring_rd_st_d7_ns_12_yincheng_rd_0_fwd1_right_st_d7_ns_12_0_fwd0: 59.6 m for a chord of 48.3 m, net turn
         -376 deg, turning 563 deg, worst step 180 deg

Make it at most 150 (`--max 150` prints `CONNECTOR_SHAPE OK`) without letting a connector leave the road (the checks below).

## The cause seen first (measured by the lead; check it, and find the cause of the cases that differ)
`lane_paths.connector_points` makes a cubic Bezier from the end of the approach lane to the start of the exit lane, pulls its
control points towards the centre of the junction (`pull` 0 .. 1) until every sample lies inside the fill of the junction, and
otherwise keeps the first candidate. Each candidate goes through `clamp_to_fill`, which moves **every sample outside the fill to
the nearest point of the outline of the fill** (0.5 m inwards). Consecutive samples land on different edges of the outline: the
curve becomes a zigzag along the outline, backs up and turns corners. Example (`j_lujiazui_ring_rd_st_d7_ns_12_yincheng_rd_0_fwd1_
right_st_d7_ns_12_0_fwd0`, 32 samples of 2 m): samples 0-7 run straight at heading -165 deg, sample 8 goes 0.84 m **back**
((733.58, -496.81) -> (733.88, -497.60)), and the last three steps turn 35 and 58 degrees. Draw a junction to see it:
`python F:/dev/skyrush-out/tmp/draw_junction.py <lanes.json> <junction id> <out.png> [half]` (red: the defective connectors).

The worst case of a whole race: the straight movement of `lujiazui_ring_rd_5_fwd2` into `lujiazui_ring_rd_6_fwd2` built by
`j_lujiazui_ring_rd_st_d7_ew_16` is 61.6 m for a chord of 24.2 m and turns 167 degrees (a junction 20 m away pulled it towards
its own centre); a race that had to follow it turned off the ring onto the side streets instead. (Which of two junctions that
build the same movement keeps it is `lane_links.py`, not this job: make every copy a good curve.)

## What to build
A connector is one smooth curve from the lane end to the lane start: it never goes back, no step of it turns more than 30
degrees, it winds no more than the turn it makes, and it stays on the asphalt of the junction. Do not move single samples: choose
the curve (the length of the control arms, the pull towards the centre, the way it bends) so that it stays on the fill, and where
no curve of the family fits, keep the smooth curve that leaves the fill least (the drivable surface is the collider of the
junction, `junction_fill.COLLIDER_MARGIN` wider than its asphalt). Keep `fit_to_fill` (the heights) and the ends exact (they meet
the lanes they join).

## Files you own
`blender/city/roads/lane_paths.py` and `blender/city/roads/connector_curve.py` (a new module, if you need one). Everything else is
read-only (`lane_links.py`, `junctions.py`, `junction_holes.py`, `junction_fill.py`, `levels.py`, `tools/`, `data/`, `game/`).

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-connector-curves/data
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-connector-curves/tiles --data F:/dev/skyrush-out/tmp/roads-connector-curves/full

## Plan
1. Lanes-only build of the current code; `check_connector_shape.py` on it (the baseline; it may differ a little from 1093: the
   code of the current branch cuts some junctions differently from the lanes.json of the game).
2. Draw three of the worst junctions; measure for twenty defective connectors which step made the defect (the clamp, the pull,
   the lane ends themselves); write the counts into `status/improve/roads-connector-curves.md`.
3. Implement; rebuild the lanes; re-run the check; repeat.
4. The full build and every acceptance command; numbers before / after into the status file. List the defects that are left by
   cause (for a few of them the lane ends may face each other so that no curve can join them: name the junctions).

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `python tools/city/check_connector_shape.py F:/dev/skyrush-out/tmp/roads-connector-curves/full/lanes.json --max 150` prints `CONNECTOR_SHAPE OK`.
3. `python tools/city/check_path_blockers.py .../tiles --lanes .../full/lanes.json --max-bad 25 --max-barrier-area 395000` prints `PATH_BLOCKERS OK` (no connector drives into a kerb, a parapet or a pier).
4. `python tools/city/check_surface_coverage.py .../tiles .../full/lanes.json --max-bad 3895` exits 0 (the lanes have road under them).
5. `python tools/city/check_lane_graph.py .../full/lanes.json --max-junction-termini 10` prints `LANE_GRAPH OK`; `check_lane_dupes.py ... --quiet` prints `LANE_DUPES OK`; `check_chain_links.py ... --quiet` prints `CHAIN_LINKS OK`.
6. `python tools/city/check_routes_drivable.py data/city/city.json .../full/lanes.json` prints `ROUTES_DRIVABLE OK`.
7. `python tools/city/check_junction_exits.py data/city/city.json .../full/lanes.json --max 8` prints `JUNCTION_EXITS OK`.

## Pitfalls
- The fill is why the clamp exists: a movement that bows out over the kerb puts the cars on the sidewalk (acceptance 3 and 4).
- Do not change which lanes a connector joins, which movements exist, or the junction geometry: only the path between the two
  ends. The lane graph checks (5, 7) must give the same numbers as before your change.
- `MAX_CONNECTOR` and the other limits stay.

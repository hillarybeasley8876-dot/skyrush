# roads-joint-ends — fence the deck ends where a wide elevated road meets a narrow one

## Plan
1. Baseline build into the scratch dir; run the 7 acceptance commands on it.
   `python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-joint-ends/tiles --data F:/dev/skyrush-out/tmp/roads-joint-ends/data`
   then the 7 commands of the brief.  DONE: 5 run off, 190/23 open edges, 32 lane blockers,
   barrier area 387 959 m2, attach lips 10, chain lips 0.
2. Measure the joints offline (a scratch script that copies the path maths of blender/lib/geo.py):
   the end points, the tangents, the 9.6 deg / 5.3 deg angle, the lane ends and their rays.
   `python F:/dev/skyrush-out/tmp/roads-joint-ends/design.py` -> the 5 bad lane ends are reproduced.
3. Implement `deck.build_joint_ends(city, tileset)`: the NOSE (a surface that fills the hole
   between the two decks) + the FENCE (a parapet on the outer edge of the nose and across its
   far end).  Call it from `build_roads.py` main() after the junctions, before `edgewalls.add`.
4. Build, then `python tools/city/check_joint_runoff.py <tiles> <lanes> data/city/city.json`
   -> "JOINT_RUNOFF OK" (0 run off).  Repeat until it does.
5. Run all 7 acceptance commands on the scratch build and write the before/after numbers here.
   DONE: all 7 pass (see Evidence).

## Done
- Step 1, 2, 3, 4, 5.
- `blender/city/roads/deck.py`: `build_joint_ends(city, tileset)` + helpers.
- `blender/city/roads/build_roads.py`: one call after the junctions, before `edgewalls.add`.
- The fence itself: the visible parapet (`profiles.parapet_profile()`, 0.5 m at the base, 1.0 m
  high, material `deck.PARAPET`) and its collider (`collision.build_edge_barrier`: 0.42 m thick,
  1.0 m over the deck, the face towards the traffic vertical — the collider of every parapet of
  the city; the wall of `edgewalls.add` is 0.55 m thick).  The fence overlaps the parapet of the
  wide road by 0.3 m, so there is no gap at the corner.

## What was built and why (not option 1 of the brief)
Option 1 (a fence only, across the wide deck end from the wide edge to the narrow edge) does NOT
make `check_joint_runoff` pass; measured, not guessed:
- The two end caps stand at 9.6 deg (ns_elevated/inner_ring) and 5.3 deg (nanpu_bridge/spiral)
  to each other, so there are TWO holes, not one: the wedge between the caps (0.5 to 1.9 m deep
  at the lanes of the inner lanes) and the strip beside the narrow deck (the 4 m of the wide
  deck that overhangs it).  The rays of `ns_elevated_0_fwd0` (+1 m) and `ns_elevated_0_fwd1` fall
  into the WEDGE, which no fence along the end line can close: the fence would have to stand
  where the traffic of the narrow road enters.
- The outer lane cannot be fenced at the end line either: its merge curve
  (`chain_ns_elevated_0_fwd2_inner_ring_0_fwd1`) starts at the very same point and runs in the
  same direction for its first metre, so a wall there walls the merge curve off (acceptance 3
  and 5 drive it).
So: the NOSE (a piece of deck that fills the hole between the two decks) + the FENCE on its
outer edge and across its far end.  The nose is 5 m long, so its fence stands past the merge
curve (which reaches 3.5 m).  The nose gives the merge curves a surface as well: they had none
(the chain connectors get no collision surface), so that traffic drove over the hole too.
The nose is built only where the two roads are of a different width (0.5 m or more), so the
same-width joint (inner_ring -> nanpu_spiral_upper) is left alone.

## How to test (exact commands)
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-joint-ends/tiles --data F:/dev/skyrush-out/tmp/roads-joint-ends/data
    python tools/city/check_joint_runoff.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json data/city/city.json --quiet
    python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/paths_now/chain --lip 0.25 --max-lips 0 --max-bad 0 --max-barrier-area 395000
    python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/paths_now/attach --lip 0.25 --max-lips 10 --max-bad 0 --max-barrier-area 395000
    python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles --lanes F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --max-bad 32 --max-barrier-area 395000
    python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --max-regular 190 --max-connector 23 --top 0
    python tools/city/check_lane_graph.py F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --quiet && python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --quiet

## Evidence (key output lines) — before -> after
- build: "DONE in 241.8 s", exit 0; "JOINT ns_elevated -> inner_ring: the nose ... 5.0 m",
  "JOINT nanpu_bridge -> nanpu_spiral_upper: the nose ... 5.0 m"
- joint runoff: "14 lane ends at deck joints, 5 run off / JOINT_RUNOFF FAIL 5"
  -> "14 lane ends at deck joints, 0 run off / JOINT_RUNOFF OK"
- chain paths: OK, 0 blocked points, "lips: 0" -> OK, 0 blocked points, "lips: 0"
- attach paths: OK, "lips: 10" -> OK, "lips: 10"
- all lanes: OK, worst roads yanan_rd_surface:17, st_d6b_ns_3:7, nanpu_pudong_loop:5, yanan_elevated:3
  -> OK, the same worst roads
- open edges: "190 on the regular lanes, 23 on the connector lanes" -> "181 ... 14" (OPEN_EDGES OK)
- barrier collider area: 387 959 m2 -> 388 057 m2 (+98 m2: the two fences; the cap is 395 000)
- EDGEWALLS_DEBUG at the Yan'an joint: every edge near the joint is "no wall (last reason fenced)"
  or "a lane goes through or along it" -> the edge walls build no second wall at the joint.

## Known issues
- The nose has no girder under it: it is a flat plate of asphalt (with the parapet on its edge).
  The deck below it ends at the cap of the wide road, so the nose floats.  A keel (or a girder
  that tapers like the deck's) would close that; it is a look, not a safety point, and it is
  not part of this job.
- The nose is one flat fan, so at the Nanpu joint (the spiral climbs 3.9 %) its inner edge
  follows the spiral's edge down and the plate is very slightly warped there.  It drives fine
  (no lip, the checks say so), but it is not a perfectly flat surface.
- The same-width joint (inner_ring -> nanpu_spiral_upper) keeps a 0.4 m sliver of hole between
  the two end caps (the caps stand at 3.3 deg).  No lane end falls into it today (the checker
  says so), and the brief only asks for the joints where the widths differ.

## Requests
- none

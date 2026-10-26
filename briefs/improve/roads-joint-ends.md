# Job: the joints of the elevated chain must not let a car drive off the deck

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (seconds) after a Blender
road build (about 4.5 minutes).

## Goal
The elevated chain is four roads that meet end to end (no junction between them): `ns_elevated` -> `inner_ring` ->
`nanpu_spiral_upper` -> `nanpu_bridge`. At two of those joints the roads have different widths:

| joint (Godot x, z, height) | wide road (lanes each way) | narrow road |
|---|---|---|
| (-1122.0, 1510.0), y 10.0 | `ns_elevated` end, 3 + 3 lanes, deck half width 13.5 m | `inner_ring` start, 2 + 2, half width 9.5 m |
| (981.96, 1271.62), y 42.5 | `nanpu_bridge` start, 3 + 3 lanes, half width 14.0 m | `nanpu_spiral_upper` end, 2 + 2, half width 9.5 m |

The deck of the wide road simply ends at the joint and the narrow road starts there. On the side where the wide road is wider,
the outer 4 m of the wide deck end in thin air: no deck goes on, and no parapet closes the end. A car on the outer lanes of
the wide road that drives straight on (the outer lanes are linked to the narrow road by a 6 m merge curve, the arcade car does
not follow it) drives off the end of the deck and falls 10 m (Yan'an side) or 42 m (Nanpu bridge). The random drives found it:
from the Nanpu bridge onto the spiral at 140 km/h, every one of 4 drives on the outer lane fell.

Make those deck ends safe. Either (both are fine, choose one, and say which and why in your status file):
1. **Fence the end**: a barrier across the part of the wide deck end that has no deck of the narrow road behind it — a visible
   parapet (the profile of `profiles.parapet_profile()`, material `deck.PARAPET`) and its collider (`collision.build_edge_barrier`
   or a closed box like `edgewalls.add` builds, at least 1.0 m high over the deck with a vertical face towards the traffic, at least
   0.5 m thick), from the outer edge of the wide deck to the edge of the narrow deck, along the line where the wide deck ends; or
2. **Taper the deck**: widen the narrow road's deck over its first metres (or narrow the wide road over its last metres, with
   the lanes kept), so the outer lanes run onto deck that goes on, with the parapet following the new edge.

Option 1 is the smaller change. The traffic is not affected by it: the outer lanes of the wide road are linked to the narrow
road by merge curves that stay on the deck.

## Evidence (measured, not guessed)
- `python tools/city/check_joint_runoff.py game/assets/city/roads game/world/data/lanes.json data/city/city.json` (new checker,
  2 s): 14 lane ends at deck joints, **5 run off**: `nanpu_bridge_1_back1`, `nanpu_bridge_1_back2`, `ns_elevated_0_fwd0` (only its
  +1 m offset), `ns_elevated_0_fwd1`, `ns_elevated_0_fwd2`; each prints `offset ... leaves the road 0.5 m on`: the surface ends
  right at the lane end.
- The road data: `nanpu_bridge` and `ns_elevated` have `lanes_fwd: 3, lanes_back: 3, lane_width 3.75, median 1.0, shoulder 1.75 /
  1.25`; `inner_ring` and `nanpu_spiral_upper` have `2 / 2, 3.75, 1.0, 1.0`. `profiles.layout(road)` gives `asphalt_fwd` /
  `asphalt_back` (the deck edges from the centre line, right positive).
- The joints are found by `lane_links._chain_joints(city)`: it returns `(road, here, parent, there)` with `here`/`there` = "start" or
  "end". The path of a road is `road.path` (Blender space: x east, y NORTH = -Godot z, z up), `road.frames[i] = (tangent, right, up)`.
  At a joint the two end points are the same point; the end directions differ by 5-10 degrees.

## What to build
- A function in `blender/city/roads/deck.py` (for example `build_joint_ends(city, tileset)`) that runs over
  `lane_links._chain_joints(city)`, takes the pairs where BOTH roads are elevated (`road.elevated`), and for each side ("fwd" /
  "back") of each joint where one deck edge lies more than 0.5 m outside the other road's edge, builds the fence (option 1) along
  the end line of the wider deck, from its outer edge to where the narrower deck's edge meets that line.
  - Mind the directions: the "fwd" side of one road may be the "back" side of the other (one road arrives with its path, the other
    leaves; check the tangents). Compute the edge points in world space (`p + right * asphalt_fwd` etc.) and compare positions, not
    labels.
  - The parapet of the wide road runs along its edges up to the end; your fence must meet it at the outer corner (overlap 0.3 m is fine)
    so there is no gap a car slips through.
- Call it once from `build_roads.py` `main()` after all roads and junctions are built and before `edgewalls.add` (the edge walls must
  see your barrier and not build a second wall there). `build_roads.py` is yours to edit for this call only.
- Put each piece into the tile it lies in: `tileset.builder_at(point)`.

## Files you own
`blender/city/roads/deck.py`, `blender/city/roads/build_roads.py`. Everything else, including `collision.py`, `edgewalls.py`,
`lane_links.py`, `profiles.py` and `tools/`, is read-only (you may CALL functions of those modules).

## Where the build writes (never into the repo)
Always build into your scratch directory, so your diff contains only your source files:

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-joint-ends/tiles --data F:/dev/skyrush-out/tmp/roads-joint-ends/data

About 4.5 minutes, prints `DONE in`. The checks read the tiles from `F:/dev/skyrush-out/tmp/roads-joint-ends/tiles` and the lanes from
`F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json`. To find a fence quickly: `EDGEWALLS_DEBUG=x,z,r` (Godot x and z) makes
`edgewalls.add` print what it decides for the deck edges within r metres of that point.

## Plan
1. Run the baseline build into the scratch directory and the acceptance commands below on it: they must show the 5 run-offs and the
   baseline numbers listed under Pitfalls. Read `lane_links._chain_joints`, `profiles.layout`, `deck.build_parapets`,
   `deck.build_strip_parapets` (a parapet along a polyline: a good model) and `collision.build_edge_barrier`.
2. Write your plan into `status/improve/roads-joint-ends.md`.
3. Implement, build (4.5 minutes), run `check_joint_runoff.py` on the scratch output and read which lane ends still run off. Repeat.
4. Run all the acceptance commands and put the numbers before / after into the status file.

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `python tools/city/check_joint_runoff.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json data/city/city.json`
   prints `JOINT_RUNOFF OK` (0 lane ends run off).
3. The chain paths still drive through: `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/paths_now/chain --lip 0.25 --max-lips 0 --max-bad 0 --max-barrier-area 395000`
   prints `PATH_BLOCKERS OK` (the paths that drive every chain link of the joints: your fence must not stand in a merge curve).
4. The ramp attaches still drive through: the same with `F:/dev/skyrush-out/paths_now/attach --lip 0.25 --max-lips 10 --max-bad 0 --max-barrier-area 395000`.
5. No lane is walled off: `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles --lanes F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --max-bad 32 --max-barrier-area 395000`
   prints `PATH_BLOCKERS OK` (32 blocked points today, not one more).
6. The open deck edges do not grow: `python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-joint-ends/tiles F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --max-regular 190 --max-connector 23`
   prints `OPEN_EDGES OK`.
7. The lanes are untouched: `python tools/city/check_lane_graph.py F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --quiet` prints
   `LANE_GRAPH OK` and `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-joint-ends/data/lanes.json --quiet` prints `CHAIN_LINKS OK`.

## Pitfalls
- Baselines today (the committed tiles): open edges 190 regular / 23 connector, lane blockers 32, barrier collider area 387,959 m2,
  attach lips 10, chain lips 0. Your fence adds a few hundred m2 of barrier at most; the cap is 395,000.
- A fence ACROSS the narrow road would stop all traffic: it must cover only the part of the wide deck's end where no deck of the
  narrow road lies behind it (from the wide edge to the narrow edge, about 4 m on each side of each joint). Check with the chain
  paths (acceptance 3) — they drive every link through the joint.
- The two roads' paths both end AT the joint point; their right vectors differ by 5-10 degrees, so the narrow edge does not lie
  exactly on the wide road's end line. Measure where the narrow deck's edge crosses the end line instead of assuming it.
- Do not change the lane graph, the widths of the roads or `edgewalls.py`; do not raise any limit of a check.
- Heights: the joints are at y 10.0 and y 42.5 (Godot); the fence stands on the deck there (`road.path[i].z` in Blender space).

# ROUND 2 — the lead reviewed your result: connected, but NOT drivable (read this first)

Your cut-and-link passes `check_lane_links.py` (19 of 19 attaches are linked) and `check_lanes_regression.py`. Good work on both. But a link that exists is not a link a car can follow.
The lead measured the direction change at every joint of the new attach links:

    66 links touch a ramp or an attach connector, 35 of them turn the traffic by more than 45 degrees (worst: 103, 96, 78, 76, 75, 68 degrees):
    yanan_elevated_6_back2 -> attach_yanan_elevated_6_back2_ramp_l3_wb_sb_0_fwd0   78 deg
    attach_yanan_elevated_6_back2_ramp_l3_wb_sb_0_fwd0 -> ramp_l3_wb_sb_0_fwd0     76 deg
    attach_ns_elevated_4_fwd2_ramp_l4_sb_eb_0_fwd0 -> ramp_l4_sb_eb_0_fwd0         96 deg

Why: the ramp lane starts about 6 m BESIDE the parent lane (the ramp attaches to the edge of the carriageway). Your connector bridges that 6 m lateral gap in a few metres, so it is almost a sideways step:
a traffic car following it must turn 70 to 100 degrees at the joint and drives into the parapet. A car can follow a connector only if the direction of travel changes by at most 30 degrees at every joint.

New requirement (checked by `python tools/city/check_attach_geometry.py <lanes.json> data/city/city.json --quiet`, must print `ATTACH_GEOMETRY OK`): for every lane of every ramp that starts or ends at an attach there must be a path
parent lane -> [connector] -> ramp lane (diverge) or ramp lane -> [connector] -> parent lane (merge) in which the heading changes by at most 30 degrees at every joint (heading = direction of the last/first 4 m of a lane).
Today 29 of 30 ramp lanes have no such path.

How to get there (a recipe, you may find a better one):
- A smooth lateral shift of 6 m with at most 30 degrees of heading change needs about 25 to 40 m of road. So **cut the parent lane further away from the ramp**: for a diverge, end the parent lane about 40 m BEFORE the attach
  station (the road builder really has a gore and a 150 m taper there, see `attaches.py`, so there is road room); for a merge, start the parent lane about 40 m AFTER the attach station. The parent lane's own through traffic still continues
  with the straight continuation link across that cut (you already built those).
- Build the connector as a smooth curve whose end tangents equal the headings of the two lanes it joins (a cubic Hermite / Bezier with tangent handles along each lane's heading, about 0.5 x the length), not a straight bridge.
  `lane_paths.connector_points(first, second)` is the existing helper: check how it builds the curve and whether it honours the end tangents; extend it or write your own in `lane_links.py`.
- The checker now accepts a parent lane end up to 60 m from the ramp end point (it used to be 25 m), so the longer connector is allowed. `check_lane_links.py` was updated the same way.
- Keep everything the checks already guarantee: no slivers (cuts closer than about 8 m share one cut), untouched roads identical, links end to end within 0.5 m for direct links, `LANE_LINKS OK`.

Updated acceptance (all four must pass): the lanes-only build, `check_lane_links.py ... --quiet` -> `LANE_LINKS OK`, `check_lanes_regression.py ...` -> `LANES_REGRESSION OK`, **and** `check_attach_geometry.py ... --quiet` -> `ATTACH_GEOMETRY OK`.

---

# Job: cut the parent lanes at the ramp attaches so that every attach is a drivable link

Blender road builder, lane graph only (about 25 seconds per run, no tiles, no Godot). Read `blender/city/roads/lanes.py` and the attach part of `blender/city/roads/lane_links.py` first.

## Goal
In `lanes.json` every ramp attach must be a real link that traffic can follow:
- where a ramp **leaves** its parent (`attach_start`): a lane of the parent ends next to the attach and links to a lane of the ramp that starts there;
- where a ramp **joins** its parent (`attach_end`): a lane of the ramp ends next to the attach and links to a lane of the parent that starts there.
Today **19 of 19 attaches are unlinked** (the dragon-pillar interchange ramps, the Nanpu spiral and the Pudong loop). Traffic, police and rival cars cannot enter or leave the
viaducts, and the 15 ramp lanes that just stop are wrongly labelled `terminus_kind: "map_edge"`.

## Evidence
`python tools/city/check_lane_links.py F:/dev/skyrush-out/baselines/lanes_head.json data/city/city.json --quiet` (the lanes of the unmodified builder):
```
MISSING ramp_l3_eb_nb.attach_start -> yanan_elevated: 0 source lanes, 1 target lanes within 25 m (nearest source end 378.3 m, nearest target start 0.0 m)
MISSING ramp_l3_eb_nb.attach_end   -> ns_elevated:    1 source lanes, 0 target lanes within 25 m (nearest source end 0.0 m, nearest target start 1199.3 m)
...
LANE_LINKS FAIL (19 attaches, 19 missing, 15 ramp lanes wrongly marked as map edge)
```
Read it: the ramp's own lane ends exactly at the attach (distance 0.0), but the nearest lane END of the **parent** is 378 m, 437 m, 1199 m away.

## Root cause (already found, verify it yourself)
- `lanes.segments(city, road)` cuts a road into segments **only where it passes through a junction**. A viaduct such as `yanan_elevated` has long lane segments with no end at a ramp attach.
- `lane_links.link_attaches` looks for lane **ends** (first or last point of a lane) of the parent within `ATTACH_TOLERANCE = 25 m` of the parent's path point at the attach, and pairs one with a ramp lane end (an exit end with an entry end). There is no lane end there, so `parent_cands` is empty and it silently `continue`s.
- The generator's own lane graph (`tools/city/city_rules_graph.py`, `_split_points`) already splits every road at its attaches; the Blender lane builder never did. That mismatch is the bug.

## What to build (design is yours, within these constraints)
1. **Cut the parent's segments at every attach station** (for both `attach_start` and `attach_end` of every ramp whose parent is that road): the lanes of the two halves must end and start **exactly at the same point** (share the path index at the cut) so the gap is 0 m.
2. **Link the halves**: a lane that crosses a cut must stay drivable, so add the straight link from the end of the first half to the start of the second half of the same lane (mind the back carriageway: its points are reversed, so its "first half" in travel order is the later part of the path).
3. Then `link_attaches` finds a parent lane end at the attach and links it to the ramp lane (directly if they touch within 0.5 m, else through the connector lane it already knows how to build). Check that it picks the right half: an exit end must pair with an entry end.
4. **No slivers**: attaches that lie within about 8 m of each other, or within about 8 m of a junction cut or the road's end, must share one cut (or reuse the existing cut), otherwise you create lanes of a few metres. The checker fails lanes shorter than 5 m.
5. The cut must not change geometry or lengths: only how the same lane polylines are divided and linked.
6. Keep the lane id scheme `<road>_<segment>_<side><index>`. Segment numbers on the cut roads will shift: that is fine, nothing outside `lanes.json` may depend on them (grep `game/` and `tools/` for hard-coded lane ids of the cut roads and report what you find under `## Requests`; do not edit `game/`).

## Files you own
`blender/city/roads/lanes.py`, `blender/city/roads/lane_links.py`. Not yours: `build_roads.py` (already has `--lanes-only`), tiles/geometry modules, anything under `game/`, `tools/city/check_*.py`.

## Plan
1. Run the baseline build and both checkers (commands below) to see the numbers. Look at `lanes.json` around one attach yourself: lanes of `yanan_elevated` near the `ramp_l3_wb_sb` attach, their segment indices and end points.
2. Write the plan into `status/improve/roads-lane-split.md`.
3. Implement the cut in `segments()` (or a helper called from it), the continuation links in `build_lanes`, fix anything `link_attaches`/`lane_at` needs. Run the lanes-only build after each step (25 s).
4. Run all three acceptance commands. Fix the regression checker's complaints before anything else: they usually point at a sliver or at an untouched road you changed by accident.
5. Update the status file with the numbers.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --lanes-only --data F:/dev/skyrush-out/tmp/roads-lane-split/data` (about 25 s, prints `DONE in`).
2. `python tools/city/check_lane_links.py F:/dev/skyrush-out/tmp/roads-lane-split/data/lanes.json data/city/city.json --quiet` prints `LANE_LINKS OK` (19 attaches linked, no ramp lane wrongly marked as map edge).
3. `python tools/city/check_lanes_regression.py F:/dev/skyrush-out/tmp/roads-lane-split/data/lanes.json F:/dev/skyrush-out/baselines/lanes_head.json data/city/city.json` prints `LANES_REGRESSION OK` (roads without attaches identical, same drivable length per road, no slivers, links consistent and end to end).

## Pitfalls
- Adding a link from any ramp lane to any parent lane just to satisfy the checker: it needs a parent lane END within 25 m of the attach, so only a real cut passes; the lead will also read your diff.
- Cutting every road at every point: roads without attaches must stay byte-identical (check 3 tests it).
- Forgetting the back carriageway (`side == "back"`): its points are reversed, so lane start/end and first/second half swap.
- Breaking `start_junction` / `end_junction` of the halves: `link_junctions` uses them to build the turning movements. A cut end that is not a junction must be `None`.
- Passing a cached state between runs: each lanes-only run starts clean in a fresh Blender.

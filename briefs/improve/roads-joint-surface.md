# Job: the attach gore must carry the cars (collision under every attach connector lane)

Blender road builder (`blender/city/roads/`). No Godot needed: your check is an offline Python script (2 seconds) after a Blender build (about 4 minutes).

## Goal
Where a ramp meets its parent, the lane graph has a connector lane that carries traffic from the ramp's lane to the parent's lane (or the reverse), crossing the **gore**: the paved wedge between the parent's outer edge and the ramp's edge.
A car driving that connector falls through the world because **the gore has no collision surface**. Make every point of every attach connector lane stand on a road collider.

## Evidence (measured on the current build, not guessed)
1. `python tools/city/check_surface_coverage.py game/assets/city/roads game/world/data/lanes.json --prefix attach_ --tol 0.4` on the rebuilt tiles: **all 30 attach connector lanes have uncovered samples: 302 of 650 (46 %)**.
   (The script parses the exported tiles, takes every `*surface-colonly` triangle and asks for each lane point: is there a surface triangle under it within 0.4 m of the lane height?)
2. The lead drove 19 attach joints with an autopilot in the real game: 4 of the first 6 runs **fell off the deck at the joint** (the car ends 10 to 40 m below the path, health 0 to 50). Example: from the Nanpu bridge onto the Pudong loop the car fell 40 m.
3. Cause in the code: `blender/city/roads/attaches.py`, function `build_gore`, builds the gore as render geometry:
   `tileset.builder_at(mid).add(ASPHALT, bm)`. The collision of a road is a different object: `collision.py` adds its asphalt strip with `builder.add_named(SURFACE_NAME, bm, surface="asphalt")`
   (`SURFACE_NAME = "surface-colonly"`, placed `SURFACE_DROP = 0.015` m under the visible asphalt). The gore never gets one, and neither (check it) does the acceleration-lane widening (`build_acceleration`) or the taper.

## What to build
- A **collision surface under the gore** (and anything else the connector lanes cross at the joint): the same quads as the visible gore (or a slightly larger set), added to the tile builder with `add_named(collision.SURFACE_NAME, ...)`, dropped `SURFACE_DROP` under the visible surface, in the tile the quad lies in (`tileset.builder_at(mid)`), as `build_gore` already does for the render quads.
- The gore must meet the decks it joins **without steps**: the surface heights at the parent edge and at the ramp edge must match the decks there (the quads use the parent's and the ramp's frames, check that the heights come out equal to the lane heights within 0.4 m; the checker measures it).
- Look at what else the connector crosses: the gore starts 45 m (`GORE_LENGTH`) before the attach, the connector lane is 40 to 60 m long and the parent lane's cut can be about 40 m away from the ramp's end. If the connector leaves the gore, the part outside also needs ground: look at `build_acceleration` and the parent deck's widening, and the 12 quads of `_gore_stations`.
- Do **not** add a collider where no lane drives over: keep the colliders thin (one-sided surface quads, like `collision.build_surface`), and do not touch the parapet/concrete colliders in this job.

## Files you own
`blender/city/roads/attaches.py`, `blender/city/roads/collision.py`. Everything else, including `lanes.py`, `lane_links.py` and `tools/`, is read-only.

## Where the build writes (do not write into the repo)
Always build into the scratch directory, so your diff contains only your two source files:

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/roads-joint-surface/tiles --data F:/dev/skyrush-out/tmp/roads-joint-surface/data

It takes about 4 minutes and prints `DONE in`. Then the checks read the tiles from `F:/dev/skyrush-out/tmp/roads-joint-surface/tiles` and the lanes from `F:/dev/skyrush-out/tmp/roads-joint-surface/data/lanes.json`.
If you only change the colliders, the lanes do not change; `--only tx,tz` builds one tile (faster, for trying), but the acceptance runs the full build.

## Plan
1. Run the baseline build and the checks (commands below) to see the numbers on your own checkout. Read `attaches.py` (`build_gore`, `build_acceleration`) and `collision.py`.
2. Write your plan into `status/improve/roads-joint-surface.md`.
3. Implement the gore collision. Build (about 4 minutes), run the checks. Look at which connector samples are still uncovered (add `--csv F:/dev/skyrush-out/tmp/roads-joint-surface/uncovered.csv` to dump them: road,x,y,z) and cover them.
4. Run the lane checks. Update the status file with the numbers before and after.

## Acceptance (the runner executes these itself, in order)
1. The full build above (prints `DONE in`).
2. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-joint-surface/tiles F:/dev/skyrush-out/tmp/roads-joint-surface/data/lanes.json --prefix attach_ --tol 0.4 --max-bad 0 --max-area 2402500` prints `SURFACE_COVERAGE bad samples: 0`.
3. The same checker on all lanes with `--tol 0.4 --max-bad 26519 --max-area 2402500` (today 26 519, almost all junction connectors that other ground slabs cover in the real game): the total must not go UP (the run exits 0 only when it is at most 26 519).
4. `python tools/city/check_lane_links.py F:/dev/skyrush-out/tmp/roads-joint-surface/data/lanes.json data/city/city.json --quiet` prints `LANE_LINKS OK` and `python tools/city/check_attach_geometry.py F:/dev/skyrush-out/tmp/roads-joint-surface/data/lanes.json data/city/city.json --quiet` prints `ATTACH_GEOMETRY OK` (you must not change the lane graph).
5. `python tools/city/check_lanes_regression.py F:/dev/skyrush-out/tmp/roads-joint-surface/data/lanes.json F:/dev/skyrush-out/baselines/lanes_head.json data/city/city.json` prints `LANES_REGRESSION OK`.

## Pitfalls
- The checker also limits the TOTAL area of all surface colliders: today 2 377 453 m2 (XZ projection), the limit is 2 402 500 m2, so you may add about 25 000 m2 for all 30 connectors together (a gore wedge is about 300 m2). A bigger slab fails the acceptance.
- Making the collision surface huge (a slab under the whole interchange): it would let cars drive where there is no road. Cover the connector lanes' corridor, not the sky.
- Raising the tolerance of the check or editing `tools/`.
- Heights: a gore quad built from the wrong frame is 1 to 2 m off the deck; then the lane is "covered" at 0.4 m only if you get the height right. Check the numbers per attach.
- A tile border in the middle of a gore: every quad goes into the tile it lies on (use `tileset.builder_at(mid)`), do not build the whole gore in one tile.

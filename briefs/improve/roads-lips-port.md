# Job: port the "no roof over the ramp lane" fix of the branch job/roads-lips onto the current road builder

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (5 to 60 seconds) after a Blender build (about 5 minutes).

## Why this job exists
Two earlier jobs worked on `blender/city/roads/attaches.py` at the same time:
- `roads-blockers` (MERGED into the current branch): cut the barrier colliders where the traffic crosses, moved the acceleration lane code into `deck.py` (`deck.build_acceleration`, `deck.build_chevrons`, `deck.build_cushion`, `deck.build_cable_anchors`) and the paving helpers into `collision.py` (`collision.pave(builder, pa, ra, rb, pb)`, `collision.quad`, `collision.build_connectors`, `collision.lane_index`, ...). `attaches.py` keeps the gore, the gaps and the lane-driven rules (`build_gore`, `parapet_gaps`, `_gore_rows`, ...).
- `roads-lips` (NOT merged: it conflicts): fixed the "roof" defect described below, in the OLD `attaches.py` that no longer exists in that form. Its branch is still in the repository: `git diff 4a7ad06..job/roads-lips -- blender/city/roads/attaches.py` shows exactly what it changed against the old file (`git show job/roads-lips:blender/city/roads/attaches.py` is its whole version; its status file is `git show job/roads-lips:status/improve/roads-lips.md`).
Your job: **make the roof fix work on the current code**, and keep everything the blockers job achieved.

## The defect the roads-lips branch fixes (read `briefs/improve/roads-lips.md` for the full story)
The acceleration strip of the parent deck (6 m wide, 150 m long before the attach) and the gore carry a collision surface (`surface-colonly` quads, one sided, dropped 1.5 cm under the visible asphalt). Where such a quad lies over the RAMP's own lane corridor, at the parent's height, it is a solid 0.3 to 0.9 m ABOVE the ramp's lane: the ramp's cars drive into a step or under a roof (the lead's autopilot cars got stuck or launched). The branch fix: a quad gets no collider when it lies over the ramp's corridor (`_over_corridor`) or over any lane as a ledge (`_roofs_lane`), and `_roof_cut` narrows the carriageway collider of the parent and of the ramp where one deck roofs the other's lane.

## What to do
1. Read the branch diff and the current files. Put your plan into `status/improve/roads-lips-port.md`.
2. Port `_lanes`, `_roofs_lane`, `_over_corridor`, `_roof_cut` and their constants (`CORRIDOR_MARGIN`, `LANE_CLEAR`, `CAR_HALF`, `ROOF_MIN`, `ROOF_MAX`) so that they work with the current structure. `deck.py` imports `collision`, and `attaches.py` imports `deck` and `collision`: put the shared helpers into `collision.py` (one place, no circular import). `collision.pave` gets the optional argument `collide: bool = True` (the visible asphalt is always built, the collider only when `collide` is true). `deck.build_acceleration` passes `collide=not (_over_corridor(...) or _roofs_lane(...))`, `attaches.build_gore` passes `collide=not _over_corridor(...)` and calls `_roof_cut` as the branch does.
3. Keep the docstrings and comments of the current files. (The branch deleted most of them to save lines; the code you write follows the density of the surrounding code.)
4. Build, run the checks, fix, repeat.

## Files you own
`blender/city/roads/attaches.py`, `blender/city/roads/deck.py`, `blender/city/roads/collision.py`, `blender/city/roads/build_roads.py`. Everything else is read-only.

## Acceptance (the runner executes these itself, in order)
Scratch directory: `F:/dev/skyrush-out/tmp/roads-lips-port`.
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/roads-lips-port/tiles --data F:/dev/skyrush-out/tmp/roads-lips-port/data` prints `DONE in` (about 5 minutes).
2. Steps (the steps of roads-lips): `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lips-port/tiles F:/dev/_scratch/attach_paths_v2 --lip 0.25 --max-lips 12 --max-bad 0 --min-barrier-area 290000` prints `PATH_BLOCKERS OK` (at most 12 surface-step positions AND no barrier hit in the 19 ramp paths).
3. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lips-port/tiles F:/dev/_scratch/chain_paths_v2 --lip 0.25 --max-lips 0 --max-bad 0 --min-barrier-area 290000` prints `PATH_BLOCKERS OK`.
4. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lips-port/tiles --lanes F:/dev/skyrush-out/tmp/roads-lips-port/data/lanes.json --max-bad 40 --min-barrier-area 290000` prints `PATH_BLOCKERS OK` (the blockers job reached 8).
5. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-lips-port/tiles F:/dev/skyrush-out/tmp/roads-lips-port/data/lanes.json --prefix attach_ --tol 0.4 --max-bad 0 --max-area 2445000` prints `SURFACE_COVERAGE bad samples: 0`.
6. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-lips-port/tiles F:/dev/skyrush-out/tmp/roads-lips-port/data/lanes.json --prefix chain_ --tol 0.4 --max-bad 40 --max-area 2445000` exits 0.
7. `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-lips-port/data/lanes.json --quiet` prints `CHAIN_LINKS OK`.

## Pitfalls
- Re-introducing the invisible walls: step 2 also demands zero barrier hits, because the roof fix moves colliders around the same places.
- A circular import (`deck` <-> `attaches`): the helpers belong in `collision.py`.
- Dropping the collider of the whole strip (the coverage check 5 and the diff are read).
- Editing a checker.

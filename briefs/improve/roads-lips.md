# Job: the acceleration strip must not roof the ramp (surface steps on the ramp approaches)

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (5 to 60 seconds) after a Blender build (about 4 minutes).

## Goal
When a ramp joins a main road, the main road's deck widens over the last 150 m before the attach (`attaches.build_acceleration`, the "acceleration lane", 1:25, up to 6 m wide) and the ramp runs along it. The previous job gave that strip a **collision surface** (`attaches._pave` adds a `surface-colonly` quad under every visible quad) so that a car does not fall through it. But the strip follows the HEIGHT OF THE PARENT while the ramp lane beside it has its own height, and where they overlap in plan the strip's collider lies 0.3 to 0.9 m **above the ramp's lane**: the ramp's cars drive UNDER a solid roof, or into a step. In the real game the autopilot car gets stuck or launched there.
Make the ramp approaches smooth: no surface collider may stand 0.25 m or more above a ramp's lane (up to 0.9 m) within the car's footprint.

## Evidence (measured on the committed build)
1. The real car (the lead's path-following autopilot, 19 ramp joints): **9 of 18 runs failed** so far, among them `ramp_l4_nb_wb.attach_end` (stuck at speed 0, nothing but surface colliders around) and `ramp_l3_wb_sb.attach_end` (health 52, speed jump of 21 km/h, fell off the deck at the joint).
2. `python tools/city/check_path_blockers.py game/assets/city/roads F:/dev/_scratch/attach_paths_v2 --lip 0.25` prints for those paths `LIPS 59, first 0.27 m above the path at 56 m` and `LIPS 21, first 0.90 m above the path`; 201 lip positions in all 19 paths. (A lip = the highest UP-FACING surface-collider triangle under the car's footprint is 0.25 to 0.9 m above the lane; a deck 1 m or more overhead does not count, a car passes under it.) The chain paths (`F:/dev/_scratch/chain_paths_v2`) have 0 lips.
3. Example, `ramp_l4_nb_wb.attach_end`, the surface colliders found at the centre of the lane: at 60 m `[9.55]` (the lane is at 9.57: fine); at 66 m `[9.39, 9.88]`; at 72 m `[9.25, 9.81]`; at 96 m `[8.85, 9.40]`: a SECOND surface 0.5 to 0.6 m above the lane, over the ramp's centre line, from 66 m on. That is the acceleration strip of `yanan_elevated` (parent) at the parent's height lying over the ramp's lane.

## Root cause (verify by reading `attaches.py` and the numbers above)
`build_acceleration` builds the strip as the parent's edge widened by up to 6 m, with the parent's heights (`parent.path[i].z`), and `_pave` adds the collider quad for every visible quad. The ramp's lane runs along the same stretch (it is the reason for the strip), a few metres from the parent's edge, at the ramp's own height, which differs by up to 1.2 m from the parent's height until the attach. Where the strip is wider than the distance between the parent's edge and the ramp's lane, the two decks overlap in plan with a vertical offset: the render shows it as z-fighting steps, the colliders as a roof and a step.

## What to build
In `blender/city/roads/attaches.py` (the only file you own): the collision surface of the acceleration strip must not overlap the ramp's own deck. Concretely, for every quad of the strip (the loop at the end of `build_acceleration`):
- keep the visible asphalt quad as it is;
- add the collider quad only where the quad does not lie over the ramp's corridor: the distance in plan from the quad's centre to the ramp's centre line (`ramp.path`, use `road.nearest(point)` on the RAMP road, i.e. the `road` argument of `build_acceleration`) is at least `ramp half width + 0.5 m` (`lay["asphalt_half"]` is the ramp's half width); a quad that is partly over the corridor is dropped whole;
- the connector lanes of the attach keep their ribbon collider (`build_connectors`), the gore keeps its collider: do not touch them. After your change `check_surface_coverage.py ... --prefix attach_` must still say 0 bad samples (the connector corridor stays covered by the gore and the ribbons).
Also check the gore quads (`build_gore`/`_pave`) with the same lip check: the gore is built from the parent's edge and the ramp's edge, so it should follow both decks; if the numbers show lips from the gore, fix them too (blend the heights of the wedge from the parent's edge height to the ramp's edge height).
If after that lips remain, look at the csv (`--csv`) and the coordinates and fix the cause; every lip position that you leave gets a line in your status file (path, position, why).

## Files you own
`blender/city/roads/attaches.py`. Everything else is read-only. A change elsewhere goes under `## Requests`.

## Plan
1. Run the baseline build and the checks (commands below) and put the numbers into `status/improve/roads-lips.md`.
2. Implement the strip change; build; run the checks.
3. Look at the paths that still have lips (the checker prints the first position); fix; repeat.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/roads-lips/tiles --data F:/dev/skyrush-out/tmp/roads-lips/data` prints `DONE in`.
2. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lips/tiles F:/dev/_scratch/attach_paths_v2 --lip 0.25 --max-lips 12 --max-bad 100000` prints `PATH_BLOCKERS OK` (the barriers are another job; only the lips are judged here: at most 12 lip positions in all 19 paths).
3. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-lips/tiles F:/dev/_scratch/chain_paths_v2 --lip 0.25 --max-lips 0 --max-bad 100000` prints `PATH_BLOCKERS OK`.
4. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-lips/tiles F:/dev/skyrush-out/tmp/roads-lips/data/lanes.json --prefix attach_ --tol 0.4 --max-bad 0 --max-area 2445000` prints `SURFACE_COVERAGE bad samples: 0`.
5. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-lips/tiles F:/dev/skyrush-out/tmp/roads-lips/data/lanes.json --prefix chain_ --tol 0.4 --max-bad 40 --max-area 2445000` exits 0 (the chain connectors: today 35 bad samples, they may not get worse).
6. `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-lips/data/lanes.json --quiet` prints `CHAIN_LINKS OK`.

## Pitfalls
- Deleting the strip's collider altogether (the parent's own traffic can drift onto it; the checks above keep the connector covered, and the lead reads the diff).
- Lowering or raising the strip or the ramp to hide the difference: the heights belong to the lanes; do not change a deck height in this job.
- Dropping quads by a rule that is too wide (the whole strip): the collider area (check 4) and the diff are read.

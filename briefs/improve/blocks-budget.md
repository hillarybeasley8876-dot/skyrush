# Job: bring the building tiles under their triangle budgets (23 of 63 tiles are over)

Blender building builder (`blender/city/buildings/`). No Godot needed: your checker is an offline Python script (1 second) after a Blender build of a few tiles (about 20 seconds per tile).

## Goal
`game/assets/city/blocks/tests/test_blocks.gd` demands per 512 m tile: the NEAR mesh at most **600 000 triangles**, the FAR LOD at most **40 000 triangles**. On the current map, built from the current `data/city/city.json`, **23 of 63 tiles break a budget**: 3 near tiles (up to 742 000) and 21 far tiles (up to 89 000; 17 of them were over budget on the committed assets before the map changed as well). Fix the generators so that every tile fits, **without gutting the city** (the skyline of the far LOD is what you see from the sky lanes and from the 300 m camera).

## Evidence (measured on a trial build of the current city.json into `F:/dev/skyrush-out/tmp/buildings_trial`, reference numbers in `F:/dev/skyrush-out/baselines/blocks_trial.json`)
- Near tiles over 600 000: `blocks_-1_-2` 742 176, `blocks_-1_-1` 617 148, `blocks_-2_1` 601 906 (`stats.tris` in the sidecar `blocks_<tx>_<tz>.json`).
- Far LOD over 40 000 (counted from the index accessors of `blocks_<tx>_<tz>_far.gltf`): `-4,-2` 89 326 (216 buildings: 410 triangles per building), `-4,-1` 77 874, `1,-2` 77 790, `2,-1` 77 376, `2,-2` 70 956, `-4,0` 66 710, `-2,1` 59 896 ... 21 tiles in all; the far total is 2.09 million triangles for 19 223 buildings.
- The far mass of one building (`blender/city/buildings/far.py`, `add_far_from_record`) is a podium box, a shaft box and, above 40 m, a setback box, each extruded from the lot outline (so a lot outline with 20 vertices gives 20 walls per box), plus a crown strip, optionally LED edge lines (`_edge_lines`), a mechanical floor band (`_mechanical_floor`), a mast (`_mast`), a beacon and a rooftop billboard. Most of the triangles come from the outline vertex count times the number of boxes and strips.

## What to build
1. **Far LOD** (`blender/city/buildings/far.py`, and `far_objects` in `build_city.py` if you need to change how the buckets are filled): reduce the triangles per building with a detail rule that keeps the silhouette: the outline is simplified for the far mass (Douglas-Peucker with a tolerance of about 1.5 m, never below 4 points), tiny details are dropped first (the edge lines, the rooftop billboard, the mast of buildings under 90 m), the podium merges into the shaft for buildings under 25 m; the tower (above 40 m) keeps its setback and its crown. Then make it **budget-aware per tile**: if a tile is still over 40 000 triangles, raise the detail drop level for that tile (drop the setback box of buildings under 80 m, then merge podium+shaft, then simplify the outline harder) until it fits; never drop below one box per building and never drop a building.
2. **Near tiles** (`build_city.py`, `cells.py`, `kit.py`, the style modules as needed): for a tile over 600 000 triangles, reduce the optional detail of the least important buildings until it fits (the optional detail is whatever your reading of the style code says is decoration: signs, AC units, balcony rails, window frames, ornament; the farthest-from-the-road and the smallest buildings first), or lower the segment counts of curved parts. Tiles that are already under budget must come out BYTE-IDENTICAL in their triangle counts (do not change their look).
3. Keep everything deterministic (same city.json gives the same tiles).

## Files you own
`blender/city/buildings/` (all of it). Everything else is read-only.

## Plan
1. Build 3 tiles that are over budget and look at the numbers (`python tools/gd.py blender run blender/city/buildings/build_city.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/blocks-budget/blocks --only "-4,-2;-1,-2;2,-1"`; the log prints per tile the number of buildings and triangles and, for big tiles, a material breakdown). Write the plan into `status/improve/blocks-budget.md`.
2. Implement the far rule, rebuild those tiles, run `check_blocks_budget.py` for them. Then the near rule.
3. Build the full list of over-budget tiles (the acceptance command) and fix what is still over.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py blender run blender/city/buildings/build_city.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/blocks-budget/blocks --only "-1,-1;-1,-2;-1,0;-1,1;-1,2;-2,-1;-2,0;-2,1;-2,2;-3,-1;-3,2;-4,-1;-4,-2;-4,0;0,1;0,2;1,-1;1,-2;2,-1;2,-2;2,-3;2,0;3,-2;0,0;-3,0;3,1;1,1"` prints `TOTAL tris` (about 15 minutes; the last four tiles are under budget today and must stay as they are).
2. `python tools/city/check_blocks_budget.py F:/dev/skyrush-out/tmp/blocks-budget/blocks --ref F:/dev/skyrush-out/baselines/blocks_trial.json --only "-1,-1;-1,-2;-1,0;-1,1;-1,2;-2,-1;-2,0;-2,1;-2,2;-3,-1;-3,2;-4,-1;-4,-2;-4,0;0,1;0,2;1,-1;1,-2;2,-1;2,-2;2,-3;2,0;3,-2;0,0;-3,0;3,1;1,1"` prints `BLOCKS_BUDGET OK`: every tile under 600 000 near and 40 000 far triangles, and not gutted (at least 95 % of the buildings, 60 % of the near triangles, 25 % of the far triangles of the reference).
3. `python tools/city/check_blocks_untouched.py F:/dev/skyrush-out/tmp/blocks-budget/blocks --ref F:/dev/skyrush-out/baselines/blocks_trial.json --tiles "0,0;-3,0;3,1;1,1"` prints `BLOCKS_UNTOUCHED OK` (the four tiles that were under budget have exactly their reference near triangles and buildings).

## Pitfalls
- Dropping buildings or whole blocks; flattening every tower to a box (the check keeps 25 % of the far triangles, the lead looks at screenshots).
- A rule that depends on the tile name or on the order of the tiles.
- Changing the look of tiles that are under budget.
- Slowing the build down by more than 30 %.

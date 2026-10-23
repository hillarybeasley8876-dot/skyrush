# Job: no lot piece the building planner cannot build (the clipper leaves slivers)

Map job: read `briefs/improve/_map-common.md` first (how the map is generated, how it is judged, the inner loop).

## The defect (the lead measured it; reproduce it first)
`game/assets/city/blocks/tests/test_blocks.gd` ("every lot of the map carries a building and is built at least 30 %") fails for 12 lots of the real map, and its offline twin
`python tools/city/check_blocks_built.py game/assets/city/blocks` (read the sidecars of the building tiles) prints the same 12:
`b_d0_029_s12, _s31, _s54` (tile -1,0) and `b_d7_042_s8, _s12, _s15, _s20, _s23, _s25, _s27, _s29, _s31` (tile 1,-1). All 12 are PIECES (`_sN`) of a big lot that the clipper
`city_blocks.clear_of_roads` (job city-lots-clear) cut away from the road corridors. They are slivers: 81 to 340 m2 but only 3 to 8 m wide. The building planner (blender/city/buildings,
setback 10 m, minimum frontage 6 m) cannot put a building into a strip that narrow: some pieces get none, some get an oversized building (coverage 2 to 3 times the lot).
The lead's numbers over all 112 pieces of the map (2A/P = twice the area over the perimeter, about half the width of a strip):
 2A/P under 2 m: 12 pieces, 4 without a building;   2 to 4 m: 41 pieces, 5 without;   4 to 6 m: 36 pieces, 2 without;   6 m and more: 23 pieces, none without a building.
`MIN_PIECE_AREA = 80.0` in `tools/city/city_blocks.py` is the only size rule of the clipper and it looks at the area only.

## What to do
1. Reproduce: `python tools/city/check_blocks_built.py game/assets/city/blocks` is NOT in your sparse checkout (no game/); use the numbers above and build the two tiles yourself in step 3.
2. Teach the clipper a shape rule: a piece is kept only when a building can stand on it. Start with `2A/P >= MIN_PIECE_WIDTH` (the lead suggests 6.0 m, but find the value with the real builder:
   the smallest value for which the two tiles below have no empty or under-built lot; do not use a value that drops compact lots: the share of the lot AREA that is kept must stay
   above 99 %, step 5). Put the rule into `city_blocks.py` next to `MIN_PIECE_AREA` (a named constant with a comment), 15 lines at most.
3. Write `tools/city/selftest_slivers.py` FIRST (see below), see it fail, then implement.
4. Regenerate the map into your scratch folder, build the two tiles with the real builder, run the check:
   `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-slivers/city.json`
   `python tools/gd.py blender run blender/city/buildings/build_city.py -- --city F:/dev/skyrush-out/tmp/city-slivers/city.json --out F:/dev/skyrush-out/tmp/city-slivers/blocks --only "-1,0;1,-1"` (about 1 to 2 minutes)
   `python tools/city/check_blocks_built.py F:/dev/skyrush-out/tmp/city-slivers/blocks --tiles "-1,0;1,-1" --city F:/dev/skyrush-out/tmp/city-slivers/city.json` must print `BLOCKS_BUILT OK`.
   (If the builder does not accept `--only`/`--out` as written, read its `parse_args`; the brief of the lead is a description, the code is the truth.)

## selftest_slivers.py (you write it; the lead runs it on the old and the new code)
Build synthetic pieces and call the function you wrote (import `city_blocks`): an 8 m x 55 m strip is dropped; a 7 m x 20 m strip is dropped; a 30 m x 40 m rectangle is kept; an L-shaped piece
with a 20 m wide arm is kept; a 12 m x 12 m square is kept or dropped as your rule says (document which). And the real map: after `clear_of_roads` no piece of the real city has `2A/P` under your constant.
It prints `selftest_slivers: 0 case(s) wrong` and exits 0, and it must FAIL on the code before your change.

## Files you own
`tools/city/city_blocks.py`, `tools/city/selftest_slivers.py`. Everything else is read-only (the checkers are the lead's: never edit them).

## Acceptance (the runner executes these itself, in order; scratch folder `F:/dev/skyrush-out/tmp/city-slivers`)
1. `python tools/city/selftest_slivers.py` prints `selftest_slivers: 0 case(s) wrong`.
2. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-slivers/city.json` (about 30 s).
3. the two tiles built with the real builder (command above), prints `DONE`.
4. `python tools/city/check_blocks_built.py F:/dev/skyrush-out/tmp/city-slivers/blocks --tiles "-1,0;1,-1" --city F:/dev/skyrush-out/tmp/city-slivers/city.json` prints `BLOCKS_BUILT OK`.
5. `python tools/city/check_lots_kept.py F:/dev/skyrush-out/tmp/city-slivers/city.json F:/dev/skyrush-out/baselines/lots_cur.json --keep 0.0 --total 0.99` prints `LOTS_KEPT OK`.
6. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-slivers/city.json --baseline tools/city/rules_baseline.json` prints `ACCEPT_RULES OK`.
7. `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-slivers/city.json && python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-slivers/city.json` print `ROUTES_SHAPE OK`, `NETWORK_SIZE OK`.

## Pitfalls
- A threshold so high that compact lots disappear: step 5 (area kept over 99 %) and the lead's diff read.
- Fixing only the two tiles you build: the rule is geometric and must hold for every piece of the map (the selftest's last case).
- Touching the building planner (blender/): it is not yours; the generator is.
- Editing a checker, a rule or a baseline.

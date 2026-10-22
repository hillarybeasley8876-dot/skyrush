# Job: a cop under a deck must not bust the player above, and a hiding spot under a deck must not hide a player on the deck (police layers)

Godot GDScript, units `game/ai/police/` and `game/ui/hud/hud_pursuit.gd`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first.

## Goal
Two police rules measure with a 3D radius and never compare levels. On the real map the streets run under the elevated roads, so:
1. **Busted through the deck.** `PolicePursuit.update_busted` counts every unit within `BUST_RANGE := 12.0` m (3D) of the player; the HUD does the same with `BUSTED_RANGE := 12.0` in `game/ui/hud/hud_pursuit.gd`. A cop that drives on the street 10 m below the deck makes the busted meter of a slow player on the deck fill (and the HUD shows the "busted" warning), although the cop cannot touch the player.
2. **Hiding under a deck from the deck.** `PolicePursuit._update_hiding_spot` sets `in_hiding_spot` when the player is within `HIDE_RADIUS` (3D distance) of a hiding spot. The spots are at street level UNDER decks (a spot at y = 0 under the inner ring at y = 10; the dragon pillar spot under a deck at y = 9): a player who drives on the deck above such a spot is 10 m away in height and gets the double evade rate ("hiding under a deck, in a tunnel or in a parking garage").

## Evidence (read the code)
- `game/ai/police/police_pursuit.gd`: `_update_hiding_spot(player)` (around line 158) and `update_busted(delta, player, units)` (around line 165): `unit.global_position.distance_to(player.global_position) > BUST_RANGE`.
- `game/ui/hud/hud_pursuit.gd` (around lines 44 to 50): the same 12 m test for the "busted" warning.

## What to build
One rule for the folder: two things are on the same level when their heights differ by at most `LEVEL := 4.0` m. Put the constant in `police_pursuit.gd` (the HUD file may read it as `PolicePursuit.LEVEL` or have its own const with a comment).
1. `update_busted`: a unit only counts when it is within `BUST_RANGE` (keep the 3D distance as it is) AND within `LEVEL` of the player in height.
2. `_update_hiding_spot`: a spot only hides the player when the player is within `HIDE_RADIUS` AND within `LEVEL` of the spot's height.
3. `hud_pursuit.gd`: the same level test for the busted warning.
Nothing else changes: no tuning, no new allocation in the per-tick loops.

## Files you own
`game/ai/police/` and `game/ui/hud/hud_pursuit.gd`. Existing tests are read-only. You add ONE new test file `game/ai/police/tests/test_layers.gd`.

## The test you write FIRST (`game/ai/police/tests/test_layers.gd`)
Look at `game/ai/police/tests/police_test.gd` (the helper `T`), `test_busted.gd` and `test_bust_crowd.gd` for how a pursuit, a player and police units are built. Checks (print `PASS ...` / `FAIL ...`, end with `POLICE LAYER TESTS OK (0 failures)` and quit 0, or `POLICE LAYER TESTS FAILED` and quit 1):
1. **Hiding, same level (control)**: `PolicePursuit.new()` with `hiding_spots = [Vector3(200, 0, 1660)]` and a player (stub car, `core/stubs/stub_car.tscn`, `gravity_scale = 0.0`) at (200, 0.6, 1665): `_update_hiding_spot(player)` -> `in_hiding_spot` is true.
2. **Hiding, player on the deck**: the player at (200, 10.6, 1663) (3 m away in plan, 10.6 m up): `in_hiding_spot` is false.
3. **Busted, same level (control)**: a pursuit in the chase state, the player standing still (speed 0) and a police unit 5 m away at the same height: after `update_busted` has been called for 2 seconds (physics-step sized `delta`), `busted > 0`.
4. **Busted, cop under the deck**: the same with the unit 5 m away in plan but 10 m lower: `busted` stays 0 after 2 seconds.
5. **HUD**: if `hud_pursuit.gd` has a function that decides the "busted" warning from the units around (read it), check it the same way: same level warns, 10 m lower does not. If it cannot be called without a whole HUD, build the HUD like `game/ui/hud/tests/test_hud.gd` does; if that is too heavy, skip this check and write it in your status file under `## Not done`.
Run it BEFORE you change anything: 2 and 4 (and 5) must fail; 1 and 3 must pass. If a control fails the test is wrong, not the code.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/police/` and `python tools/gd.py check --only=res://ui/hud/` print `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/police/tests/test_layers.gd` prints `POLICE LAYER TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/police/tests/test_layers.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-layers/tests --allow-fail test_perf` ends with `RUN_TESTS_RATCHET OK` (`test_perf` checks millisecond budgets that a busy machine fails; every other police test must pass), and `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-layers/tests_hud --allow-fail test_hud_perf` ends with `RUN_TESTS_RATCHET OK`.

## Pitfalls
- A level test that also switches the feature off for airborne or flying players (the existing rule "never busted while airborne" stays as it is).
- Comparing the height of the unit with the height of the player's lane instead of the player's position.
- Changing `BUST_RANGE`, `HIDE_RADIUS` or the fill rates.

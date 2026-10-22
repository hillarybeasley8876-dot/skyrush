# Job: rivals must not avoid, follow or slipstream cars that are on another level (rival layers)

Godot GDScript, unit `game/ai/rivals/`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first.

## Goal
The rival racers look at "the cars near me" with a 3D radius and measure ahead / beside in the flat frame of their racing line, and never compare heights. On the real map a race line runs on the Yan'an elevated road while the Yan'an street runs under it (x/z equal, 10 m apart in height). So a rival on the deck:
- brakes or weaves for a car on the street under it ("car ahead in my lane");
- treats the player driving on the street below as a blocker, or as a car to slipstream.
Fix this: a rival only reacts to cars on its own level.

## Evidence (read the code first)
- `game/ai/rivals/rival_avoid.gd`:
  - `update_blocker(...)` loops over `ctx.near_of(car)` and the player and calls `_consider(node, ...)`; `_consider` uses `_relation(...)` (x = ahead, y = to the side) and never tests the height. A car 10 m below, 50 m ahead in the same column becomes `block_node` and the rival brakes.
  - `_avoid_offset(...)` has the same loop (`rel := node.global_position - car.global_position`, tests `rel.length_squared()`, `ahead`, `side`): a street car beside the line under the deck makes the rival swerve.
- `game/ai/rivals/rival_speed.gd`: `_slipstream(car, ctx, offset)` loops `ctx.rivals` and `ctx.player` and `_in_wake(node, pos, tangent, right)` tests only `ahead` and `rel.dot(right)`: a car on another level gives the rival the 4 % slipstream bonus.
- `game/ai/rivals/rival_director.gd` collects the near lists by 3D radius (leave it as it is: the filter belongs in the three consumers).

## What to build
One tiny shared rule in ONE place of your folder (for instance a `static func on_my_level(a: Node3D, b: Node3D) -> bool` in `rival_context.gd`, or a const + helper in `rival_avoid.gd` that `rival_speed.gd` also uses): two cars are on the same level when `absf(a.global_position.y - b.global_position.y) <= LEVEL` with `const LEVEL := 4.0`. A flying car (`VehicleBase.is_airborne()`) is not a special case here.
Use it in the three places above: `_consider`, the loop of `_avoid_offset`, `_in_wake`. Nothing else changes (no tuning, no new allocation in the per-tick loops).

## Files you own
`game/ai/rivals/`. Existing tests are read-only. You add ONE new test file `game/ai/rivals/tests/test_layers.gd`.

## The test you write FIRST (`game/ai/rivals/tests/test_layers.gd`)
There is no existing unit test of `RivalAvoid`/`RivalSpeed`: read `rival_avoid.gd`, `rival_speed.gd`, `rival_context.gd`, `rival_line.gd` and `tests/test_rival_driving.gd` to see how a car, a line and a context are built (`RivalLine` from a few points along +X; `RivalContext` fields `near`, `player`, `rivals`; a rival `ArcadeCar` or `RivalCar` placed on the line; other cars are `res://core/stubs/stub_car.tscn` with `gravity_scale = 0.0` and a fixed position). No physics world is needed if you only call the functions.
Checks (`PASS ...` / `FAIL ...`; end with `RIVAL LAYER TESTS OK (0 failures)` and quit 0, or `RIVAL LAYER TESTS FAILED` and quit 1):
1. **Blocker, same level (control)**: the rival at y = 10.2 on a line along +X, a stub car at the same height 50 m ahead in the same column, in `ctx.near[rival_instance_id]`; `update_blocker(car, ctx, 0.0, line, 0.0, 30.0, 0.1)` -> `block_node == stub` and `block_distance` about 50 (within 3 m).
2. **Blocker, car on the street below**: the same with the stub at y = 0.6 (9.6 m lower): `block_node == null` and `is_inf(block_distance)`.
3. **Player below is not a blocker**: `ctx.player` = the stub at y = 0.6, 50 m ahead: `block_node == null`; and at y = 10.6 it is the blocker.
4. **Avoidance, same level**: a stub 2 m to the right and 12 m ahead at the rival's height: `_avoid_offset(car, ctx, 0.0, line, 0.0)` is not 0.0 (it moves away); on the street below (y = 0.6) it is exactly 0.0.
5. **Slipstream**: `RivalSpeed`'s `_in_wake(node, pos, tangent, right)` is true for a car 15 m ahead in the same column at the same height and false at 10 m lower.
Run it BEFORE you change the code: 2, 3 (below half), 4 (below half) and 5 (below half) must fail; 1 and the same-level halves must pass. If a same-level check fails, the test is wrong, not the code.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/rivals/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/rivals/tests/test_layers.gd` prints `RIVAL LAYER TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/rivals/tests/test_layers.gd --files auto` prints `MUTATION_CHECK OK` (the old version of every source file you changed is put back for one run and your test must FAIL on it).
4. `python tools/run_tests.py --filter res://ai/rivals/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-rivals/tests --allow-fail test_performance,test_race_flow,test_real_route,test_rival_driving` ends with `RUN_TESTS_RATCHET OK` (those four fail for other reasons today: a millisecond budget, a missing gate texture set, rivals stuck on the real map; every other rivals test must still pass).

## Pitfalls
- Filtering by a bigger 3D radius instead of the height.
- Applying the level rule to the wrong car: it is the rival's height against the other car's height, not against the line.
- A test whose "below" cases pass only because the stub is out of range (50 m ahead is inside `FOLLOW_DISTANCE`/`AVOID_DISTANCE`, check the constants).
- Per-tick allocations.

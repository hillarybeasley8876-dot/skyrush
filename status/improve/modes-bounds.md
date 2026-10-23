# modes-bounds — a lost player is put back on the road

## Plan

1. READ first: `SPEC.md`, `CONTRACTS.md`, `briefs/improve/_godot-common.md`,
   `briefs/improve/modes-bounds.md`, `game/modes/mode_director.gd`, `game/modes/tests/test_modes.gd`,
   `game/world/world.gd` (`nearest_road_transform`, `is_ready`), `game/world/api/spawn_placer.gd`
   (`closest_lane`: the score is `flat + |lane.y - car.y| * 3.0`, so the height decides between the
   deck and the street), `game/core/contracts/vehicle_base.gd` (`reset_to` zeroes the velocities,
   `telemetry.flying/airborne/airtime`), `game/core/contracts/car_telemetry.gd`,
   `game/vehicle/modules/car_readout.gd` (the telemetry is written every physics tick), the
   sandbox (`game/core/sandbox/sandbox.gd`: the road loop is 596 x 196 m, the ground 2400 x 2400
   at y = 0, no water and no kill floor).
2. Write `game/modes/tests/test_out_of_bounds.gd` FIRST: sandbox + player car + mode director,
   free mode, four scenarios (lost, on the road, the timer restarts, flying/grid). The class is
   loaded with `ResourceLoader.exists` / `load` (never `preload`, never a static `OutOfBounds`
   type, never a static `ModeDirector.out_of_bounds`), so the OLD code prints FAIL lines instead
   of a script error.
   Verify: `python tools/gd.py test res://modes/tests/test_out_of_bounds.gd` → the lost player
   FAILS (it stays 404 m from the lane), the other three pass.
3. Add `game/modes/out_of_bounds.gd` (`class_name OutOfBounds`, `extends RefCounted`):
   `update(delta, player, world) -> bool`; lost = > 15 m from `nearest_road_transform`; put back
   after 3 s of continuous lost time; no counting while flying / airborne < 6 s / frozen; the scan
   runs 4 times a second at most; `reset_to` + one toast.
   Verify: `python tools/gd.py check --only=res://modes/` → `0 failed, 0 engine errors`.
4. Wire it into `ModeDirector`: a public `out_of_bounds` member, `update` called from
   `_physics_process` (a null player or world → nothing).
   Verify: `python tools/gd.py test res://modes/tests/test_out_of_bounds.gd` → `OUT OF BOUNDS TESTS OK`.
5. Acceptance: the four commands of the brief (check, test, mutation_check, run_tests) + the
   rivals folder (the rivals tests use the mode director).

## Done

- `game/modes/out_of_bounds.gd` (new, 116 lines): the class `OutOfBounds`.
  - `update(delta, player, world) -> bool` — true on the tick that puts the player back.
  - lost = the 3D distance to `world.nearest_road_transform(car position).origin` > `LOST_DISTANCE` (15 m);
    the world weighs the height of a lane, so the tunnel (y = -28) and the decks are roads.
  - put back after `LOST_SECONDS` (3 s) of being continuously lost; the timer restarts when the
    player is found again (the measurement is throttled, so the restart lags by up to 0.25 s).
  - the timer does not count while `telemetry.flying` is true, while the car is airborne for less
    than `AIRBORNE_GRACE` (6 s) or while `player.freeze` is true (the grid of a race).
  - the put back: `player.reset_to()` with the nearest lane + 0.5 m (the lane is measured once
    more, the player may have fallen a long way), the velocities are cleared by `reset_to`; one
    toast `已回到路面  BACK ON THE ROAD`.
  - the distance is measured 4 times a second (`CHECK_INTERVAL` 0.25 s), not every tick.
  - nothing happens when the player or the world is null or when the world is not built
    (`Game.world_built()` and, for the real world, `is_ready()`).
- `game/modes/mode_director.gd`: `var out_of_bounds: OutOfBounds = OutOfBounds.new()` and a
  `_physics_process` that calls `out_of_bounds.update(delta, Game.player, Game.world)` in every
  mode (free roam, race, pursuit).
- `game/modes/tests/test_out_of_bounds.gd` (new, 12 checks): the scenarios of the brief plus a
  positive control (a lost car is put back) and a check that the player is not put back at once.

## In progress / next

Nothing: the job is finished. The lead can commit.

## How to test (exact commands)

```
python tools/gd.py check --only=res://modes/
python tools/gd.py test res://modes/tests/test_out_of_bounds.gd
python tools/mutation_check.py --test res://modes/tests/test_out_of_bounds.gd --files auto
python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-bounds/tests
```

## Evidence (key output lines)

- The test on the OLD code (before the change): `FAIL the lost player is put back on a lane  = 404.00 m from the lane`,
  `FAIL one toast tells the player  = 0`, `OUT OF BOUNDS TESTS FAILED (3 failures)`.
- The test on the new code:
  `PASS the lost player is not put back at once`, `PASS the lost player is put back on a lane  = 0.65 m from the lane`,
  `PASS the player is above the lane  = 0.00 m, the lane is at 0.65 m`, `PASS one toast tells the player  = 1`,
  `PASS the player on the road does not move  = 0.01 m`, `PASS no toast for a player on the road  = 0`,
  `PASS the timer restarts when the player is found again  = 0`, `PASS the player is still lost  = 404.00 m from the lane`,
  `PASS the mode director owns the recovery`, `PASS a flying player is not put back`,
  `PASS a frozen player is not put back`, `PASS a lost player is put back`, `OUT OF BOUNDS TESTS OK`.
- `python tools/gd.py check --only=res://modes/` → `CHECK 24 files, 0 failed, 0 engine errors, 0 warnings`.
- `python tools/mutation_check.py --test res://modes/tests/test_out_of_bounds.gd --files auto` →
  `MUTATION_CHECK OK: the test fails on the old code of 068733ce82 (3 FAIL lines, first: FAIL the lost player is put back on a lane  = 404.00 m from the lane)`.
  (also run with both files reverted: `--files game/modes/mode_director.gd game/modes/out_of_bounds.gd` → the same `MUTATION_CHECK OK`).
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out ...` → `6 tests, 6 passed, 0 failed or timed out`.
- The rivals folder (`res://ai/rivals/`, it uses the mode director) fails 4 tests
  (`test_performance`, `test_race_flow`, `test_real_route`, `test_rival_driving`) — the same 4
  tests fail with the mode director reverted to the base version: a pre-existing failure of the
  rivals unit, not caused by this job.

## Known issues

- The sandbox has no water and no kill floor, so the "river" of the test is the flat ground
  400 m outside the road loop. A car under the map (y = -30) falls forever in the sandbox: it
  stays airborne, and the 6 s air grace would hide it, so the test puts the car on the ground.
- The timer restarts up to 0.25 s late (the measurement is throttled to 4 Hz). Two spells of
  2 s therefore reach 2.25 s at most, below the 3 s of the put back.
- The world of the game weighs the height of a lane by 3, so a car in the river is put back on
  the quay street and not on the deck 10 m above it (the deck lane is 3 x 11 m further in the
  score). The put back measures the lane once more, at the height the car has when it is put
  back.

## Requests

(none)

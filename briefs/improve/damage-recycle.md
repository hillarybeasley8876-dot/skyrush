# Job: a wrecked traffic or police car that comes back out of its pool must be a whole car again

Godot GDScript, units `game/damage/`, `game/ai/traffic/` and `game/ai/police/`. Read `briefs/improve/_godot-common.md` first.

## Goal
Traffic cars and police cars live in pools: a car that is wrecked sinks, fades out and is hidden, then goes back into its pool, and the next spawn takes it out again and puts it on a lane. The wreck flow leaves the car as a wreck: a car that is reused looks wrong and acts wrong:
- the meshes of the visual stay at `transparency = 1.0` (invisible) - the AI wreck fades them out and nothing brings them back;
- `is_wrecked` stays true and the health stays 0, so the car cannot be hurt, wrecked or taken down again (the damage unit ignores a wreck);
- the damage tier, the dent painter, the detached parts and the smoke of the damage unit still belong to the old wreck;
- the player collides with a solid, invisible, immortal car.
After this job a recycled car is a whole new car.

## Evidence (read the code)
- `game/damage/wreck_flow.gd` `_sink_away(id)`: sets `car.freeze = true`, `collision_layer = 0`, `collision_mask = 0`, tweens the position down and `_fade_out(visual, 0.0)` (transparency to 1.0), then `_hide(id)` (`car.visible = false`). The same file has the code that puts the transparency back for the PLAYER's respawn (`ghost.saved`, around line 225): the AI cars have no restore.
- `game/ai/traffic/traffic_car.gd` `place(lane, distance)` puts the car on a lane (`visible = true`, collision restored after it has arrived, speed, mode FAR), `set_active(false)` parks it; `traffic_pool.gd` `release(car)` / `spawn_at(...)` / `acquire(...)`. Nothing resets `is_wrecked`, `health`, the transparency or the damage state.
- `game/ai/police/police_pool.gd` `take_unit(kind)` makes a pooled unit visible again (`visible = true`, `collision_layer = 2`) and `release_unit(car)` parks it (`_park`), `game/ai/police/police_car.gd` has its own `reset`-like code (read it, around lines 165 to 200). Same gaps.
- The damage unit keeps a `CarDamage` per car in its registry (`game/damage/car_damage.gd`, `damage_director.gd` `state_of(car)`), with the tier, the dent painter, `fx`, the moved parts and so on. The respawn of the player resets it (read `respawn` / `_restore...` in `damage_director.gd` and `wreck_flow.gd`).

## What to build
1. A new signal on the event bus, already there: `Events.vehicle_recycled(vehicle: VehicleBase)` (read the comment in `game/core/events.gd`). The pools emit it when they put a car back into play: `TrafficCar.place()` (or `TrafficPool.spawn_at`/`acquire`, whichever sees every reuse exactly once) and `PolicePool.take_unit()`.
2. The damage unit listens (`damage_director.gd`) and restores the car completely, the way the player's respawn does: `is_wrecked = false`, `health = max_health`, `telemetry.health_norm = 1.0`; the transparency of every mesh of the visual back to 0 (or to the value the unit saved before the fade; the AI car has none: 0.0); the visual and the car visible; no running fade/sink tween for that car (a pending `_hide` of the OLD wreck must not hide the new car: guard it by an id/serial); the `CarDamage` state of the car fresh (tier 0, painter reset, parts back on, smoke stopped, the moved doors back); the collision layer and mask are the pool's business (leave them), `freeze` is the pool's business.
   If a restore function for the player's respawn exists, reuse its pieces rather than copying them.
3. Do not call the damage unit from the traffic or police code: the signal is the only link.

## Files you own
`game/damage/`, `game/ai/traffic/`, `game/ai/police/`. Existing tests are read-only. You add ONE new test file `game/damage/tests/test_recycle.gd`.

## The test you write FIRST (`game/damage/tests/test_recycle.gd`)
Use `game/damage/tests/damage_test_kit.gd` (`Kit.make_floor`, `Kit.make_director`, `Kit.make_car`) and look at `test_respawn.gd` and `test_pool.gd` for how a director, cars and the wreck flow are driven. For a traffic car use the pool for real: `TrafficPool` / `TrafficCar` as `game/ai/traffic/tests/test_wreck.gd` builds them (a `DriveContext` with `TrafficTestRoad.build(3)`); for a police car `PolicePool` / `PoliceCar` (see `game/ai/police/tests/test_pool.gd`). Checks (`PASS ...` / `FAIL ...`, end with `RECYCLE TESTS OK (0 failures)` and quit 0, or `RECYCLE TESTS FAILED` and quit 1):
1. **Traffic**: wreck a traffic car (`car.wreck(null)` or a lethal `apply_damage`), run until the wreck flow has hidden it (`visible == false`, about 8 s of physics frames), release it to the pool and take it out again with `spawn_at(...)`: the car is visible, `is_wrecked == false`, `health == max_health`, every `MeshInstance3D` of its visual has `transparency == 0.0`, and a later `apply_damage(10.0, ...)` lowers the health by about 10 (so it is a living car again). The wreck-flow tween of the first life must not hide it again during the next 3 s.
2. **Police**: the same with a `PoliceCar` and `take_unit`.
3. **A car that never was wrecked** is unchanged by the signal (health stays, no flicker).
4. **A car that was dented** (a tier-1 hit) is back to tier 0 with its parts on after a recycle.
Run it BEFORE you change anything: checks 1, 2 and 4 must fail for the right reason (print the values).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://damage/`, `--only=res://ai/traffic/` and `--only=res://ai/police/` each print `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://damage/tests/test_recycle.gd` prints `RECYCLE TESTS OK`.
3. `python tools/mutation_check.py --test res://damage/tests/test_recycle.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://damage/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_damage --allow-fail test_budget`, `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_traffic --allow-fail test_lanes_world` and `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_police --allow-fail test_perf` each end with `RUN_TESTS_RATCHET OK` (the allowed tests check millisecond budgets that a busy machine fails; all others must pass).

## Pitfalls
- Restoring the transparency but not `is_wrecked`/health (the car is visible and still immortal), or the reverse.
- A pending sink tween of the old wreck that hides the reused car 8 seconds later.
- Calling `car.wreck()` code paths that emit the wreck signals again during the restore.
- A restore that costs a scan of the scene tree per spawn (the traffic spawns cars all the time): only cars that were wrecked need the full restore; for the others the handler returns at once.

# damage-recycle — a recycled AI car is a whole car again

## Plan
1. READ the code: wreck_flow, damage_director, car_damage, dent_painter, traffic_pool/car,
   police_pool/car, events. DONE.
2. Write `game/damage/tests/test_recycle.gd` (traffic + police + untouched + dented).
   Verify it FAILS on the old code. DONE (12 FAIL lines).
3. `game/damage/wreck_flow.gd`: a serial per wreck life (`Sink`), the pending timer and the
   fade/sink tweens are void when the car is recycled (`cancel_sink`), `restore_visual` puts
   the transparency back to 0 and the car back on the screen. DONE.
4. `game/damage/car_recycler.gd` (new) + `damage_director.gd`: the unit listens to
   `Events.vehicle_recycled`; a car that needs it (wrecked / hurt / tier > 0) is repaired,
   made opaque and gets a fresh `CarDamage` state. The cars that were never hurt return at
   once (no scan of the scene tree per spawn). DONE.
5. `game/damage/car_damage.gd` + `car_state_manager.gd` + `dent_painter.gd` +
   `part_manager.gd`: `recycle()` — tier 0, the dents and the scrape gone, the parts back on,
   the smoke stopped, the visual back at rest. DONE.
6. `game/ai/traffic/traffic_car.gd`: `place()` emits `Events.vehicle_recycled`.
   `game/ai/police/police_pool.gd`: `take_unit()` emits it and gives the unit its collision
   mask back (the wreck flow takes it away). DONE.
7. Run the acceptance. DONE (all green).

## How to test (exact commands)
- `python tools/gd.py check --only=res://damage/`
- `python tools/gd.py check --only=res://ai/traffic/`
- `python tools/gd.py check --only=res://ai/police/`
- `python tools/gd.py test res://damage/tests/test_recycle.gd`
- `python tools/mutation_check.py --test res://damage/tests/test_recycle.gd --files auto`
- `python tools/run_tests.py --filter res://damage/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_damage --allow-fail test_budget`
- `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_traffic --allow-fail test_lanes_world`
- `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/damage-recycle/tests_police --allow-fail test_perf`

## Done
- The pools say on the bus that a car is back into play (`Events.vehicle_recycled`):
  `TrafficCar.place()` and `PolicePool.take_unit()`. No call from a pool into the damage
  unit: the signal is the only link.
- The damage unit listens and restores the car: the wreck of the old life is void (the
  pending sink timer, the fade and the hide are cancelled by the serial of the wreck), the
  car is repaired (not a wreck, full health, full telemetry), its meshes are opaque again,
  and its damage state is fresh (tier 0, no dent, no scrape, no smoke, the parts that came
  off are back on, the doors that sprang are closed, the visual is back at rest).
- A car that was never hurt costs nothing: the handler reads three fields and one
  dictionary lookup and returns.
- The police pool gives a unit its collision mask back: the wreck flow takes the mask away
  (`collision_layer = 0`, `collision_mask = 0`) and a unit that came out of the pool with
  the mask at 0 drove through everything.

## In progress / next
- nothing.

## Evidence (key output lines)
- `python tools/gd.py test res://damage/tests/test_recycle.gd` -> `RECYCLE TESTS OK (0 failures)`
  (44 PASS lines: the traffic wreck, the traffic recycled during the fade, the police wreck,
  the dented police car, the untouched car).
- The same test on the old code (before the fix):
  `FAIL the traffic car is not a wreck any more`,
  `FAIL the traffic car has its health back: got 0.000, want 40.000`,
  `FAIL the traffic car is opaque again`,
  `FAIL a hit of 10 costs the traffic car 10 HP: got 40.000, want 10.000`,
  `FAIL the old wreck did not hide the recycled car`,
  `FAIL the police car is opaque again`,
  `FAIL the recycled car is clean`, `FAIL the front bumper is back on the car`.
- `python tools/gd.py check --only=res://damage/` -> `CHECK 45 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/gd.py check --only=res://ai/traffic/` -> `CHECK 37 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/gd.py check --only=res://ai/police/` -> `CHECK 65 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/mutation_check.py --test res://damage/tests/test_recycle.gd --files auto` ->
  `MUTATION_CHECK OK: the test fails on the old code of a2f3a00e71 (13 FAIL lines, first: FAIL the traffic car is not a wreck any more)`
- `python tools/run_tests.py --filter res://damage/ ... --allow-fail test_budget` ->
  `12 tests, 12 passed, 0 failed or timed out` / `RUN_TESTS_RATCHET OK (0 failing, ...)`
- `python tools/run_tests.py --filter res://ai/traffic/ ... --allow-fail test_lanes_world` ->
  `11 tests, 10 passed, 1 failed or timed out` / `RUN_TESTS_RATCHET OK (1 failing, all of them on the allow list)`
- `python tools/run_tests.py --filter res://ai/police/ ... --allow-fail test_perf` ->
  `19 tests, 19 passed, 0 failed or timed out` / `RUN_TESTS_RATCHET OK (0 failing, ...)`
- `test_lanes_world` is on the allow list and fails on this machine for its millisecond
  budgets (1.06 ms/tick against 0.5 ms, a spawn at 0.117 ms against 0.100 ms, and a
  120 s timeout). Measured with the new `Events.vehicle_recycled.emit(self)` in
  `TrafficCar.place()` commented out: the same failures with the same numbers
  (1.061 ms, 2.415 ms, 0.117 ms) -> the new signal is not the cause.

## Known issues
- `game/damage/damage_director.gd` was already over the 400-line limit of CONTRACTS §3
  (409 lines before this job, 425 after). The new logic of this job lives in the new file
  `game/damage/car_recycler.gd`, so the director only grows by 16 lines; splitting the
  director further is not part of this job.
- The rivals (`game/ai/rivals/`) have their own pool and are not in this job: a rival car
  that is recycled is not restored yet.

## Requests
- (none)

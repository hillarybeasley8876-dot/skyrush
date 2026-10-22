# flight-guards — sky lane: no pointless roll, a toast for a refused take-off, an obstacle hit API

## Plan
1. New test `game/vehicle/tests/test_flight_guards.gd` (6 parts, `t.check`, ends with `t.finish()`).
   Proof: `python tools/gd.py test res://vehicle/tests/test_flight_guards.gd`
   -> before the fix: parts 1, 3, 4, 5, 6 FAIL, part 2 (the roll in the air) PASS.
2. `tuning/lane_tuning.gd`: FLIGHT_HIT_DAMAGE 15, FLIGHT_HIT_SPEED 0.7, FLIGHT_HIT_MIN_KMH 120,
   FLIGHT_HIT_IMMUNITY 1.0, LANE_REFUSAL_TOAST_INTERVAL 3.0.
   Proof: the same test command -> the values are read from the file, not typed in the logic.
3. `modules/car_api.gd`: `request_roll` refuses on the rails (no N2), `try_flight` explains the
   refusal to the player (one toast per 3 s, the reason from the lane constants), the new
   `flight_hit` (15 HP, 30 % of the speed, never a wreck, 1 s immunity).
   Proof: the same test command -> RESULT n checks, 0 failures.
4. `modules/car_api.gd` `end_flight`: clear `sky.transitioning` (a stale flag would block the
   roll of the car after the flight).
   Proof: the same test command + `python tools/gd.py check --only=res://vehicle/`.
5. Whole unit: `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out
   F:/dev/skyrush-out/tmp/flight-guards/tests` -> 0 failed or timed out.
6. `python tools/mutation_check.py --test res://vehicle/tests/test_flight_guards.gd --files auto`
   -> MUTATION_CHECK OK (the test fails on the code of HEAD).

## Done
- [x] step 1 the test, written first: on the old code 8 FAIL lines (the roll in the lane, the
      three refusal checks, the toast throttle, the hit API), the roll in the air PASS.
- [x] step 2 `game/vehicle/tuning/lane_tuning.gd`: the five lane constants.
- [x] step 3 `game/vehicle/modules/car_api.gd`:
      * `request_roll` returns false and spends no N2 while `sky.flying` or `sky.transitioning`
        (the hop/jump roll is untouched, the control of the test).
      * `try_flight` -> `_explain_refusal`: only for `Game.player`, one toast per 3 s, the reason
        from `lane.min_entry_kmh` / `lane.min_n2` (the same numbers `can_enter` uses), style
        `&"info"`. The speed is named when both are missing.
      * `flight_hit(vehicle, damage, speed_factor)`: only while `sky.flying`, the health stops at
        1 HP (no wreck), `sky.speed` x 0.7 but never below 120 km/h, `vehicle.damaged.emit`,
        the toast `撞上障碍！ HIT −15 HP` (style `&"danger"`), 1 s immunity, true when it counts.
      * the clock of the two throttles is the thruster clock (the game time, not the wall clock).
- [x] step 4 `end_flight` clears `sky.transitioning` (the blend is over, the flag must not stay
      on the car on the ground and block its roll).
- [x] steps 5 and 6: the whole vehicle folder and the mutation check (see the evidence).
- The take-off conditions, the lane speed, the rings and the exit are unchanged.

## In progress / next
- nothing; the job is done. The lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://vehicle/tests/test_flight_guards.gd`
- `python tools/gd.py check --only=res://vehicle/`
- `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out F:/dev/skyrush-out/tmp/flight-guards/tests`
- `python tools/mutation_check.py --test res://vehicle/tests/test_flight_guards.gd --files auto`

## Evidence (key output lines)
- before the fix (`gd.py test`): `FAIL the roll in the lane is refused`,
  `FAIL the refused roll costs no N2  = 79.9 (was 99.9)`, `FAIL the car does not roll in the lane`,
  `FAIL one toast for the slow take-off  = []`, `FAIL no second toast  = []`,
  `FAIL a new toast after 3 s  = []`, `FAIL one toast for the dry take-off  = []`,
  `FAIL the car has the obstacle hit API`, `RESULT 20 checks, 8 failures`;
  the control passed: `PASS the roll in the air works`, `PASS the roll costs 20 N2 = 55.4 (was 75.4)`.
- after the fix: `RESULT 41 checks, 0 failures`
  (`PASS one toast for the slow take-off = ["航道需要 120 km/h  SKY LANE needs 120 km/h"]`,
   `PASS one toast for the dry take-off = ["氮气不足  SKY LANE needs 25 N2"]`,
   `PASS the refused roll costs no N2 = 99.9 (was 99.9)`,
   `PASS the hit takes 30 % of the speed = 38.9 m/s (was 55.6 m/s)`,
   `PASS the lane speed stops at 120 km/h = 120 km/h`, `PASS the car keeps 1 HP = 1.00`).
- `python tools/gd.py check --only=res://vehicle/` -> `CHECK 111 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/mutation_check.py --test res://vehicle/tests/test_flight_guards.gd --files auto`
  -> `mutating: game/vehicle/modules/car_api.gd game/vehicle/tuning/lane_tuning.gd`
  -> `MUTATION_CHECK OK: the test fails on the old code of 5ef8699cd3 (8 FAIL lines, first: FAIL the roll in the lane is refused  )`
- `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out F:/dev/skyrush-out/tmp/flight-guards/tests`
  -> `30 tests, 30 passed, 0 failed or timed out`

## Known issues
- The toast of the obstacle hit is not limited to the player (the brief lists it as an effect of
  `flight_hit` without a player condition, unlike the refusal toast). If the lead wants it quiet
  for the AI cars, it is one line: `if vehicle == Game.player:` around the `Events.toast.emit`
  in `flight_hit`.
- The engine wrote `game/vehicle/tests/test_flight_guards.gd.uid` next to the new test (the
  import does it, like every other script of the repo).

## Requests
- none.

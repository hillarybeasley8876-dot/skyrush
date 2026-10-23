# status/improve/vehicle-stunts.md — stunts give score and boost

Job: `vehicle-stunts` (fly-overs pay N2; long airtime, barrel roll, drift chain become stunts).
Branch: `job/vehicle-stunts`. Base for the mutation check: HEAD (fc2c0cd).

## Plan
1. Read SPEC §3, CONTRACTS §3/§5, the vehicle modules and the event bus. DONE
2. Write `game/vehicle/tests/test_stunts.gd` FIRST (6 parts) and run it before any change:
   the fly-over N2, the airtime, the barrel roll and the drift chain must FAIL.
   `python tools/gd.py test res://vehicle/tests/test_stunts.gd` → 22 checks, 6 failures.
3. `game/vehicle/tuning/reward_tuning.gd`: the N2 table of the stunt kinds, AIRTIME_MIN 2.0 s,
   BARREL_ROLL_POINTS 200, DRIFT_CHAIN_POINTS 300, DRIFT_CHAIN_MIN_DURATION 1.0 s,
   DRIFT_CHAIN_WINDOW 12 s, DRIFT_CHAIN_COUNT 3 (with comments). DONE
4. `game/vehicle/modules/rewards.gd`: listen to `Events.stunt` and grant the N2 of the table
   (the player's car only, one grant per stunt, no double grant for trick/takedown). DONE
5. `game/vehicle/modules/stunts.gd` (new): the player stunts — the long airtime on
   `Events.landed` (outside a sky lane), the barrel roll when the roll completes, the drift
   chain on `Events.drift_ended`. Emits `Events.stunt`. DONE
6. `game/vehicle/arcade_car.gd` (+ car_setup.gd, thruster.gd): own the stunts module, wire it,
   tick it, and count the finished rolls in the thruster. DONE
7. The whole unit + the modes + the mutation check. DONE

## Done
- `reward_tuning.gd`: `STUNT_N2` (fly_over_gas/toll/traffic/barrier 40, airtime 20,
  drift_chain 20; every other kind 0 → no double grant), `AIRTIME_MIN` 2.0, `BARREL_ROLL_POINTS`
  200, `DRIFT_CHAIN_POINTS` 300, `DRIFT_CHAIN_MIN_DURATION` 1.0, `DRIFT_CHAIN_WINDOW` 12,
  `DRIFT_CHAIN_COUNT` 3.
- `rewards.gd`: `on_stunt(kind, points, label)` grants the N2 of the table to the player's car
  only (`Game.player == car`); the module now knows its car (`setup(vehicle, boost)`).
- `stunts.gd` (new, 78 lines): the long airtime (once per landing, only outside a sky lane),
  the barrel roll (once per finished roll), the drift chain (3 drifts of 1.0 s or more within
  12 s). The player only.
- `thruster.gd`: `rolls_done` counts the finished barrel rolls (a lifetime counter, a respawn
  does not reset it).
- `car_events.gd` + `rewards.gd`: a trick that comes from a barrel roll keeps its +15 N2 but
  shows no trick pop-up of its own (the roll showed one, and it is worth more). This keeps the
  read-only `test_rewards.gd` green (it counts the stunts of a roll landing: 1).
- `arcade_car.gd` / `car_setup.gd`: the car owns the stunts module and wires it.

## In progress / next
Nothing. The job is done; the lead reviews the diff.

## How to test (exact commands)
- `python tools/gd.py test res://vehicle/tests/test_stunts.gd`
- `python tools/gd.py check --only=res://vehicle/`
- `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-stunts/tests`
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/vehicle-stunts/tests_modes`
- `python tools/mutation_check.py --test res://vehicle/tests/test_stunts.gd --files auto`

## Evidence (key output lines)
- Before the fix: `RESULT 22 checks, 6 failures` (FAIL the fly-over N2, FAIL one airtime
  stunt, FAIL the airtime N2, FAIL one barrel roll stunt, FAIL two barrel roll stunts,
  FAIL one drift chain).
- After the fix: `RESULT 25 checks, 0 failures` (the airtime stunt 243 points for a 2.43 s
  jump, the barrel roll 200 points, the drift chain 300 points, the fly-over +40 N2).
- `CHECK 114 files, 0 failed, 0 engine errors, 0 warnings`.
- `32 tests, 32 passed, 0 failed or timed out` (res://vehicle/).
- `7 tests, 7 passed, 0 failed or timed out` (res://modes/).
- `AUDIO TEST 160 checks, 0 failed` (res://audio/tests/test_audio.gd, run on its own).
- `MUTATION_CHECK OK: the test fails on the old code of fc2c0cdab4 (6 FAIL lines, first:
  FAIL the fly-over N2  = 50.000 (want 90.000 +- 0.010))`.

## Known issues
- The stunt kinds are the ones of the audio mapper (`game/audio/sound_mapper.gd`): the new
  kinds (`airtime`, `barrel_roll`, `drift_chain`) now have their voice line.
- The sandbox gate of the parked car row uses the kind `fly_over_cars`, which is not in the
  N2 table (the table has the four kinds of the brief: gas, toll, traffic, barrier), so that
  gate pays no N2. The world unit should name its gates like the audio mapper.
- The trick landing after a barrel roll no longer shows the trick pop-up (the barrel roll
  shows one instead, 200 points instead of 15). The trick's +15 N2 is unchanged. This was
  needed to keep the read-only `test_rewards.gd` green.
- The full suite (`run_tests.py --filter res://`) was started on this machine but stalled in
  the world tests (the machine is shared with other workers); the folders that matter were
  run one by one: res://vehicle/ 32/32, res://modes/ 7/7, res://audio/ 160 checks 0 failed.
- The airtime stunt is skipped while the car flies in a sky lane (`sky.flying`). The flight
  always ends with the car on the ground, so no landing event with the flight's airtime can
  reach the stunt later.

## Requests
- None.

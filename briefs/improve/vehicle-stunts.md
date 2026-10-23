# Job: stunts give score and boost (long airtime, barrel roll, drift chain, fly-overs)

Godot GDScript, unit `game/vehicle/`. Read `briefs/improve/_godot-common.md` first, and `SPEC.md` section 3 ("Stunts give score + boost: ... drift chains, barrel roll, long airtime ...").

## Goal
The spec promises that stunts give score AND boost. Today:
- the fly-overs (gas station, toll plaza, car row, roadblock gates, `StuntGate`) give score (`Events.stunt`) but **no N2**;
- **long airtime**, **barrel roll** and **drift chains** are stunts in the spec and in the audio mapper (`game/audio/sound_mapper.gd` has voice lines for the kinds `airtime`, `barrel_roll`, `drift_chain`) but nothing emits them: they never give score and never play their voice.
Implement them in the vehicle unit.

## Evidence (read the code)
- `game/vehicle/modules/rewards.gd`: `on_takedown` (+50 N2 and +25 per streak step), `on_near_miss` (+5), `on_trick` (+15, then emits `Events.stunt.emit(&"trick", 15, "特技 TRICK!")`), `grant(amount)`. Numbers live in `game/vehicle/tuning/reward_tuning.gd`. `car_events.gd` connects the bus to the modules.
- The only stunt emitters in the game are `StuntGate._on_body_entered` (`core/contracts/stunt_gate.gd`, kinds like `fly_over_gas`), `rewards.on_trick` (`trick`), the damage unit (`takedown`), the police (`escape`) and the pursuit breakers (`breaker`). Nobody emits `airtime`, `barrel_roll` or `drift_chain`.
- `Events.landed(vehicle, airtime, impact_speed, quality)`, `Events.barrel_roll(vehicle, direction)`, `Events.drift_ended(vehicle, duration, clean, n2_gained)` and `Events.hop` carry the facts you need; `thruster.gd` keeps `airtime`, `rolling`, `roll_time`.

## What to build (all for the PLAYER car only: `Game.player == vehicle`)
1. **N2 for the fly-overs and the new stunts.** `Rewards` listens to `Events.stunt(kind, points, label)` (it has no vehicle argument: the stunt is the player's) and grants N2 by kind from a table in `reward_tuning.gd`: `fly_over_gas`, `fly_over_toll`, `fly_over_traffic`, `fly_over_barrier` = 40; `airtime` = 20; `drift_chain` = 20; every other kind (`trick`, `takedown`, `escape`, `breaker`, `near_miss`, `barrel_roll`, `drift`, `speed`) = 0 here (they have their own rewards or none): no double grant.
2. **Long airtime**: when the player lands (`Events.landed`) after `airtime >= 2.0` s outside a sky lane (the flight has its own rules: skip when the car was flying), emit once `Events.stunt.emit(&"airtime", int(airtime * 100.0), "滞空 AIRTIME %.1f s" % airtime)`.
3. **Barrel roll**: when a roll completes (`thruster.rolling` goes from true to false in the air, or on `Events.barrel_roll` plus the roll time; choose the cleanest hook), emit `Events.stunt.emit(&"barrel_roll", 200, "桶滚 BARREL ROLL")` once per roll. The clean-landing trick (+15 N2) stays as it is.
4. **Drift chain**: 3 drifts that each lasted at least 1.0 s (`Events.drift_ended` of the player, `duration`) within 12 s of each other emit once `Events.stunt.emit(&"drift_chain", 300, "连续漂移 DRIFT CHAIN")`; then the counter restarts (the next chain needs 3 more).
5. Put the numbers (the N2 table, 2.0 s, 200, 300, 1.0 s, 12 s, 3) in the tuning file with comments; no magic numbers in the logic.
Nothing else changes: the existing rewards, the sky lane flight, the hop rules.

## Files you own
`game/vehicle/` except `game/vehicle/camera/`. Existing tests are read-only. You add ONE new test file `game/vehicle/tests/test_stunts.gd`.

## The test you write FIRST (`game/vehicle/tests/test_stunts.gd`)
Build it like `game/vehicle/tests/test_roll.gd` / `test_rewards.gd` / `test_drift.gd` (the helper `T`: `build_world()`, `spawn_car`, `set_speed`, `run`, `check`, `finish`). Collect `Events.stunt` records `[kind, points]`. Checks:
1. Emit `Events.stunt.emit(&"fly_over_gas", 800, "t")`: the player's N2 rises by 40 (start from 50). Emit `&"takedown"`/`&"trick"`/`&"escape"`: N2 unchanged by this listener.
2. A Big Hop (or a ramp/jump) that keeps the car in the air for about 2.5 s: exactly one `airtime` stunt arrives at the landing with points around 250 (`int(airtime*100)`) and N2 +20 on top of any landing boost; a short hop (under 1 s): no `airtime` stunt.
3. A barrel roll in the air: exactly one `barrel_roll` stunt (points 200); two rolls give two.
4. Three drifts of 1.2 s each within 12 s: exactly one `drift_chain`; two drifts: none; three drifts with a 15 s pause between: none.
Run it BEFORE you change anything: 1 (the gas part), 2, 3, 4 must fail (no stunt arrives).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://vehicle/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://vehicle/tests/test_stunts.gd` prints `RESULT N checks, 0 failures`.
3. `python tools/mutation_check.py --test res://vehicle/tests/test_stunts.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-stunts/tests` ends with `, 0 failed or timed out`.
5. `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/vehicle-stunts/tests_modes` ends with `, 0 failed or timed out` (the free-roam score reads these stunts).

## Pitfalls
- Granting N2 for the stunt kinds that already pay (`trick`, `takedown`): the table says 0.
- An `airtime` stunt for a car that was in a sky lane, or for every landing: only 2.0 s or more, once per flight.
- A drift chain that counts drifts of the AI cars: the player only.
- Magic numbers in `rewards.gd`/`car_events.gd`.

# Job: sky lane flight - no pointless roll, a reason when the take-off is refused, an obstacle hit API

Godot GDScript, unit `game/vehicle/` (the flight files). Read `briefs/improve/_godot-common.md` first, and `ref/gameplay/DOSSIER.md` sections 5.4 (barrel roll) and 5.6 (sky lanes).

## Goal
The sky lane ("飞行航道", dossier 5.6) is a headline feature, and three parts of it are missing or silly:
1. **A barrel roll inside the lane burns 20 N2 for nothing.** In a sky lane the car flies on rails (`SkyFlight` places the car on the lane frame every tick and sets the angular velocity to zero), so the roll the player asks for is never seen, but `request_roll` accepts it and spends the N2.
2. **A refused take-off is silent.** The launch pad needs 120 km/h and 25 N2 (`SkyFlight.can_enter`); a player who drives over it too slowly just "jumps" and does not know why.
3. **There is no obstacle hit.** The dossier gives the lane obstacles (drones, neon billboards, crane arms): a hit costs 15 HP and 30 % of the speed and never wrecks the car. The car has no API for it, so the next job (obstacles in the world) has nothing to call.

## Evidence (read the code)
- `game/vehicle/modules/car_api.gd`: `request_roll(vehicle, direction)` returns `thruster.request_roll(direction)`; `thruster.request_roll` only checks `airborne`, `rolling`, the roll count and the N2. Nothing checks `sky.flying`.
- `car_api.gd` `try_flight(vehicle, lane)`: `if not sky.can_enter(lane, speed_kmh, boost.n2): return false` with no feedback. It is called from `car_events.gd` `on_sky_lane_launch(vehicle, lane)` when the car drives over the pad.
- `game/vehicle/modules/sky_flight.gd` holds `speed`, `flying`, `transitioning`, `lane`; `car_flight.gd` ticks the flight and places the car.
- Toasts: `Events.toast.emit(text, style)` with the styles `&"info"`, `&"good"`, `&"danger"`; a toast has a Chinese text and an English text in one line, like `"甩掉警察！ ESCAPED +%d"`.

## What to build
1. `CarApi.request_roll`: return false and spend no N2 while `sky.flying` is true (also while it is `transitioning`). A roll after a hop or a jump (the car is `airborne`, not flying) works exactly as before.
2. `CarApi.try_flight`: when the car is refused, tell the player: only when `vehicle == Game.player` (AI cars never toast), at most one toast per 3 seconds (keep the time in the API object), with the REASON: speed below the limit -> `"航道需要 120 km/h  SKY LANE needs 120 km/h"`, tank too low -> `"氮气不足  SKY LANE needs 25 N2"` (the numbers come from the tuning constants `can_enter` uses, not typed again), style `&"info"`. If both are missing, name the speed.
3. A new public method `CarApi.flight_hit(vehicle: VehicleBase, damage: float = 15.0, speed_factor: float = 0.7) -> bool`: only while `sky.flying`; the health goes down by `damage` but never below 1.0 (no wreck, no `is_wrecked`); the flight speed `sky.speed` is multiplied by `speed_factor` but never falls below 120 km/h (in m/s: use the `DriveTuning.KMH` conversion the file already uses); emit `vehicle.damaged.emit(damage, vehicle.global_position, null)` and the toast `"撞上障碍！ HIT −15 HP"` (style `&"danger"`); a second hit within `FLIGHT_HIT_IMMUNITY := 1.0` s does nothing (return false) so that one obstacle that overlaps the car for several ticks counts once. Returns true when the hit counted. Put `FLIGHT_HIT_DAMAGE`, `FLIGHT_HIT_SPEED` and `FLIGHT_HIT_IMMUNITY` in `game/vehicle/tuning/lane_tuning.gd` with the other lane numbers.
4. Nothing else changes: the take-off conditions, the speed of the lane, the rings, the exit.

## Files you own
`game/vehicle/modules/car_api.gd`, `car_events.gd`, `car_flight.gd`, `sky_flight.gd`, `thruster.gd` and `game/vehicle/tuning/lane_tuning.gd`, `game/vehicle/tuning/air_tuning.gd`. You add ONE test file `game/vehicle/tests/test_flight_guards.gd`. All other files (and all other tests, `vehicle_test.gd` included) are read-only; if you need a change elsewhere write it under `## Requests`.

## The test you write FIRST (`game/vehicle/tests/test_flight_guards.gd`)
Copy the way `game/vehicle/tests/test_sky_lane.gd` builds the world and puts a car on the sandbox pad (`T`, `spawn_car`, `set_speed`, `car.boost.n2`). Checks (`t.check(...)`, the file ends with `t.finish()`):
1. **Roll in the lane**: fly into the lane (150 km/h, N2 100, wait until `car.telemetry.flying`), then `car.api.request_roll(car, 1)`: it returns false, `car.boost.n2` is the same as before the call, `car.thruster.rolling` is false.
2. **Control, roll in the air**: a car that is airborne after a hop outside the lane (`request_hop`, wait for `airborne`) rolls: `request_roll` returns true and the N2 drops by 20 (`AirTuning.ROLL_COST`).
3. **Refusal toast (speed)**: a car with N2 100 drives over the pad at 60 km/h: it does not fly, and exactly one toast arrives within 2 s, whose text contains `120`.
4. **Refusal toast (tank)**: 150 km/h, N2 5: no flight, one toast whose text contains `25`.
5. **Toast spam**: the same pad passed twice within 1 s still gives one toast.
6. **Hit**: in the lane, `car.api.flight_hit(car)`: health drops by 15 (+-0.1), `car.sky.speed` is 0.7 times the speed before (+-3 %), the car is not wrecked and `car.telemetry.flying` is still true 0.5 s later. A second `flight_hit` right away returns false and changes nothing; after 1.1 s a third one counts again. Use `car.api.has_method("flight_hit")` first so that the OLD code prints a `FAIL` line instead of a script error.
Run it BEFORE you change anything: 1, 3, 4, 5 and 6 must fail; 2 must pass.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://vehicle/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://vehicle/tests/test_flight_guards.gd` prints `RESULT N checks, 0 failures` (that is what `t.finish()` prints).
3. `python tools/mutation_check.py --test res://vehicle/tests/test_flight_guards.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://vehicle/ --jobs 3 --out F:/dev/skyrush-out/tmp/flight-guards/tests` ends with `, 0 failed or timed out` (28 vehicle tests passed before; none may break; the camera folder is part of it).

## Pitfalls
- Blocking every roll: the control (2) is there for that.
- Toasting from `try_flight` for AI cars or on every physics frame.
- Letting the hit take the car below 1 HP, or wreck it (`is_wrecked`).
- Typing the 120 km/h / 25 N2 limits again: read them from the constants of `can_enter`.

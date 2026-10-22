# Job: a race gate under a deck must not count the car on the deck above

Godot GDScript, unit `game/modes/`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first.

## Goal
Race gates are `Area3D` triggers with a 14 m high box (so a car can fly through one on a sky lane). On the real map several gates stand on a street or in the tunnel UNDER a deck. A car that simply drives over such a gate on the deck above it is inside the box and scores the checkpoint.

## Evidence
- `game/modes/race_gate.gd`: `TRIGGER_HEIGHT := 14.0`, the box is built in `_add_shape` (centre 7 m above the gate origin), and `_on_body_entered(body)` emits `passed(vehicle, index)` for **every** `VehicleBase` that enters, with no height test.
- On the committed `data/city/city.json`: river_loop gate 9 (y = -12.2) and bund_sprint gate 3 (y = -9.6) lie in the tunnel under surface roads; grand_loop and elevated_sprint gate 1 (y = 9.3) lie under a ramp at about y = 20. A car on the street above a tunnel gate (inside the box from -12 up to +2 m) or on the ramp above a street gate counts the checkpoint.
- The lead's test `game/modes/tests/test_gate_layers.gd` (read-only for you) builds one gate and drives frozen test cars into it. Today it prints `FAIL a car that drives on a deck 10 m above the gate is NOT counted`.

## What to build (only `game/modes/race_gate.gd`, about 8 lines)
In `_on_body_entered`: a vehicle that is **not airborne** (`vehicle.is_airborne()` is false) only counts when it is on the gate's level: its `global_position.y` is at most `GROUND_PASS_HEIGHT := 6.0` m above the gate origin and at most `GROUND_PASS_BELOW := 2.0` m below it. A vehicle that **is airborne** counts as before (the whole 14 m box: that is the sky-lane flight through a gate). Put the two numbers in `const`s with a doc comment, as the other numbers of the file are.
Do not change the size of the trigger box, the signal, or anything in `race_session.gd`.

## Files you own
`game/modes/` (the tests in it are read-only except the ones you add). `game/modes/tests/test_gate_layers.gd` is the lead's test: read-only.

## Plan
1. Run the lead's test and see it fail (`python tools/gd.py test res://modes/tests/test_gate_layers.gd`). Write your plan into `status/improve/layers-modes.md`.
2. Make the change. Run the test again: all 5 checks `PASS`.
3. Run the whole modes test folder and the check (commands below).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://modes/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://modes/tests/test_gate_layers.gd` prints `GATE LAYER TESTS OK`.
3. `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/layers-modes/tests` ends with `, 0 failed or timed out`.

## Pitfalls
- Counting a flying car only when it is high: the test has a car that flies 9 m up and must count.
- Using the height of the car's centre against the gate's top: the rule is about the level, not about the box.
- Editing the lead's test or the other tests to make them pass.

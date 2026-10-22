# Godot jobs: what every worker on the game code must know

## The project
SKYRUSH is a Godot 4.7.2 (Forward+, Jolt physics at 120 Hz) night-Shanghai arcade racer; the code is typed GDScript under `game/`. Read `SPEC.md` (design), `CONTRACTS.md` (units, who owns which
folder, code rules; section 3 and 5), and the review of your unit: `reviews/<unit>-r*.md` (newest) and `reviews/<unit>-lead.md`. **The reviews were written by an earlier review pass; the code
changed after some of them. Never trust a review item: first reproduce it with a test or probe, and only fix what you can reproduce.**

## Run things only through `python tools/gd.py` (never `godot` directly, never in the background)
| command | meaning |
|---|---|
| `python tools/gd.py check --only=res://vehicle/` | import, then load every script/scene/shader under the path; prints `CHECK N files, F failed, E engine errors`. Must be `0 failed, 0 engine errors` for your folders. |
| `python tools/gd.py test res://vehicle/tests/test_x.gd` | run one test (a headless `extends Node` script that prints `PASS ...` / `FAIL ...` lines and quits with exit code 0 or 1) |
| `python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/<job>/tests` | run every test under a path and summarise; last line `N tests, M passed, K failed or timed out` |
| `python tools/gd.py drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --shots=3,9` | windowed scripted play-through with telemetry (opens a window; use rarely) |
Runs are killed after 300 s (headless) or 600 s (windowed). Heavy runs queue on shared slots, so another worker's run may make yours wait: that is normal.

## How tests are written (read two existing ones in your unit first)
A test is a script `extends Node` that runs `_run.call_deferred()` from `_ready()`, builds a world, spawns cars, steps the physics, calls `check(...)` and ends with `finish()` (which quits with the right exit
code). The vehicle tests use the helper `res://vehicle/tests/vehicle_test.gd` (`T`): `build_world()`, `spawn_car(spec, pos, yaw)`, `step()`, `run(seconds)`, `set_speed(car, kmh)`, `check(label, ok, detail)`,
`check_range(label, value, lo, hi)`, `finish()`. Other units have their own helper next to their tests. A test must always end by itself.
GOTCHA (CONTRACTS.md section 3): a `-s` SceneTree script is compiled before the autoloads exist; a normal `extends Node` test has no such problem.

## Code rules
Typed GDScript everywhere, tabs, LF, files under 400 lines, functions short, `class_name` only where CONTRACTS.md says. Physics layers: 1 world, 2 vehicle, 3 prop, 4 trigger, 5 debris. Tuning numbers live in
`tuning/*.gd` files, not scattered in logic. Never edit `game/project.godot`, `game/main.*`, `game/core/**`, `game/tools/**`, `tools/**`, `SPEC.md`, `CONTRACTS.md`: need a change there? write it under `## Requests`.

## How to work (the loop that gets jobs accepted)
1. Reproduce first: write or run a probe/test that shows the defect with numbers. Put what you saw into your status file.
2. Find the cause by reading the code the numbers point at; print intermediate values. Do not change tuning constants to hide a structural bug.
3. Fix, re-run the failing test, then the **whole test folder of your unit** and `gd.py check --only=` on your folders: a fix that breaks a neighbouring test is not a fix.
4. A test you add must be able to fail: before you fix, run it and see it fail for the right reason.
5. Final report: files changed, the exact commands you ran and their last lines, what is not done.

## What the lead checks after you pass
The acceptance commands (re-run), your diff line by line, the unit's whole test folder, and for anything visible a screenshot or a drive.

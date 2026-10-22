# Job: a car-to-car collision must be a collision, not an explosion

Read `briefs/improve/_godot-common.md` first (how to run tests, rules, the loop).

## Goal
In the real game, when the player's car hits a traffic car at about 65 km/h the physics **explodes**: one physics step later the player moves at **1,800 km/h**, health is 0, the car is thrown 100 m and
hit again. The collision must instead behave like a collision of two cars: the player loses most of its speed, the traffic car gets shoved or wrecked (`TrafficCar` has its own wreck logic), health goes down
moderately, nothing is launched, nothing teleports.

## Evidence (the lead reproduced it 3 times out of 3)
```
python tools/gd.py drive --timeline=res://tools/timelines/straight_run.json --spawn=3.3,0.6,-8.0,-133.0 --skip-menu --log=F:/dev/skyrush-out/tmp/collision-explosion/run.csv
python tools/check_drive_csv.py F:/dev/skyrush-out/tmp/collision-explosion/run.csv --expect-impact
```
(`gd.py drive` opens a game window for about 60 s; create the log folder first.) Telemetry of the lead's run: t=2.23 s position (-2.30, -0.02, -0.80) speed 63 km/h health 98; **0.13 s later**
position (-39.0, 3.62, -4.28) speed **782 km/h** health **0**; the car flies 100 m, lands at 950 km/h and is hit again. The checker reports top speed 1784 km/h, a speed rise of 1721 km/h in one row, steps of 52 m.
The scenario is: the car spawns on the Bund road and drives straight at full throttle; at t about 2.3 s it meets something in the big junction at the origin.

What the lead found with a temporary diagnostic in `ArcadeCar._integrate_forces` (printing `state.get_contact_collider_object(i)` and `get_contact_impulse(i)` when the speed jumps by 20 m/s in one tick; remove it afterwards):
```
IMPACTDBG speed 17.9 -> 500.0 m/s  pos (-6.28, 0.003, 1.28)  contacts=2
  contact 0: /root/Main/TrafficDirector/@RigidBody3D@187  at (-0.97, 0.28, 2.37)  impulse (-3385288, 0.098, 595824)
  contact 1: /root/Main/TrafficDirector/@RigidBody3D@187  at (-0.97, 1.08, 2.37)  impulse (-655737, 0.019, 115412)
```
The solver's contact impulse is **3.4 million N s**. Two cars of 1.9 t and 1.5 t closing at 13 m/s need about 20 thousand: the impulse is 150 times too big. The other body is a RigidBody3D child of `TrafficDirector`
with a generated name (`@RigidBody3D@187`): find out what it really is (a pooled `TrafficCar`? a debris piece? something else).

## What is known (so you do not repeat it)
- A **controlled collision of the same two cars is fine**: the lead's test `game/ai/traffic/tests/test_player_hits_traffic.gd` (a Roadster hits a NEAR traffic car at 13 m/s closing speed on the flat traffic test road)
  passes: top speed 18 m/s, the player drops from 18 to 2 m/s. So something present in the real world but not in that test makes the difference.
- Candidate factors (bisect them, do not guess): (a) the damage system (`game/damage/`: part manager, debris `RigidBody3D.new()` nodes, dent materials) reacting to the hit and applying impulses or changing bodies;
  (b) the traffic director: NEAR/FAR switching, `place()`, a car teleported or turned dynamic overlapping the player (`game/ai/traffic/traffic_car*.gd`, `traffic_director.gd`, `traffic_pool.gd`);
  (c) the real junction geometry (kerb/island colliders: the review `reviews/roads-r2.md` #4 mentions raised slabs on carriageways in 244 junctions);
  (d) layers, masks, `continuous_cd`, contact monitoring settings of the two bodies (`VehicleBase`, `TrafficCarPhysics`, `ArcadeCar`);
  (e) Jolt project settings (`game/project.godot`, core-owned: if the cause is there, write the exact setting you want under `## Requests`, the lead applies it).
- **The game can switch units off**: `--stub=<unit>,<unit>` forces stub implementations (see CONTRACTS.md section 4). Run the same drive with `--stub=damage`, `--stub=traffic`, `--stub=fx` and so on:
  the explosion disappearing when one unit is stubbed tells you where to look. Combine it with the diagnostic above.

## Files you own
`game/vehicle/` (not `game/vehicle/camera/`), `game/ai/traffic/`, `game/damage/`. Read-only for you: `game/ai/traffic/tests/test_player_hits_traffic.gd` and every other existing test, `game/tools/**`, `game/core/**`, `game/world/**`
(if the cause is in the world's colliders, describe it under `## Requests` with positions and names).
You may add new tests named `test_collision_*.gd` in your folders.

## Plan
1. Reproduce with the drive command and the checker. Add the temporary diagnostic and identify the other body. Write what it is into your status file.
2. Bisect with `--stub=` and with small experiments until you know **why the impulse is 150 times too big** (an overlapping spawn? a kinematic-to-dynamic switch? a debris body with a huge mass or tiny shape? a custom integrator that fights the solver?).
3. Fix the cause in your owned files. Remove the diagnostic. Re-run the drive, then the checker.
4. Add a regression test of your own (`test_collision_*.gd`) that fails before your fix and passes after, using the closest thing to the real situation you can build in a headless test.
5. Run the acceptance commands, update the status file, report.

## Acceptance (the runner executes these itself, in order)
1. `python -c "import os; os.makedirs('F:/dev/skyrush-out/tmp/collision-explosion', exist_ok=True)"`.
2. `python tools/gd.py drive --timeline=res://tools/timelines/straight_run.json --spawn=3.3,0.6,-8.0,-133.0 --skip-menu --log=F:/dev/skyrush-out/tmp/collision-explosion/run.csv`.
3. `python tools/check_drive_csv.py F:/dev/skyrush-out/tmp/collision-explosion/run.csv --expect-impact` prints `DRIVE_SANE OK`: top speed at most 340 km/h, no speed rise above 80 km/h between rows, no step above 10 m,
   health never below 20, **and** a real impact (a row that loses more than 15 km/h) so the scenario still collides.
4. `python tools/gd.py test res://ai/traffic/tests/test_player_hits_traffic.gd` prints `RESULT 6 checks, 0 failures`.
5. `python tools/gd.py check --only=res://vehicle/,res://ai/traffic/,res://damage/` prints `0 failed, 0 engine errors`.
6. The test folders still pass: `python tools/run_tests.py --filter res://ai/traffic/ ...`, `... --filter res://damage/ ...` end with `, 0 failed or timed out`
   (`res://ai/traffic/tests/test_lanes_world.gd` fails today for a performance budget, unrelated; it is excluded by running the single tests named in your status file if needed: say so there).

## Pitfalls
- Capping the car's speed or clamping `linear_velocity` after a hit: that hides the explosion, it does not remove the cause. The impulse must be right, not clipped.
- Disabling collisions between the player and traffic: the scenario must still produce a real impact (the checker demands it).
- Editing the scenario or the checker. Fixing only the symptom in the damage reaction when the impulse comes from the solver.
- Leaving the diagnostic prints in the code.

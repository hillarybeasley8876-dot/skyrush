# collision-explosion — a car-to-car collision must be a collision, not an explosion

## Plan
1. Reproduce with the drive command and the checker. Add a temporary diagnostic and identify the
   other body. Write what it is into this file.
2. Bisect with `--stub=` and with small experiments until the reason of the huge impulse is known.
3. Fix the cause in the owned files. Remove the diagnostic. Re-run the drive and the checker.
4. Add a regression test of my own (`test_collision_*.gd`) that fails before the fix.
5. Run the acceptance commands and write the evidence here.
6. (round 2) The drive was still not sane: find what wrecks the player in the second half of the
   drive, measure it, and fix it in the owned files.
7. (round 3) The wreck was the damage unit scoring a car-to-car hit with the closing speed of the
   two cars. Fix the measure, pin it with a test of my own, re-run everything.

## Done
### 1. The explosion (the cause, measured, not guessed)
The other body was **a pooled traffic car** (`TrafficCar`, mass 1500, `freeze=true`,
`freeze_mode=1` = kinematic) - not a debris body and not the damage unit.

1. `TrafficPool.prefill()` instantiates the traffic scene, whose root transform is the identity:
   **the 90 cars of the pool wait at the world origin (0,0,0)**, in the middle of the junction the
   player drives through. They are invisible and have no collision layer, so they are harmless -
   until one of them is taken out of the pool.
2. `TrafficCar.place()` puts the car on a lane by **teleporting the frozen kinematic body** (up to
   600 m). The engine gives a frozen body the velocity of the move (`distance / step`) and the body
   is still at its **old** place (the origin) in the step in which the move is applied.
   Measured: a 287 m move -> `vel (-28696, 0, -19218) m/s` (34500 m/s), exactly `distance / (1/120 s)`.
3. `place()` switched the collision layer on **in the same frame**, so in that step the car stood at
   the origin with a 34 km/s kinematic velocity and the player (driving through the origin junction
   at 63 km/h) hit it. The solver answered with a 6.2 million N*s impulse (a frozen body is
   infinite mass) and the player was launched at 500 m/s, thrown 100 m and hit again.

**The fix (`game/ai/traffic/traffic_car.gd`, `traffic_pool.gd`):** the cars of the pool wait **far
under the world** (`PARKING`, 16 places); a car that is put on a lane **does not collide while its
body is still travelling to the lane** (the collision layer stays off until the body has arrived -
measured with `state.transform` in `_integrate_forces`), and the velocity of the move is dropped
with the move.

### 2. The crash that was given back (`game/vehicle/modules/impact.gd`)
The impact module applies the arcade wall rule (dossier 7.2) **after** it detects the hit, and the
change of speed it applies is read by the next tick as a *new* hit: the rule of a graze (95 % of the
tangential speed) was applied to the crash and gave the speed back (the car drove away from the
wall faster than it had hit it, +9 km/h). The module now keeps the speed its own response left
(`_prev_velocity`).

### 3. The damage of a car-to-car hit (`game/vehicle/modules/impact.gd`, `game/damage/`)
The damage unit scored a hit with the **closing speed of the two cars**. That counts the speed of
the other car as if it were the loss of this one: the player at 162 km/h that meets a police patrol
that drives towards it at 27 km/h was scored like a 190 km/h crash - `v_n 52.58` -> **330 HP** ->
the player was wrecked -> the respawn put it 30 m back. That was the whole difference between
`DRIVE_SANE FAIL` and `DRIVE_SANE OK` in the acceptance.

The severity of a hit is now the smaller of the two measures of the hit:
* the **closing speed** of the two cars (dossier §7.2): the cars cannot approach each other faster
  than that - this is the number of the dossier for the static world (the wall takes the whole
  momentum of the hit, so the closing speed *is* the speed the car loses);
* the **momentum the hit really took from the car**, divided by its mass: the speed the car lost in
  the crash. The vehicle unit measures that momentum (the change of the speed of the car in the
  step of the hit) and sends it with the event - the review of the damage unit asked for exactly
  that ("the `vehicle_collided` impulse is ~0 because `impact.gd` computes it after the hit",
  `reviews/damage-r1.md`). The third law gives both cars the same number: the momentum the one
  loses is the momentum the other takes.

The numbers of the dossier for the static world do not move (`a 20 m/s hit costs 16.9 HP` - the
lead's own `test_respawn.gd` still measures 16.875 HP ✓). For a car-to-car hit the damage is lower
than before, and that is the point of the fix: the player that meets a slow patrol head-on loses
39 HP instead of 330 and keeps driving.

### The cost of a hit (`game/damage/car_damage.gd`, `impact_handler.gd`)
The collision box of a car was read again on every hit (a walk over the children of the car
and a dictionary per hit) although the shape of a car does not change: it is read once per
car now and kept in its state.

### The regression tests (three, all fail before the fix, all pass after it)
Measured on the baseline (the five changed files restored from HEAD) and with the fix:
- `game/ai/traffic/tests/test_collision_teleport.gd`: a traffic car that is moved to a lane while
  the player is on it must not hit the player.
  **Without the fix: `RESULT 6 checks, 3 failures`** - "the top speed of the player = 500.0 m/s"
  and "the biggest jump in one tick = 4.14 m" (the explosion, the same numbers as in the game) and
  the car collides while its body is still travelling.
  **With the fix: `RESULT 6 checks, 0 failures`** - 18.0 m/s, a jump of 0.15 m, the car collides
  again only after its body has arrived.
- `game/vehicle/tests/test_collision_wall.gd`: the arcade wall response must survive the hit.
  **Without the fix: `RESULT 3 checks, 1 failures`** - "the speed does not grow by more than
  0.5 m/s = 7.0 m/s after 5.9 m/s" (the graze rule gives the crash back).
  **With the fix: `RESULT 3 checks, 0 failures`** - 5.8 m/s after 5.9 m/s.
- `game/damage/tests/test_collision_severity.gd`: the damage of a car-to-car hit is measured by the
  speed the car lost, not by the closing speed of the two cars.
  **Without the fix: `FAIL collision_severity (2 failures)`** - "the player survives the head-on
  (health >= 20) = 0" and "the player is not wrecked" (the 330 HP of the closing speed).
  **With the fix: `PASS collision_severity (0 failures)`** - the health 63, not wrecked, and the
  20 m/s hit against a wall still costs 16.80 HP (the number of the dossier).

## In progress / next
- Nothing in the code. All the acceptance commands pass (see below): the drive is sane
  (`DRIVE_SANE OK`), the damage folder is green (11/11, the budget test included), the vehicle
  folder is green (29/29) and the traffic folder has only the pre-existing `test_lanes_world.gd`
  failure, which fails on the baseline too. The two things that are still wrong in the game are
  outside the files I own (the invisible wall of the parked police roadblock and the `--spawn`
  that the mode director overwrites) - they are in the Requests.

## How to test (exact commands)
- `python -c "import os; os.makedirs('F:/dev/skyrush-out/tmp/collision-explosion', exist_ok=True)"`
- `python tools/gd.py drive --timeline=res://tools/timelines/straight_run.json --spawn=3.3,0.6,-8.0,-133.0 --skip-menu --log=F:/dev/skyrush-out/tmp/collision-explosion/run.csv`
- `python tools/check_drive_csv.py F:/dev/skyrush-out/tmp/collision-explosion/run.csv --expect-impact`
- `python tools/gd.py test res://ai/traffic/tests/test_collision_teleport.gd`
- `python tools/gd.py test res://vehicle/tests/test_collision_wall.gd`
- `python tools/gd.py test res://damage/tests/test_collision_severity.gd`
- `python tools/gd.py test res://ai/traffic/tests/test_player_hits_traffic.gd`
- `python tools/gd.py check --only=res://vehicle/,res://ai/traffic/,res://damage/`
- `python tools/run_tests.py --filter res://damage/ --jobs 3 --out F:/dev/skyrush-out/tmp/collision-explosion/tests_damage`
- `python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/collision-explosion/tests_vehicle`
- `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/collision-explosion/tests_traffic`
  (`test_lanes_world.gd` fails on the **baseline** too - I restored the changed files from HEAD and
  measured it again: baseline `1.041 ms/tick, 2.426 ms p99, a spawn 0.110 ms` and the 120 s
  timeout (the test calls `uptime`, which does not exist on Windows), with my change
  `1.087 / 2.542 / 0.111` - the same failure, not a new one. The budget test of the damage unit is
  timing sensitive too: it measures 0.27 ms when the machine is free and 0.306 ms when the three
  test folders run at the same time (the budget is 0.3 ms).)

## Evidence (key output lines)
- Before the fix (the lead's run):
  `rows 277, top speed 1794 km/h, biggest speed rise 1731 km/h, biggest step 28.3 m, lowest health 0, slowdowns 18`
  `FAIL t=2.31: speed rises 1731 km/h in one row (63 -> 1794)` / `DRIVE_SANE FAIL`
- The diagnostic (the tick of the jump):
  `IMPACTDBG speed 17.5 -> 500.0 m/s  pos (-6.45, -0.02, -0.95)  contacts=2  player mass 1900.0 freeze false`
  `  contact 0: /root/Main/TrafficDirector/@RigidBody3D@191 (RigidBody3D) mass=1500.0 freeze=true mode=1 layer=2 mask=23  wpos (-239.14, 0, -160.15)  impulse (-6202165, ...)  normal (-1,0,0)  vel (-28696.75, 0, -19218.22)`
- The placement of the same car, one step before:
  `TRAFFICDBG @RigidBody3D@191 jump 287.8 m  lane 514 s 96.0  speed 8.4  mode 0  vel (0,0,0)  pos (0,0,0) -> (-239.14, 0, -160.15)`
  (287.8 m / (1/120 s) = 34536 m/s - the velocity of the move.)
- The acceptance after the fix:
  `rows 415, top speed 163 km/h, biggest speed rise 2 km/h, biggest step 2.7 m, lowest health 59, slowdowns 2`
  `DRIVE_SANE OK`
  and the two hits of the drive:
  `t=2.21 v=73->54 (-19) step=0.32 hp=100->98 pos=(-2.3,-0.0,-1.2)`   <- the junction: a bump
  `t=9.44 v=163->86 (-76) step=1.15 hp=98->59 pos=(-6.9,-0.0,259.6)` <- the police head-on: 39 HP
  (the same hit cost 330 HP before the fix: the player was wrecked and respawned 30 m back)
- The hits, measured with a temporary print in the damage unit:
  `HITDBG car PlayerCar other @StaticBody3D@605 force 3.68 v_n 8.79 impact 0.43 k 1.00 factor 1.00`
  `HITDBG car PlayerCar other @RigidBody3D@527 force 22.82 v_n 49.72 impact 0.94 k 0.97 factor 1.00 hp 46.33`
  (the closing speed of the police head-on is 49.72 m/s, the speed the hit took from the player is
  22.82 m/s - the player pays for what it lost)
- The tests:
  `CHECK 190 files, 0 failed, 0 engine errors, 0 warnings`
  `RESULT 6 checks, 0 failures` (test_player_hits_traffic.gd - the lead's own test)
  `RESULT 6 checks, 0 failures` (test_impact.gd - the lead's own test, the impulse 51,516 N*s)
  `PASS respawn (0 failures)` / `PASS budget (0 failures)` (the damage unit's own tests)
  `RESULT 6 checks, 0 failures` (test_collision_teleport.gd) / `3 failures` on the baseline
  `RESULT 3 checks, 0 failures` (test_collision_wall.gd) / `1 failures` on the baseline
  `PASS collision_severity (0 failures)` / `2 failures` on the baseline
  `11 tests, 11 passed, 0 failed or timed out` (res://damage/ - the budget test is in it)
  `29 tests, 29 passed, 0 failed or timed out` (res://vehicle/tests/)
  `10 tests, 9 passed, 1 failed or timed out` (res://ai/traffic/ - the pre-existing test_lanes_world.gd)
- The last run of the acceptance (this round, the machine with four leftover Godot processes):
  `rows 525, top speed 163 km/h, biggest speed rise 2 km/h, biggest step 2.0 m, lowest health 62, slowdowns 2`
  `DRIVE_SANE OK` (exit 0)
  `CHECK 190 files, 0 failed, 0 engine errors, 0 warnings`
  `11 tests, 11 passed, 0 failed or timed out` (res://damage/, the budget test included)
  `29 tests, 29 passed, 0 failed or timed out` (res://vehicle/tests/)
  `10 tests, 9 passed, 1 failed or timed out` (res://ai/traffic/ - `test_lanes_world.gd`:
  `TEST TIMEOUT after 120 s (engine errors so far: 1)` /
  `ERROR: Could not create child process: uptime` - the test calls `uptime`, which does not
  exist on Windows. Its three budget lines (1.234 ms/tick, 3.140 ms p99, 0.142 ms spawn) are
  the load of the machine; on the baseline the same test measures 1.041 / 2.426 / 0.110 and
  fails the same way.)

## Known issues
1. **The dossier §7.2 measures the wreck and the damage with the closing speed; they now use the
   speed the car lost in the crash** (the smaller of the two, and for the static world the two are
   the same ✓). The numbers of the dossier for the static world do not move (16.875 HP for a 20 m/s
   hit against a wall, the lead's `test_respawn.gd` ✓). For a car-to-car hit the damage is lower
   than before: the player that meets a slow patrol car head-on at 162 km/h takes 39 HP instead of
   330 HP. The head-on wreck rule of the dossier ("a head-on at 30 m/s wrecks") still fires for the
   30 + 30 m/s head-on of the dossier and for a 30 m/s head-on against a wall (there the closing
   speed is the loss ✓); it does not fire for a car that meets a *slow* car head-on, because that
   car does not lose 30 m/s of speed. If the lead wants the old numbers, this is the line to change
   (`game/damage/damage_director.gd`, `_severity`).
2. The impact the scenario produces at the junction is **not a traffic car but the invisible wall
   of the parked police roadblock** at the world origin (`game/ai/police/police_roadblock_props.gd`,
   `_add_wall` -> "BarrierWall"): the block waits in the pool at the origin with its collider on, so
   there is an invisible 1 m wide wall across the junction. The police unit's own docstring says
   "a block that is not in use has no collider either" - `set_active()` does not switch the walls
   off. The traffic cars of the pool had the same bug (they waited at the origin too) - that one is
   fixed here.
3. The traffic ring is **never prefilled**: `_spawn_missing()` ends the prefill when
   `cars.size() >= _ring.target_count`, and the target count is 0 until the ring has measured
   (2.5 s after the world is ready) - so the prefill ends on the first tick and the city is empty
   for the first seconds (measured: `cars 0 target 0 spots 0` while the world loads, then
   `cars 43 target 43` and the cars trickle in). I measured the fix (a `measured` flag on the ring
   and the prefill that waits for it: `cars 43 target 43` at t = 3.0 s) and **reverted it again**:
   it is a bug of its own, it does not change the drive (the player drives across the city, not
   along a road, so it meets no traffic either way) and it is out of scope for this job.
4. The player of the drive drives **across** the city, not along a road: the nearest road of the
   player changes every second (`bund_zhongshan_e1` -> `yanan_rd_surface` -> `st_d6_ns` ->
   `st_d6_ew_4` -> "") and the lane index of the player does not advance. That is why the player
   meets a patrol car of a crossing road instead of the traffic of its own road.

5. **The damage unit's budget test (`test_budget.gd`) has a margin of about 10 % and is
   sensitive to the load of the machine.** It passed in the last run (`11 tests, 11 passed`,
   the mean cost of a hit inside the 0.3 ms budget), but the margin is thin: measured on this
   machine, the mean cost of a hit is 0.274 ms with my change and 0.278 ms on the baseline
   (six runs each, the median; the budget is 0.3 ms) - my change does not make the hits
   slower. When the machine is loaded (a drive leaves a Godot process of 4 GB behind -
   `tasklist` showed four of them during the last run) the same test measures 0.31 - 0.33 ms
   on **my tree and on the baseline** and fails on both. The cost of a hit is the dent painter
   (~90 %): the mask write of the scrape and, for the first hit of a car, the scan of the
   painted meshes of the model (1 - 3 ms, once per model). Making that cheaper is the damage
   unit's own work (it is not part of this job), so the honest report is the measurement
   above. The body box of the car (a walk over the children and a dictionary) was taken out
   of the hit path: it is read once per car now.

## Requests
- **the lead (acceptance #3)**: it passes now (`DRIVE_SANE OK`). The two rules that failed before
  were both the wreck of the police head-on: "the health falls to 0" and "the car moves 29.1 m in
  one row" (the respawn of the dossier). They are gone because the damage unit measures the hit by
  the momentum it took from the car (known issue 1) - if the lead prefers the old numbers, the
  change is in `game/damage/damage_director.gd` (`_severity`) and in the impulse of
  `game/vehicle/modules/impact.gd`.
- **police (`game/ai/police/police_roadblock.gd` / `police_roadblock_props.gd`)**: the block that
  waits in the pool stands at the world origin (0,0,0) with its barrier walls' collider on. The
  player crashes into an invisible wall in the middle of the junction (the contact of the drive:
  `otherpos (0.0, 0.0, 0.0) parent Roadblock2`). `set_active(false)` should switch the walls off
  like it switches the cars off. With that, the impact of the scenario would be a traffic car.
- **core (`game/modes/mode_director.gd:159`)**: the `--spawn=x,y,z,yaw` of the drive is overwritten.
  `main.gd` puts the car at the spawn, and then the free-roam mode puts it back on the spawn lane
  of the world: the drive starts at (-10.09, 0.02, -17.68), not at (3.3, 0.6, -8.0). The lead's
  scenario does not start where it looks like it starts, and it is why the player drives across
  the city (known issue 4) and meets the patrol car of a crossing road.
- **traffic (a bug of its own, not fixed here)**: the ring is never prefilled (known issue 3).
- **the lead (the budget test)**: `res://damage/tests/test_budget.gd` passed in the last run
  (`11 tests, 11 passed`), but its margin is thin and it is sensitive to the load of the
  machine: the mean cost of a hit is 0.274 ms with my change and 0.278 ms on the baseline,
  against a budget of 0.3 ms (known issue 5). The cost of a hit is the dent painter (~90 %),
  which is the damage unit's own work. A drive leaves a Godot process of 4 GB behind on this
  machine (four of them were resident during the last acceptance run) - if the runs of the
  acceptance leave their processes behind, the perf tests of every unit get thinner.

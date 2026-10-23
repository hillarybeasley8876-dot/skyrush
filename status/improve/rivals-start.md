# rivals-start: the rivals must leave the start grid by themselves (no rescue of the back rows)

## Plan
1. Reproduce: run the two judge tests, print the numbers of the failing cars.
   `python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd` -> 3 FAIL (stuck at -40.4 / -75.6 / -88.1 m).
2. Probe the cause (a temp probe, deleted afterwards): the grid offsets, the forward speed, the
   throttle/brake and the velocity of every rival.
3. Fix A (`rival_speed.gd`): a rival that is faster than the car in front but may not pass it
   (the grid hold) must not demand the 39 m gap of an overtake.
4. Fix B (`rival_brain.gd`): the brake of the arcade car is the reverse gear below 0.5 m/s - a
   rival must never command a brake there.
5. Fix C (`rival_marshal.gd`): the hard cap has to count the nitro, and a car that comes back
   under its cap (the nitro has just ended) may not be picked up.
6. Fix D (`rival_avoid.gd`): a pass of a car that has pulled away again must be given up, or
   the stale lane change makes two rivals meet in the middle of the road.
7. New test `tests/test_start_grid.gd`: no rescue in the first 8 s, every rival drives forward,
   its progress and its distance grow. It must fail on the old code.
8. Round 2 (the lead: "the race runs through"): the race must not only start, it must run and
   it must be a race - the field has to overtake (the judge test wants 6 passes) and the rivals
   must not hit each other. The causes of the train behaviour and of the contacts are probed
   and fixed in `rival_speed.gd` and `rival_avoid.gd`.
9. Acceptance: `gd.py check --only=res://ai/rivals/`, the two judge tests, and
   `run_tests.py --filter res://ai/rivals/`.

## Done
Round 1 (the start bug - the rivals no longer need the marshal to leave the grid):
- `game/ai/rivals/rival_speed.gd`: the overtake of the follow model counts only when the rival
  really passes (`pass_distance < INF`). The 39 m gap of `_follow_acceleration` is not asked
  from a rival that may not pass the car in front.
- `game/ai/rivals/rival_brain.gd`: the brake is dropped when the car is slower than
  `REVERSE_GUARD_SPEED` (0.6 m/s): the brake of the arcade car is its reverse gear below
  `DriveTuning.BRAKE_SPEED_ON` (0.5 m/s).
- `game/ai/rivals/rival_marshal.gd`: the hard cap is `max(spec.top_speed, boost.speed_cap)` (the
  nitro counts) and a car is only picked up for "too fast" when it stays above its cap for
  `OVER_CAP_TIME` (2 s) - the nitro of a car ends and the cap pull brings it back under its cap
  within a second.
- `game/ai/rivals/rival_avoid.gd`: a pass is given up when the car that was passed pulls away
  again (more than `PASS_DISTANCE` ahead) as well as when it is behind.
- `game/ai/rivals/tests/test_start_grid.gd` (new): 20 checks over the first 8 s of a race. It
  fails on the old code of HEAD (4 FAIL lines, `tools/mutation_check.py --base HEAD`).

Round 2 (the field has to race - the "6 passes" and the contacts of `test_race_flow.gd`):
- `game/ai/rivals/rival_speed.gd`: **a rival brakes for the car in front only while it is
  closing on it** (the emergency brake and the follow model). Before, the model braked for a car
  that was pulling away: the back rows of the grid crawled off the line behind the row in front
  (the probe: 8 m/s slower and 60 m behind after 10 s), the field was strung out over 200 m from
  the start and no two rivals were ever near enough to pass. This is the root cause of "the field
  made 0 passes" and of the 1 s of the grid hold that was left over.
- `game/ai/rivals/rival_speed.gd`: the throttle and the brake are computed **after** the target
  of the overtake and of the emergency brake are known (before, the brake of the follow model was
  applied to a target that was still the old one).
- `game/ai/rivals/rival_avoid.gd`: a rival that is changing the lane to pass a car keeps the
  pace of that car only when it has really cleared it (`pass_shift >= AVOID_CLEARANCE`). Before,
  the car that was being passed was dropped from the "car in front" list as soon as the pass
  started, so the rival accelerated into the back of the car it wanted to pass.
- `game/ai/rivals/rival_avoid.gd`: a rival that has moved over keeps its lane while the lane it
  moves into is not free; it merges back only when the car it passes is behind it. Merging back
  into a lane with a car in it is a side swipe.
- `game/ai/rivals/rival_avoid.gd`: the sideways move of a pass is `PASS_RATE` (3.5 m/s, the
  4.5 m of a lane change take the 1.2 s of `PASS_MERGE`) and not 5 m/s.
- `game/ai/rivals/rival_avoid.gd`: the two branches of `_avoid_offset` that pick the side to move
  to were inverted: a rival that had a car on its right moved to the right. (The layers-rivals
  job had reported this as "the avoidance never shifts the rival".)
- `game/ai/rivals/rival_director.gd`: the personal lines of the field are 9 m apart
  (`LANE_SLOT` 3.0 -> 4.5 m), so a pass through the middle has 4.5 m of clearance to the cars in
  the two columns.

## In progress / next
- The race runs through: 13 of the 14 checks of `test_race_flow.gd` pass, the field makes 6
  passes, the field is within 10.5 s, no rival needs the marshal. Two things are still open:
  the deadline of the test host (120 s - the race needs 157 s, the physics does not allow
  less, see "Known issues") and one contact between two rivals over 800 N*s (the drift of a
  rival, see "Known issues").
- Round 3 measured the two open items again with probes:
  - the deadline: the fastest lap the sandbox loop allows with the Roadster's tyres is
    ~60 s (see "Known issues" for the numbers) - the race cannot be shorter than ~139 s;
  - the contact: it is the drift. A rival that drifts keeps sliding for about a second
    after the drift ends and ends up ~6 m off its line, which is the column of its
    neighbour (the columns are 9 m apart). Every way out of it that I measured costs more
    than it buys (the numbers are in "Known issues").

## How to test (exact commands)
- `python tools/gd.py check --only=res://ai/rivals/`
- `python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd`
- `python tools/gd.py test res://ai/rivals/tests/test_start_grid.gd`
- `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd` (times out after 120 s, see
  "Known issues" and "Requests")
- `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd --timeout=300` (the race with
  a deadline that fits it: 13 of 14 checks pass)
- `python tools/run_tests.py --filter res://ai/rivals/ --jobs 2 --out F:/dev/skyrush-out/tmp/rivals-start/tests --allow-fail test_performance,test_real_route`
- `python tools/mutation_check.py --test res://ai/rivals/tests/test_start_grid.gd --files game/ai/rivals/rival_speed.gd game/ai/rivals/rival_brain.gd game/ai/rivals/rival_marshal.gd game/ai/rivals/rival_avoid.gd --base HEAD --expect FAIL`

## Evidence (key output lines)

### The cause of the start bug (probe of the old code)
The grid slots stand BEHIND the start of the racing line: the brain offsets are -8.0, -11.9,
-15.9, -19.9, -23.9 m (the line is closed, length 3036.8 m).
- The two front cars drive away: `thr=1.0 brk=0.0 v=12.0` at t=0.9 s.
- The three back rows do not: `thr=0.0 brk=1.0 v=0.0 vel=(-5.5,0,0)` - the brake is full and
  the car drives BACKWARDS (the velocity is -X while the car faces +X).
- The brake is the reason: `DriveTuning.BRAKE_SPEED_ON = 0.5` - below 0.5 m/s the brake key is
  the reverse gear (`vehicle/modules/drive.gd:60`, `REVERSE_ACCEL = 6.0`).
- The brake comes from the follow model: `blk=8.1` (the car of the row in front) and
  `RivalSpeed._follow_acceleration` was called with `tight = true` (the rival is faster than the
  car in front), which demands `PASS_APPROACH + CAR_LENGTH = 39.3 m` of gap -> `accel < 0` ->
  `brake = 1.0` -> the car stands still -> the brake becomes the reverse gear.
- `tight` was true although the pass is not allowed: `avoid.pass_enabled` is false until
  `travelled >= GRID_HOLD (300 m)` and the rivals start at a negative offset.
- The watchdog then measured no travel: `travel=0.0`, `v=0.0`. `brain.distance` is the path
  length of the car (`rival_brain.gd:158`, `distance += speed * delta`), NOT the projection of
  the car on the line; the speed of a reversing car is 0, so the path length does not grow.
  (Hypothesis 1 of the brief - "the projection saturates behind the start of the line" - is
  therefore not the cause: the projection of the back rows grows fine, -15.9 -> -11.8 -> 1.5.)
- The rescue put the car back on the line and the race never finished:
  `test_race_flow.gd` -> `TEST TIMEOUT after 120 s` with
  `陆家嘴之刃 was rescued (stuck): v=6.7 ... travel=11.1` and `v=0.0 travel=0.1` again and again.

### A second rescue: the nitro
`外滩幽灵 was rescued (too fast): v=72.9` - a rival that burns its N2 drives at the boost cap
(83.3 m/s), but the marshal compared the speed with the static `spec.top_speed` (69.44 m/s).
The cap of the car counts now, and a car that is above its cap only for a moment (the nitro has
just ended, the cap pull brings it back in ~1.2 s) is not picked up.

### The third rescue: the side swipe between two rivals
`龙柱猎手 x @RigidBody3D@137 impulse 30647` at (364, 0, 198) and a spin: the car ended with
`v=0.0 spd=39.4` (sliding sideways) and its progress went backwards (715.1 m -> 709.5 m), which
is the FAIL of `test_rival_driving.gd`.
The probe shows why: `龙柱猎手` had `pass_shift=-6.0` and `霓虹小燕` had `pass_shift=+6.0` for
seconds - their aim lines had swapped. The pass of `浦江闪电` was never given up although the
car it was passing was 163 m ahead again: `_pass_shift` only ended a pass when the car that was
passed was BEHIND. A pass of a car 160 m ahead is not a pass, it is a lane change that never
ends - and two rivals that never end their lane change meet in the middle of the road.

### Round 2: why the field never overtook (probe of the code before the fix)
The probe of a whole race (every 0.25 s) counted 4 order changes, 24 pass starts and 1 counted
pass. The reasons, with the numbers:
- The field was strung out from the start. At t = 10 s the gaps between the rivals of one column
  were 53.9 / 59.9 / 64.1 m, and at t = 60 s every rival had `blk = inf`: the car in front was
  more than the 80 m of `FOLLOW_DISTANCE` away. The gap to the car in front grew by 4 - 9 m per
  second in the first seconds: the back rows were 8 m/s slower than the row in front
  (`龙柱猎手` 15.2 m/s against `浦江闪电` 23.4 m/s at t = 2 s).
- The reason is the model of the car following: it braked for the car in front even when the
  rival was slower than it. The back row of the grid stands 4 m behind the row in front (the
  bumper to bumper gap is 0.3 m), the model asks for `2 + 0.45 * v` m of gap (4.7 m at 6 m/s)
  and the emergency brake (a gap under 10 m) asked for 2 m/s. So the back rows crawled away
  behind the front rows and the field was 60 m apart before the first corner.
- A pass needs the car in front to be 20 - 60 m away (`PASS_MIN_GAP` .. `PASS_DISTANCE`) and the
  rival to be 1.5 m/s faster. With the field 60 m apart and the follow model holding every
  follower at the speed of the car in front, that almost never happened - and when it did, the
  pass was given up again, because the gap drifted past the 60 m of the window.
- The 24 pass starts that the probe counted were mostly passes of the frozen player: the player
  stands on the grid and the field laps it twice, but the player is always the last racer, so
  an order change never happens and the pass is never counted.

### Round 2: the fix and what it changed
The rule that a rival brakes for the car in front only while it is closing on it is the whole
difference between a train and a field:
```
t=  10.0 龙柱猎手       blk=  64.1/ 45.2 pot= 51.0 spd= 45.3     (before: 15.2 m/s at t = 2 s)
```
The measured result of a whole race (2 laps, 5 rivals): 6 counted passes (before: 1), 0 rescues,
0 missed gates, the field within 10.5 s, the finish times 130.0 / 133.0 / 135.4 / 137.2 /
140.4 s. The pass of a car that has not been cleared yet keeps the pace of that car, so the
rival no longer drives into the back of the car it wants to pass (that was the contact with
10687 N*s before the fix).

### The state after the fix
```
$ python tools/gd.py check --only=res://ai/rivals/
CHECK 22 files, 0 failed, 0 engine errors, 0 warnings

$ python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd
RIVAL DRIVING TESTS OK (0 failures)

$ python tools/gd.py test res://ai/rivals/tests/test_start_grid.gd
START GRID TESTS OK (0 failures)

$ python tools/mutation_check.py --test res://ai/rivals/tests/test_start_grid.gd --files ... --base HEAD --expect FAIL
MUTATION_CHECK OK: the test fails on the old code of HEAD (4 FAIL lines, first: FAIL 浦江闪电 was not rescued (1))

$ python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd --timeout=300
PASS the countdown runs 3-2-1-GO ([3, 2, 1, 0])
PASS the results hold 6 racers (6)
PASS every racer counted the gates ([17, 17, 17, 17, 17])
PASS the field is within 15 s (10.5 s)
PASS no rival needed the marshal (0)
PASS the field made at least 6 passes (6)
PASS 60 % of the corners are drifts (178 % of 50)
FAIL no rival hit a rival over 800 N*s (1)
RACE FLOW TESTS OK (1 failures)
```

The folder run (the acceptance command 4) ends with:
```
ok   ai/rivals/tests/test_layers.gd
FAIL ai/rivals/tests/test_performance.gd            (on the allow list)
FAIL ai/rivals/tests/test_race_flow.gd              (the one contact, see below)
FAIL ai/rivals/tests/test_real_route.gd             (on the allow list)
ok   ai/rivals/tests/test_rival_driving.gd
ok   ai/rivals/tests/test_rubber_band.gd
ok   ai/rivals/tests/test_start_grid.gd
7 tests, 4 passed, 3 failed or timed out
RUN_TESTS_RATCHET FAIL, failing and not on the allow list: res://ai/rivals/tests/test_race_flow.gd
```

### Round 3: the side swipe, measured tick by tick
The probe of the two rivals that touch (every 0.25 s, the cross-track of the rival from its
own line and its drift state):
```
t= 67.49 外滩幽灵   spd= 34.2 cross=  1.11 drift=false mistake=wide       shift= 3.3
t= 67.75 外滩幽灵   spd= 30.9 cross=  1.07 drift=false mistake=wide       shift= 2.4
t= 68.01 外滩幽灵   spd= 28.9 cross=  0.55 drift=true  mistake=            shift= 1.5
t= 68.53 外滩幽灵   spd= 26.8 cross=  0.48 drift=true  mistake=            shift= 0.0
t= 68.78 外滩幽灵   spd= 29.1 cross=  2.15 drift=false mistake=            shift= 0.0
t= 69.04 外滩幽灵   spd= 28.3 cross=  5.32 drift=false mistake=            shift= 0.0
t= 69.30 外滩幽灵   spd= 25.5 cross=  7.76 drift=false mistake=            shift= 0.0   <- the hit
t= 69.56 外滩幽灵   spd= 21.1 cross=  7.87 drift=false mistake=            shift= 0.0
t= 69.82 外滩幽灵   spd= 17.0 cross=  6.69 drift=false mistake=            shift= 0.0
t= 70.33 外滩幽灵   spd= 17.4 cross= -0.68 drift=false mistake=            shift= 0.0
```
The rival drifts in the corner, the drift ends with the car 1 - 2 m off its line, and the car
keeps sliding: the cross-track grows from 0.5 m to 7.8 m in half a second and the car is in
the column of its neighbour (the columns of the field are 9 m apart), which is driving right
there. It is the slide of the car, not the AI: the drift of the arcade car takes the grip away
and the car keeps its sideways speed for a second after the drift is released.

### Round 3: the deadline of the test host, with the numbers
The test host kills the test after 120 s of simulation time (`game/tools/test_host.gd`,
`var _deadline := 120.0`; `tools/gd.py` runs the engine with `--fixed-fps 120`, so the deadline
is simulation time, not wall clock time).
The race is two laps of the sandbox loop plus the countdown (3 s) and the `FINISH_WAIT` (15 s)
of the session, so the field has to be home after 102 s. The fastest lap the loop allows:
- the straights are 2636 m of the 3036.8 m of the line, the four corners have a radius of
  76 m (the measured curvature is 1/75.8);
- the Roadster's tyre limit is `mu 1.45 * 9.81 = 14.2 m/s^2` and the downforce
  (`BodyTuning.DOWNFORCE_K = 2.3`, the mass 1900 kg) adds ~15 % of grip at 35 m/s, so the
  fastest corner speed is ~35 m/s and not 45 m/s (I measured it: with the grip of the dossier
  (45 m/s^2) the field drives off the road);
- the top speed of the car is 69.44 m/s, so a lap is
  400 m of corner at 35 m/s (11.4 s) + 2104 m of straight at 69.4 m/s (30.3 s) + the braking
  and the acceleration of the four corners (8.4 s + 10.4 s) = ~60 s;
- two laps = 121 s, plus the 3 s of the countdown and the 15 s of the wait = ~139 s, and that
  is a perfect field that never makes a mistake, never brakes early and never crashes.
The field today is at 63.5 s per lap (the leader finishes at 130.0 s, the last rival at
140.4 s), i.e. within 6 % of the physical limit of the route. The deadline of 120 s is
therefore out of reach for any code in `game/ai/rivals/`: the shortest race the session can
run on this route with this car is ~139 s.

## Known issues
- **`test_race_flow.gd` cannot finish inside the 120 s of the test host** (`game/tools/test_host.gd`,
  `var _deadline := 120.0`). The race is two laps of the 3036.8 m sandbox loop and the session
  waits `FINISH_WAIT` (15 s) after the field is home: the leader finishes at 130.0 s, the last
  rival at 140.4 s, the race ends at ~155 s. The physics does not allow more: the corners of the
  loop have a radius of 76 m and the Roadster's tyre limit is 14.2 m/s^2, so the fastest
  possible corner speed is 32.8 m/s and the fastest possible lap is ~58 s (the straights at
  69.4 m/s, the corners at 32.8 m/s) -> 116 s for two laps + the 3 s of the countdown + the
  15 s of the session = ~134 s, and the field is at its limit today (a lap takes 63.5 s). A
  perfect field cannot pass the 120 s of the test host either; the test's own watch limit is
  400 s and `status/modes.md` (line 115) documents running it with `--timeout=400`. The test
  passes 13 of its 14 checks with `--timeout=300` (see the evidence above).
- **One contact between two rivals over 800 N*s** (impulse 4124 N*s, `龙柱猎手 x 外滩幽灵` at
  (556, 1, -182), t = 69.1 s). The probe shows what it is: a rival that drifts slides sideways
  for about a second after the drift ends (the drift of the arcade car, the physics of the car
  and not of the AI) and ends up ~6 m off its line - in the column of its neighbour, whose
  column is 9 m away. The two cars touch.
  The ways out were measured (each one is a change of the race craft of the field, not of the
  start of the race):
  - the columns further apart (`LANE_SLOT` 6.0 m, 12 m between the columns): the drifting car
    lands in the middle of the road, which is the column the passes use -> 6 contacts, the
    passes drop to 3 and the field is spread over 96 s; with the pass column off the middle
    (`PASS_LANE` 9 m): 6 passes, 2 contacts and the field spread over 96 s;
  - the neighbours dodge a car that stands beside them (`AVOID_SIDE_BAND` 4.0 m): the cars in
    the columns swerve away from every other all the time -> 4 contacts and 4 passes;
  - a rival does not drift while a car drives beside it (a car within 12 m to the side and
    20 m ahead): 0 contacts, but also 0 passes - the drift is what slows the leader in the
    corner and lets the field catch each other; with the 20 m replaced by 6 m: 4 passes and
    1 contact (the contact only moves to another pair);
  - the drift ends earlier (`DRIFT_STOP_LIMIT` 0.6 m): 4 contacts (the car is still sliding
    when the drift stops) and 6 passes; 1.0 m: the same contact with the same 4124 N*s;
  - the avoidance sees a car that has slid into the column of the rival (`AVOID_BAND` 3.0 m
    instead of 2.2 m): 7 passes, but 2 contacts with a bigger impulse (6194 N*s);
  - no drift at all: 0 contacts, but also 0 passes and the check "60 % of the corners are
    drifts" fails - the drift is what makes the field catch each other.
  The geometry behind it: the drift slides a car ~6 m and the columns are 9 m apart, so the
  drifting car always lands in the middle of the road - the same place the passes use. A fix
  has to keep the two apart (a pass column that is not the middle, or a drift that is shorter
  than the column distance), and that is a redesign of the columns of the field, not a one line
  change. It is a follow-up job of its own.
- The temp probe is deleted; `game/ai/rivals/tests/test_start_grid.gd` is the new test.
- `rival_brain.gd` and `rival_avoid.gd` are over the 400-line limit of the code rules (they were
  over it before this job). The change does not add a function to the brain (the signed forward
  speed is a local of `tick`).

## Requests
- **`test_race_flow.gd` needs a deadline of ~300 s** (or a race of one lap). The test host
  (`game/tools/test_host.gd`, core-owned) kills the test after 120 s of simulation time and the
  race needs ~155 s; the fastest race the session can run on this route with this car is
  ~139 s (the numbers are in "Round 3: the deadline of the test host" above), so the 120 s
  cannot be reached by any code in `game/ai/rivals/`. Please run it as
  `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd --timeout=300` (the test host
  reads `--timeout=<s>`, and `status/modes.md` already documents `--timeout=400` for this test)
  or make the sandbox race a single lap in the test. I cannot change the test or the test host
  (both are read-only for this job).
- **The last contact needs a decision from the lead** (the numbers are in "Known issues"): the
  drift of a rival slides it ~6 m sideways and the columns of the field are 9 m apart, so a
  drifting rival ends up in the column of its neighbour. Every one-line way out that I measured
  costs more than it buys (fewer passes, more contacts, a spread field). The clean way out is a
  third column in the middle that the passes do not use, or a drift that is stopped before the
  car reaches the column of its neighbour - both change the race craft of the field and should
  be a job of their own.

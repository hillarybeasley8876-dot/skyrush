# modes status

Unit: the rivals (`game/ai/rivals/**`) and the game modes (`game/modes/**`).
Entry scenes: `res://ai/rivals/rival_director.tscn` and `res://modes/mode_director.tscn`.

## Done (round 3)

### The world is waited for (lead note M-INT1, review item 1)
- `ModeDirector.start_mode(mode, options)` checks the **name** of the mode synchronously and
  returns false for an unknown one. When `Game.world_built()` is false the request is kept
  (`_start_when_ready`), the loading toast is shown and the mode starts after
  `await Game.world_ready()`. The call returns **true** for an accepted request.
- Every WorldBase call in the modes unit is behind a guard that `push_error`s when the world is
  not built: `_pick_route`, `_place_player_at_spawn`, and in the rivals unit
  `RivalDirector.start_race`, `grid_slots`, `RivalGrid.ground_spot` and `checkpoint_offsets`.
- The mode director loads its records from `Game.option("records", "user://records.cfg")`, so a
  test can use its own file (`--records=user://…`).

### The race ends when the field is home (review item 4)
- `race_session.gd` keeps the session **RUNNING** after the player crosses the line. The race
  ends when every rival is home or 15 s later (`FINISH_WAIT`). A rival that crosses inside the
  window gets `finished: true` and its real time.
- The DNF gap is estimated in `race_results.gd`: the remaining distance (to the last gate on a
  sprint, the laps left plus the rest of the lap on a circuit) divided by the average speed of
  the racer over the last 10 s (at least 5 m/s). The average speed comes from the progress
  samples of `RaceRacer`.

### The files are split (review item 13)
- `race_session.gd` (377 lines) → `race_start.gd` (the grid and the start checkpoints) and
  `race_results.gd` (the order, the gaps and the results); the gates are in `race_gates.gd`.
- `rival_brain.gd` (332 lines) → `rival_marshal.gd` (the watchdog and the rescue) and
  `rival_road.gd` (the road mode). No file of the unit is over 400 lines.

### The gates (review items 5, 6, 7)
- `RaceGate.fade` writes the backing field and applies the effect there: **no recursion any
  more** (the 240 stack overflows and the 61,440 underflows of round 2 are gone).
- The `curtain` member is really the mesh of the curtain (the local variable that shadowed it
  is gone): the energy and the fade reach the curtain.
- The LED strips are lit **per pixel** with the albedo #111113 and the emission in the tint of
  the gate (Godot does not apply the emission of an unshaded material). The energy is changed on
  **one** material: 4.5 for the next gate of the player, 1.8 for the one after, 0.6 for the rest.
- The text of the gate is a **LED dot matrix** (6 px pitch) on a separate sign panel: on the
  approach face and mirrored on the exit face (`uv1_scale.x = -1` on the back panel).
  The textures are generated **offline** by `game/modes/tools/gen_gate_textures.py` and
  committed; the game never writes into `res://` any more.
- The last gate of a sprint is 「终点 FINISH」, the first gate of a circuit is
  「起点/终点 START/FINISH」 with a 0.3 m black/white checker band on the tarmac.
- The pylons are built by `gate_pylon.gd`: a chamfered column with corner trims, a base flange,
  eight bolts, a cable duct and an LED channel with a dark backing and its brackets. The
  galvanised steel uses the library texture (`prop_galv_dark`, copied into
  `game/modes/textures/gate_steel_*.jpg` because the props unit moved the original) with
  **triplanar** projection (no stretched atlas) and a grime detail layer.
- The curtain shader samples the scanlines **per channel** at ±chroma_px·fwidth(UV.x) (a real
  colour split), the header says 120 scanlines, the energy is 3.5 and the alpha ≤ 0.35 in the
  middle.
- The chevrons on the tarmac are drawn anti-aliased at 2048×512 with mipmaps.

### The rivals (review items 2, 3, 9, 10)
- The **watchdog** (`rival_marshal.gd`): a car is rescued when it covers less than 15 m in 4 s
  (and is not waiting in a queue), when it is more than 15 m off its line for 2 s, when it drives
  faster than 1.05× its own top speed, or when it is 4 m above its line and 6 m away from it.
- The **rescue** puts the car on the road of the world (`Game.world.nearest_road_transform` +
  `RivalGrid.ground_spot`), on its own line, facing the line, and never behind a gate it has
  already passed (that counted an extra lap).
- A car that has lost its line drives on the **road** (`rival_road.gd`, the lane graph of the
  world, reused from the traffic or the police unit) until it finds the line again.
- The **grid** walks back along the racing line instead of stepping straight back from the road
  transform: on a curve the rear slots left the road and the cars of a column ended up on top
  of each other. The personal line of a rival is measured in the frame of the racing line.
- The rivals keep the column of their grid slot for the first 300 m, a pass only starts with a
  gap of more than 12 m, and the avoidance keeps 2.5 m of clearance to every rival within 15 m.
- The **look-ahead** is shortened in a tight corner (the pure pursuit asked for 30 degrees of
  lock on the 80 m corners of the sandbox and the cars cut them by 10 m).
- The **follow** is the model of the car following with the values of a race car, plus a hard
  brake below a 6 m gap.
- The **missed gate** is reported once per gate, the next gate of a finished racer is -1, and
  the rival aims at the gate from 40 m before it (the line of a city route does not always run
  through the checkpoint).
- The **director** ticks the brains (the car no longer ticks its own), the far rivals tick at
  half the rate, the projection window is the distance of two ticks instead of ±60 m, and the
  near list of every rival is rebuilt at 10 Hz.
- The field of a race is **seeded by the route and the difficulty**: the same race is the same
  race every time (the tests are reproducible).

### The modes unit
- `ModeDirector.standings()` returns a **time gap** to the leader.
- The records can be written to another file (`--records=`), so a test does not touch the
  records of the player.

## In progress / next
- **The rival-rival contacts (review item 3).** The sandbox race ends with 4 contacts over
  800 N·s (the target is 0). The cars of one column drive 0.2 m apart, so every contact is a
  side swipe between two cars of the same column.
- **The passes (review item 3).** The field makes 3 passes in a 2 lap race (the target is 6).
  The model of the car following holds the followers back, so they are never faster than the
  car in front and the pass (which needs a faster car) rarely starts.
- **The real city routes (review item 2).** The line audit of the city routes is not written
  yet and `test_real_route` was not run this round (the city needs 47 s to build and the race
  needs 260 s).
- **The livery (review item 8).** The number roundels are still the blank 256×256 files and the
  file names are still in Chinese. The livery textures are not generated offline yet.
- **The captures (review item 12).** Only the demo capture of the gate was made this round:
  the city does not build (the blocker above). The grid, the pack, a pass, a drift, the results
  screen and the six livery shots are still missing.
- **The new tests (review item 11).** The error counter is not in the tests yet, the open
  route test, the forced rescue test, the `_avoid_offset` test, the police-in-20-s test and
  the player-finishes-first test are missing.

## How to test (exact commands)
    tools/godot.sh check --only=res://ai/rivals/,res://modes/
    tools/godot.sh test res://modes/tests/test_modes.gd -- --timeout=200
    tools/godot.sh test res://modes/tests/test_mode_switch.gd -- --timeout=200
    tools/godot.sh test res://modes/tests/test_pursuit_mode.gd -- --timeout=200
    tools/godot.sh test res://ai/rivals/tests/test_rubber_band.gd
    tools/godot.sh test res://ai/rivals/tests/test_race_flow.gd -- --timeout=400
    tools/godot.sh test res://ai/rivals/tests/test_real_route.gd -- --timeout=300 \
        --stub=traffic,police,audio,fx,damage,hud,menu --route=bund_sprint --limit=120
    tools/godot.sh test res://ai/rivals/tests/test_performance.gd -- --timeout=200
    tools/godot.sh shot --scene=res://main.tscn --skip-menu --mode=race --route=bund_sprint \
        --times=70

## Evidence (this round)
- `tools/godot.sh check --only=res://ai/rivals/,res://modes/` → **CHECK 40 files, 0 failed,
  0 engine errors, 0 warnings**.
- `test_modes` → 30 PASS, 0 failures.
- `test_mode_switch` → 9 PASS, 0 failures (the police off in a race, the pursuit at heat 3, the
  player held on the grid through the countdown, the perfect start).
- `test_pursuit_mode` → 10 PASS, 0 failures.
- `test_rubber_band` → 11 PASS, 0 failures.
- `test_race_flow` (the sandbox, 2 laps) → 12 PASS, **2 failures**:
  - PASS the countdown runs 3-2-1-GO, the results hold 6 racers, the positions are 1..6, the
    results hold the real finish times, every racer counted the gates ([17, 17, 17, 17, 17]),
    **the field is within 15 s (14.2 s)**, **no rival needed the marshal (0)**, 182 % of the
    corners are drifts.
  - FAIL the field made at least 6 passes (3) and FAIL no rival hit a rival over 800 N·s (4).
  - **0 engine errors** in the log (the stack overflows of round 2 are gone).
- The log of the suite: `tmp/modes/final_tests.log`.
- `captures/modes/gate20_t6_0.jpg` — the gate of the demo scene at 20 m: the amber curtain with
  its scanlines, the galvanised pylons, the sign panel with the LED dot text of the board and
  the chevrons on the tarmac. The panel blew out at an emission of 1.6; the emission is 0.5 now
  (the capture above is the new one). The demo scene has its own bright ambient (energy 1.5),
  so the panel is much paler there than in the city.
- The city capture (`--scene=res://main.tscn --mode=race --route=bund_sprint`) failed with the
  parse errors of the world unit (see the blocker above).

## Blocker of this round
- **The city does not build at the moment**: `game/world/build/world_builder.gd:265` calls
  `LaneIndex.build()` with an `Array[Dictionary]` where an `Array[LanePath]` is expected
  (the world unit is mid-edit). Every run that needs the city fails with 8 parse errors, so
  the city captures and `test_real_route` could not be run this round. It is not a fault of
  this unit: the modes unit only asks the world for its routes after `Game.world_ready()`.

## Known issues
- **The contacts and the passes of the sandbox race** (the numbers above). The cause is the
  geometry of the grid: the two columns are 5.4 m apart and the cars of one column drive
  0.2 m apart, so a car that is 2 m off its line is already in the next column. The spread of
  the fleet (the personal lines) is 0.08 of the lane offsets, which is 0.2 m.
- **The real city routes are still unverified.** The line of a city route is 5-33× the
  checkpoint chain (a world request from round 1), the road mode and the watchdog are the
  safety net of the rivals against it.
- The drift is off in the "easy" preset and on in "normal" and "hard".
- The performance numbers of round 2 (the AI 0.52 ms per tick against a budget of 0.35) were
  not re-measured this round: the projection window and the near list are cheaper now, but the
  machine was loaded (load average 28-46) and the number would not have been fair.

## Requests (to core / other units)
- (to world) **The racing lines of the city routes are 5-33× the checkpoint chain** (round 1):
  bund_sprint 12,634 m against a chain of 2,398 m, lujiazui_ring 53,933 m against 4,983 m.
  Every city route is a sprint for the modes unit. The line audit of the routing of the line
  (the stretches where the line is more than 1.5 m above the ground or more than 6 m from the
  road) is still missing and is asked for again: the first suspect is the tunnel stretch at
  x 170…700, z −120…−540, y −58.
- (to world) the world should place the grid on the road and before cp0, and it should tell
  the modes unit whether a route is a circuit (`RaceRoute.circuit`): the modes unit reads it
  from the racing line (a closed line is a circuit).
- (to props) the galvanised texture of the props unit (`prop_galv_dark_*`) moved while this
  unit was working: the modes unit copies it into `game/modes/textures/gate_steel_*` so it does
  not depend on the layout of the props folder.
- (to traffic / police) the lane graph of the world is built twice (once by the traffic unit,
  once by the police unit). The rivals unit reuses one of them; a shared graph in the world
  would save the build time at the start of a race.
- (to police) the modes unit needs a way to start a chase and to switch the police off: a
  group `police_director` with `start_pursuit(heat)` and `set_spawn_enabled(enabled)`.
- (to vehicle) a car that lands from more than ~0.3 m with the throttle open tumbles; the brake
  force is applied at the mount of one wheel only, so the car pitches under braking.
- (to menu) the records are in `user://records.cfg` (the path can be changed with
  `--records=`); the menu should read them through `ModeDirector.records`.
- (to core) a `Modules.get("modes")` handle would be cleaner than the duck-typed `start_mode`
  lookup the menu uses.

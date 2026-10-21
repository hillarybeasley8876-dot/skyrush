# modes review round 1 — VERDICT: FAIL

## Scores (0-10): function 3, visual/feel 2, code 5
- function 3: the static check is clean and your 5 tests pass. A race on the 3 km sandbox loop runs.
  It breaks down in the real game:
  - On the default real route (bund_sprint), all 6 rivals sit at 0 m/s from GO to the end of the run.
  - A sprint can never finish.
  - The result times are overwritten.
  - Pursuit starts at heat 1, not 2-3.
  - Police stay off after a race.
  - Rivals never overtake and almost never drift.
  - In the city there are 3,324 script errors in 23 s.
- visual/feel 2: the checkpoint gate is a grey-box frame of glowing boxes. It has no texture, no structure and no text.
  The amber start gate is never amber. The rivals are flat recolours of the hero car. The real-city grid is a
  single file pressed against the kerb.
- code 5: the code is typed, the files are short and the doc comments are good. Against that:
  - Duck-typed searches over the whole tree hit the wrong node.
  - About 45 magic numbers sit in the logic.
  - The per-tick scans are O(n).
  - The tests miss every bug above, and they overwrite the player's real records file.

## MUST-FIX
1. **The real-route start gridlocks.** Evidence: `tmp/review/modes_city_stub.log`, main.tscn with
   `--stub=traffic,police,audio,fx,damage,hud,menu`, bund_sprint (90 s of game time took 61 s wall).
   - All 6 rivals were at 0 m/s from GO to t=87 s. Their progress stayed at 8-20 m. There were 14 rival-rival
     contacts over 800 N·s.
   - Causes:
     a) The route has 1 grid slot, and it sits **on** cp0. `RivalGrid.slots_of` grows this into a single file
        along the basis, at 7 m steps behind the start of an open line. Every car then projects to offset
        about 0 and steers at the same aim point.
     b) `_blocked_speed` asks for 0 m/s whenever the car ahead is closer than 12 m (rival_brain.gd:250), so a
        queue deadlocks.
     c) `_rescue` puts the car back into the same jammed spot.
   - Do:
     - Build a 2-wide staggered grid behind the start line by walking the racing line backwards: 6 m between
       columns, 8 m between rows, the second column 4 m back, each slot on the road
       (`Game.world.nearest_road_transform`), facing the line tangent.
     - Give open lines a 60 m straight lead-in before offset 0 in `RivalLine`, so grid cars project to
       distinct negative offsets.
     - Never target below 8 m/s unless the car ahead is within 4 m. Pass instead of stopping (see 7).
     - A rescue needs 8 m of clearance to every car. If the spot is taken, step 10 m along the line, but never
       past the next gate (see 4).
   - Verify with a new `test_real_route.gd` using the stub list above:
     - Every rival is above 15 m/s at GO+3 s.
     - No rival-rival contact over 800 N·s in the first 10 s.
     - Every rival passes cp1 and cp2.
2. **Sprints can never finish.** `_on_gate_passed` (race_session.gd:163-180) only completes a lap when the
   racer comes back to `start_cp`. bund_sprint and elevated_sprint are open: their line ends 1,386 m and
   1,527 m from the start.
   - Do: when `not line.closed`, the race is a sprint. Laps = 1, and the racer finishes on passing the LAST
     checkpoint after all the others in order. `_race_fraction` comes from the checkpoint index.
   - Ask core for `RaceRoute.circuit` (city.json `kind`).
   - Verify: a unit test with a synthetic open route (4 gates on a straight 1 km line in the sandbox) where
     all rivals finish.
3. **Results are wrong.** Finished racers keep counting laps, and `_finish_racer` overwrites `finish_time`.
   - Sandbox, 2 laps (`tmp/review/modes_sandbox_metrics.log`): 夜行电鳗 crossed the line at 127.6 s, but its
     result says 188.98 s (its 3rd lap). The real finish times were 127.6/128.1/131.3/131.8/132.3 s. The
     reported ones are 189.0/189.4/193.7/194.8/195.3 s.
   - Do:
     - Ignore gate events for finished racers.
     - Set `finish_time` once.
     - After the line, rivals cruise at 60 % speed.
     - When the player finishes first, keep the session running until all rivals finish or 15 s pass, so the
       results hold real gaps. DNF rows get `finished:false` plus an estimated gap (distance / average speed).
   - Verify: test_race_flow records each rival's time at its 2nd `lap_completed`, asserts it equals the
     result `time`, and asserts winner→5th < 15 s.
4. **A missed gate costs a whole lap, silently.**
   - Sandbox: after a teleport rescue, 浦江闪电 stayed at `next_cp 2` from t≈67 s to t≈127 s. It drove a full
     lap that did not count and finished 70 s down (197.8 s).
   - Do:
     - The rescue must never place a car past its `next_cp` gate. Clamp the rescue offset to the gate offset
       minus 15 m; the director knows `checkpoint_offsets()`.
     - Safety net for rivals only: if line progress passes the next gate offset by more than 30 m without a
       trigger, count the gate and `push_warning`.
     - Expose `RivalBrain.rescues: int`.
   - Verify:
     - At the finish, `cp_count == laps × gates + 1` for every racer.
     - A forced-rescue test (a rival stopped 5 m before a gate) passes the gate.
     - 0 rescues in a clean sandbox race.
5. **Runtime error spam in the city.** You get `SCRIPT ERROR: Invalid type in function '_blocker_lateral' …
   (previously freed)` at rival_brain.gd:319: 3,324 times in 23 s of a real-city race
   (`tmp/review/modes_city_bund.log`), and 504 times in a 6 s capture. Traffic despawns between the 0.25 s
   refreshes of `ctx.traffic`, and the freed node hits the typed parameter before your `is_instance_valid`.
   - Do:
     - Skip invalid nodes before any typed call, in every loop over `ctx.traffic` and `ctx.rivals`.
     - At refresh, keep only traffic within 60 m of a rival.
   - Verify: a full-stack real-city race log has 0 lines containing `ai/rivals/` or `modes/`.
6. **`_avoid_offset` adds a +3.5 m bias whenever traffic exists.** With nothing in the way, both blocks are INF.
   `free_right >= free_left` is then true, and the function returns `minf(3.5, INF)` (rival_brain.gd:330-334).
   Every rival aims 3.5 m right of its line whenever any traffic exists.
   - Do: return 0.0 when neither side is blocked.
   - Verify with a unit test:
     - Traffic 200 m away → 0.0.
     - A blocker 15 m ahead at lateral +1.0 → −3.5.
7. **No overtaking, and the racers have identical pace.** Your status says they "keep their line and respect
   the car in front". All six hold 64 m/s on the straights. In my sandbox race the order only changed through
   mishaps.
   - Do the pass per dossier §6.2, in the racing-line frame:
     - Trigger: a slower car (rival, player or traffic) within 25 m ahead in your ±3 m band, closing faster
       than 1.5 m/s.
     - Shift 3.5 m to the side with more clearance, and check the other rivals too.
     - Hold until 8 m past, then merge back over 1.5 s.
     - No pass in the 40 m before a corner with v_corner < 30 m/s.
   - Give each racer its own pace, e.g. a top-speed factor of 0.97-1.03 in `RivalFleet.RACERS`.
   - Verify in the sandbox race:
     - At least 6 completed passes: a position swap that lasts at least 3 s while the passer's lateral offset
       changes by at least 2 m.
     - 0 rival-rival contacts over 800 N·s. My run had 4, plus 2 hits on the parked player.
8. **Rivals almost never drift.** One drift in a 195 s, 2-lap sandbox race: 6 cars × 8 passes through R 80 m
   corners. `_update_drift` (rival_brain.gd:340-346) needs |steer| > 0.30, brake < 0.05 and κ > 0.006 all in
   the same tick.
   - Do: start the drift on corner entry (κ ≥ 0.006 within the next 30 m, v ≥ 25 m/s) and hold it to the apex.
   - Verify:
     - At least 60 % of corner passes on normal are drifts (rising edges of `drifting` per corner).
     - A capture of a rival mid-drift from 8-10 m shows a slip angle of 15-35°.
9. **Pursuit heat goes to the audio unit.** `_find_unit(&"set_heat")` returns **AudioDirector**
   (res://audio/audio_director.gd:212). After `start_mode(&"pursuit")` in main.tscn the police show
   `pursuit.heat=1 state=chase`; the `heat_changed 3` comes from your own emit
   (`tmp/review/modes_switch.log`). Without audio, the fallback finds `force_heat` and then calls `set_heat`
   on the police director, which does not exist.
   - Do:
     - Drop the whole-tree method-name searches: mode_director.gd:155-170 and pursuit_session.gd:67-85, which
       are also a duplicate. CONTRACTS §3 says groups/Events/Game.
     - Put RivalDirector in group `rival_director`.
     - Ask the police unit for group `police_director` + `start_pursuit(heat)` + `set_spawn_enabled(bool)`.
     - Until then: emit the infraction first, then call `force_heat(heat)` on the node that has both
       `force_heat` and `remove_all_units`.
   - Verify (main.tscn): 1 s after `start_mode(&"pursuit", {})`, the police director reports `pursuit.heat == 3`
     and `state == &"chase"`.
10. **Police are never switched back on.** A race sets `spawn_enabled=false`; free and pursuit never reset it.
    My run: race → free gives `spawn_enabled=false`; pursuit gives `spawn_enabled=false units=0`.
    - Do: every `start_mode` sets it explicitly: free true, pursuit true, race `options.police`.
    - Verify: a race → free → pursuit switch test; at least 1 police unit within 20 s of the pursuit start.
11. **The countdown freeze is undone.** Started the way the menu does it (`menu._on_request_mode(&"race", …)`),
    the log shows `player.freeze=false` at COUNT 3/2/1/0: menu.gd:359 calls `_freeze_car(false)` after
    `start_mode`, so the player can jump the start. Separately, a race stopped during the countdown leaves the
    player frozen.
    - Do: hold the car through the COUNTDOWN every frame (re-freeze, pinned at its slot with zero velocity),
      release it in `_start_race`, and unfreeze in `RaceSession._exit_tree()`.
    - Verify:
      - Through the menu path: freeze=true at every countdown tick, false one frame after GO.
      - 完美起步 still triggers with the throttle pressed 0.2 s before GO.
12. **5 rivals per race, not 6.** SPEC §3 says "vs 5 rivals", the brief goal says "5 rival Roadster-class cars",
    and the dossier §7.7 budget is "player + 5 rivals". Keep the 6-name roster, pick 5 per race
    (deterministic from route + difficulty).
    - Verify: `racers.size() == 6`.
13. **Rebuild the gate visuals.** The user asked that every texture and material be refined (贴图纹理什么都要细化).
    ART.md §5 says holograms are additive, scanlined, with a chromatic edge and jitter. The brief says
    "simple glowing ring meshes or the props sky-lane gate scaled".
    - What is wrong now:
      - The gate is 3 BoxMeshes with a flat unshaded colour at energy 2.4, which reads as near-white cyan on
        screen.
      - The 60 scanlines sit on BoxMesh face UVs.
      - There is no frame, texture, number or text.
      - The 6 cm strip box cuts through the pillars.
      - **The first gate is not amber.** `tint` is an `instance uniform`, but race_gate.gd:34 calls
        `material.set_shader_parameter`. See `captures/review/modes/review_modes_r1_cp0_cp0.jpg`: CP0 is
        pale cyan.
    - Do:
      a) **Pylons:** physical, 0.7×0.7×7.5 m, with library textures (diff+nor+rough, e.g.
         `game/assets/props/street/sky_lane_gantry_prop_galv_dark_*`). Add a 0.25 m plinth with hazard
         chevrons #F2C200/#111113, bolts, and LED edge strips in the tint at E3 energy (4-5).
      b) **Top beam:** an LED board texture generated into `game/modes/textures/`.
         - Checkpoints: 「检查点 3/8 CHECKPOINT」 in Noto Sans SC.
         - Start/finish: 「起点 START」/「终点 FINISH」 on a checker band.
      c) **Curtain:** a plane across the opening with `SH_hologram` (MaterialLibrary) or the verified
         recipe in ref/art/DOSSIER.md §4.6/§7.3:
         - 220 world-height scanlines.
         - 2 px RGB split at the edges.
         - 12 Hz glitch slots at 8 %.
         - ±10 % jitter at 24 Hz.
         - A fresnel edge.
         - Energy 3.5, alpha ≤ 0.35 in the middle.
      d) **Ground:** a Decal with chevrons at 0.6 opacity, instead of the box.
      e) **Tints:**
         - Start/finish #FFB000, checkpoints #19E6FF.
         - The player's NEXT gate at full energy, the one after at 40 %. Passed gates fade out in 0.5 s.
         - Set the tint with `set_instance_shader_parameter`, or use a plain uniform.
      The props `sky_lane_gate.glb` (Ø 14 m ring, SH_hologram) is the style anchor.
    - Verify with captures (HUD hidden) at three distances:
      - 5 m: plinth stripes, bolts and the pylon texture are readable.
      - 20 m: the board text is readable at 1600×900.
      - 100 m: the gate still reads and the curtain is not blown out (no pixel above 95 % white).
14. **Add rival liveries.** The user's texture demand and the brief's "different paints/visuals" call for them.
    Right now the rivals are the hero car with a flat recolour. Under city light, #1E9BD8 (浦江闪电) and
    #6A4BC8 (外滩幽灵) both read as blue (`captures/review/modes/review_modes_r1_pack_t12_0.jpg`).
    - Do: per-racer Decals parented to the body, with textures generated into `game/ai/rivals/textures/`:
      - A 0.55 m racing-number roundel on both doors and the hood: #F2F6FF disc, #111113 number.
      - The handle on the side skirts in Noto Sans SC Bold, 0.18 m.
      - A two-tone stripe in a 35 % darker shade of the paint.
      - One parody sponsor per car (东方霓虹 / 浦江电讯 / 申城快递).
    - Give 外滩幽灵 a paint from a different hue family (e.g. pearl black #1A1B22 with violet stripes).
    - Verify: a 3/4-front close-up of all six cars at 3 m in city light. No z-fighting, and no decal swims on
      the moving body.
15. **Clean up the records handling.**
    - `test_modes._test_records()` writes to the REAL `user://records.cfg`. After a test run, the player's file
      held `test_route=110.0` and `best_score=500.0` (see `~/Library/Application Support/Godot/app_userdata/
      飞驰申城 SKYRUSH/records.cfg`).
    - Do:
      - Make the path a constructor argument; tests use `user://test_records.cfg` and delete it.
      - Guard `get_section_keys` with `has_section`. A file with only [scores] logs errors today.
      - Save the free-roam high score when it is beaten, not only as a side effect of `build_results()`,
        which is lost if the player quits from free roam.
    - Verify: the md5 of records.cfg is unchanged by a full test run.
16. **Make `start_mode` robust.** My run:
    - An unknown mode returns false but leaves `Game.mode=bogus` and kills the running session.
    - `_start_race` without a route returns true with no session.
    - An unknown route id silently races bund_sprint.
    - With `--skip-menu` and no `--mode`, no session runs, so free roam has no score.
    - Do: validate before `_stop_session()`; return false with a readable warning; warn about route
      fallbacks; start `Game.mode` (free) when the menu is skipped.
    - Verify: test_modes covers each case.
17. **Code rules.**
    - Name the magic numbers as consts with units:
      - rival_brain.gd:
        - :91-92 (0.6, 1.15, 14.2)
        - :122-127 (0.5, 4.0, 0.35, -2.0, 8.0, 0.15, 0.25)
        - :148 (25.0)
        - :175-176 (0.00045, 0.0004, 0.9; these belong in the presets)
        - :188 (5.0)
        - :197 (60.0, 1.25)
        - :228-231 (6.0, 0.35, 8.0)
        - :250 (2.0, 8.0)
        - :262/264/284/286/300/303 (1.0, 2.0, 3.0, 3.2)
        - :343-344 (0.05, 5.0, 12.0)
        - :355-364 (30.0, 100.0, 6.0)
        - :383-386 (0.4, 0.6, 0.16)
      - rival_director.gd:64 (4.5, 0.5) and :141 (25.0)
      - race_session.gd:121 (7)
      - race_gate.gd:84-86
    - Split rival_brain.gd (389 lines) BEFORE adding 7/8, e.g. `rival_speed.gd` and `rival_avoid.gd`.
      No file may exceed 400 lines.
    - Remove shadowing: the `throttle`/`brake` locals in `tick()`, `offset` in `setup()`.
    - Type the loop in race_gate.gd:56.
18. **Performance: measure and fix.**
    - Sandbox A/B (`tmp/review/modes/rr_perf.gd`): 0.7-0.8 ms per physics tick without rivals,
      1.9-2.2 ms with 6. That is +2.4-2.8 ms per 60 Hz frame, over dossier §7.7 (car controllers ≤ 1.5 ms per
      frame for 18 cars).
    - In the city, three O(rivals × traffic) loops run per tick over ~110 traffic cars.
    - Do:
      - Precompute a speed profile per route with a backward pass,
        `v[i] = min(v_corner[i], sqrt(v[i+1]² + 2·a_brake·STEP))`, so `speed_limit_ahead` is O(1) instead
        of ~117 samples per tick.
      - Turn `straight_ahead` (which scans up to the whole 12-100 km line) into a table.
      - Cull the traffic list (see 5).
      - Tick at 60 Hz beyond 150 m from the camera (§7.7).
    - Verify: report the A/B in ms/tick in status, sandbox and city. Target ≤ 0.35 ms per tick for 5 rivals.
19. **Make the tests catch real bugs, and replace the evidence.**
    - test_race_flow (sandbox, 2 laps) must assert:
      - exact finish times;
      - `cp_count` per racer;
      - 0 rescues;
      - at least 6 passes;
      - at least 60 % drifting corners;
      - 0 rival-rival contacts over 800 N·s;
      - a spread under 15 s.
    - Add `test_real_route.gd` (see 1) and `test_mode_switch.gd` (main.tscn: 9, 10, 11, 16). Each run must stay
      under 300 s wall.
    - Your real-city evidence `captures/modes/realrace_t30_0.jpg` is a blank dark frame at 0 km/h. Deliver
      real-city captures:
      - the grid during the countdown (2-wide, behind the amber start gate);
      - the pack at GO+10 s;
      - a pass;
      - a drift;
      - the results screen.
      List the paths in status/modes.md.
20. **File these requests in status/modes.md, with the numbers.**
    - (to world) The racing lines are 5-33× the checkpoint chain:

      | route | racing line | checkpoint chain |
      |---|---|---|
      | bund_sprint | 12,634 m | 2,398 m |
      | elevated_sprint | 91,965 m | 2,789 m |
      | grand_loop | 102,777 m | 15,159 m |
      | lujiazui_ring | 53,933 m | 4,983 m |
      | river_loop | 38,282 m | 6,888 m |

      The loops are not closed (end gaps 313-423 m). Every route has exactly 1 grid slot, placed on cp0; you
      need ≥ 6 slots behind cp0. The lines themselves are world-r1 MUST-FIX 6.
    - (to police) the group and API in 9.
    - (to core) `RaceRoute.circuit` and `Events.race_standings_changed`.
    - Process (lead note, mandatory): scratch files go under `tmp/modes/` only. Round 1 used /tmp/dbg_test.gd,
      game/ai/rivals/tests/dbg_test.gd and game/modes/tests/dbg_test.gd.

## SHOULD-FIX
- Free roam only scores police takedowns (`kind != &"police"`, free_session.gd:71). Count &"rival" and
  &"traffic" too. The comment promises "a streak" but there is none: add the §3.5 streak (10 s window) or drop
  the claim.
- Change the toast "BUSTED" to 「被捕 BUSTED」 (dossier §8.4, Chinese first).
- N₂ only fires when the rubber band wants more than top speed (rival_brain.gd:357). Use it on straights over
  250 m whenever the tank is full (§6.2); suppress it only when leading the player by more than 150 m.
- The aim point uses `right_at(offset)` instead of `right_at(offset + look)` (rival_brain.gd:182-183). On
  curves the lateral offset rotates; every rival rode +1.6…+2.8 m right of its personal line in the sandbox.
- Expose `ModeDirector.standings()` → `[{name, position, lap, gap}]` for the HUD until the core signal
  exists. The HUD showed 「1ST/7」 for a player parked at the back of the grid.
- The gate trigger is 9 m tall, so a sky lane over a gate misses it. Use 14 m, or count by line progress.
- `_rival_cars()` can append null (`car as RivalCar`). The player's result name is "" in the sandbox.

## Verified OK
- `check --only=res://ai/rivals/,res://modes/` → 26 files, 0 failed, 0 engine errors, 0 warnings.
- The 5 tests pass as written:

  | test | result |
  |---|---|
  | rubber band | 11 PASS |
  | modes | 22 PASS |
  | pursuit | 10 PASS |
  | rival driving | 0 failures |
  | race flow | 10 PASS (waited 198 s) |

- Rubber band exactly per §6.2: 1−0.00045·gap / 1+0.0004·gap; ranges [0.88,1.03], [0.93,1.06], [0.97,1.10];
  off at ≥ 90 %.
- Look-ahead L = 18 + 1.25 v, PD Kp 2.2 / Kd 0.25, v_corner = √(A/κ).
- Mistake intervals match §6.2. Observed on normal: 3 per rival in 195 s.
- 3-2-1-GO in 1.0 s steps. race_countdown, race_started, checkpoint_passed, lap_completed and race_finished
  carry the contract payloads.
- With the direct `--mode=race` start, the player is frozen through the countdown (stub run: freeze=true at
  COUNT 3..0).
- Six fictional racers with Chinese handles. Muted paints go through the paint instance uniform and show in
  the sandbox grid.
- `start_mode(mode, options)` is documented in status.
- The records API (best time, best lap, high score) is in place.
- Ownership: every Write/Edit in jobs/modes/log.jsonl is inside game/ai/rivals/**, game/modes/** or
  status/modes.md. No scratch is left behind.
- Static typing everywhere except race_gate.gd:56.
- For the lead, not modes: the Bund grid area itself runs at 5 fps in free roam with no race (player spawned
  at -41,0,0.6), against 26 fps at the free spawn. That is a world/buildings performance issue.

## Evidence
- `tools/godot.sh check --only=res://ai/rivals/,res://modes/` → `CHECK 26 files, 0 failed, 0 engine errors`.
- The 5 unit tests (commands from status/modes.md) → all PASS. Logs: `tmp/review/modes_drive.log` and
  `tmp/review/modes_flow.log`.
- Afterwards, `records.cfg` contains `[times] test_route=110.0 [laps] test_route=30.0 [scores] best_score=500.0`.
- Real-city race, full stack, started the menu's way (`tmp/review/modes/rr_city_race.gd`):
  - Command: `tools/godot.sh test …/rr_city_race.gd -- --timeout=280 --skip-menu --route=bund_sprint`.
  - Output lines: `ROUTE bund_sprint len=12634 cps=6 grid=1 end_gap=1385.6`;
    `COUNT 3 t=0.01 player.freeze=false` (likewise for 2, 1, 0); `SCRIPT ERROR … '_blocker_lateral' …
    (previously freed)` ×3,324.
  - Rivals 龙柱猎手, 陆家嘴之刃 and 夜行电鳗 sat at 0 m/s for 16-20 s. 23 s of game time took 270 s wall.
  - Log: `tmp/review/modes_city_bund.log`.
- Same route with `--stub=traffic,police,audio,fx,damage,hud,menu --limit=90`: the run ends with
  `END t=90.0 wall=61 finished=false`. All 6 rivals are at 0 m/s, progress 8-20 m, with 14 rival-rival contacts
  (`tmp/review/modes_city_stub.log`).
- Sandbox, 2 laps, with metrics (`--sandbox --route=sandbox_loop`):
  - Before the overwrite: `夜行电鳗 … fin127.6`. After: `RESULT … "time": 188.98`.
  - 浦江闪电 stuck at `next2 cp8` from t=67 s to t=127 s.
  - `drifts={霓虹小燕:1}`.
  - `contacts={"rr": 4, "rp": 2}`, rescues 2, mean lateral +1.6…+2.8 m.
  - Log: `tmp/review/modes_sandbox_metrics.log`.
- Mode switch (`tmp/review/modes/rr_switch.gd`, log `tmp/review/modes_switch.log`):
  - `first node with set_heat(): AudioDirector (res://audio/audio_director.gd)`
  - `after free: spawn_enabled=false`
  - `pursuit +3.0s: police.heat=1 state=chase units=0`
  - `bogus mode returned false Game.mode=bogus session=<null>`
- Performance: sandbox `PERF … wall 0.7-0.8 ms per physics tick` without rivals vs `1.9-2.2 ms` with 6
  (`tmp/review/modes/rr_perf.gd`).
- Windowed fps at the same camera:

  | setup | fps |
  |---|---|
  | race | 4-5 |
  | race, traffic and police stubbed | 16 |
  | no race, player at the free spawn | 26 |
  | free roam, player spawned on the grid | 5 |

- Captures in `captures/review/modes/`:
  - `review_modes_r1_cp0_cp0.jpg`: CP0 is cyan, not amber; the gate is a box frame.
  - `review_modes_r1_cp0_pillar_close.jpg`: a flat, washed-out pillar with no texture.
  - `review_modes_r1_sb_grid.jpg`: the sandbox grid.
  - `review_modes_r1_cg_t1_0.jpg`: real city, the player last in a single file at the kerb, gate about
    60 m ahead.
  - `review_modes_r1_pack_t12_0.jpg`: the blue and violet rivals read the same.
  - Contact sheets: `worker_sheet_s.jpg`, `city_sheet_s.jpg`, `sb_sheet_s.jpg`, `cg_sheet_s.jpg`,
    `pack_sheet_s.jpg`, `cp0_sheet_s.jpg`.
- Route lengths vs checkpoint chain: the python one-liner over `data/city/city.json` (numbers in MUST-FIX 20).

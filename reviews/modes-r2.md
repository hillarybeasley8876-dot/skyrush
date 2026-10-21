# modes review round 2 — VERDICT: FAIL

## Scores (0-10): function 4, visual/feel 3, code 4
- function 4: the mode switch, the police link, the countdown hold, the records file and the 5-rival field now
  work, and so do sprint detection and the sandbox race. Against that:
  - Lead note M-INT1 is not done. A race at boot cannot start (`start_mode` → false), and your own
    `test_real_route` now crashes.
  - On a real route only 1 of 5 rivals finishes in 260 s.
  - When the player finishes first, the race ends at once and every rival gets an invented time.
  - Each gate the player passes causes a stack overflow: 552,960 engine error lines in a 10 s run.
- visual/feel 3:
  - The pylon textures point to files that do not exist, so the pylons are flat pale boxes.
  - The LEDs are unshaded, so they cannot glow.
  - The board text faces away from the drivers.
  - All 5 number-roundel textures and all 8 board textures are 100 % transparent.
  - The livery stripes are flat quads floating across both wheels.
  - Round 2 produced no new real-city captures.
- code 4: the typing and doc comments are good. Against that:
  - race_session.gd is 452 lines (the limit is 400).
  - A setter recurses forever, and a local variable shadows the `curtain` member.
  - The "60 Hz far tick" does nothing.
  - The tests pass while the engine reports errors, and they check with 200 s and 137 % tolerances.
  - Lead process rules were broken again.

## MUST-FIX
1. **Lead note M-INT1: wait for the world (mandatory).**
   - The problem: `ModeDirector._ready` → `start_mode` → `_place_player_at_spawn` (mode_director.gd:127) and
     `_pick_route` (:108-120) call WorldBase while the city is still building (it takes 47-50 s).
   - Evidence:
     - main.tscn logs `WARNING: [world] the API was used before the city was built … _place_player_at_spawn
       (mode_director.gd:127) ← _start_free ← start_mode ← _ready (mode_director.gd:41)`.
     - Before the build, `start_mode(&"race", {route: bund_sprint})` returns **false** ("unknown route
       'bund_sprint'" + "no route to race on"), so `--mode=race` at boot never races.
     - Your `test_real_route` now dies at test_real_route.gd:40: `Invalid access to property or key 'racers' on
       a base object of type 'Nil'`, then TEST TIMEOUT (exit 2).
   - Do:
     - `start_mode` checks the mode name synchronously. When `not Game.world_built()`, it stores the request,
       shows the loading state, does `await Game.world_ready()`, and then starts. It returns true for an
       accepted request.
     - Every WorldBase call in modes and rivals runs only after the build: `_pick_route`, the spawns,
       `RivalDirector.start_race`, `grid_slots`, `RivalGrid.ground_spot`, `checkpoint_offsets`. If one runs
       too early, `push_error`.
     - In test_real_route, `await Game.world_ready()` first. Add a case: start_mode before the build → the
       countdown starts after the build.
   - Verify:
     - `tools/godot.sh shot --scene=res://main.tscn --skip-menu --mode=race --route=bund_sprint --times=70`
       shows the grid and countdown.
     - The log has 0 lines `[world] the API was used before the city was built`.
2. **A full race on a real route does not complete. This is the brief's acceptance item.**
   - My run: `tmp/review/modes/r2_city_metrics.gd`, with world + player + rivals + modes and the race started
     after `world_ready`. Route bund_sprint: 10 gates, line 5,982 m, sprint.
   - At t=260 s only 浦江闪电 had finished (244.8 s):
     - 龙柱猎手 sat at 1,661 m of progress for 160 s while driving at 12-60 m/s.
     - 夜行电鳗 sat at 2,575 m.
     - 陆家嘴之刃 sat at 3,565 m at **100→122 m/s**. That is above the 91.7 m/s hard cap, so it is falling.
     - There were 70 wall hits of 800 N·s or more, and only 5 rescues.
   - The second run, with positions:
     - From t≈100 s, 3-4 rivals are at **y −54…−58 m** on a surface (car y minus ground height = 0.0), and
       **54-236 m from their line point**. Examples: (468,−58,−473) and (−112,−58,−62).
     - The marshal never picks them up: `_update_stuck` (rival_brain.gd:216-229) only fires below 2 m/s, or
       when the car is more than 10 m off the line and also below 10 m/s.
   - Do:
     a) Add a watchdog that rescues a car when any of these is true:
        - `travelled` grows less than 15 m in 4 s;
        - `|cross| > OFF_LINE` for more than 2 s, at any speed;
        - speed > 1.05 × the hard cap;
        - |car.y − line y| > 4 m with |cross| > 6 m.
     b) Rescue onto the road. Use `Game.world.nearest_road_transform()` + `RivalGrid.ground_spot()`, not
        "line point + 0.35 m" (rival_brain.gd:248-250).
     c) Add a line audit to test_real_route:
        - Walk the racing line in 5 m steps.
        - Print every stretch where |line.y − ground_height| > 1.5 m, or the nearest road is more than 6 m
          away, with its offsets and positions.
        - File the stretches as a world request with the numbers. Suspect first: the tunnel stretch at
          x 170…700, z −120…−540, y −58.
   - Verify: test_real_route (after world_ready, stubs as in your status) on bund_sprint, then
     lujiazui_ring and river_loop. Each must show:
     - all 5 rivals finish, with winner→5th ≤ 25 s;
     - ≤ 2 rescues per rival;
     - no rival above 92 m/s;
     - ≤ 5 wall hits of 800 N·s or more per rival.
3. **Rivals still collide at the real-route start.**
   - Two runs on bund_sprint had 3 and 4 rival-rival hits of 800 N·s or more in the first 10 s. The round-1
     target is 0.
   - Do:
     - For the first 300 m, each rival keeps the lateral offset of its grid column.
     - No pass starts until the gap to the car ahead is more than 12 m.
     - `rival_avoid` keeps at least 2.5 m of lateral clearance to every rival within 15 m ahead.
   - Verify: 0 such contacts in the first 10 s, in 3 consecutive test_real_route runs.
4. **When the player finishes first, the race ends at once; the 15 s wait is dead code.**
   - `_finish_racer` calls `_finish_race()` for the player (race_session.gd:289-294). The state becomes
     FINISHED, so `_check_finished` (:315-319) never waits.
   - Evidence: in `tmp/review/modes/r2_player_finish.gd` the player passes all 8 sandbox gates. The state
     right after is 3 (FINISHED). All 5 rivals are `finished:false` with **gaps of 146.7-233.4 s in a 4.4 s
     race**.
   - Do:
     - Keep the session RUNNING after the player finishes.
     - End it when every rival is home, or 15 s later.
     - Compute the DNF gap as the remaining distance divided by the racer's average speed over the last 10 s
       (at least 5 m/s). Remaining distance means: to the last gate on a sprint; on a circuit, the laps left
       plus the rest of this lap. Today `_estimated_gap` ignores the laps left.
   - Verify with a new test that feeds the player's gates:
     - the state stays RUNNING for up to 15 s;
     - every rival that crosses inside the window gets `finished:true` and its real time;
     - DNF gaps are under 60 s on the sandbox loop.
5. **`RaceGate.fade` recurses forever.**
   - The setter (race_gate.gd:42-44) calls `_apply_fade`, which assigns `fade` again (:284).
   - Evidence:
     - test_race_flow: 240 `SCRIPT ERROR: Stack overflow` and 61,440 `ERROR: Stack underflow! (Engine Bug)`
       lines in a 249,641-line log. It still prints "RACE FLOW TESTS OK".
     - My scratch: 2,160 overflows and 552,960 underflow lines (a 120 MB log) in 10 s. `gates[0].fade` stays
       1.00 and the curtain stays visible, so passed gates never fade.
   - Do: assign the backing field inside the setter and apply the side effects there. `_apply_fade` must not
     assign `fade`.
   - Verify:
     - 0.6 s after the player passes gate 0: `fade == 0.0` and the curtain is hidden.
     - The log has 0 lines containing "Stack".
6. **The gate's lights and text do not work.**
   a) **The `curtain` member is never set.** race_gate.gd:130 `var curtain := MeshInstance3D.new()` shadows
      the member (:48). So `set_energy` (:278-279) and the fade (:286-287) never reach the curtain; my scratch
      prints `curtain member null: true`.
      - Do: rename the local and assign the member.
   b) **The LEDs cannot glow.**
      - `_led_material()` (:181-188) is SHADING_MODE_UNSHADED with emission energy 4.5.
      - Godot does not apply EMISSION to unshaded materials (godotengine/godot#11036, by design). The strips
        render as flat tint at ≤ 1.0: no bloom past the glow threshold of 1.1 (ART §4), and every
        `set_energy` level is invisible. See `captures/review/modes/r2_pylon5_crop.jpg`: a flat amber bar
        with no halo.
      - Do:
        - Use per-pixel shading, albedo #111113, emission = tint.
        - Energy: 4.5 for the player's next gate, 1.8 for the one after, 0.6 for the rest.
        - Change the energy on one material instead of building new materials on every call.
   c) **Drivers never see the board text.**
      - The Label3D sits at local z −0.195, rotated 180° (:231-232), with `double_sided=false`. It faces the
        race direction, so only a driver who has already passed the gate can read it.
      - `r2_city_gate20.jpg` / `r2_gate20_beam_crop.jpg` (taken from the grid, 20 m back) show a plain amber
        bar with no text. Your gate captures were taken from the exit side.
      - Do: put the text on the approach face, and mirror it on the exit face.
   d) **There is no finish gate.**
      - `_build_gates` (race_session.gd:90) only uses &"start" and &"checkpoint", so the last sprint gate reads
        「检查点 10/10」.
      - Do:
        - On a sprint, the last gate is 「终点 FINISH」.
        - On a circuit, gate 0 is 「起点/终点 START/FINISH」 with a 0.3 m black/white checker band.
7. **Gate art: refine every texture (贴图纹理什么都要细化). Today it is a flat box gate.**
   - **The pylon textures do not exist.**
     - `GALV_DIFF/NOR/ROUGH` point to `res://assets/props/sites/sky_lane_gantry_prop_concrete_*`. There are no
       such files, and `_apply_texture` returns silently.
     - So the pylons are a flat #C6CCD4 box, metallic 0.75: the palest surface in the night frame
       (`r2_pylon5_crop.jpg`). That breaks ART §2 (the car is the brightest object) and §8 (grey-box, near
       white).
     - Do:
       - Use `res://assets/props/textures/prop_galv_dark_{diff,nor_gl,rough}.jpg` (they exist), with a grime
         or streak layer from `assets/textures/Leaking016A` / `SurfaceImperfections001`.
       - When a texture is missing, `push_error` instead of failing silently.
   - **The BoxMesh UVs stretch the texture.** A BoxMesh uses a 3×2 UV atlas, so each 0.7 × 7.5 m pylon face
     shows a ⅓ × ½ crop of the texture: about a 7:1 vertical stretch. The chevrons on the plinth top are "Z"
     distorted.
     - Do: `uv1_triplanar = true` with `uv1_scale` in metres. That is ≥ 512 px/m for props (ART §5).
   - **Shape.**
     - The pylons have no bevels, flange or bolts. r1 asked for bolts; none are there.
     - Do:
       - A chamfered pylon with corner trims.
       - A 0.02 m base flange.
       - 8 bolts of Ø 0.04 m per plinth.
       - A cable duct up to the beam.
       - An LED channel with a dark backing and mounting brackets (ART §5 neon).
   - **The LED board.**
     - Today the whole beam box glows amber at 0.35 (`r2_gate20_beam_crop.jpg`).
     - The 8 generated `game/modes/textures/gate_board_*.png` are 100 % transparent (1 colour, (0,0,0,0)) and
       never used.
     - Do:
       - A galvanised beam housing.
       - A separate front panel: a dark #0A0F1E face with the text as LED dots at a 6 px pitch, plus an
         emission mask.
       - The checker band from 6d.
   - **No runtime writes into `res://`** (gate_textures.gd:140, rival_livery.gd:241-249). `res://` is
     read-only in an export.
     - Do: generate the textures once with a deterministic script, commit them, and delete the blank files.
   - **The curtain.**
     - The "2 px RGB split" scales red/blue brightness by about 1.6 % (race_gate.gdshader:40-42); it is not
       a channel offset.
     - Do:
       - Sample the scanline and edge pattern per channel at ±chroma_px·fwidth(UV.x).
       - Fix the header, which still says 220 lines while `scan_lines = 120`.
       - Use energy 3.5 with alpha ≤ 0.35 in the middle (r1 recipe); it is 0.8 today.
   - **The ground chevrons have stair-step edges** (`r2_pylon5_crop.jpg`).
     - Do: draw them anti-aliased at ≥ 512 px/m, with mipmaps.
   - Verify with captures in the CITY (main.tscn after world_ready, HUD hidden, 1600×900):
     - 5 m: the galvanised texture, bolts and undistorted plinth chevrons are visible.
     - 20 m **from the grid side**: the board text is readable.
     - 100 m: the gate reads, and no curtain pixel is above 95 % white.
     - The same set from the exit side.
8. **The livery is broken** (`captures/review/modes/r2_livery_crops.jpg`, `r2_city_livery*.jpg`).
   - **The number roundels are invisible.** All 5 `game/ai/rivals/textures/livery_number_*.png` are 256×256
     and fully transparent. `_texture()` loads an existing file before it renders (rival_livery.gd:170-175),
     so they stay blank for good. Neither the disc nor the number appears on the doors or the hood.
   - **The stickers float off the body.** They are flat quads at `half_width + 0.006` (:44-89) on a curved
     body. The 3.4 m stripe hangs in the air and crosses **both wheels** at hub height.
   - **The text cannot be read.**
     - The handle is about 0.18 m of grey on orange.
     - The sponsor is #FFD23F on #C8862A.
     - Neither is readable at 4 m.
   - Do:
     - Use Decal nodes parented to the car's visual root. A child Decal moves with the car; it does not swim.
       Give each a `cull_mask` layer used only by the body, a projection depth ≤ 0.25 m, and fades of 0.05.
       Or ask the shaders unit for a livery slot in `SH_car_paint`.
     - The stripe follows the shoulder line and stops 0.15 m before each wheel arch.
     - The roundel: a #F2F6FF disc with a #111113 number in Noto Sans SC Black, 0.55 m across, with a 0.03 m
       black ring. At least 1024 px per roundel.
     - The handle: Smiley Sans, 0.18 m, with an outline that contrasts with the paint.
     - Generate the textures offline, with ASCII snake_case names such as `livery_handle_r03.png`
       (CONTRACTS §1). Today the names are Chinese.
   - Verify in city light:
     - a 3/4-front shot at 3 m of each of the 6 cars, plus side views at 4 m;
     - nothing off the body, no z-fighting, and readable numbers.
9. **Performance is over budget, and the far tick does nothing.**
   - Numbers (`test_performance`, load average 12, not 40):
     - 0.828 ms/tick without the rivals and 3.739 ms with 5. That is +2.911 ms per physics tick, or 5.8 ms
       per 60 Hz frame.
     - The AI alone is **0.521 ms/tick: FAIL** against 0.35.
     - Dossier §7.7: car controllers ≤ 1.5 ms per frame for 18 cars.
   - Why the far tick is a no-op:
     - `FAR_TICK` (rival_director.gd:161-167) only skips `set_context()`, and `ctx` is one shared object
       anyway.
     - `RivalCar._physics_process` (rival_car.gd:50-55) still ticks the brain every physics frame.
   - Do:
     - The director ticks the brains. Rivals more than 150 m from the camera tick at 30-60 Hz and hold their
       last controls in between.
     - The `project()` window is ±(2·v·dt + 6 m) instead of ±60 m (61 segments per tick). Do a full
       re-search only when the car is off the line.
     - In `rival_avoid`, reject nodes with `distance_squared_to` before any other math. Refresh each rival's
       near list at 10 Hz.
     - Ask the vehicle unit for the §7.7 "2 wheel probes" mode for far AI cars.
   - Verify: on an idle machine (`uptime` printed in the log, load < 8), the AI costs ≤ 0.35 ms/tick and the
     5 rivals cost ≤ 1.5 ms/tick in total.
10. **The missed-gate net spams the log, and rivals drive around gates.**
    - `_check_gate` (rival_brain.gd:325-331) warns on every tick once it is past the threshold.
    - After a finish, the next gate becomes 0, which lies behind the car on a sprint. The result is
      **3,747 identical "浦江闪电 drove past gate 0"** warnings in one bund_sprint race, and 425 in the
      sandbox race_flow.
    - Real misses happen too: 霓虹小燕 missed gates 2/4/5/7 and 陆家嘴之刃 missed 4/5/7/8. So rivals drive
      past the visible gates.
    - Do:
      - Warn once per gate.
      - Set `next_gate = -1` when a racer finishes.
      - Within 40 m before each gate, pull the lane offset toward the gate centre.
      - Make the trigger as wide as the road plus 2 m.
    - Verify: bund_sprint ≤ 5 "drove past" lines per race; the sandbox has 0.
11. **The tests hide the bugs** (round-1 item 19 is not met).
    - **test_race_flow passes with errors.** It reports OK with 240 stack overflows, 61,440 engine errors and
      524 warnings.
      - Do: add a logger (see `res://tools/error_counter.gd`, `OS.add_logger`). FAIL on any SCRIPT ERROR or
        ERROR.
    - **The finish-time check is hollow.** "The results hold the real finish times" accepts a result up to
      **200 s** after the last lap time (test_race_flow.gd:166).
      - Do: store `elapsed` at each racer's final `lap_completed`, and assert |result.time − stored| < 0.05 s.
    - **The drift ratio is not a ratio.** It reads "137 % of 49".
      - Do: count per (rival, corner) whether at least 1 drift happened.
    - **test_real_route crashes.** See 1.
    - **Tests asked for in round 1 are still missing:**
      - a synthetic open route, 4 gates on a straight 1 km line, where every rival finishes (r1 #2);
      - a forced rescue 5 m before a gate (r1 #4);
      - the `_avoid_offset` test: 200 m → 0.0; 15 m ahead at +1.0 → −3.5 (r1 #6);
      - at least 1 police unit within 20 s of the pursuit start (r1 #10);
      - the player finishes first (item 4).
    - Verify: run each new test against the current bug once, and note the FAIL in status. Then fix the bug
      and show the PASS.
12. **The evidence is not real** (round-1 item 19).
    - Round 2 has no new real-city captures. `realrace_t30_0.jpg`, `freecity_t8_0.jpg` and
      `pursuitcity_t10_0.jpg` date from round 1 (00:38-01:22).
    - The status descriptions do not match the images:
      - `race_grid.jpg` is an empty sandbox road with **no car on it**, not "the six painted rivals in two
        columns".
      - `race_t18_0.jpg` and `race_t133_0.jpg` each show one car on a straight.
      - `gate5_t6_0.jpg` shows one thin pylon from far away.
    - All gate shots use the demo's own bright ambient (energy 1.5, race_demo.gd:59-62), not the game's
      lighting.
    - Deliver these, in the CITY after world_ready, at 1600×900:
      - the grid during the countdown, from behind (2-wide, with the start board readable);
      - the pack at GO+10 s;
      - a pass;
      - a rival mid-drift at 8-10 m with a slip angle of 15-35°;
      - the results screen;
      - the 6 livery shots (item 8);
      - the gate at 5/20/100 m (item 7).
    - Describe each image truthfully in status.
13. **Code rules.**
    - **The file limit.** race_session.gd is **452 lines**; the limit is 400 (CONTRACTS §3). Split it before
      the item-4 change, for example into `race_gates.gd` (build/energy/fade) and `race_results.gd`
      (order/results/gaps).
    - **Magic numbers left in the logic:**
      - rival_speed.gd:60-61 (45.0, 0.6, 1.15, 14.2);
      - rival_speed.gd:72-76 (0.9, 0.00045, 0.0004 — move them into the presets, as r1 asked);
      - rival_speed.gd:101 (2.0) and :111-113 (30.0, 100.0);
      - rival_livery.gd:46-88 (0.62, −0.35, 1.25, 0.32, 0.15, 0.78, 0.85, 1.7, 1.6, 0.46, −0.2, 3.4);
      - race_gate.gd:110 (0.4), :222-231 (64, 0.011, 16) and :268 (0.35);
      - race_session.gd:247 (0.4).
    - **Untyped loops.** `for side in [-1.0, 1.0]` at rival_livery.gd:44/59/72/85. Use a typed
      `Array[float]` const.
    - **File names.** Use ASCII snake_case names (item 8). `var brain_usec` is declared between functions
      (rival_car.gd:39); move it to the top.
    - **Comments and status that do not match the code.** Correct each:
      - "galvanised pylons with the library textures";
      - "the generated board texture is the glow of the pixels behind the letters";
      - "220 scanlines";
      - "a fresnel edge" (the shader uses a horizontal UV ramp);
      - "ticks the far rivals at 60 Hz";
      - "the number roundel on the doors and the hood";
      - "walked back along the racing line" (rival_grid.gd:61-73 steps straight back from one road
        transform).
14. **Process (lead notes, mandatory).**
    - **Scratch files.** `/tmp/dbg.gd` (Oct 20 04:53, round 2) is still on disk. Round 2 again wrote
      `/tmp/dbg_test.gd` and `game/*/tests/dbg_test.gd`. Scratch belongs in `tmp/modes/` only, and is deleted
      after use.
    - **Background runs.** Godot ran in the background:
      `nohup bash -c '… tools/godot.sh test …' > tmp/modes/perf.log 2>&1 &` and then `sleep 400`, several
      times. The lead rule is no Godot or Blender in the background. Run in the foreground with `--timeout`.
    - Verify:
      - `ls /tmp/dbg*` finds nothing;
      - the job log has no `nohup` or `&` Godot runs;
      - you have read the `## INT` sections of `reviews/modes-lead.md` and done them (M-INT1 = item 1).

## SHOULD-FIX
- **`ModeDirector.standings()`.** The "gap" field returns `racer.progress`, the distance covered
  (mode_director.gd:158). Return a time gap to the leader.
- **Disk writes in free roam.** `FreeSession._add_score` saves records.cfg on every point once the high score
  is beaten, so every near miss writes to disk. Save at most every 5 s, at the end of the session, and on quit.
- **Tests that write the player's records.**
  - `ModeDirector.records` always uses `user://records.cfg`. Any test where the player finishes writes into
    the player's file: my scratch added `sandbox_loop=4.408…`, which I removed.
  - Add an option (`Game.option("records")`) for tests.
  - The file still holds `test_route=110.0/30.0` from the round-1 tests. Mention it to the lead for a
    one-time cleanup.
- **The grid on curves.** The grid steps straight back from the road transform at the start
  (rival_grid.gd:70-72). On a curved approach the rear slots leave the road. Walk the lane path back instead.
- **Livery generation stalls.** `RivalLivery.apply` renders up to 3 SubViewports per car at race start. That
  becomes a non-issue once the textures are generated offline (item 8).

## Verified OK
- **The static check is clean.** `check --only=res://ai/rivals/,res://modes/` → `CHECK 34 files, 0 failed,
  0 engine errors, 0 warnings`.
- **The quick tests pass:** test_rubber_band 11 PASS · test_modes 30 PASS · test_pursuit_mode 10 PASS ·
  test_mode_switch 9 PASS.
- **Round-1 items now fixed:**
  - r1 #9: the pursuit starts at heat 3 with police state `chase`.
  - r1 #10: a race turns the police off; free roam and pursuit turn them back on.
  - r1 #11: the player is held on the grid through the countdown, even when unfrozen; the perfect start fires.
  - r1 #12: 5 rivals per race (`racers=6`).
  - r1 #15:
    - The records path is a constructor argument.
    - The md5 of the player's records.cfg (`e9159bf6…`) is unchanged by the 4 quick tests.
    - The sections are guarded.
  - r1 #16:
    - An unknown mode is refused and the session is left alone.
    - An unknown route falls back to the first route, with a warning.
- **Sprint vs circuit.**
  - bund_sprint → `sprint=true laps=1 gates=10`. A rival finished the sprint at 244.8 s.
  - The finish time is written once, and finished rivals cruise at 60 %.
  - The sandbox 2-lap field is within 14.7 s, with 13 passes and 0 rival-rival contacts.
- **The real-route start rolls** (r1 #1, partly fixed):
  - GO+3 s speeds were 18.0-30.1 m/s in both runs.
  - Every rival passed cp1 and cp2.
  - The grid has 2 columns about 6 m apart, with 8 m rows and a 4 m stagger.
- **No freed-object error spam** (r1 #5). A full-stack city race (main.tscn) had 0 SCRIPT ERROR lines from
  `ai/rivals/` or `modes/`.
- **The `_avoid_offset` bias is gone.** It returns 0 when neither side is blocked.
- **The speed profile is a backward pass** (rival_line.gd:215-230), so the speed lookup is O(1). The straight
  table and the traffic cull (60 m) are in.
- **Round-1 SHOULD-FIX items done:**
  - 「被捕 BUSTED」;
  - free roam scores police, rival and traffic takedowns, with the 10 s streak;
  - `standings()` exists;
  - the gate trigger is 14 m tall;
  - N₂ fires on straights over 250 m and is suppressed beyond a 150 m lead;
  - the aim point uses `right_at(offset + look)`.
- **The requests are filed in status:** the world line table, the police API, vehicle landing and brake, menu
  records, and core signals.
- **Ownership is respected.** Every Write/Edit in jobs/modes/log.jsonl is inside `game/ai/rivals/**`,
  `game/modes/**` or `status/modes.md`. `tmp/modes/` is cleaned.
- **Not counted against modes:**
  - test_rival_driving could not run (11:37-11:46). The vehicle unit was mid-edit:
    `Parse Error … res://vehicle/modules/car_air.gd`, so `ArcadeCar` did not resolve.
  - The world currently skips about 290 road tiles ("not imported yet").

## Evidence
- `tools/godot.sh check --only=res://ai/rivals/,res://modes/` → `CHECK 34 files, 0 failed, 0 engine errors,
  0 warnings`.
- **Quick tests.** Logs: `tmp/review/modes_r2_{test_rubber_band,test_modes,test_pursuit_mode,switch}.log`.
  Results as above.
- **test_race_flow** (`tmp/review/modes_r2_flow.log`, 62 s wall, exit 0):
  - Key lines: `RACE FLOW TESTS OK (0 failures)`, `60 % of the corners are drifts (137 % of 49)`.
  - Also in the log: 240 × `SCRIPT ERROR: Stack overflow … @fade_setter (race_gate.gd:43/44) ↔ _apply_fade
    (:284)`, 61,440 × `Stack underflow`, and 524 × `drove past gate` (425 of them for 浦江闪电, gate 1).
- **test_real_route** (`tmp/review/modes_r2_real.log`, exit 2): `TEST TIMEOUT after 300 s … TEST ERROR
  …test_real_route.gd:40 … Invalid access to property or key 'racers' on a base object of type 'Nil'`.
- **test_performance** (`tmp/review/modes_r2_perf.log`, load average 11.9):
  - `PERF without the rivals 0.828 ms per tick, with 5 rivals 3.739 ms, the rivals cost 2.911 ms`
  - `FAIL the AI of the rivals costs less than 0.35 ms per tick (0.521 ms)`
- **Real-route race, after world_ready** (`tmp/review/modes/r2_city_metrics.gd`):
  - Run 1, log `tmp/review/modes_r2_city.log`:
    - `BEFORE world_ready: start_mode(race) -> false` (warnings: unknown route, no route).
    - `ROUTE bund_sprint line=5981 m chain=3527 m cps=10 end_gap=1939.0`.
    - `GO+3s speeds: 龙柱猎手 30.0 霓虹小燕 21.6 陆家嘴之刃 29.3 夜行电鳗 18.0 浦江闪电 18.0`.
    - At t=260:
      - contacts `rr_10s 3, rr 6, rw 70`, `rescues=5`;
      - 浦江闪电 `fin244.8`, and the other 4 not finished;
      - 陆家嘴之刃 at `3565m 122m/s`.
    - 3,747 × `浦江闪电 drove past gate 0`.
  - Run 2, with positions (`tmp/review/modes_r2_city2.log`), at t=100-150:
    - Rivals at `pos(468,-58,-473) d_line105.5 y-ground-0.0`, `pos(511,-54,-194) d_line164.6`,
      `pos(-171,-58,-197) d_line235.8`.
    - `rr_10s 4`, `rw 19`, `rescues=1`.
- **Player finishes first** (`tmp/review/modes/r2_player_finish.gd`, `tmp/review/modes_r2_pfinish.log`):
  - `curtain member null: true`
  - `LED shading_mode=0 (0=unshaded) emission_energy=4.5`
  - `player finished=true time=4.4 session state right after = 3`
  - `gate0 fade=1.00 curtain visible=true`
  - 5 × `RESULT … "finished": false … "gap": 146.7…233.4`
  - 2,160 × `Stack overflow`
- **Texture content** (PIL): `livery_number_{5,7,12,23,31}.png` and `gate_board_*.png` → `unique colours: 1
  (0,0,0,0)`. The galvanised texture files named in race_gate.gd:24-26 do not exist (`ls`: No such file).
- **City captures** (main.tscn full stack, race started after world_ready, `tmp/review/modes/r2_city_shot.gd`),
  in `captures/review/modes/`:
  - `r2_city_grid.jpg`, `r2_city_livery.jpg`, `r2_city_livery_side.jpg`, `r2_city_gate20.jpg`,
    `r2_city_pylon5.jpg`, `r2_city_pack10.jpg`;
  - the sheets `r2_sheet_city1.jpg` and `r2_sheet_city2.jpg`, and the crops `r2_livery_crops.jpg`,
    `r2_gate20_beam_crop.jpg` and `r2_pylon5_crop.jpg`;
  - the worker's captures `r2_sheet_worker.jpg`;
  - the reference comparison `r2_ref_vs_ours.jpg` (NFS Heat cp05 vs our gate and livery).
  - Boot log: `WARNING: [world] the API was used before the city was built … _place_player_at_spawn
    (mode_director.gd:127)`.
- **Process:**
  - `ls -la /tmp/dbg.gd` → `803 B, Oct 20 04:53`.
  - jobs/modes/log.jsonl has `nohup bash -c '… tools/godot.sh test …' &` with `sleep 400`, and `cat >
    /tmp/dbg.gd`.

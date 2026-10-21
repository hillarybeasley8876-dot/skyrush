# menu review round 4 — VERDICT: FAIL

Reviewer: lead art director (Opus). Last round. The user demand stands: **贴图纹理什么都要细化**. Checked in three
**real boots** of `main.tscn` (windowed, keys only, 1600×900 → 2200×943 → 1600×1000, load average ≈ 34), a headless
probe, the six unit tests and the worker log. Most r3 must-fixes are really closed (fast back, overlay stack, results
columns, chevron/arrows, glow ghosts, double connect, prefs file). Still failing: quit-to-menu does not re-park the car,
an engine error on every pause, leaked screens, free roam starts on the promenade steps, the title beats were never
re-authored, the loading skyline misses most of the r3 targets, and the main list is unreadable over bright façades.
Lead notes: tests `extends Node` OK, no background runs OK, `tmp/menu/` deleted OK, CORE CHANGE OK (the tests use
`user://test_skyrush_menu.cfg`; the player's `skyrush_menu.cfg` was not touched by any run of mine).

## Scores (0-10)
- **function: 5** — keyboard and gamepad navigation, mode start, camera hand-back, the fast confirm→back, the overlay
  stack and `--skip-menu` work. Against it: the re-park after a session is broken (claimed done), one engine error per
  pause, covered screens leak, free roam starts the car on the pavement facing stone benches, 122 ms hitch on 竞速赛.
- **visual/feel: 4** — the panels, the controls page, the results table and the 21:9 / 16:10 layouts are clean.
  Against it: three rear-view title beats on a generic side street with little sky (not the Bund, not night), a
  flat-vector loading skyline with the progress bar drawn across the tower bases, and a menu list with no backing.
- **code: 6** — typed, every file ≤ 400 lines (max `menu.gd` 390), consts named. Against it: an unguarded
  `Array.back()`, screens that can never free, a 40k-node tree walk on every push, dead code, `Variant` access to the
  unit's own classes in the demo, 12 Writes over the 120-line limit.

## MUST-FIX

1. **CRITICAL: quit-to-menu leaves the car where the session ended (the r3 re-park "done" claim is false).**
   - Evidence (`tmp/review/menu_r4/drive2.log`): after 自由驾驶 → 2 s throttle → Esc → 退出到主菜单 → 返回主菜单:
     `frame 0..5 player=(-105.9069, -0.027169, -337.925) frozen=true spot=(-105.9069, 0.0, -312.6259) has=true`, and
     `1 s later … player=(-105.9069, -0.027169, -337.925)`. A manual `stage.park_the_car()` one frame later works at
     once: `manual park_the_car -> player=(-105.9069, 0.0, -312.6259)`.
   - First boot (`drive.log`): `main again … player=(-106.0543, -0.027076, -366.2372)`. That is **0.39 m from the
     lane centreline** `j_bund_zhongshan_e1_st_d0_ew_4_…_st_d0_ew_4_1_back0` (python over `lanes.json` 15:25), in
     the middle of a junction. The title stage frames a granite wall and a ceiling, and the car is not in the shot:
     `r4_main_again.jpg`, `r4_main_2200x943.jpg`, `r4_main_1600x1000.jpg` (`sheets/r4s_results_again_s.jpg`, `r4s_219_s.jpg`).
   - Likely cause: `menu.gd::_on_request_main_menu()` (l. 236–245) runs `_stacks.clear_front()` →
     `front_end.close()` → `_freeze_car(false)`. Then `front_end.repark()` calls `reset_to()` on a **dynamic** body
     and freezes it (KINEMATIC) in the same frame, right after `Game.set_paused(false)` re-activated the physics
     server. The teleport is lost: the car even rolled 0.2 m on. Every working park (boot, my manual call) happened
     on an already-frozen body.
   - Fix:
     - `front_end.repark()`: freeze first, then `park_the_car()`.
     - Then `await tree.physics_frame` twice and check `Game.player.global_position.distance_to(stage.parking_spot())
       < 0.1`. If not, park again once.
     - Print `[menu] re-parked at … (moved X m)`.
   - Verify:
     - Real boot: free → 3 s throttle → pause → quit → main menu. The player is ≤ 0.1 m from the spot 0.5 s later,
       with zero velocity, and the title beat shows the whole car.
     - Make it a step of `menu_demo.gd` (`--menu-keys=`) and paste the log line in status.

2. **An engine error on every pause and on every pause → results** (`check clean` acceptance).
   - Evidence:
     - `ERROR: Can't take value from empty array` at `push_overlay (res://ui/menu/menu_stacks.gd:79)`, reached from
       `_open_pause (menu.gd:189)` and from `_on_request_screen (menu.gd:207)`.
     - Probe: 10 × Esc pause/resume → `errors_delta=10`.
     - Real boot: `pause … errors_delta=1`.
     - `test_stacks` and `test_results` print the same error 1 and 7 times — and still say PASS.
   - Cause: `var below: Control = overlay.back()` runs when the overlay is empty (the first pause, or after
     `_clear_overlay_now()`).
   - Fix:
     - `var below: Control = null if overlay.is_empty() else overlay.back()`.
     - Delete the duplicate `replace_overlay()` (l. 89, unused).
     - The menu tests must fail on any engine error: add a `menu_test_base` Logger (you already have `ErrorCounter`) and
       `_expect(errors == 0, "no engine errors")` at the end of every test file.
   - Verify: the 6 tests print no `ERROR:` line; real boot pause / pause→results adds 0 errors.

3. **Covered screens are never freed (a node leak per race / pursuit start).**
   - Evidence (probe): `R leak before close: … ScreenMain(vis=false,pm=4), ScreenRaceSetup(vis=true,pm=0)` →
     `R leak after close 1.2s: layer=[ScreenMain(vis=false,pm=4)] old_main_valid=true`. The next main menu is named
     `ScreenMain2`, and the hidden one is still there at the end of the probe.
   - Cause:
     - `_hide_if_covered()` sets `PROCESS_MODE_DISABLED`.
     - `menu_stacks.gd::_remove()` then only calls `play_exit()`, whose fade runs in `menu_screen.gd::_process()`. A
       disabled node never processes, so it never reaches `queue_free()`.
     - This hits every `clear_front()` with a covered screen: 开始比赛, 开始追捕, and any mode start from a sub-screen.
       Each leak is a hidden main menu with its logo and five glow SubViewports.
   - Fix: in `_remove()`, a screen that is covered (or not visible) is freed at once (`queue_free()`); only the
     visible top screen plays its exit.
   - Verify: a test that runs main → race setup → `close_front_end()` → 1 s → `front_layer.get_child_count() == 0`,
     and the next main is named `ScreenMain`. Same for pursuit.

4. **自由驾驶 starts the car on the pavement, facing stone benches: after 3 s it is beached on the promenade steps.**
   - Evidence:
     - `drive.log`: `drive mode=free cam=/root/Main/ChaseCamera/Camera kmh=111.5`.
     - `r4_drive.jpg` and `r4_pause.jpg` (`sheets/r4s_fast_drive_s.jpg`, `r4s_pause_s.jpg`): the car sits on the
       granite steps of the promenade, and the chase camera is wedged between a trunk and a granite wall.
     - The brief: "gets the player into a drive in seconds".
   - Cause: the title spot is on the pavement, 4.9 m from the nearest lane (by design). `_start_mode(&"free")` only
     unfreezes the car there.
   - Fix:
     - When the front end closes into **free roam**, place the car first with
       `Game.world.nearest_road_transform(Game.player.global_position)`, facing the lane (the same call as
       `Game.respawn_player()`), while it is still frozen. Then unfreeze it.
     - Race and pursuit keep the grid of the modes unit.
   - Verify (real boot): 自由驾驶 + 3 s throttle → the player is within 1.75 m of a lane centreline, at ≥ 80 km/h, and
     touches no static body. Capture it.

5. **The title beats were never re-authored (r1 #7, r3 #3d): three rear views of a generic side street.**
   - Evidence: `r4_title_beat{0,1,2}.jpg` and `r4_title_xfade.jpg` (`sheets/r4s_title01_s.jpg`, `r4s_title2x_s.jpg`),
     and `sheets/r4s_title_vs_sh01_s.jpg` (beat 0 over `sh01_bund_gold_facades.jpg`).
   - `title_stage.gd` `BEATS` (l. 22–29) are the demo's candidates a / d / b: (0, 1.7, 11), (6, 2, 9) and (2, 1.1, 7).
     All sit behind the car, at FOV 44–48.
   - What the frames show:
     - The car is small and seen from the rear in every beat. The wedge nose, canopy and profile never show.
     - Sky fills only a corner in beats 0 and 2. No crown stands against the sky, except a cut-off green roof in beat 1.
     - A flat, untextured dark-green median strip fills the lower-left third. A tree trunk stands 1–2 m behind the
       car in beat 2.
     - 飞驰申城 sits on a bright canopy.
     - It reads as early evening on a side street, not as the Bund at 1 a.m.
   - r1 asked for: low 3/4 front (h 0.9 m, r 6.5 m, FOV 38); side profile with the façades (h 1.4 m, r 9 m, FOV 32);
     high toward Pudong (h 6 m, r 14 m).
   - The landmarks are right there (city.json pois):
     - 江海关 (−158, top 79 m, −328) is 54 m WSW of the spot (−105.9, 0, −312.6).
     - 汇丰 (−168, −268) is WSW of the spot.
     - The Pearl (637.5, −634.9) is at bearing 67° ENE, across the river (river bank x ≈ −74 at z −332).
   - Fix (offsets relative to the car, which faces −Z; aim = car + (0, 0.6, 0) unless noted):
     - A **front 3/4**: camera (+4.6, 0.9, −4.6), FOV 38. The nose fills the frame, with 汇丰 / 江海关 behind.
     - B **profile**: camera (+9.0, 1.4, 0.0), FOV 32, looking west. The right flank, with the Bund road and 江海关 behind.
     - C **Pudong**: camera (−13.0, 6.0, +5.6), FOV 40, aim car + (6, 2.5, −2.6). The car in the lower third,
       with the river and the Lujiazui skyline in the upper half.
     - Run them through the existing line-of-sight validation (`camera_offsets`). If one is blocked, move along its
       radius, not to a rear view.
     - Keep the 9 s / 1.2 s rhythm. Keep the façade request to bund/world in status.
   - Verify (the 3 beats, side by side with `sh01` and `sh02_bund_bluehour_aerial.jpg`):
     - the whole car is 20–40 % of the frame width;
     - a crown (江海关, 汇丰 or the Pearl) shows against the sky in ≥ 2 beats;
     - sky ≥ 20 % in beat C;
     - no trunk or pole crosses the car;
     - the grass strip covers ≤ 10 % of the frame.

6. **Loading skyline: most r3 #4d targets missed, and the progress bar is drawn across the tower bases.**
   - Evidence: `sheets/r4s_skyline_vs_sh03_s.jpg` (a 1:1 crop of `r4_load95.jpg` over `sh03_lujiazui_led_ads.jpg`) and
     `r4s_loading_s.jpg`.
     - Bar position: `loading_screen.gd` `PROGRESS_TOP 600` (box 600–700, virtual 1080) collides with `skyline.gd`
       `HORIZON 0.58` (y 626), so "55% 正在规划车道" sits in the river band.
     - River: reflections cover **3.2 %** of the river band (pixels brighter than the water median + 30, y 535–625).
       r3 asked for 40–60 %. `skyline_river.gd` draws `STREAKS 9` × `STREAK_WIDTH 3.0` px, which can never reach its
       own `COVER_SHARE 0.5`.
     - Pearl: a 1 px spire and two dotted outline circles; no lit spheres.
     - Shanghai Tower: two crossing sine strokes with no body. It reads as a DNA helix.
     - Brightness: the landmarks are darker than the bar and the tip text (ART §11: second-brightest after the logo).
     - Missing detail: no LED façades or roof signs (sh03 has a full LED façade, red signs and a blue screen), no haze
       or glow. Fills are flat and the windows sit in regular dotted rows.
   - Fix:
     - Bar: put the progress band below the Bund row (bar top ≥ 0.84 × 1080 + 24 = 931), so nothing is drawn over
       the skyline.
     - Pearl: filled spheres, lower `#FF2BD6` r ≥ 18 px and upper `#9B5CFF` r ≥ 12 px, with an additive two-pass
       glow, 12–16 chasing LED dots per sphere, three legs, a top sphere and a spire.
     - Shanghai Tower: a filled tapered body `#0B1024` → `#141A2E`, with its two edges twisted 120° over the
       height, 3–4 spiral `#7FD4FF` lines and a lit crown.
     - LED façades: at least 2 generic towers with an animated LED façade (scrolling bands or one large real word,
       e.g. 申城 / 霓虹, in `#FF2BD6` / `#19E6FF` / `#FFB000`), plus 3–5 small red or blue roof signs.
     - Haze: a `#5A1F4F` light-pollution gradient over the lower 25 % of the sky and a soft glow behind each
       landmark.
     - River: 6–10 jittered streaks per landmark, 4–14 px wide, α 0.25–0.6, in its colours, broken into shimmering
       dashes.
   - Verify:
     - A 1:1 crop next to `sh03` and `sh02`.
     - River coverage ≥ 40 % (same measure).
     - The brightest pixels outside the logo are on the landmarks.
     - The bar touches no skyline pixel.

7. **The main-menu list and the title logo are hard to read over the lit scene** (acceptance "text crisp CJK").
   - Evidence: `r4_main.jpg`, `r4_fastback.jpg`, `sheets/r4s_crops.jpg`.
     - The list sits straight on the floodlit façade with no backing: the rows are a `Color(1,1,1,0.035)` film.
     - Sampled text/background contrast of the unselected rows and their EN sub-labels: ≈ **2.1–2.8:1**
       (`r4_main.jpg`, x 75–195, y 285–311).
     - On the title, 飞驰申城 sits on the bright tree canopy in all three beats.
   - Fix (keep the rows flat):
     - Main menu: a left scrim behind the logo and the list, a horizontal gradient of panel glass `#0A0F1E` from α 0.78
       at x 0 to α 0 at x 760 (virtual 1080), full height.
     - Title: a top scrim (`#0A0F1E` α 0.55 → 0 over the top 300 px) behind the logo, next to the existing prompt band.
   - Verify (same sampling on the brightest beat, plus a 1:1 crop): row titles ≥ 4.5:1, sub-labels ≥ 3:1.

8. **A 122 ms hitch on 竞速赛 and a 40k-node tree walk on every push / pop.**
   - Evidence: `drive2.log`: `idle main 1 s worst_ms=20` → `push race_setup worst_ms=122` → `pop race_setup worst_ms=50`.
     `drive.log`: `find_by_script(hud) 20.14 ms found=true nodes=40455`.
   - Cause:
     - Every front push or pop emits `front_changed(true)` → `front_end.open()`.
     - `open()` calls `_set_hud_visible()` → `Bridge.find_by_script(tree.root, …)`, a recursive walk of the whole tree.
       It also calls `Bridge.set_music(&"menu")` and `_freeze_car(true)` again.
     - Race setup: `_build_list()` clears `_length_cache` (l. 140) on every open and calls `get_baked_length()` on every
       racing line. The r3 "cache the route lengths" is therefore not a cache.
   - Fix:
     - `open()` does its one-time work only when the front end really opens (the front stack was empty).
     - Keep the HUD CanvasLayer in a field and find it again only when it is invalid.
     - Fill a static per-world route-length dictionary after `Game.world_ready()`, a few routes per frame while the
       title runs.
   - Verify (rig, same run): the worst frame of each push and pop is ≤ 2× the idle worst frame. Write the numbers in
     status.

## SHOULD-FIX
1. **Gamepad-only scripted test.** My probe walked it fine: Start → pause → D-pad → A settings → D-pad → B → B, and
   results → A. The tests only press D-pad up/down, A and B on main / race. Add the full walk, including D-pad ←/→ on
   雨效 and asserting the row index.
2. **`loading_screen.is_done()` stall rule.** After 4 s without a progress event it shows the title even while the world
   is still building. Use `Game.world_built()` (CONTRACTS §4) and keep the stall rule only for `Game.world == null`.
3. **Small text.** Row sub-labels are 14–15 px and panel headers 13 px (virtual), so they render at 11–12.5 px at
   1600×900. Use ≥ 16 px.
4. **Main-menu logo.** 飞驰申城 at 37 px under glow gains 2.4 / 3.0 smears (2× crop in `r4s_crops.jpg`). For
   `font_size < 80`: no wide pass and a tight gain ≤ 1.2.
5. **`logo_glow.gd` doc and consts disagree.** The doc says radius 14 / 28; `TIGHT_RADIUS 8` and `WIDE_RADIUS 16` (r3
   asked for 14 px σ≈5 and 28 px). Make them agree.
6. **Dead code.** `menu_stacks.gd` `COVER_FADE` (l. 25) and `replace_overlay()` (l. 89); `menu_screen.gd::uncover()` (l. 108).
7. **The demo reads its own unit through `Variant`.** `menu_demo.gd` l. 124–147 uses
   `.get("front_end")/.get("stage")/.set(...)`. Use typed `menu.front_end.stage` (r3 #10d).
8. **Sprint routes.** 外滩冲刺 and 高架冲刺 are `kind: sprint` in `data/city/city.json`, but the setup offers laps and
   shows 每圈 / 全程. `RaceRoute` has no `kind`: request it (core / world) and hide the laps row for sprints.
9. **Process.** 12 Writes went over the 120-line limit this round (`logo.gd` 250, `title_stage.gd` 317, `test_menu.gd`
   314, `skyline_lujiazui.gd` 240, `row.gd` 149, …), and there was one `sleep 90`.
10. **Exit leaks.** `test_stacks` and `test_layout` end with "2 resources still in use" and RID leaks. Re-check after #3.

## Verified OK
- **Static check:** `CHECK 52 files, 0 failed, 0 engine errors, 0 warnings`. Every file is ≤ 400 lines (max `menu.gd`
  390), statically typed, with no untyped `var`.
- **Tests:** MENU 44 PASS, STACKS 26, RACE SETUP 13, RESULTS 22, TITLE STAGE 9, LAYOUT 82, all "(0 failures)". The
  hidden engine errors are MUST-FIX 2.
- **r3 #1 (fast confirm→back):** real boot `fastback … main_visible=true alpha=1.00` and one hint bar
  (`r4_fastback.jpg`).
- **r3 #2 (overlay stack):** pause → settings shows one panel and one hint bar (`r4_pause_settings.jpg`); the results
  replace the pause screen.
- **r3 #3 (first park):** derived after the build. `TITLE UP built=true`, then
  `spot=-105.9, 0.0, -312.6 clearance=4.91 m (searched in 148 ms)`. The current `lanes.json` gives 4.86 m to
  `st_d0_ns_1_back0`. Traffic could not be watched this round (see notes).
- **r3 #4a–c (loading):**
  - The first frame is opaque: the top-left 400×200 of `r4_load_first.jpg` has max RGB (13, 10, 27), the sky colour.
  - Labels read 正在规划车道 LANES and 就绪 READY.
  - The reveal, tip and grid run on the wall clock.
- **r3 #5 (layout):**
  - 飞驰申城 clears the list.
  - Results use CN / EN / value columns (`r4_results_free.jpg`).
  - Race setup fits 9 rows, and the 开始比赛 jump works ("已选路线 PICKED 外滩冲刺", 1 圈).
  - The 2200×942 and 1600×1000 captures show no overlap.
- **r3 #6–#8:**
  - The ▶ chevron and the cyan bar are drawn.
  - The ◂ ▸ arrows clear the values.
  - The disabled TARGET row is dimmed.
  - Rows are flat; panels keep the glass.
  - The title logo glow has no displaced copies (1:1 crop).
- **r3 #9:** no "already connected" error after settings ↔ controls.
- **r3 #10:**
  - `Prefs` is read-only with `--quality=`, and the tests use their own file. The player's `skyrush_menu.cfg` is
    unchanged (mtime 11:00) after my runs.
  - `test_menu.gd` is 313 lines, and the stick-left test exists.
  - The rig waits for the world and the title (240 s).
- **r3 #11:** 43 captures in `captures/menu/` at three aspects.
- **Title frame rate (acceptance ≥ 60):** beat 0 / 1 / 2 average 67.3 / 70.0 / 69.7 fps at load ≈ 34 (worst frame
  95 / 50 / 50 ms; 617–755 draw calls).
- **`--skip-menu`:** `front=[] overlay=[] mode=free cam=/root/Main/ChaseCamera/Camera hud_visible=true`.
- **Hand-back:** after 自由驾驶 the chase camera and the HUD come back (111.5 km/h after 3 s).
- **Navigation:** keyboard-only works in the real boot. My gamepad-only probe passes: Start → pause, A, D-pad, B, and
  results A → resumed.
- **Ownership and process:**
  - Every round-4 Write/Edit in the worker log is under `game/ui/menu/**` or `status/menu.md`.
  - `tmp/menu/` is deleted.
  - No background runs.

## Evidence (from /Users/minimax/m/skyrush; scratch `tmp/review/menu_r4/`, captures `captures/review/menu/`)
- `tools/godot.sh check --only=res://ui/menu/` → `check.log`.
- `tools/godot.sh test res://ui/menu/tests/<6 files>` → `test_*.log`. The engine errors are in `test_stacks.log` and
  `test_results.log`.
- **Probe** (`tools/godot.sh test …/tmp/review/menu_r4/probe.gd` → `probe.log`):
  - `R leak after close 1.2s: layer=[ScreenMain(vis=false,pm=4)] old_main_valid=true`;
  - `R start->pause … errors_delta=1`;
  - `R churn 10x pause/resume: overlay children=0 errors_delta=10`;
  - `R pad B -> overlay=[] paused=false`.
- **Real boot 1** (`slots.py heavy` + `test_host` windowed, `drive.gd` → `drive.log`):
  - `TITLE UP built=true`;
  - `find_by_script(hud) 20.14 ms … nodes=40455`;
  - `beat0 fps_avg=67.3 …`;
  - `drive … kmh=111.5`;
  - `pause … errors_delta=1`;
  - `main again … player=(-106.0543, -0.027076, -366.2372) spot=(-105.9069, 0.0, -312.6259)`.
- **Real boot 2** (`drive2.gd` → `drive2.log`): the re-park frames 0–5, `manual park_the_car -> player=(-105.9069, 0.0,
  -312.6259)`, and the push / pop worst frames. Boot 3 (`--skip-menu` → `skip.log`).
- **Lanes** (python over `game/world/data/lanes.json`, 15:25): the spot is 4.86 m from `st_d0_ns_1_back0`; the
  post-session car is 0.39 m from a junction lane.
- **Routes:** checkpoint-polygon length vs the shown lap — grand_loop 9.13 vs 41.73 km, elevated_sprint 4.88 vs
  27.81, river_loop 6.21 vs 19.16, bund_sprint 4.30 vs 7.08, lujiazui_ring 1.36 vs 3.19.
- **Captures:**
  - `r4_load_first` / `r4_load{40,70,95}`;
  - `r4_title_beat{0,1,2}`, `r4_title_xfade`;
  - `r4_main`, `r4_race`, `r4_race_picked`, `r4_pursuit`;
  - `r4_settings_rain`, `r4_controls`, `r4_fastback`, `r4_drive`;
  - `r4_pause`, `r4_pause_settings`, `r4_results_free`, `r4_main_again`;
  - `r4_{main,race}_{2200x943,1600x1000}`, `r4_repark_manual`, `r4_skip_menu`.
  - Sheets in `sheets/r4s_*_s.jpg`: the title next to `sh01`, the skyline next to `sh03`, and the 1:1 crops.
- **Worker log** (`jobs/menu/log.jsonl` from line 12195): edited paths, 12 Writes over 120 lines, one `sleep 90`.

## Notes for the lead (other units)
- **traffic / ai common:** boot 1 failed to compile `res://ai/common/lane_hash.gd:165` ("Cannot infer the type of obj")
  and `traffic_car_driving.gd:103`, so there was no traffic. Boot 2 watched no traffic. The title clearance to the
  traffic could not be re-measured this round; the lane clearance (4.86 m) was.
- **world:**
  - The racing lines are 1.6–5.7× longer than their checkpoint polygons (41.73 km for 申城大环线).
  - Boot 2 failed to compile `world/build/prop_occupancy.gd:118` ("Cannot infer the type of world"), and `world.gd`
    with it. Boot 3 built 0 routes.
- **world / roads:** the median grass is a flat, untextured dark-green plane (ART §5). It fills a third of the title
  frames.
- **bund / world:** the landmark POIs (江海关, 汇丰) are prisms. The menu request for real façades stands.
- **core:** `RaceRoute` lacks the `kind` (sprint / race / pursuit) that `city.json` has.

# menu review round 3 — VERDICT: FAIL

Reviewer: lead art director (Opus). The user demand stands: **贴图纹理什么都要细化**. This round was checked in a
**real boot** (main.tscn, async world, keys only) at 1600×900, 1600×1000 and 2200×943. Lead notes: tests
`extends Node` (OK), scratch cleaned (OK), but captures were run in the background and polled with
`sleep 580/590` (lead rule: no Godot in the background), and the new CORE CHANGE (10-20 10:20) is violated by
the tests (item 10a).

## Scores (0-10)
- **function: 5** — navigation, mode start, camera hand-back, retry options and subtitles work. Blocking: a quick
  confirm→back leaves a blank screen, the overlay stack still stacks screens, and in the real boot the title car
  is parked in a lane again and gets rammed.
- **visual/feel: 3** — logo spacing and the cross-fade are fixed. Against it: a placeholder loading skyline that
  shows the world through it, raw step names, title shots with no sky or crown, 飞驰申城 hidden under the main
  list, overlapping text on the results, no ▶ chevron, opaque "glass", double hint bars, a zoom-ghost logo glow.
- **code: 5** — typed and split, but a tween race, a double `connect`, a dead uniform, `test_menu.gd` 450 lines,
  `menu.gd` at the 400 limit, tests that miss every bug above and delete the player's prefs file.

## MUST-FIX

1. **CRITICAL: a quick confirm→back leaves the front end blank.**
   - Evidence: probe `R fastpop front=["ScreenMain"] main.visible=false process_mode=4 alpha=0.0 hints_front=0`.
     Real game `captures/review/menu/r3_fast_back.jpg` (DOWN, ENTER, BACKSPACE one frame apart): no menu at all,
     yet `state front=["ScreenMain"] selection=1` — the player navigates blind.
   - Cause: `menu_stacks.gd::_cover()` starts a 0.18 s tween that ends with `base.cover()`. `_uncover()` never kills
     it, so it hides the screen again (`visible=false`, `PROCESS_MODE_DISABLED`) after the pop; the new fade-in tween
     is bound to the now-disabled node and freezes. `test_menu._test_keyboard` does ENTER→BACKSPACE, but
     `_test_covered_screen_is_hidden` replaces the main screen with a fresh one, so the bug is never seen.
   - Fix: `menu_screen.gd` owns `var _cover_tween: Tween` and `var _covered: bool`; `begin_cover()` / `begin_uncover()`
     `kill()` the running tween before starting a new one; the end callback hides only if `_covered` is still true.
   - Verify (test): push race_setup, pop after 1, 3 and 6 frames, wait 0.5 s → main `is_visible_in_tree()`,
     `modulate.a == 1.0`, `process_mode == PROCESS_MODE_INHERIT`, exactly 1 visible HintBar. Same for
     settings→controls and pause→settings.

2. **The overlay stack still draws screens on top of each other (r2 #1, overlay half not done).**
   - Evidence: probe `R pause->settings overlay=["ScreenPause","ScreenSettings"] pause.visible=true hints_overlay=2`
     and `R pause->results … pause.visible=true hints_overlay=2`. In `r3_pause_settings_169.jpg` and
     `r3_results_free_169.jpg` the two hint bars print over each other ("↑↓ 选择选择 ←→ … 继续游戏 返回") and the
     dims stack (0.55 + 0.60), so the street is almost black.
   - Cause: `menu_stacks.gd::push_overlay()` never covers `overlay.back()` (`push_front` does).
   - Fix: the same cover/uncover (with the fix of 1) on the overlay stack. Results opened from pause → 退出
     replace the pause screen (its 继续 already resumes).
   - Verify: a test for pause→settings and pause→results: after 0.3 s pause is hidden and `overlay_layer` has exactly
     one visible HintBar; back shows pause again with one hint bar. Recapture both at the 3 aspects.

3. **Real boot: the Roadster is parked in a traffic lane again and traffic rams it (r2 #3 regressed).**
   - Evidence (`tmp/review/menu_r3/drive.log`):
     - `R t=8.0 loading up, world_built=false player=(-115.0, 0.0, -300.0)`.
     - `R stage spot=(-115.0, 0.0, -300.0)`, i.e. `FALLBACK_SPOT`.
     - `nearest lane centreline 0.14 m (bund_zhongshan_e1)`.
     - `min_traffic=3.2 m` centre-to-centre at t=57.5 s: they touched.
     - `r3_race_219.jpg` / `r3_sheet_detail2.jpg`: a black traffic car is wedged into the Roadster, whose nose is up.
   - Cause:
     - `title_stage.gd::_ready()` runs `_derive_spot()` one frame after the loading screen is pushed. The world is
       still building (≈34 s here), so `get_lane_paths()` is empty and the stage falls back.
     - CONTRACTS §4 (10-20) requires `await Game.world_ready()` before any WorldBase call at start-up.
     - `front_end.open()` also parks the car while the loading screen is up.
     - `test_title_stage.gd` hides all this: its FakeWorld has lanes before the stage exists.
   - Real lanes at z −300 (`game/world/data/lanes.json`, 10:11; check them again, do not copy):
     - Bund northbound `bund_zhongshan_e1_0_fwd0/1/2`: x −121.45 / −118.16 / −114.87 (3.35 m wide).
     - Bund southbound `back0/1/2`: x −124.76 / −128.07 / −131.36.
     - A second street, `st_d0_ns_1`: x −110.19 (fwd0) and −107.05 (back0).
     - `NEARBY_RADIUS 40` takes that street in too. There is no 7.5 m gap between −114.87 and −110.19, so
       "outermost lane + 3.75 m" cannot work here.
   - Fix:
     - (a) Derive and park only after `Game.world_built()`: in `front_end.open()`, `await Game.world_ready()` first.
       Do not activate the stage camera while the loading screen is the top screen.
     - (b) Never park at an unvalidated point: delete `FALLBACK_SPOT` as a parking spot.
     - (c) Validate each candidate against every non-elevated lane within 40 m (centreline distance ≥ 3.75 m).
       - Search outward in 0.5 m steps on both sides, up to 20 m.
       - Require a down ray that hits ground at |y| < 0.3.
       - Require a 2.5 m sphere query that finds no static body (lamp, tree, wall).
       - Print the spot and its clearance. If nothing qualifies, take the best clearance and keep the
         `spawns.title` request in status.
     - (d) Re-author the 3 beats for that spot. Each beat shows the whole car and at least one façade crown or the
       江海关 clock tower against the sky (`ref/art/img/sh01_bund_gold_facades.jpg`). Today no beat shows any sky:
       beats 0 and 1 frame an uplit wall, beat 2 a grey floodwall (`r3_sheet_title.jpg`).
   - Verify:
     - Real boot: the spot is ≥ 3.75 m from every lane centreline; every node in `traffic` stays ≥ 4.5 m from the
       player for 40 s; no damage on the player.
     - Test: a FakeWorld that starts with `loading_fraction 0.3` and no lanes, then adds the lanes and emits
       `loading_progress(1.0)` 10 frames later. The car is parked only after that, with ≥ 3.75 m clearance.

4. **Loading screen in the real boot: the world shows through it, raw step names, frozen animation, placeholder art.**
   - Evidence (`r3_sheet_loading.jpg`, strip at 40 / 55 / 70 / 100 %):
     - (a) At 40 % (t 17.7 s) the half-built street, a façade and a car show through the skyline. The screen is
       still fading in: the 0.22 s fade runs on process delta, which is capped at ≈ 0.067 s per frame while the
       world builds at 1–2 fps.
     - (b) The status label prints the builder's phase ids: "blocks", "lanes", "furniture".
     - (c) The logo reveal crawls: "SK" at 40 % and at 55 %, "SKY" at 70 %, "SKYRU" at 100 %, after 34 s on screen.
     - (d) The skyline is a flat placeholder:
       - dark `#0A1024` shapes on `#1A1033`;
       - the Pearl is a rectangle and two dim circles;
       - 上海中心 and 环球金融中心 are plain trapezoids: no twist, no aperture;
       - Jin Mao is a stack of rectangles, and the Bund is 9 identical boxes;
       - every window uses the same polka-dot hash grid.
       ART §11 (10-20) says "never a uniform polka-dot grid": the landmarks must wear their LED signatures.
   - Fix:
     - (a) The boot loading screen is opaque from its first frame (no fade-in from the world).
     - (b) Map the labels:
       - terrain / roads / blocks / lanes → 正在铺设地形 TERRAIN / 正在铺设道路 ROADS / 正在生成街区 BLOCKS / 正在规划车道 LANES;
       - furniture / signals / sites → 正在摆放街道设施 STREET FURNITURE / 正在点亮信号灯 SIGNALS / 正在布置地标 LANDMARKS;
       - 读取城市数据 → 读取城市数据 CITY DATA; 就绪 → 就绪 READY;
       - anything else → 正在载入世界… LOADING WORLD.
     - (c) Drive the logo reveal, the tip timer, the grid scroll and the flicker from wall-clock time
       (`Time.get_ticks_usec()`), so they run at real speed when frames are sparse.
     - (d) Redraw the skyline per ART §11 and `sh02_bund_bluehour_aerial.jpg` / `sh03_lujiazui_led_ads.jpg`:
       - **Pearl**: three legs, magenta/violet spheres (`#FF2BD6` / `#9B5CFF`) with chasing LED dots, the small top
         sphere and a spire.
       - **Shanghai Tower**: a twisting taper (two curved edges offset ≈ 120° over the height), spiral LED lines and
         a lit crown.
       - **SWFC**: the trapezoid aperture cut out of the top and outlined blue-white `#CFE8FF`.
       - **Jin Mao**: 13 tiers with warm gold `#FFCF87` bands and a spire.
       - **Generic towers**: 15–30 % of the windows lit, in clustered floor bands; cool-white crown lines on half of
         them; red beacons blinking at 1 Hz.
       - **Bund front**: domes and the 江海关 clock tower, floodlit `#E9C98F`.
       - **River**: vertical reflection streaks in each landmark's colours, 40–60 % of the river band, jittered.
       - **Values**: sky `#05060F`, masses `#0B1024`–`#141A2E`, landmarks the brightest after the logo.
       - Every colour and proportion is a named const.
   - Verify:
     - A real-boot strip at 40 / 70 / 100 %. The first frame shows no 3D pixel: the max luminance of the top-left
       400×200 matches the sky colour ± 3.
     - The labels read in Chinese.
     - A side-by-side with `sh03_lujiazui_led_ads.jpg`.

5. **Overlaps the layout test cannot see (acceptance: "no overlap at 16:9/16:10/21:9").**
   - (a) **Main menu: 飞驰申城 is hidden under the first row at every aspect** (`r3_main_{169,1610,219}.jpg`,
     `r3_sheet_detail2.jpg`).
     - Cause: `logo.gd::_init` sets `custom_minimum_size = Vector2(0, 190)`. The 134 px rect of `main_menu.gd:51`
       therefore grows to 190 px, and the CN baseline (0.90 × 190) lands at y 227, below the list top at 214.
     - Fix: no fixed minimum in the widget. The logo returns its height from the font size (word ascent + gap +
       CN size), and the screen places the list at `logo bottom + 16`.
   - (b) **Results (free and pursuit): the labels run into the English names.**
     - Evidence (`r3_sheet_crops.jpg`): "擦肩而过"×"NEAR MISS", "撞毁车辆"×"WRECKS", "撞毁警车"×"TAKEDOWNS0". The
       labels are 4-character words in a 48 px rank column. The table also uses only ≈ 300 px of the 868 px panel.
     - Fix, stat rows: CN 22 px at x 16 in a 140 px column, EN 15 px dim at x 160, the value right-aligned 16 px
       from the row's right edge.
     - Fix, race standings: rank 56 px, the name expands, the time is right-aligned at the right edge.
   - (c) **Race setup: 返回 is cut off.** The 9 rows need 9×60 + 8×6 = 588 px, but the scroll box is 572 px, so 返回
     is cut by the panel bottom (`r3_race_169.jpg`), and nothing scrolls the selection into view.
     - Fix: call `ScrollContainer.ensure_control_visible(row)` on `selection_changed`, and size the panel so the 9 rows
       fit at 1080.
   - (d) **`test_layout.gd` prints no PASS line at all and only compares each label with its parent's width.**
     - Fix: per screen and size, collect the global rects of the visible Labels and logos. Assert that no two
       overlap and that all are inside the viewport. Assert and print the label count (> 0).

6. **The focus treatment is incomplete, and the choice arrows and disabled rows do not show.**
   - **No ▶ chevron.** `menu_item.gd:47` and `setting_row.gd:54` override `_draw()` without `super._draw()`, and
     `row.gd::_apply_focus()` never calls `queue_redraw()`. 4× crop: the selected 自由驾驶 has the bar but no ▶.
     The status claim "the drawn ▶ chevron" is false.
   - **The ◀ ▶ arrows are inside the value text.** Probe: `R rain value text x=[749, 768] arrows L=[750, 756]
     R=[760, 766]`. They are cyan on cyan, so invisible (crop of 雨效 "开").
     - Fix: the left arrow ends 8 px before the text, the right arrow starts 8 px after it. Use the 22 px
       `arrow_space` you already reserve.
   - **Disabled rows are not dim.** `set_enabled(false)` sets α 0.45, and `_apply_focus()` then overwrites it with
     0.75 / 1.0. The pursuit TARGET row looks like HEAT while the goal is 逃脱追捕.
     - Fix: `modulate.a = lerpf(UNSELECTED_ALPHA, 1.0, _focus) * (1.0 if enabled else DISABLED_ALPHA)`.
   - **Dead uniform.** Delete the unused `uniform float focus` (`glass_panel.gdshader:28`; r2 #6 asked for it).
   - Verify with 4× crops: the selected main row (▶), 雨效 reading "◀ 开 ▶", and the pursuit setup with goal = 逃脱追捕
     (TARGET at 45 %).

7. **The glass still reads as an opaque plate (r2 #6).**
   - Evidence: pixels of `r3_pursuit_169.jpg` inside the rows are (16,19,34)–(23,26,42), whether the scene behind is the
     grey wall (≈ 94,95,100) or the gold façade (124,68,17). That is ≈ 6–7 % see-through.
   - Cause: every row is itself a glass plate (`blur_amount 0.25`) that samples the screen copy taken before the UI,
     so a row shows ≈ 0.25 × 30 % of the scene and covers the panel's 30 %.
   - Fix: rows are not glass. `row.gd` draws a flat film without the screen texture: `Color(1,1,1,0.035)`, or
     `#19E6FF` at α 0.10 plus the bar when selected. The panel keeps tint α 0.70.
   - Verify:
     - The same sample: inside a row over the façade, R is ≥ 20 higher than over the grey wall.
     - Text `#F2F6FF` on the plate has contrast ≥ 4.5:1.

8. **The logo glow is still a zoom-ghost (r2 #2a).**
   - Evidence (`r3_sheet_xfade_logo.jpg`, bottom right, 1:1): the 4 passes scale the whole word ×1.04–1.18 around
     its centre, so the outer letters get displaced copies. The S has a magenta copy ≈ 30 px to its left, the H a
     cyan copy ≈ 30 px to its right, and 飞驰申城 shows double images.
   - Fix:
     - Draw the word once into a transparent SubViewport, blur it with a 2-pass separable gaussian (radius 14 px,
       σ ≈ 5) and tint it magenta → cyan.
     - Composite it under the crisp glyphs at α 0.6, plus a wider pass (radius 28 px, α 0.25). Do the same for
       飞驰申城 in cyan.
     - Keep the 2 px split.
     - `glyph_positions()` and `_draw_word()` must share one advance loop (today there are two copies).
   - Verify: a 1:1 title crop with a halo around every glyph and no displaced duplicates.

9. **Engine error every time the player comes back from 操作说明.**
   - Evidence: "Signal 'selection_changed' is already connected to … settings_screen.gd::_on_selection_changed"
     (probe and real boot).
   - Cause: `settings_screen.gd::_build_rows()` connects again on every `on_enter()`.
   - Fix: connect once, in `_ready()`.
   - Verify: a test that runs settings → controls → back ×3 and counts 0 engine errors.

10. **Tests, rules and the capture rig.**
    - (a) **The tests delete the player's saved menu prefs.**
      - `test_results.gd:72` and `test_race_setup.gd:55` call `DirAccess.remove_absolute(".../skyrush_menu.cfg")`, and
        the rain row writes that file.
      - Per the lead's CORE CHANGE (10-20 10:20), dev and test runs must not touch the player's saved state.
      - Fix: `Prefs.new(path)` with `user://test_skyrush_menu.cfg` in the tests. When the run has `--quality=`, Prefs
        does not read or write the player's file (the same rule as core `Settings`).
    - (b) **File size.** `test_menu.gd` has 450 lines (limit 400): split it (navigation / stacks / title + camera).
      `menu.gd` is at exactly 400: split it before adding 1–3 (e.g. move the input dispatch out).
    - (c) **Stick left.** Add the stick-LEFT test; r2 #5 asked for all 4 directions, and only down / up / right exist.
    - (d) **Capture rig.**
      - `menu_demo.gd` `TITLE_TIMEOUT := 30.0` is shorter than boot + world build (42 s here), so the scripted keys
        fire on the loading screen. Wait for `Game.world_built()` and the title, with a 240 s timeout.
      - Type the menu (`const Menu := preload("res://ui/menu/menu.gd")`, `as Menu`) instead of `menu.call("…")`.
    - (e) **Process (lead rule).** No `run_in_background` captures and no `sleep` over 60 s. Run one capture per
      screen in the foreground.

11. **Evidence (r2 #9, not done this round).**
    - `captures/menu/` still holds the 14 round-2 files (06:22–09:32), 16:9 only.
    - After 1–10, delete them and capture through key navigation in a real boot, at 1600×900, 1600×1000 and 2200×943:
      - loading at 40 / 70 / 100 %;
      - the 3 title beats and the 0 / 0.6 / 1.2 s cross-fade strip;
      - main, race, race with a route picked, pursuit, settings (cursor on 雨效), controls (keyboard and pad);
      - drive, pause, pause → settings;
      - results free / race / pursuit;
      - the frame after a fast ENTER → BACKSPACE.
    - Write the per-beat fps and the traffic clearance into status. My `captures/review/menu/r3_*` set shows the shape.

## SHOULD-FIX
- **Title frame rate.** Measured beat 0 / 1 / 2: 28.7 / 18.3 / 18.9 fps average, worst frame 73–75 ms, 906 / 1,319 / 390
  draw calls, 2.75 / 2.49 / 1.99 M primitives, at load average 15–25. Not ≥ 60; mostly the world's cost (W-INT4).
  - Run `--menu-perf` per beat on an idle machine (load < 8) and keep the menu's own cost ≤ 1 ms per frame.
  - The cross-fade does a GPU → CPU readback (`get_image()`) every 9 s. Measure the frame time at the beat change;
    if it is over 20 ms, cross-fade on the GPU (e.g. two SubViewport targets).
- **Re-park after quit-to-menu.** Back in the menu the car stays where the player quit
  (`player=(-115.0, -0.03, -343.2)`). Re-park it at the validated spot.
- **One row pattern per list.** Settings mixes "画质 QUALITY" + CN subtitle rows with menu items ("操作说明" + EN
  sub-label).
- **Small text.** At 1600×900 the hint bar (17 px virtual), the credits (14 px) and the loading "提示 TIP" (14 px)
  render at 11–14 px. Use ≥ 18 px for hints and ≥ 16 px for the rest.
- **Cache the route lengths** in race setup. Every open re-bakes every racing line, and the world's lines raise
  "The target vector can't be zero" (race_setup.gd:194, 139 trace lines).
- **Dynamic access on your own code.** `menu_screens.gd:41 screen.set("kind", name)` and
  `controls_page.gd:111 chip.get("text")` → typed casts.
- **Magic numbers in drawing code** (`skyline.gd`, the logo underline 3 / 6 / 40 / 0.18 / 0.25, the
  `results_screen._add_row` positions) → named consts.
- **Esc on race and pursuit results** pops back into the finished session. Make back the same as 继续.

## Verified OK
- **Static check:** `tools/godot.sh check --only=res://ui/menu/` → `CHECK 41 files, 0 failed, 0 engine errors, 0 warnings`.
- **Tests:** `test_menu` 53 PASS, `test_race_setup` 13, `test_results` 22, `test_title_stage` 3 assertions, `test_layout`
  0 failures, all `extends Node` (lead rule).
- **Logo:** the spacing is fixed (running `x += advance`; "SKYRUSH" reads right at 150 px). 飞驰申城 is at 0.64×, the
  split is 2 px, the underline clears the Chinese, and REVEAL / SWEEP are named.
- **Cross-fade:** the beat change cross-fades; the strip `r3_title_xfade0-2.jpg` (0 / 0.6 / 1.2 s) shows the dissolve.
- **Stick:** one move per push for up, down and right; a 1 s hold gives 1 move + 6 repeats.
- **Retry and results:** retry keeps the route, laps and difficulty; the four pursuit subtitles are right; free-roam 继续
  resumes.
- **Race setup:** LAP and TOTAL are on two lines. Picking 高架冲刺 shows "已选路线 PICKED 高架冲刺" and the cursor
  jumps to 开始比赛 (`r3_race_picked.jpg`).
- **Camera hand-back:** after 自由驾驶 the camera is `/root/Test/Main/ChaseCamera/Camera`, the car does 108.3 km/h
  after 3 s and the HUD is up (`r3_drive.jpg`).
- **Loading timing:** in the real boot the loading screen was on top for 61 frames and 1.72 s of clamped time (≥ 60 and
  ≥ 1.5 s).
- **Layout and controls:** the pause panel is sized to its content. The slider grabber is a tick; key caps show
  ↑ ↓ ← → and Esc; A / B / X / Y have their colours; Start is a three-bar chip; hints are per screen.
- **Settings cursor:** kept after the controls page (7 → 7).
- **r2 #10:** the dead code, the `.call()` on the router and the duplicate list and tree searches are gone.
- **Ownership:** every round-3 Write/Edit is under `game/ui/menu/**` or `status/menu.md`, and `tmp/menu/` was deleted.

## Evidence (from /Users/minimax/m/skyrush; scratch in `tmp/review/menu_r3/`, captures in `captures/review/menu/`)
- **Check and tests:** `tools/godot.sh check --only=res://ui/menu/` and the five `tools/godot.sh test
  res://ui/menu/tests/*.gd` → all PASS (logs `tmp/review/menu_r3/test_*.log`).
- **Logic probe** (headless test_host, `logic.gd` → `logic.log`):
  - `R fastpop front=["ScreenMain"] main.visible=false … process_mode=4 alpha=0.0 hints_front=0` → item 1.
  - `R pause->settings … pause.visible=true hints_overlay=2` and `R pause->results … hints_overlay=2` → item 2.
  - `ERROR: Signal 'selection_changed' is already connected` → item 9.
  - `R back from controls: selection before=7 after=7` → OK.
  - `R rain value text x=[749, 768] arrows L=[750, 756] R=[760, 766]` → item 6.
- **Real boot** (`drive.gd` via `slots.py heavy`, windowed, keys only, sizes 1600×900 / 1600×1000 / 2200×943 → `drive.log`):
  - `R t=8.0 loading up, world_built=false player=(-115.0, 0.0, -300.0)`.
  - `R t=42.4 title up; loading frames=61 secs=1.72 world_built=true frac=1.0`.
  - `R stage spot=(-115.0, 0.0, -300.0)`; `nearest lane centreline 0.14 m (bund_zhongshan_e1)`;
    `min_traffic=3.2 (@RigidBody3D@6034 t=57.5)`.
  - `R beat0 fps_avg=28.7 worst_frame_ms=75 draws=906 prims=2754340`, `beat1 18.3 / 73 / 1319`, `beat2 18.9 / 73 / 390`.
  - `R after free cam=/root/Test/Main/ChaseCamera/Camera mode=free`, `R driving kmh=108.3`.
  - `R results state={ "overlay": ["ScreenPause", "ScreenResults"] … }`.
  - `R fast back state={ "front": ["ScreenMain"] … "selection": 1 }`, with the blank screen in `r3_fast_back.jpg`.
- **Lane data** (python over `game/world/data/lanes.json`): `(0.14, 'bund_zhongshan_e1_0_fwd2', x −114.87)`,
  `(3.21, …fwd1, −118.16)`, `(5.35, 'st_d0_ns_1_fwd0', −110.19)`, `(8.85, 'st_d0_ns_1_back0', −107.05)`.
- **Captures** (`captures/review/menu/`):
  - Per screen: `r3_{loading,title,main,race,pursuit,settings_rain,controls,pause,pause_settings,results_free}_{169,1610,219}.jpg`.
  - Title: `r3_title_beat{0,1,2}.jpg`, `r3_title_xfade{0,1,2}.jpg`.
  - Other single shots: `r3_loading_strip{0,1,2}.jpg`, `r3_race_picked.jpg`, `r3_controls_pad.jpg`, `r3_drive.jpg`,
    `r3_main_again.jpg`, `r3_fast_back.jpg`.
  - Sheets: `r3_sheet_{loading,title,xfade_logo,screensA,screensB,crops,1610,219,misc,detail2}.jpg`. The title sheet
    is shown next to `sh01_bund_gold_facades.jpg`.
- **Pixel sample** (PIL) on `r3_pursuit_169.jpg`: rows (16,19,34)–(23,26,42); scene left of the panel ≈ (94,95,100);
  façade right of the panel (124,68,17) → item 7.

## Notes for the lead (other units)
- **world:**
  - The async build took ≈ 34 s here at 1–2 fps. Process delta is capped at ≈ 0.067 s per frame, so every UI
    animation during loading crawls; the build should yield more often.
  - The racing lines bake with "The target vector can't be zero" (duplicate points).
- **world / city_layout:**
  - At z −300 the street `st_d0_ns_1` (lanes at x −110.19 / −107.05) runs 4.7 m east of the Bund's outer northbound
    lane, so there is no shoulder.
  - `plaza_bund_promenade` lies at x −149.7…−141.5, west of the road.
  - Please provide `spawns.title`.
- **damage:** 378 × "Trying to assign value of type 'Nil' to a variable of type 'PackedInt32Array'" at
  `res://damage/dent_painter.gd:242` in one real boot.
- **npc_cars / police:** `police_drone.glb` has an invalid UID, and a preload fails at boot.

PASS needs items 1–11 closed, with the probes above turned into tests under `game/ui/menu/tests/`, and a new real-boot
capture set taken through key navigation at the three aspects.

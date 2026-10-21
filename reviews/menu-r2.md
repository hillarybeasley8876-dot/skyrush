# menu review round 2 — VERDICT: FAIL

Reviewer: lead art director (Opus). Lead notes (`reviews/menu-lead.md`) are met: tests `extends Node`,
runs end by themselves, no scratch outside owned paths in round 2. The user demand stands:
**贴图纹理什么都要细化**. Every screen, glyph and panel must look finished in the REAL navigation flow.

## Scores (0-10)
- **function: 5**. Up from 3: the camera hand-back, `--skip-menu`, route picking, the info panel, any-key,
  the sounds, the settings state and the mouse are fixed. Still failing: sub-screens draw on top of the
  main menu, the stick floods up/left, retry drops the race options, the loading screen shows for 2
  frames, and traffic still rams the parked Roadster.
- **visual/feel: 3**. The hero logo reads "SKY RUS H". Overlapping screens and hint bars, opaque "glass",
  a burning SUV wedged into the title car, and a generic random-box loading skyline.
- **code: 6**. The split is tidy, files are ≤ 400 lines and typed. Against it: new dead code, duplicated list
  and tree-walk logic, two vacuous tests, leftover magic numbers and dynamic `.call()` on your own router.

## MUST-FIX

1. **CRITICAL: pushed screens are drawn on top of the screens they cover (overlap at every aspect).**
   - Evidence, probe: `R stack=["ScreenMain","ScreenRaceSetup"] main.visible=true main.alpha=1.0`.
   - Evidence, captures in `captures/review/menu/` (real key navigation):
     - `r2q_race.jpg`: "竞速赛 RACE" is printed over the main menu logo.
     - `r2q_pursuit.jpg` and `r2q_settings.jpg`: the main list, the main info panel and the new panel all show.
     - `r2q_controls_pad.jpg`: "操作说明 CONTROLS" sits over "设置 SETTINGS" and cannot be read.
     - Every sub-screen has 2–3 `HintBar`s on top of each other (`r2q_crops.jpg`: "↑↓ 选择↓·选择→·调整ter 确认ter 确认c 返回sc 返回").
     - Results over pause: two dims (0.68 + 0.72), so the scene is almost black.
   - Your captures hide this: `menu_demo.gd` opens each screen with `push_front(…, replace=true)`, so only
     one screen is ever on the stack.
   - Fix (`menu_stacks.gd`): when a screen is pushed on either stack, fade the covered screen out over
     0.18 s. At the end set `visible = false` and `process_mode = PROCESS_MODE_DISABLED`. On pop, show it
     again and fade it in. If you want one logo across sub-screens, make it a single header owned by the
     root, not a copy per screen.
   - Verify:
     - Test: push main → race_setup, wait 0.3 s, assert `main.is_visible_in_tree() == false` and exactly one
       visible `HintBar`. Repeat for settings → controls and pause → results.
     - Add `--menu-keys=DOWN@2.6,ENTER@2.8,…` (a list) to the demo. Capture race_setup, pursuit_setup,
       settings and controls **reached by keys from the main menu** at 1600×900, 1600×1000 and 2200×943.

2. **The logo letter spacing is broken: it reads "SKY RUS H"** (`r2_title_zoom.jpg`, every screen).
   - Cause: `logo.gd:65` uses `x = left + advance * float(i)`, the current glyph's advance × its index.
     Probe at 104 px:

     | | S | K | Y | R | U | S | H |
     |---|---|---|---|---|---|---|---|
     | code x (px) | 0 | 48 | 84 | 153 | 208 | 245 | 318 |
     | real x (px) | 0 | 49 | 97 | 139 | 190 | 242 | 291 |

   - Fix: keep a running `x += advance`, with kerning. Easier: shape the word once with `TextLine` and take
     the glyph offsets from `TextServer.shaped_text_get_glyphs`.
   - Also required:
     - (a) **Real glow.** At 1:1 the 3 rings × 4 offsets (α 0.22/0.11/0.07) only ghost the letters and no
       halo is visible. Use a CanvasItem shader or a blurred SubViewport pass: radius ≥ 12 px, core α ≈ 0.6,
       magenta `#FF2BD6` → cyan `#19E6FF`.
     - (b) **Chromatic split at 2 px.** It is 1.5 px, and the comment says 2.
     - (c) **Chinese first (ART §7).** Set 飞驰申城 at ≥ 0.62× the SKYRUSH font size (today 0.48), with its
       own cyan glow.
     - (d) **Title size.** On the title use `font_size` ≥ 150. Today the word covers ~17 % of the width.
     - (e) **Magic numbers.** Name 1.4 (reveal speed) and 0.32 (sweep speed). r1 13e is still open.
   - Verify: a test prints the glyph x positions: they increase, and each gap equals the advance ± kerning.
     Also a 1:1 crop of the title logo.

3. **Title stage: the Roadster is parked inside a traffic lane, so traffic rams it and it burns on the title.**
   - Evidence: `r2_title_beat1.jpg` and `r2_title_zoom.jpg` show a white SUV embedded in the car's nose,
     with flames on the SUV's roof.
   - `TITLE_SPOT (-115, 0, -300)` is inside the road according to `game/world/data/lanes.json`:
     - 1.15 m from the centreline of `bund_zhongshan_e1_4_fwd0` (x −116.14).
     - 2.35 m from `bund_zhongshan_e1_4_fwd1` (x −112.67), the rightmost lane, whose edge is at x −110.92.
   - My r1 estimate (road centre −123.4) does not match the current road data. Check the data; do not copy
     numbers.
   - Fix: derive the spot from the lane data at runtime. Take the rightmost lane at z −300 and move
     outward by 1.75 (lane half) + 1.0 (car half) + 1.0 (margin), ≈ x −108.9 today. Check
     `road_furniture.json` for lamps, trees and curbs at that spot. If the shoulder is not free, request a
     `spawns.title` point from world in status.
   - Framing: compare with `ref/art/img/sh01_bund_gold_facades.jpg`.
     - Every beat shows the whole car and at least one façade crown or the 江海关 clock tower against the sky.
     - No single prop may cover more than 10 % of the frame. Today a low-poly canopy fills about 1/3 of beat 0,
       and the façades read as a blank wall.
     - Report the untextured canopies and the flat black window panes to props/bund in status.
   - **Cross-fade: dead code.**
     - Cause: `title_screen.gd::_stage()` reads `menu.get("title_stage")`, which `menu.gd` does not have. It
       is always null, `beat_changed` has 0 connections (probe), and the camera simply lerps for 1.2 s.
     - Fix: take the typed `menu.front_end.stage`. At a beat change, snapshot the viewport image into a
       full-screen TextureRect, cut the camera, then fade the snapshot α 1 → 0 over 1.2 s. Delete the 22 %
       white flash.
   - Verify:
     - Print the car's distance to every lane centreline: ≥ 3.75 m.
     - In a 40 s title run, every node in group `traffic` stays ≥ 3 m from the player, and there is no
       wreck, fire or smoke.
     - Captures of the 3 beats, plus a 0.0 / 0.6 / 1.2 s strip across one beat change.

4. **The loading screen is on screen for 2 frames, and its art is generic and static.**
   - Real boot: `R loading frames=2 wall_ms=656`, then `frames=2 wall_ms=603` on a second boot.
   - Cause: `loading_screen.gd::is_done()` compares wall-clock ms with `_started_ms`, so the long first frames
     use up the 1.5 s. r1 9e asked for a delta clamp.
   - Fix: in `_process`, add `_shown += minf(delta, 0.1)` and require both `_shown >= MIN_SECONDS` and
     ≥ 60 rendered frames.
   - Art: `skyline.gd` draws 26 random boxes with a regular dot grid (`menu_loading_t2_8.jpg`). That is not
     Shanghai. It also only redraws on resize, so the "animated" grid and the neon pulse never move.
   - Fix the art:
     - Draw the Lujiazui silhouette: 东方明珠 (two spheres and a spire), 上海中心 (twisting taper),
       环球金融中心 (bottle-opener top), 金茂 (pagoda steps).
     - Add the Bund roofline in front and a river reflection band. References: `sh02_bund_bluehour_aerial.jpg`
       and `sh03_lujiazui_led_ads.jpg`.
     - Animate the grid scroll and a neon flicker at ≤ 15 Hz, with `queue_redraw()` in `_process`.
   - Verify:
     - A windowed boot prints how long the loading screen was the top screen: ≥ 1.5 s and ≥ 60 frames.
     - A 3-frame strip at 0.0, 0.5 and 1.0 s shows motion.

5. **Stick UP and stick LEFT still flood.**
   - Probe: 8 motion events on `JOY_AXIS_LEFT_Y` from −0.3 to −1.0 moved the selection from 3 to 0 (clamped
     at the top). One move was expected. A DOWN push moves exactly once.
   - Cause: `menu.gd::_input` dispatches every motion event for which `is_action_pressed` is true (deadzone
     0.2). `MenuInput.action_of()` returns `menu_up` as "pressed" for an up push, but as "released" for a
     down push. So only up and left pushes reach `_dispatch`.
   - Fix: `_input` never dispatches an `InputEventJoypadMotion`. Leave the axes to `poll()` (thresholds
     0.5 / 0.3); keys and buttons stay in `_input`.
   - Verify:
     - A stick test for all 4 directions: up and down on the main menu; left and right on a `ChoiceRow`, one
       step per push.
     - A 1.0 s hold gives 1 move + 6 repeats.

6. **The glass panels are opaque plates, and the settings rows have no focus highlight.**
   - Glass: `glass_panel.gdshader:58` computes `mix(screen * 0.28, tint.rgb, 0.78)`. Only ≈ 6 % of the scene
     shows through, so the blur is invisible and every panel reads as flat `#0A0F1E`. In the pause panel of
     `r2_detail2.jpg`, nothing of the street shows through.
   - r1 9a asked for a tint at 70 %, i.e. 30 % blurred backdrop.
   - Fix the glass:
     - Use `mix(textureLod(screen, SCREEN_UV, 3.0).rgb, tint.rgb, tint.a)` with `tint.a = 0.70`.
     - Keep the 3 % grain and the 2 px scanlines.
     - Add a vertical gradient (top 8 % lighter) and a 1 px dark inner line at the bottom for depth.
   - Focus: `setting_row.gd:100` sets a `focus` uniform that the shader never reads, and never sets `bar`.
     Settings, race difficulty/laps and pursuit rows get no bar, no ▶ chevron and no 10 px slide; only the
     alpha (0.75 → 1) and the sub-label colour change.
   - Fix the focus: move the `menu_item.gd` focus treatment into `row.gd` so every row shares it, and delete
     the unused uniform.
   - Verify:
     - A 1:1 crop of a panel over a lit façade shows the warm light, blurred, through the plate.
     - Text contrast on the plate stays ≥ 4.5:1.
     - A 1:1 crop of the settings screen with the cursor on 雨效.

7. **Results: retry drops the options, the pursuit subtitle is wrong, and free-roam 继续 does not resume.**
   - Retry, cause: `results_router.gd::_race_payload` and `::_pursuit_payload` contain no `"options"`. Probe:
     the payload keys are kind, results, route, route_title, best_time and best_lap.
   - Retry, effect: 重试 emits `request_mode(&"race", {})`, so modes falls back to its default route, laps and
     difficulty.
   - Retry, fix: the router keeps the options passed to `start()` and copies them into every payload.
   - Pursuit subtitle: the probe gives `heading=时间到 TIMEOUT subtitle=被警察拦下`. Use one subtitle per
     result:

     | result | subtitle |
     |---|---|
     | escaped | 甩开了追捕 |
     | busted | 被警察拦下 |
     | success | 目标达成 · 撞毁 n 辆 |
     | timeout | 时间到 · 未能甩开 |

   - Free roam 继续: the button says "回到自由驾驶", but it pops back to the pause menu. Close both overlays
     and resume.
   - Verify:
     - Test: race on route `r_b`, laps 3, hard → results → 重试. `start_mode` receives the same three options.
     - Test: the subtitle for each of the four pursuit results.

8. **Text runs over panel borders.**
   - Evidence: the race info line "每圈 LAP 2.42 km 全程 TOTAL 4.84 km" (22 px) is wider than its 384 px
     content box and crosses the panel's right edge (`r2_detail2.jpg`, top right).
   - Fix: split LAP and TOTAL onto two lines.
   - Verify: a test opens every screen at 1920×1080, 1920×1200 and 2520×1080 (virtual) and asserts that each
     `Label.get_minimum_size().x` fits its parent's width.

9. **The evidence and tests must reflect the real flow.**
   - `test_menu.gd:207` sets `camera.current = true` just before `_start_mode`. "The game camera is current
     again" therefore passes even if the hand-back breaks. Remove that line.
   - `test_menu.gd:243` asserts `menu.get("title_stage") == null`. That property never exists. Assert
     `menu.front_end.stage == null` instead.
   - `captures/menu/` mixes r1 files (`*_t3_0`, 23:xx) with r2 files. The 16:10 set has no pause, pursuit
     or loading capture, and the 21:9 set has only 3 screens.
   - Delete the stale files, then recapture at 16:9, 16:10 and 21:9 through key navigation:
     - title (3 beats), main, race (and route picked), pursuit, settings, controls, pause;
     - results for all 3 kinds, and the drive shot;
     - loading during a real boot.

10. **Code rules (CONTRACTS §3, CLAUDE.md: no dead code, no duplication, no `.call()` on your own code).**
    - (a) Dynamic calls on your own typed router: `race_setup.gd:203` `router.call("best_time", …)` and
      `pause_menu.gd:113` `router.call("build_payload", …)`. Call them directly.
    - (b) Dead code to delete:
      - `panel.gd:36` creates `title_label` but never adds it to the tree (an orphan Label per panel), and
        `set_title` does nothing.
      - `menu_screen.gd:31` `static var last_device` is never written.
      - `title_stage.gd:118` `+ Vector3(0.0, 0.0, 0.0)`.
      - `menu_demo.gd:95` `get_process_delta_time() * 0.0`.
      - The flash code in `title_screen.gd`, if you do not wire it (see 3).
      - Also fix `logo.gd:77`: the `_draw_glow` doc comment sits above `_now()`.
    - (c) Duplicated logic:
      - `menu_list.gd` and `option_list.gd` are the same list (select, move, refresh). Keep one.
      - There are four recursive tree searches: `bridge.gd::_search`, `results_router.gd::_search`,
        `front_end.gd::_set_hud_in` and `menu_demo.gd::_find_menu`. Use one helper.
    - (d) `title_stage.gd:16`: the comment on `AIM_HEIGHT` describes the wrong thing. The dolly also moves the
      camera **out** (`+ dolly`), while the comment says "in".

## SHOULD-FIX
- **Controls page** (`controls_page.gd`, `key_chip.gd`):
  - The key caps show the OS key names "Up/Down/Left/Right/Escape". Use ↑ ↓ ← → and "Esc".
  - Steer shows "左摇杆 X" twice. Use one chip, "左摇杆 ◀▶".
  - `Shape.PILL` is drawn as a plain rectangle. Draw true pills (radius = h/2).
  - Tint the A/B/X/Y rings `#3BB54A` / `#E2322B` / `#2A7DE1` / `#F5C400`.
  - The 12 px English sub-labels are too small; use at least 14 px.
- **Glyph coverage** (probe). The Start glyph ☰ and the ₂ of "N₂" are in none of the shipped fonts, and Smiley Sans has
  no ▶ or ✓. They render only through the macOS system fallback.
  - Draw the Start button as a chip (three bars).
  - Write N₂ as "N2" or "氮气".
  - Take ▶ and ✓ from Noto Sans SC.
- **Hints.**
  - The pause gamepad hint says "☰ 暂停", but Start resumes there.
  - The main menu says "Esc 返回" / "☰ 暂停", but neither does anything there.
  - Write the hints per screen.
- **Pause and results layout.**
  - The pause panel is 470 px tall for 4 rows, so it is half empty (`r2_detail2.jpg`). Size it to its content.
  - On the results screen, give the player's row a highlighted plate, alternate the row tint, and bring the
    value column closer to the labels.
- **Choice rows and sliders.**
  - Show choice values as "◀ 高 ▶" so ←/→ is discoverable.
  - The slider grabber is the default theme dot. Use a cyan 4 × 16 px tick.
- **Settings cursor.** Returning from 操作说明 resets the cursor to 画质, because `on_enter` rebuilds the rows.
  Keep the selection.
- **Pursuit setup.**
  - Modes defines `count` as "the number of police cars to take down". Label it 撞毁目标 TARGET.
  - Disable it when the goal is 逃脱追捕.
  - Save the pursuit options in the prefs.
- **Title frame rate (≥ 60 fps) is not verified.** I measured 33.8 fps average and 14.2 fps minimum, with 582
  draw calls and 3.28 M primitives, at 1600×900 under load average 41. Re-run `--menu-perf` at
  1920×1080 high when the load average is below 8, and report each beat separately.
- **HUD hiding.** The HUD is still hidden by walking the whole tree (`front_end.gd::_set_hud_in`). Keep the
  request to the hud unit in status.

## Verified OK
- **Static check.** `tools/godot.sh check --only=res://ui/menu/` → `CHECK 40 files, 0 failed, 0 engine errors, 0 warnings`.
- **Tests.**
  - `test_menu`: 41 PASS, `test_race_setup`: 12 PASS, `test_results`: 13 PASS. 0 failures.
  - All three test files `extend Node` (lead rule).
- **r1 #1: the camera is fixed.**
  - In the real game, after 自由驾驶: `cam=/root/Test/Main/ChaseCamera/Camera hud=true mode=free`, driving at 119 km/h.
  - `--skip-menu`: `r2_skip_t3_0.jpg` shows the chase view at 142 km/h with the HUD.
- **Title screen.**
  - Any key (KEY_X) opens the main menu.
  - The prompt sits on the band at 80 % of the height, clear of the car.
  - The HUD is hidden on the title (`hud=false`).
  - The car is parked facing north (`fwd=(0,0,-1)`).
  - The title camera's far plane is 1200 m.
- **Race setup.**
  - Enter on a route row picks it: "✓ 已选", the bar stays lit, and the info panel reads "已选路线 PICKED 高架冲刺".
  - The cursor then jumps to 开始比赛.
  - Lap and total lengths come from the racing line.
- **Main menu.**
  - The info panel follows the selection (`r2q_pursuit.jpg`).
  - The rows have the 0.12 s focus treatment: cyan bar, ▶, a 10 px slide, a cyan sub-label and 75 % alpha
    on unselected rows (`r2q_crops.jpg`).
- **Other screens and wiring.**
  - The rain row reads the real weather state, and the test toggles it.
  - The mouse click is fixed.
  - UI sounds go through the `audio` group.
  - The loading tips are corrected (+50, the N₂ wording).
  - Hints follow the last device used.
- **Ownership.** Every round-2 Write/Edit is under `game/ui/menu/**` or `status/menu.md`, with no new scratch in
  `game/tools`. `/tmp/diag.gd` and `/tmp/probe7.gd` are not this worker's files.
- **Code size and typing.** Every file is ≤ 400 lines (the largest is `menu.gd`, 391), and static typing is
  used throughout.

## Notes for the lead (other units)
- **BLOCKER (world/env/core): the game crashes while the menu camera is active.** It happened twice:
  - `drive_169.log`: during title beat 1 → 2.
  - `drive_169q.log`: right after quit-to-menu.

  Each time, 6 × "Reflection probe atlas index invalid. Maximum amount of reflection probes in use (64)"
  were followed by `FATAL: Index p_index = -1 is out of bounds (size 64)` and signal 5. The likely cause is
  `world/build/probe_placer.gd`: it toggles probe visibility every 0.5 s (MAX_ACTIVE 4), which may leak atlas
  slots as the camera moves.
- **Audio:** 178 × "Invalid access to property or key 'playing' on a base object of type 'Nil'" at
  `res://audio/oneshot_pool.gd:105`.
- **Camera:** `vehicle/camera/camera_effects.gd:162` has a parse error ("player" not declared), so
  `set_motion_blur` may be missing.
- **fx:** `fx/thrusters/thruster_rig.gd:262` has a parse error (`trigger()` arguments).
- **props/bund:** the title framing is dominated by flat low-poly tree canopies and black window panes.

## Evidence (commands run from /Users/minimax/m/skyrush; scratch in `tmp/review/menu_r2/`)
- **Static check:** `tools/godot.sh check --only=res://ui/menu/` → CHECK 40 files, 0 failed.
- **Tests:** `tools/godot.sh test res://ui/menu/tests/{test_menu,test_race_setup,test_results}.gd`
  → MENU / RACE SETUP / RESULTS TEST PASS.
- **Logic probe** (headless, test_host) `--test=$PWD/tmp/review/menu_r2/logic.gd`:
  - `R stick UP 8 events: sel 3 -> 0 (expected 2)` and `R stick DOWN 8 events: sel 0 -> 1 (expected 1)` → item 5.
  - `R stack=["ScreenMain", "ScreenRaceSetup"] main.visible=true main.alpha=1.0` → item 1.
  - `R menu.get(title_stage)=<null> front_end.stage=@Node3D@41`, `R beat_changed connections=0` → item 3.
  - `R race payload keys=["kind","results","route","route_title","best_time","best_lap"] has options=false` → item 7.
  - `R pursuit timeout heading=时间到 TIMEOUT subtitle=被警察拦下` → item 7.
  - `R logo x(code)=[0,48,84,153,208,245,318]` and `R logo x(real)=[0,49,97,139,190,242,291]` → item 2.
- **Lane check** (python over `game/world/data/lanes.json`): `(1.15, 'bund_zhongshan_e1_4_fwd0', …)`,
  `(2.35, 'bund_zhongshan_e1_4_fwd1', …)` → item 3.
- **Glyph probe** (`glyphs.gd`): text font `☰=false ₂=false`; display font `▶=false ✓=false`.
- **Windowed real-game driver** (`drive.gd`, `slots.py heavy`, 1600×900):
  - `R loading frames=2 wall_ms=656` / `603` → item 4.
  - `R title fps_avg=33.8 fps_min=14.2 draws=582 prims=3276166` (load average 41).
  - `R after free cam=/root/Test/Main/ChaseCamera/Camera … hud=true`.
  - `R results state={"overlay": ["ScreenPause", "ScreenResults"] …}`.
  - Two crashes (see the lead notes).
- **Captures** in `captures/review/menu/`:
  - Title: `r2_title_beat0/blend01/beat1.jpg`, `r2_title_sheet.jpg` (vs `sh01_bund_gold_facades.jpg`),
    `r2_title_zoom.jpg`.
  - Screens: `r2q_{title,main,race,race_picked,pursuit,settings,controls_pad,drive,pause,results_free}.jpg`,
    `r2q_sheet.jpg`, `r2q_crops.jpg`.
  - Other: `r2_skip_t3_0.jpg`, `r2_detail2.jpg`, and `r2_worker_sheet.jpg` (your loading, results, 21:9 and
    16:10 shots).

PASS needs all 10 MUST-FIX items closed, with the probes above copied into `game/ui/menu/tests/` and a new
capture set taken through the real key navigation.

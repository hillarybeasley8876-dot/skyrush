# menu review round 1 — VERDICT: FAIL

Reviewer: lead art director (Opus). No `reviews/menu-lead.md` exists yet; the items below are binding.
User demand for this project: **贴图纹理什么都要细化** — every surface, panel and glyph must look finished.

## Scores (0-10)
- **function: 3** — d-pad/keys, pause and results open, but the menu steals the game camera (the game is
  unplayable both from the menu and with `--skip-menu`), the race setup always starts the last route
  scrolled over, the main-menu info panel never changes, the left stick floods, and there are no sounds.
- **visual/feel: 3** — crisp CJK and the right palette, but every screen is a flat scrim + 1 px outline
  box, no transitions, a logo whose "glow" is a no-op, and a title shot where traffic crashes into the
  parked Roadster (smoke and debris) with no Bund in frame and the prompt printed over the car.
- **code: 5** — tidy split and ≤ 400 lines, but dynamic `.call()` on its own widgets, dead code,
  private access into the camera unit, a signal-arity bug, and score/record logic duplicated from `modes`.

## MUST-FIX

1. **CRITICAL: the orbit camera stays the active camera, so gameplay is rendered from a frozen camera.**
   Evidence: with `--skip-menu`, `get_viewport().get_camera_3d()` = `/root/@Node3D@1025/@Camera3D@1026`
   (script `res://ui/menu/widgets/orbit_camera.gd`) while the car drives at 85.7 km/h. Capture
   `captures/review/menu/r1_skip_menu.jpg` shows the underside of a bridge with no car and no HUD. From the
   menu: after 自由驾驶 the camera is still the orbit camera (`r1_drive.jpg`: the car is a speck 40 m away).
   Cause: `orbit_camera.gd::_ready()` sets `camera.current = true` even when its processing is disabled.
   `menu.gd::_on_front_changed(false)` only disables processing and never gives the camera back.
   Fix: (a) do not create or add the orbit camera at all when `_skip_menu`. (b) Delete both
   `camera.current = true` lines. (c) In `_on_front_changed(true)`, remember
   `_game_camera := get_viewport().get_camera_3d()` (when it is not the orbit camera), then call
   `_orbit.camera.make_current()`. In `_on_front_changed(false)`, call `_orbit.camera.clear_current(false)`,
   then `_game_camera.make_current()` if it is still valid.
   Verify: in `test_menu.gd`, add a Camera3D that is current before the menu opens. After
   `_start_mode(&"free", {})`, assert that it is current again. Also assert that the orbit camera is never
   current with `--skip-menu`. Recapture with `tools/godot.sh shot --scene=res://main.tscn --out=menu_skip
   --skip-menu --press=accelerate --times=3`: the chase view must be behind the moving car.

2. **Race setup can only start the last route the cursor passed.** Evidence (reviewer probe
   `tmp/review/menu_logic.gd`, 3 routes r_a/r_b/r_c): highlight r_a, press ↓ ×5 to 开始比赛, press Enter →
   `{route: "r_c"}`. Cause: `race_setup.gd::_on_selection_changed` sets `_route_index` for every route row
   the cursor crosses. With the real 5 routes, keyboard and gamepad can only race 滨江环线.
   Fix: (a) Enter/A on a route row picks that route: show a cyan ✓ and a persistent left bar, then jump
   the focus to 开始比赛. Moving the cursor only previews in the info panel and never changes the picked
   route. (A `ChoiceRow` "路线 ◀ 外滩冲刺 ▶" is also acceptable.) (b) Show the length as
   `route.racing_line.get_baked_length()`: per lap, and total = laps × lap. Today a route with an 800 m line
   shows "1.00 km", and sprints get a bogus closing segment. (c) Default the laps to `route.laps`.
   (d) Restore `prefs.last_route/difficulty/laps` on enter (today they are written but never read).
   Verify: a test that walks from row 0 to START and asserts the first id, and a test that picks row 2
   with Enter.

3. **The main-menu info panel never follows the selection.** Evidence: after ↓, `sel=1`, but the panel
   still reads "自由驾驶 FREE ROAM / 在申城街头随意驰骋…". `handle_action` never calls `_show_details`.
   Fix: give `menu_list.gd` a `selection_changed` signal (as `option_list.gd` has) and refresh the panel on
   it. Verify: the test asserts the panel title after each ↑/↓.

4. **The left stick floods the selection (gamepad-only navigation is broken).** Evidence: one push sent as
   8 `InputEventJoypadMotion` events (0.3 → 1.0) moved the selection from 0 to 4; 1 was expected. Every
   motion event above the 0.2 deadzone counts as a new press, and the echo filter only covers keys.
   Fix: add edge detection to `menu_input.gd`: press when |axis| crosses 0.5, release below 0.3. Add one
   repeat rule for held stick, d-pad and arrows: the first repeat after 0.40 s, then every 0.12 s.
   Verify: a test sends those 8 events and asserts exactly one move.

5. **"按任意键开始" only reacts to the six menu actions.** Evidence: KEY_X leaves the title open. Gamepad
   Start maps to `pause` → `_handle_back()` → no-op, yet "Press Start" is the console convention.
   Fix: the title accepts any non-echo key press, any joypad button (Start included) and any mouse click.
   Verify: tests for KEY_X, JOY_BUTTON_START and JOY_BUTTON_Y.

6. **No UI sounds at all.** `play_ui` is never called (`grep -rn play_ui game/ui/menu` matches only its
   definition), and status/menu.md's "the bridge prefers it over the local fallback" is false. The audio
   unit already ships `play_sfx(id)` on the node in group `audio`, with ids `ui_hover`, `ui_click`,
   `ui_confirm`, `ui_back` and `ui_whoosh` (`game/audio/sfx/*.ogg`), plus `set_music_state(&"menu")`.
   Fix: add `Bridge.ui_sound(id)` via `get_tree().get_first_node_in_group(&"audio")`. Play `ui_hover` on a
   move, `ui_confirm` on accept, `ui_back` on back, `ui_click` on a value change and `ui_whoosh` on a
   screen push/pop. Call `set_music_state(&"menu")` when the front end opens.
   Verify: a test with a fake node in group `audio` that counts the ids per action.

7. **Title stage: the car is parked in a live traffic lane, gets rammed, and the Bund is not in frame.**
   Evidence: `r1_title_a.jpg`/`r1_title_b.jpg` show a white SUV and a black car crashing into the frozen
   Roadster, with smoke and debris (the same wreck is behind the main menu in `r1_main_crop.jpg`). There are
   no gold façades: compare `captures/review/menu/r1_title_vs_sh01.jpg` with
   `ref/art/img/sh01_bund_gold_facades.jpg`. "按任意键开始" and "飞驰申城 · NEON SHANGHAI" are printed over the
   car's roof and cannot be read.
   Fix: add a menu-owned `widgets/title_stage.gd`. Whenever the front end opens (boot and quit-to-menu), it
   calls `Game.player.reset_to(TITLE_SPOT)`. TITLE_SPOT is on the east shoulder of 中山东一路, off the
   lanes: the road centre is x ≈ −123.4 at z ≈ −300, with 2+2 lanes × 3.5 m, a 1 m shoulder and a 4 m
   sidewalk, so the spot is ≈ (−115.0, 0, −300), heading north. The car's inner side must stay ≥ 7.3 m
   east of the centre line; if the curb gets in the way, ask world for a `spawns.title` point in status.
   Frame 江海关 (−159, −328) and 汇丰 (−149, −268) behind
   the car (city.json pois) with authored beats instead of a single orbit:
   - low 3/4 front: h 0.9 m, r 6.5 m, FOV 38
   - side profile with the façades: h 1.4 m, r 9 m, FOV 32
   - high toward Pudong: h 6 m, r 14 m

   Each beat lasts 9 s, with a slow dolly and a 1.2 s cross-fade. Aim at the car centre + 0.6 m. Move the
   prompt to about 80 % of the screen height on a dark gradient band, and keep text out of the central
   40 % × 50 % where the car sits.
   Verify: title captures at t = 2/8/14 s show a clean car, gold façades, no smoke and readable text. If
   the façades do not render there, file a request in status (bund/world), not a workaround.

8. **Results data is wrong or incomplete, and duplicates the modes unit.** Evidence: the pursuit results
   rows are `热度|HEAT|0 级`, `撞毁警车|TAKEDOWNS|0`, `用时|TIME|--:--.--`, because the payload built in
   `menu.gd::_on_pursuit_state_changed` has no takedowns or time. Pursuit **TIMEOUT** (180 s default) and
   **SUCCESS** (takedowns goal) never open a results screen; the menu only listens for escaped/busted.
   `score_tracker.gd` scores a takedown at 100 for any non-traffic kind with no wreck penalty, while
   `modes/free_session.gd` (what the HUD and records use) scores 50 for police only and −25 per wreck.
   Best times live in `user://skyrush_menu.cfg` while modes keeps `user://records.cfg` (`GameRecords`).
   Fix: delete `score_tracker.gd` and the menu's record store. Take every result from the modes unit, i.e.
   the node you already find for `start_mode`: its `session.finished(results)`, or `last_results` /
   `session.build_results()`. Show race `best_lap` and DNF (`finished == false`), with rows sorted by
   `position`. Show the pursuit `result` (escaped/busted/success/timeout), `takedowns/target`, `time` and
   `heat`. Show free-roam score/stunts/near misses/wrecks/takedowns/time and `best_score`. Read best times
   from `records.best_time(route)`.
   Fix two loading tips: "撞废一辆警车 +100 分" must say +50. "小喷、双喷…都吃它" is wrong: 小喷 is earned
   by drifting, and N₂ is spent by boost/hop/hover/roll/sky lane (SPEC §5).
   Verify: a test with a fake director that emits a pursuit timeout and a free result. Capture all three
   results kinds.

9. **Visual refinement (the user: 贴图纹理什么都要细化). Every screen is a flat `ColorRect` scrim plus a
   `StyleBoxFlat` with a 1 px border. Required:**
   a. **Glass panels**: a shader (`widgets/glass_panel.gdshader`) used by panel.gd, menu rows and the pause
      and results screens:
      - backdrop blur (`hint_screen_texture, filter_linear_mipmap`, `textureLod` LOD ≈ 2.5)
      - tint `#0A0F1E` @ 70 %, 3 % animated film grain, 2 px scanlines @ 4 % alpha
      - 1 px top highlight `#F2F6FF` @ 25 %
      - 14 px cut corner (match the HUD's `ui/hud/glass_panel.gd`) and cyan `#19E6FF` corner brackets

      Use the same shader for one HUD-matching header strip per panel.
   b. **Logo**: the "soft glow pass" in `logo.gd:63-66` draws the same glyph at the same position, so it
      does nothing. Build a real glow: 4–6 offset or blurred passes, or a CanvasItem shader halo. Add a
      2 px magenta/cyan chromatic split, a scanline shimmer and a neon underline that wipes in. Set
      **飞驰申城 in Smiley Sans at ≥ 0.6× the SKYRUSH cap height**, letter-spaced (ART §7: Chinese first);
      today it is a 24–30 px Noto line.
   c. **Focus highlight**: animate it over 0.12 s: a gradient bar `#19E6FF` → transparent, a ▶ chevron, the
      title sliding +10 px and the sub-label turning cyan. Unselected rows sit at 75 % alpha.
   d. **Transitions**: 0.18–0.25 s fade + 24 px slide on every push/pop that never blocks input, with
      `ui_whoosh`.
   e. **Loading**: real art, not a 96 % flat rect: a skyline silhouette or animated grid behind the logo,
      a segmented progress bar with glow, and at least 1.5 s on screen. Today it is never visible: the world
      build makes the first frame seconds long, `_loading_time += delta` jumps past `LOADING_GRACE` and
      the title replaces it at once (`r1_loading.jpg` already shows the title). Clamp the delta to 0.1 s.
   f. **Controls page**: key-cap chips (6 px radius, `#1A2236` fill, 1 px `#3A4A6A` border, `#F2F6FF`
      text) and gamepad glyph chips (A/B/X/Y circles, LB/RB/LT/RT pills) instead of plain amber text.
   g. **Hints**: device-aware. Show "Ⓐ 确认 Ⓑ 返回 ☰ 暂停" after a joypad event and keyboard hints after a key
      event; the quit prompt "再次按 Enter 退出" must follow the device too. Drop "←→ 调整" where ←/→ do nothing
      (main menu, pause, results).

   Verify: a before/after contact sheet of all 8 screens at 1600×900, and 1:1 crops of a panel corner and
   the logo.

10. **Settings must reflect and persist the real state.** The rain row starts from `prefs.rain`
    (default on), not from the weather controller, and the saved pref is never applied at boot. Fix: the
    initial value comes from `is_raining()` on the node in group `weather`, and saved rain/motion-blur
    values are applied once when the menu starts. Delete the `_config` private access in
    `bridge.gd:70-74`; call only the public `set_motion_blur` of `vehicle/camera/camera_effects.gd`, and ask
    camera for a getter in status. Verify: a test toggles rain and asserts `weather.is_raining()`.

11. **Mouse click is broken.** Every click errors with `Error calling from signal 'clicked' to callable:
    'VBoxContainer(menu_list.gd)::_on_item_clicked': Method expected 1 argument(s), but called with 0`
    (seen in the probe). Fix: `item.clicked.connect(_on_item_clicked.bind(item))`. Verify: the test emits
    `clicked`, asserts the navigation and expects 0 engine errors.

12. **Prove the ≥ 60 fps title acceptance, and complete the evidence.** Measured: 10–17 fps (load avg
    22–37 while other jobs ran) and 34 fps at 1920×1080, with 1317 draw calls, 1.0 M primitives and a
    camera far plane of 3000 m. That is not conclusive under load, but your "27–95 fps" is not evidence
    either. Add a `--menu-perf` flag to `menu_demo.gd` that prints average and minimum fps over 10 s plus
    `Performance` monitors, and run it on an idle slot. If it is below 60 at 1080p high, cut the title
    camera's cost: far plane 1200 m, and framing that does not look down the whole city. Recapture every
    screen at 16:9 **and 16:10** (today only race_setup/results/controls were checked, by me) plus 21:9,
    and add the "menu → 自由驾驶 → driving" shot.

13. **Code rules (CONTRACTS §3 static typing, CLAUDE.md no dead code / no duplication).**
    a. Replace `item.call("set_text", …)` and `hints.call("set_hints", …)` with typed `MenuItem`/`HintBar`
       references: `main_menu.gd:142-162`, `menu_list.gd:77,102` and `option_list.gd:76-100` (give the rows
       a typed base class).
    b. Use `Array[Control]` for `menu_stacks.gd` `front`/`overlay`.
    c. `main_menu.gd:157/167` declares the `names`/`english` arrays twice; make them one const.
    d. Delete the dead code: `Bridge.UI_CLICK`, `OrbitCamera.set_target_point`, `OptionList.row_activated`,
       `MenuList.clear_items`, `MainMenu._on_item_adjusted`.
    e. Name the magic numbers in logic: `logo.gd` 1.4 / 0.32 / 0.14, `title_screen.gd` 2.6,
       `loading_screen.gd` 4.5.
    f. `menu.gd` is 392 lines. Split it **before** adding the fixes (e.g. `title_stage.gd`,
       `results_router.gd`) and commit the split separately.

## SHOULD-FIX
- Find units by group, not by a depth-first walk of the whole tree on every call (`bridge.gd::find_unit`):
  `audio`, `weather` and `environment` are groups. Keep the duck-typed `start_mode` lookup (the modes unit
  documents it), but cache the node.
- Quit-to-menu leaves the modes session running (race rivals and timers). Ask modes for a public
  `stop_mode()` in status, and until it exists park the session.
- Build the controls page from `core/input_setup.gd` / `InputMap` so it cannot drift from SPEC §4.
- Pursuit setup: expose `goal` (escape / takedowns), `count` and starting `heat`, which modes already
  accepts (`mode_director.gd` header).
- HUD hiding by scanning the tree for `res://ui/hud/hud.gd` stays a workaround; keep the request in status.
- Process: the worker log shows scratch files created in core-owned `game/tools/` (probe_inputmap.gd,
  t.gd, tmptest/, probe_auto.gd) and in `/tmp`. They were deleted, but use `tmp/` in the repo only.
- Fix the status/result claims: the test has 23 checks, not 24; there is no UI-sound "fallback"; and no
  16:10 capture existed.

## Verified OK
- `tools/godot.sh check --only=res://ui/menu/` → `CHECK 31 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://ui/menu/tests/test_menu.gd` → 23 PASS, `MENU TEST PASS (0 failures)`.
- Ownership: every Write/Edit in `jobs/menu/log.jsonl` is under `game/ui/menu/**` or `status/menu.md`.
- Files ≤ 400 lines (the largest is `menu.gd` at 392). Uses the shared `ui/theme` palette and fonts; the
  fonts are OFL with licence files shipped.
- CJK renders crisp: Smiley Sans titles and Noto Sans SC body (`r1_main_crop.jpg`, 1:1).
- No UI/UI overlap on race setup and results at 16:10 or controls at 21:9 (`r1_aspect_sheet.jpg`). I did
  not re-check the worker's 21:9 main-menu shot.
- Pause: Esc and gamepad Start open and close it, and `Game.set_paused` toggles (probe + test).
  Settings → `Settings.set_quality` and `Settings.set_volume` are wired.
- Confirm presses are answered in the same input event, and `_await_release` blocks carry-over confirms
  (the BEAK RASH cadence rule).
- `--skip-menu` skips the front end, but it is not usable until MUST-FIX 1 is done.

## Notes for the lead (other units, not the menu worker's fault)
- HUD: parse errors while capturing (`The member "UI" already exists in parent class
  res://ui/hud/glass_panel.gd`; `Failed to load script "res://ui/hud/hud.gd"`).
- Traffic drives straight into a stopped player car; the title fix (#7) avoids that, but traffic should
  brake for obstacles.
- World/bund: no gold façades are visible around the player spawn (−123.5, −300.5), although city.json
  places 汇丰 (−149, −268) and 江海关 (−159, −328) right there.
- Core/world: the world builds synchronously and nobody emits `Events.loading_progress`, so no loading
  screen can show real progress.

## Evidence (commands run from /Users/minimax/m/skyrush)
- `tools/godot.sh check --only=res://ui/menu/` → `CHECK 31 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://ui/menu/tests/test_menu.gd` → 23 × PASS, `MENU TEST PASS (0 failures)`.
- Logic probe (headless, through core test_host):
  `godot --headless --path game -s res://tools/test_host.gd -- --test=$PWD/tmp/review/menu_logic.gd`
  - `R after DOWN sel=1 desc=在申城街头随意驰骋… title=自由驾驶  FREE ROAM` → MUST-FIX 3
  - `R stick 8 motion events (one push) -> sel=4 (expected 1)` → MUST-FIX 4
  - `ERROR: … menu_list.gd)::_on_item_clicked': Method expected 1 argument(s), but called with 0` → 11
  - `R title + KEY_X front=["ScreenTitle"]` → MUST-FIX 5
  - `R route0 length label=长度  LENGTH   1.00 km` (the racing line is 800 m) and
    `R started options={ "route": "r_c", "difficulty": "normal", "laps": 2 }` (r_a picked; route laps 3) → 2
  - `R orbit camera current after start=true` → MUST-FIX 1
  - `R START in game overlay=["ScreenPause"] paused=true` / `R START again overlay=[] paused=false` → OK
  - `R pursuit results rows=["热度|HEAT|0 级|", "撞毁警车|TAKEDOWNS|0|", "用时|TIME|--:--.--|"]` → 8
- Windowed real game (`tmp/review/menu_drive.gd`, 1600×900):
  - `R title fps samples=[1.0, 1.0, 10.0, 13.0, 13.0, 14.0, 14.0, 15.0, 15.0, 17.0]` (load avg 22–43)
  - `R player=PlayerCar pos=(-123.5, 0.0, -300.5) mode=menu`
  - `R after start front=[] mode=free cam=/root/@Node3D@1031/@Camera3D@1032` (the orbit camera)
  - `R driving … speed=53.45 cam=/root/@Node3D@1031/@Camera3D@1032`
- `--skip-menu` (`tmp/review/menu_skip.gd`): `R skip-menu cam=/root/@Node3D@1025/@Camera3D@1026
  parent_script=(res://ui/menu/widgets/orbit_camera.gd)`, `R skip-menu driving … v=85.70`
- Perf (`tmp/review/menu_perf.gd`, 1920×1080): `fps=34.0 render_cpu_ms=2.53 process_ms=49.46 draws=1317
  prims=1002526 cam_far=3000`; the GPU timer reads 0 on Metal.
- Captures (`captures/review/menu/`): `r1_loading.jpg` (already the title), `r1_title_a.jpg`,
  `r1_title_b.jpg`, `r1_main.jpg`, `r1_main_crop.jpg`, `r1_drive.jpg`, `r1_pause_live.jpg`,
  `r1_skip_menu.jpg`, `r1_skip_vs_worker.jpg`, `r1_title_vs_sh01.jpg` (vs `ref/art/img/sh01_bund_gold_facades.jpg`),
  `r1_rs_16x10_t4_0.jpg`, `r1_res_16x10_t4_0.jpg`, `r1_ctl_21x9_t4_0.jpg`, `r1_aspect_sheet.jpg`;
  worker sheets `w_sheet1.jpg` and `w_sheet2.jpg`.

PASS needs all 13 MUST-FIX items closed, with a re-run of the probes above (copy them into
`game/ui/menu/tests/`) and a fresh capture set.

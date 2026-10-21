# menu status

## Done

**Round 3 → round 4 (this session)** — every must-fix of the r3 review is implemented, tested
and captured. The review's own probes are now tests under `game/ui/menu/tests/`.

| # | the r3 must-fix | what was done | where |
|---|---|---|---|
| 1 | **A quick confirm → back left the front end blank.** | The screen owns its cover tween now: `begin_cover()` / `begin_uncover()` kill the running tween, and the end callback only hides the screen when it is still covered. The screen is made visible and processable *before* the fade-in tween is created (a tween on a disabled node never runs). | `screens/menu_screen.gd`, `menu_stacks.gd` |
| 2 | **The overlay stack drew the screens on top of each other.** | `push_overlay()` covers the screen below (the same cover/uncover), and the results *replace* the pause menu (the two dim plates must not stack). | `menu_stacks.gd`, `menu.gd` |
| 3 | **The Roadster was parked in a traffic lane and got rammed.** | The spot is derived from the lane data **after** `Game.world_ready()` and validated: the clearance from every lane centreline, the ground under the car, the props around it, the open sky above it and the line of sight from the camera of every beat. The stage camera is only activated when the loading screen is not on top. | `widgets/title_spot.gd` (new), `widgets/title_buildings.gd` (new), `widgets/title_stage.gd`, `front_end.gd` |
| 4 | **The loading screen showed the world, the raw phase ids and a placeholder skyline.** | The screen is opaque from its first frame (`appear_now()`), the phases are mapped to Chinese, the reveal / the tip / the grid / the flicker run on the wall clock, and the skyline was redrawn per ART §11 (the Pearl with its spheres and chasing LEDs, the twisting Shanghai Tower, the SWFC aperture, the 13 tiers of Jin Mao, the clustered windows, the Bund with its domes and the clock tower of 江海关, the reflections in the river). | `screens/loading_screen.gd`, `widgets/skyline*.gd` (3 new files) |
| 5 | **Overlaps the layout test could not see.** | The logo reports its own height (the list sits below it), the results use a CN / EN / value layout with the value at the right edge, the race setup scrolls the selection into view and its panel is tall enough for the nine rows, and the layout test now collects the global rects of every text and the logo and checks that none of them overlaps or leaves the screen. | `widgets/logo.gd`, `screens/results_screen.gd`, `screens/race_setup.gd`, `tests/test_layout.gd` |
| 6 | **The focus treatment was incomplete.** | The ▶ chevron is drawn (`row.gd` draws it, the subclasses call `super._draw()`), the ◀ ▶ arrows stand 8 px away from the value, a disabled row is dimmed by the focus formula, and the dead `focus` uniform is gone. | `widgets/row.gd`, `widgets/setting_row.gd`, `widgets/menu_item.gd`, `widgets/glass_panel.gdshader` |
| 7 | **The glass read as an opaque plate.** | The rows are not glass any more: a flat film (`Color(1,1,1,0.035)`, cyan when focused) and a hand drawn cyan bar. The panel keeps the tinted glass. | `widgets/row.gd` |
| 8 | **The logo glow was a zoom-ghost.** | The word is drawn once into a SubViewport and blurred with a two pass separable gaussian (a horizontal and a vertical pass, `blur_pass.gdshader`); the tight and the wide pass are composited under the crisp glyphs with the premultiplied blend. The glow hugs every letter, there is no displaced copy, and `glyph_positions()` and the drawing share one advance loop. | `widgets/logo_glow.gd` (new), `widgets/blur_pass.gdshader` (new), `widgets/logo_gd` |
| 9 | **An engine error every time the player came back from 操作说明.** | The settings screen connects its selection once, in `_ready()`. | `screens/settings_screen.gd` |
| 10 | **The tests, the files and the capture rig.** | The tests use their own preferences file (`user://test_skyrush_menu.cfg`) and `Prefs` never reads or writes the player's file when the run has `--quality=`; `test_menu.gd` is split (the stacks have their own file), the stick has a left test, the capture rig waits for the world and the title (240 s) and is typed. | `prefs.gd`, `tests/menu_test_base.gd` (new), `tests/test_stacks.gd` (new), `demo/menu_demo.gd` |
| 11 | **No new evidence.** | The captures of `captures/menu/` were deleted and taken again through the key navigation of a real boot at 1600×900, 1600×1000 and 2200×943. | `captures/menu/` |

**The should-fix items that are done:** the Esc on the race and the pursuit results now does what
继续 does (`screens/results_screen.gd`), the route lengths are cached (`screens/race_setup.gd`),
`chip.get("text")` is a typed cast (`screens/controls_page.gd`), the hint bar is 19 px and the
credits 16 px, the car is parked again when the player quits to the menu (`front_end.gd`), and the
magic numbers of the drawing code are named constants.

## In progress / next

1. **`spawns.title` (the world unit).** The world has no parking spot of its own on the Bund: at
   z −300 the road runs from x −131 to −114 and the blocks from x −160 to −140, so there is no
   shoulder. The menu derives the spot itself (the pavement of the Bund at z −312, 4.91 m from the
   nearest lane) and it works — but a `spawns.title` point in `data/city/city.json` would be
   better than a search over ~1800 candidates.
2. **The historic Bund façades are not in the world.** `game/assets/bund/bund_buildings.glb` (with
   the clock tower of 江海关) is never instantiated: the landmark plots of the city are plain
   prisms (`Block_* / Mass`). The title therefore frames the *procedural* city (the plane trees,
   the heritage lamps, the neon signs of the Bund), not the historic façades.
3. **The title frame rate** (the r3 should-fix): on an idle machine `--menu-perf` measured
   `baseline fps_avg=61.4 / menu fps_avg=70.5` (the front end is cheaper than the chase camera),
   so the title runs at 60 fps or better. The first measurement of the session was taken at load
   31 (the other units build the city) and said nothing (`3.4 / 3.7`).

## How to test (exact commands)

    tools/godot.sh check --only=res://ui/menu/
    tools/godot.sh test res://ui/menu/tests/test_menu.gd
    tools/godot.sh test res://ui/menu/tests/test_stacks.gd
    tools/godot.sh test res://ui/menu/tests/test_race_setup.gd
    tools/godot.sh test res://ui/menu/tests/test_results.gd
    tools/godot.sh test res://ui/menu/tests/test_title_stage.gd
    tools/godot.sh test res://ui/menu/tests/test_layout.gd

    tools/godot.sh shot --scene=res://ui/menu/demo/menu_demo.tscn --out=menu_main \
        --menu-size=1600x900 --menu-keys=ENTER --outdir=$PWD/captures/menu --times=8

`--menu-keys=` is a comma separated list of key names (`ENTER`, `DOWN`, `UP`, `LEFT`, `RIGHT`,
`ESC`, `BACKSPACE`), sent once the title screen is up, 0.35 s apart, or at an explicit wait
(`ENTER@0.02` sends the key 0.02 s after the previous one — the fast confirm → back).
`--menu-screen=` opens one screen directly, `--menu-size=` changes the window size,
`--menu-load=0.4` holds the loading screen at that fraction, `--menu-result=free` picks the kind
of the results, `--menu-beats=6` previews six candidate beats of the title stage, and
`--menu-perf` measures the frame rate and watches the traffic.

## Evidence

- `tools/godot.sh check --only=res://ui/menu/` → **CHECK 52 files, 0 failed, 0 engine errors,
  0 warnings**.
- The six test files → **MENU / STACKS / RACE SETUP / RESULTS / TITLE STAGE / LAYOUT TEST PASS
  (0 failures)**.
- The r3 probes are now tests, and they fail without the fix (checked by putting the old
  behaviour back for a moment):
  - the fast confirm → back: 6 failures without the cover/uncover fix, 0 with it;
  - the overlay stack: 2 failures without the cover of the screen below, 0 with it.
- **The real boot** (`tools/godot.sh shot … --menu-screen=title`):
  - `[menu] title stage: 3947 buildings around the title spot`
  - `[menu] title stage: spot=-105.9, 0.0, -312.6 clearance=4.91 m (searched in 153 ms)` — the car
    stands on the pavement of the Bund, 4.91 m from the nearest lane centreline (the review asked
    for ≥ 3.75 m and the traffic for ≥ 4.5 m).
  - `PERF traffic_closest=142.97 m` — the traffic never comes near the parked car.
  - `PERF baseline fps_avg=61.4 / menu fps_avg=70.5` (the machine was at load 31 the first
    time and idle the second: the numbers are only meaningful from the second run).
  - the capture of the fast confirm → back (`captures/menu/menu_fast_back_t3_0.jpg`) shows the
    main menu, fully visible, with the 竞速赛 row highlighted.
- **The captures** (`captures/menu/`, 43 files, all through the key navigation of a real boot):
  - the loading screen at 40 / 70 / 99 % (`menu_loading_0.4_t3_0.jpg`, …): opaque, the Chinese
    labels (正在生成街区 BLOCKS), the new skyline.
  - the three title beats (`menu_title_t2_0.jpg`, `menu_title_t11_0.jpg`, `menu_title_t20_0.jpg`).
  - the cross-fade strip (`menu_xfade_t7_0.jpg` … `menu_xfade_t10_0.jpg`).
  - main, race, race with a route picked, pursuit, settings (the cursor on 雨效), controls, drive,
    pause, pause → settings, the fast confirm → back, and the three results (free / race /
    pursuit) at 1600×900; main, race, pursuit, settings, controls, drive, pause, the results and
    the loading at 1600×1000 and 2200×943.
- **The crops** that the review asked for: the selected row of the main menu with the ▶ chevron
  and the cyan bar, the 雨效 row with its ◀ 开 ▶ arrows, the pursuit setup with the dimmed
  撞毁目标 row, and the results table with the values at the right edge.

## Known issues

- The title stage reads the world tree to know where the buildings are: the buildings have no
  collider, so the physics alone cannot tell a wall from a ray. The buildings are found by their
  meshes (a mass that is taller than four metres and wider than eight; the terrain and the merged
  meshes are skipped) and tested as boxes (`widgets/title_buildings.gd`).
- The world is built over ~35 s here and the title's spot search needs the built world, so the
  title cannot come up before the city does.
- The logo's glow is five SubViewports per logo (the source and the two blur passes, twice): the
  title screen and the loading screen each build one.

## Requests (to core / other units)

- **world / city_layout:** a `spawns.title` point on the Bund promenade (a place that is open to
  the sky, at least 8 m from the buildings and at least 15 m from the traffic). The menu derives
  one itself (`widgets/title_spot.gd`), but a point in `data/city/city.json` would be better than
  a search over 1800 candidates.
- **world / props (bund):** the historic façades of `game/assets/bund/bund_buildings.glb` (the
  clock tower of 江海关, the floodlit cornices) are not in the world: the landmark plots of the
  city are plain prisms. The title shows the procedural city instead.
- **world:** the world is built at 1–2 fps here, so every animation of the loading screen crawls.
  The menu now runs its animations on the wall clock, but the build itself should yield more often.
- **hud:** hide the HUD yourself when `Game.mode == "menu"` — the menu still looks it up by
  `res://ui/hud/hud.gd` in the tree.
- **modes:** a public `stop_mode()` would end a session cleanly when the player quits to the
  menu; until it exists the menu parks the session (`process_mode = DISABLED`).
- **modes:** `GameRecords` and `session.finished` are the menu's contract now — please keep them
  stable.
- **camera:** the motion-blur toggle is found through the public `set_motion_blur` of the camera
  unit's effect stack; a stable handle (or a `Settings` key) would be better.
- **environment:** the rain toggle is found through the group `weather` (`set_rain` /
  `is_raining`); a stable handle would be better.
- **audio:** the menu calls `play_sfx(id)` and `set_music_state(state)` on the node in the group
  `audio` (ids: `ui_hover`, `ui_click`, `ui_confirm`, `ui_back`, `ui_whoosh`).
- **world / core:** **BLOCKER (seen by the lead twice).** The game crashes while the menu camera is
  active: "Reflection probe atlas index invalid … Maximum amount of reflection probes in use (64)"
  followed by "FATAL: Index p_index = -1 is out of bounds (size 64)". It happened during a title
  beat change and right after quit-to-menu. The likely cause is
  `world/build/probe_placer.gd` toggling the probe visibility every 0.5 s.

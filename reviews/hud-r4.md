# hud review round 4 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function **7.0**. Every brief feature is present and fires in the demo and in game: speedo, N₂ slots with
  pending stripes, 小喷 prompt + bar, 大跳 ring, race/pursuit panels, timer, rotating minimap with the real
  city roads, toasts, banner, countdown, flight cluster, BUSTED dim, pause hide.
  - The car-attitude icon is drawn wrong: the wheels sit on the beltline and the car is off-centre (MUST-FIX 1).
  - The unit's own perf test never measures the whole HUD (MUST-FIX 2).
- visual **7.0**. Over dark scenes it is polished and coherent: textured glass, header tabs, a lit bezel,
  heat lenses, an amber banner, and a flight row that follows photo 30 closely
  (`captures/review/hud/cmp_r4_photo30.jpg`).
  - Failures:
    - the reveal-stream attitude icon (the signature flight element) reads as a car with its wheels on the roof;
    - over white the speedometer turns into a light-grey plate and the toast sub-labels fall to ≈3.2:1;
    - the minimap is a 1 px wireframe on flat black.
- code **6.0**. Typed, every file ≤ 400 lines, static/dynamic draw layers, cached bakes, no
  per-frame arrays in the hot `_draw`s.
  - `test_hud_perf.gd` aborts with a SCRIPT ERROR but still prints "OK", and status/result claim the opposite.
  - Raw literals remain in `speed_dial.gd` and `hud.gd`.
  - `hud.gd:278` has a `float(null)` crash path.
  - Two backups were left in `/tmp`.

ART.md §10 on the HUD frames (2-D overlay, so "5/20/100 m" is judged as 1×/2×/3× zoom):
- Pass:
  - (1) values read in greyscale over dark;
  - (2) palette per brief, neon ≤ 15 %;
  - (3) panel glass grain/scanlines, slot weave, dial sunburst visible at 2×;
  - (4) no visible tiling;
  - (6) no blown areas;
  - (8) edges and bezel catch light.
- Fail:
  - (1)/(10) over white: the dial ring zone washes out;
  - (9) the attitude icon geometry is broken (wheels on the beltline, plume ticks mid-door);
  - (10) a flight frame is not a store screenshot while the icon looks broken.

Lead notes (`reviews/hud-lead.md`):
- ✔ the tests extend Node;
- ✔ runs end by themselves (the probe that hit the 400 s tool timeout exited 0);
- ✘ "scratch files go to tmp/<unit>/ and are deleted": see MUST-FIX 4.

## MUST-FIX

1. **The car-attitude icon is mis-assembled: the wheels and plume ticks sit 17.95 px (0.63 m) too high,
   and the whole car is 18 px off-centre (regression of the r4 "pre-scale" refactor).**
   - Wrong:
     - `attitude_icon.gd _scaled()` subtracts `_pivot` from the body, DLO, belt and canopy points.
     - But `:111` `_wheels.append(Vector2(w.x * _scale, -w.y * _scale))` and `:118` `_plume_anchor.append(...)` do not.
     - `:181` then draws everything under `draw_set_transform(centre + _pivot, rot, 1)`.
   - My probe (`tmp/review/hud_r4/probe_icon.gd`, icon 156 px):
     - `_pivot (2.85, -17.95)`, body y −14.7 (roof) … +14.5 (sill);
     - wheel centres y −9.8 / −10.5 with their bottoms at y 0.0, i.e. mid-body ON the beltline instead of
       touching z = 0;
     - plume anchors at y −3.4 instead of the sill (+14.5);
     - the body's centre is drawn 18 px above the disc centre.
   - Capture evidence: `d6_icon.jpg` (photo 30's icon vs ours at 28° and 0°). Ours reads as a slab with
     wheels on the roof, while photo 30 shows wheels below the body.
   - Do:
     - Subtract `_pivot` from the wheel centres and the plume anchors as well (put them through `_scaled`).
     - Draw with `draw_set_transform(centre, rot, Vector2.ONE)`, so the car's bbox centre IS the disc centre.
     - Keep P1/P2 offset ±2 px.
   - Verify:
     - a test in `test_hud_layout.gd` at size 156 asserts:
       - every wheel bottom (y + r) is within ±1.5 px of the ground line (sill + 0.12 m · scale);
       - every plume anchor is within ±1 px of the sill y;
       - the transformed body bbox centre is within 1 px of the disc centre at pitch 0, 90 and 170.
     - 3× crops at pitch 0 / 28 / 170 placed next to `ref/roadster/img/30_live_hud_inverted_on_ramp.jpg`.

2. **`test_hud_perf.gd` never measures the whole HUD, yet reports OK (r3 MUST-FIX 10 not done; the status
   claims it "writes to the telemetry override").**
   - Wrong:
     - `:224` `var tele: CarTelemetry = hud.get("telemetry_override")` reads the default **null**.
     - `:225` writes that null back.
     - `:226` `tele.speed_kmh = 220.0` raises `SCRIPT ERROR: Invalid assignment ... on a base object of type
       'Nil'` in all 3 of my runs (`tmp/review/hud_r4/test_perf_{1,2,3}.txt`).
     - `_test_hud_frames` aborts, so "the HUD logic costs …" and "the HUD costs … on screen" are never
       printed, and the HUD instance and the car leak into `_test_flight_layout`.
     - The suite still ends "HUD PERF TESTS OK". The worker filtered the output with `grep -E "^(PASS|FAIL|INFO|HUD PERF)"`
       (log line 12860), so it never saw the error.
     - The worst-frame check also flakes: run 1 of 3 gave `FAIL the worst widget frame costs 1322 us`
       (load 27–48). Only pass 0 is clean, because passes 1–4 grow linearly (the documented canvas
       accumulation), so "min of the 5 maxima" is really one sample.
   - Do:
     - Create `var tele := CarTelemetry.new()` and `hud.set("telemetry_override", tele)`.
     - Count the checks: `const EXPECTED_CHECKS := 10`, and FAIL if fewer `_check` calls ran, so an aborted
       coroutine can never print OK.
     - Instantiate fresh widgets for every pass (free the old ones), so the 5 passes are comparable, then take
       the min of the per-pass maxima.
   - Verify:
     - 3 runs with no `SCRIPT ERROR`, each printing the logic and on-screen PASS lines; paste them in `status/hud.md`.
     - My probe gives the target magnitude: `hud._process` mean **14 µs** on the ground and **43 µs** in flight
       (p95 34 / 74 µs; `probe_perf.gd`).

3. **Not readable/finished over a bright background (brief: "readable over … white and … magenta";
   style "#0B0F1A @ 70 %").**
   - (a) The speedometer has no glass in its ring zone.
     - `speed_dial.gd:136` draws only `UI.backing_texture()` to r 151; its alpha falls linearly from 0.88, so it
       is ≈ 0.18 at r 120. Only the face (`:137`, r 92) is solid.
     - Over white, the zone r 112–142 straight below the hub measures RGB 171 → 215 (rel. luminance 0.41–0.68)
       against RGB 12–18 on the face (`r4white_t5_5.jpg`, `d2_speed.jpg`).
     - So the dial reads as a light-grey plate, the minor ticks (white α 0.30 / 0.12) vanish, and the labels
       survive only through their outline. Over the demo road the cyan neon strip and the lane dashes run
       through the tick ladder.
     - Do: under the face, `draw_circle(centre, BEZEL_RADIUS - 2.0, Color("0a0f1e", 0.80))` (a named const);
       keep the vignette outside the bezel.
     - Verify: the same scan gives RGB ≤ 80 at r 112–142 over white, and a 2× crop shows the 10 km/h minor
       ticks over white and magenta.
   - (b) The toast plate is below the spec.
     - `toast_row.gd:17-18` uses PLATE_TOP α 0.65 → PLATE_BOTTOM α **0.45**.
     - The English sub-label (`:71`, white α 0.85, no outline) and the points (`:75`) sit on the 0.45 end.
     - Over white the plate at the sub-label rows has relative luminance 0.24–0.29, so white text reaches
       **3.1–3.6 : 1** ("N2 RING", "HEAT 5" in `r4white_t10_3.jpg`, `r4white_t15_7.jpg`, `d3_toasts.jpg`).
     - Do: PLATE_BOTTOM α ≥ 0.70 (TOP 0.85), and give the sub-label and the points
       `outline_size` 3 in #05060F α 0.9, as on the gauges.
     - Verify: the row scan gives contrast ≥ 4.5 : 1 for the sub-label over white.

4. **Lead note violated again (r3 #12): scratch outside `tmp/hud/`, not deleted.**
   - Log line 11375: `cp attitude_icon.gd /tmp/attitude_icon_backup.gd`; line 12381: `cp n2_slot.gd /tmp/n2_backup.gd`.
   - Both files still exist (`ls -la /tmp/*backup*.gd`, 11:10 and 11:37). The user rule also says 临时产物不放 /tmp.
   - Do: delete both. Backups and probes go to `tmp/hud/` and are removed at the end of the round.
   - Verify: no `/tmp/` path in the round's Bash writes, and `ls /tmp/*backup*.gd` lists no HUD file.

## SHOULD-FIX
1. **`hud.gd:278` `float(Game.world.get("loading_fraction"))` crashes.** My probe:
   `SCRIPT ERROR: Invalid call. Nonexistent 'float' constructor` for a world without that property
   (`probe_float.gd`). It fires every 0.1 s (and skips `update_map`) when such a world has no polylines.
   Use `Game.world_built()` (CONTRACTS §4).
2. **The ₂ glyph.**
   - `hud_events.gd:133` still pushes "闪充完成 +N₂". The ₂ falls back to a full-size low "2" that hangs
     under the baseline (`d3_toasts.jpg`), while the ring toast was changed to "N2".
   - Draw the subscript the way `nitro_cluster.gd` does, or write "+N2".
   - Tighten the cluster's "N 2" (`d1_n2.jpg`): kern the 2 to −2 px and drop it to the baseline −4 px.
3. **Chinese-first headers.** The brief says "all text Chinese first", but the tabs read "RACE", "PURSUIT",
   "TIME". Use "竞速 RACE", "追捕 PURSUIT", "时间 TIME", like "地图 MAP".
4. **Minimap material.**
   - Every road is one 1 px line at ≈ α 0.45 on flat black (`d7_game.jpg`); QQ draws a readable track.
   - Draw the roads 2 px #9AA6C4 α 0.7 over a 4 px #05070D casing, and the sky lane 2 px.
   - Put the glass grain/scanline texture under the map base at α 0.5, and add 8 rim ticks every 45°.
5. **Literals (no magic numbers in logic).**
   - `speed_dial.gd`:
     - face radius `92.0` twice (`:137-138`) → `FACE_RADIUS`;
     - gloss `88.0`;
     - the arc width `9.0` four times → `ARC_WIDTH`;
     - glow `16.0`, tip `12.0`/`3.0`, tick lengths 14/8/6.
   - `hud.gd`: the timer/minimap `UI.place` literal sets are written twice (`:126/:205`, `:130/:206/:208`).
     Make them named `Rect2` layout consts.
   - `heat_pips.gd`: `gap := 6.0` twice.
   - `hud_events.gd:102`: `60` → `ToastRow.ZH_SIZE`.
   - `flight_cluster.gd`: `GAUGE_HALF` and `HALF` are the same constant.
6. **Typed containers.** `n2_slot.gd` `_tex_cache: Dictionary` / `_textures_for() -> Dictionary`,
   `skyrush_fonts.gd _tracked`, `demo_steps.build() -> Array`.
7. **The N₂ panel is mostly empty.** The right ≈ 40 % (90 × 180 px) is empty except while the 大跳 ring
   shows. Either shrink the panel to the slots (≈ 150 px), or put the per-slot readouts and the ring there
   permanently.
8. **`hud.gd:167-168`** sets `pivot_offset` once. Update it on the clusters' `resized`, so a window
   resize does not scale them about a stale corner.

## Verified OK (round 3 items)
- **Over white/magenta**: the flight gauges carry a backing, outlines and under-strokes; values read at
  1.5× (`d5_flight.jpg`).
- **N₂ in flight**: the cluster stays visible, scaled 0.8 above DOWNFORCE. Layout test PASS at
  1920×1080/1200 and 2560×1080, α 0.90 (`r4demo_t24_2`, `r4wide_t24_2`).
- **Toasts** lean "/" like the banner. Both lines follow the edge, the glass is clipped to the plate, the
  near miss is 40 px, the ring reads "N2 RING", and the lap toasts work (`d3_toasts.jpg`).
- **Dial labels** sit between the ticks and the motor ring: r 108.1–133.9 (test). The battery row sits below
  the bezel (`d2_speed.jpg`).
- **N₂ slot** (`d1_n2.jpg`):
  - the surface under the meniscus is the light end;
  - the pending stripes read;
  - the 2-texel weave reads as a weave at 2×;
  - the level ticks and the gloss are drawn above the liquid;
  - the bake is shared;
  - slot redraw 2.2–4.9 µs.
- **Countdown, BUSTED, minimap**:
  - the second race's countdown is visible (α 1.00, test);
  - BUSTED keeps the red toast bright over the dimmed panels (`r4demo_t19_3`);
  - the minimap is opaque over the in-game city with real roads, the sky lane, police and POIs
    (`d7_game.jpg`).
- **Cleanup and size**: the r3-named dead code and duplicates are gone (grep); every file is ≤ 400 lines
  (max `n2_slot.gd` 357).
- **The r3 SHOULD-FIXes**:
  - heat pips are lenses with a gradient, highlight and glow;
  - the bezel is lit and has a specular arc;
  - panels have a soft shadow and clipped glass;
  - the banner keeps the dossier's sub-line, white with an outline;
  - typed `Dictionary[int, int]`.
- **Layout matches the references**:
  - QQ PC (`cmp_r4_qq.jpg`): rank top-left, time/best/lap top-right, dial bottom-right, N₂ bottom-left;
  - roadster §6.4 (`cmp_r4_photo30.jpg`): gauge centres at 0.091/0.19/0.815/0.910 W, 0.906 H, 270° arcs,
    a "SKYRUSH LIVE" bug.
- **Ownership**: every round-4 Write/Edit targets `game/ui/hud/**`, `game/ui/theme/**` or
  `status/hud.md`. `tmp/hud/` is deleted. No HUD error in game.

## Evidence (run from /Users/minimax/m/skyrush, 2026-10-20 12:05–12:30, machine load 27–48)
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/` → `CHECK 34 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd` → 38 × PASS, `HUD TESTS OK (0 failures)`, no script error.
- `tools/godot.sh test res://ui/hud/tests/test_hud_layout.gd` → 15 × PASS, `HUD LAYOUT TESTS OK`
  (dial labels r 108.1 .. 133.9; N₂ clears DOWNFORCE at 3 aspects, α 0.90; countdown α 1.00).
- `tools/godot.sh test res://ui/hud/tests/test_hud_perf.gd`, 3 runs (`tmp/review/hud_r4/test_perf_{1,2,3}.txt`):

  | run | pass 0 widgets | worst frame | dial | result | script error |
  |---|---|---|---|---|---|
  | 1 | 175 µs | **1322 µs → FAIL** (budget 600) | 81.4 µs | `HUD PERF TESTS FAILED (1 failures)` | yes |
  | 2 | 116 µs | 475 µs | 42.8 µs | OK | yes |
  | 3 | 76 µs | 178 µs | 28.9 µs | OK | yes |

  - The script error is the same in every run: `test_hud_perf.gd:226` assigns on Nil, so the whole-HUD checks
    never print.
  - Every run also warns "non-equal opposite anchors" from `minimap_panel.gd:214 _rebuild_texture`.
- Probes (mine, `tmp/review/hud_r4/`):
  - `probe_perf.gd` → `ground: hud._process mean 14 us, median 10, p95 34, worst 166`;
    `flight: mean 43 us, median 36, p95 74, worst 1157`.
  - `probe_icon.gd` → `pivot (2.85, -17.95)`, `body y -14.7 .. 14.5`,
    `wheel 0 centre (40.2, -9.8) r 9.8 -> bottom y 0.0`, `wheel 1 (-40.2, -10.5) r 10.5 -> bottom 0.0`,
    `plume anchors y -3.42`.
  - `probe_float.gd` → `SCRIPT ERROR: Invalid call. Nonexistent 'float' constructor` (null property).
- Captures (`captures/review/hud/`, demo runs `errors=0 warnings=0`):
  - `--sixteen10 --warm=1` (1920×1200, HUD at 1:1) → `r4demo_t{1_2,3_3,4_1,5_5,6_6,8_5,9_7,10_3,11_0,12_9,14_0,15_7,16_6,17_9,19_3,20_1,20_9,22_9,24_2,25_9}.jpg`;
  - `--bg=white` → `r4white_t{5_5,10_3,11_0,15_7,19_3,24_2}.jpg`; `--bg=magenta` → `r4magenta_t{5_5,15_7,24_2}.jpg`;
  - `--widescreen` → `r4wide_t{5_5,15_7,24_2}.jpg`; default 1600×900 → `r4std_t{5_5,24_2}.jpg`;
  - in game: `--scene=res://main.tscn --times=3.0,4.6,7.0 --press=accelerate --pulse=hop@4.0 --stub=menu`
    → `r4game_t{3_0,4_6,7_0}.jpg`. Real world, ready after 0.5 s. 60 engine errors (`uniform_set` null in
    the renderer, roads not imported) and none from `res://ui/`.
- Sheets viewed:
  - `sheet_r4_states_s.jpg` (12 states);
  - detail crops: `d1_n2_s.jpg` (2×, dark/white/magenta), `d2_speed_s.jpg` (1.5×, dark/white),
    `d3_toasts_s.jpg` (1.4×), `d4_panels_s.jpg` (1.25×), `d5_flight_s.jpg` (1.5×, 3 backgrounds),
    `d6_icon.jpg` (photo 30 icon 3× vs ours 2.5×), `d7_game_s.jpg` (in-game dial + map 2×), `d8_states_s.jpg`;
  - wider views: `sheet_r4_game_s.jpg`, `sheet_r4_wide.jpg`;
  - reference comparisons: `cmp_r4_photo30.jpg`, `cmp_r4_qq_s.jpg`.
- Pixel scans (PIL):
  - dial ring zone over white: r 112/125/135/142 → RGB 171/191/205/215 vs the face r 80–100 → RGB 12–18;
  - toast rows over white: plate rel. luminance 0.24–0.29 at the sub-label rows → 3.1–3.6 : 1.
- Ownership:
  - `python3 tmp/review/hud_log_r3.py jobs/hud/log.jsonl 8876` (round 4 = session 74411987, from line 8876)
    → all Write/Edit in owned paths; Bash `cp` to `/tmp/attitude_icon_backup.gd` (l. 11375) and
    `/tmp/n2_backup.gd` (l. 12381), both still present;
  - `git status`: `game/ui/` is untracked as a whole (never committed), so the log is the ownership record.
- No feedback was sent (last round).

# hud review round 1 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function **5.0** — every widget exists and the Events wiring works, but 8 real bugs (N₂ fills from the
  top, heat pips never blink, flight layout drifts off-screen, wrong race position from lap 2, Big Hop
  "armed" 4× too early, PITCH mapping, game-time tweens, minimap overflow) and the minimap alone costs
  ~9× the whole-HUD CPU budget.
- visual **4.5** — clean layout and anchors, palette per brief; but ALL Noto Sans SC text renders Thin
  (weight 100), widgets are flat fills with no detail ("贴图纹理什么都要细化"), the attitude icon is a
  scribble, gauges do not match photo 30, and several readouts vanish over a white background.
- code **6.0** — small single-purpose files, ownership clean, check clean; but duck-typed `Control`
  references, per-frame allocations, inline dossier numbers, a perf test that never runs the minimap
  or any `_draw`, test extends SceneTree against CONTRACTS §3.

No `reviews/hud-lead.md` exists, so there are no lead notes yet.

## MUST-FIX

1. **All Noto Sans SC text, "bold" included, renders at Thin (wght 100).**
   - Wrong: `game/ui/theme/skyrush_fonts.gd:32,42` set `variation_opentype = {"wght": 400 / 800}`. In
     Godot 4.7.2 the String key is ignored. `get_supported_variation_list()` returns
     `{2003265652: (100, 900, 100)}`, so the default instance is 100. My probe
     (`tmp/review/hud_probe_font.gd`) measures the width of "TAKEDOWN PURSUIT Roadster 0123456789" at
     40 px: 755 for `{}`, `{"wght":400}`, `{"wght":800}`, `Fonts.text()` and `Fonts.text_bold()`.
     With the integer tag the widths are 400 → 798, 500 → 817, 800 → 853, 900 → 865. Visible result:
     撞毁！ (banner), 小喷!, 第1名, 通缉 and 追捕中 are all hairline-thin
     (`captures/review/hud/detail_sheet.jpg`).
   - Do: key the variation by `TextServerManager.get_primary_interface().name_to_tag("wght")`. Set
     `text()` = 500 and `text_bold()` = 800, and add `text_black()` = 900 for the banner's CJK line
     (dossier §3.5: "CJK font weight Black"). The menu shares this file and gets fixed too.
   - Verify: add a test that asserts the widths above for the same string at 40 px (text 817, bold 853,
     black 865), then recapture the banner and the race panel.

2. **N₂ COPV slots fill from the TOP and read as flat pills.**
   - Wrong: `n2_slot.gd:57` draws the liquid at `Rect2(Vector2.ZERO, Vector2(w, solid_h))`, and y = 0 is
     the top. In-game at 75 N₂ the slot is cyan in its upper ¾ and empty at the bottom
     (`captures/review/hud/r1game_t4_45.jpg`). The demo at 141 N₂ shows slot 2's 41 % hanging from the
     top (`r1demo_t1_0.jpg`). The pending stripes overshoot the rounded corners. `_draw()` allocates
     3–4 `StyleBoxFlat.new()` per redraw. The slot redraws about 24×/s while it pulses (N₂ ≥ 100 most of
     the game) and every frame during a drift, because `nitro_cluster.gd:86-93` calls `set_values`
     twice with different pending values, so the change check always fires.
   - Do:
     - (a) Fill bottom-up with `Rect2(0, h - solid_h, w, solid_h)`. Put the pending stripes directly
       above it with `Rect2(0, h - solid_h - pend_h, w, pend_h)`. Draw any pending overflow in slot 2.
     - (b) Make it a stylised COPV (`ref/roadster/img/24_copv_tank_behind_seats.jpg`):
       - dome caps top and bottom (radius w/2, 2 px rim #1C2A3A);
       - a valve nub on top (10×6 px #9AA6C4 with a 1 px highlight);
       - carbon-overwrap cross-hatch (±35°, 6 px pitch, white α 0.07);
       - level ticks at 25/50/75 % on the right edge (6 px, white α 0.35);
       - liquid gradient from #00B8D4 at the bottom to #7FF4FF at the top, with a 2 px meniscus line
         #D8FDFF;
       - a specular strip on the left third (white α 0.20 → 0).
     - Stripes: 45°, 3 px wide, 8 px pitch, #00E5FF α 0.6, clipped to the inner capsule. When full: a
       6 px outer glow #00E5FF that pulses at 1 Hz.
     - (c) Build StyleBoxes and polygons once as members and rebuild them on resize. No `.new()` in
       `_draw`. Call `set_values` exactly once per slot per frame.
   - Verify: demo at 141 N₂ shows slot 2 filled in its lower 41 %; a drift frame shows the stripes right
     above the liquid; a 2× crop shows the caps, valve, hatch and ticks.

3. **Minimap: 9× over the whole HUD budget, silently drops roads, draws outside its panel, zoomed out
   to 1.8 km.**
   - Wrong:
     - `_draw_roads()` projects every point in GDScript. `project_point` recomputes cos/sin per point,
       a new PackedVector2Array is allocated per polyline per frame, and `update_map()` redraws every
       frame. My timed subclass on `world/data/minimap.json` (5 polylines, 1,959 points), run in
       `tmp/review/hud_probe.gd`, measured **2,684 µs per `_draw`** (headless, so the real cost is
       higher). The brief allows < 300 µs for the whole HUD.
     - `MAX_POINTS := 2000` stops drawing after 2,000 points, so the full city map will lose most of
       its roads.
     - Nothing clips: `clip_contents = false` and POIs are culled with ±20 px slack. My pixel scan of the
       in-game frames at 1600×900 found 95–121 cyan/red pixels outside the panels: left of x 1360, right
       of x 1570, below y 352 (`r1game_t3_0.jpg`, `r1game_t4_45.jpg`).
     - `_scale` fits the whole world ×1.7, clamped to 0.14 px/m. That is 1,800 m across 252 px, so a
       junction 100 m ahead sits 14 px from the arrow.
   - Do:
     - (a) Draw the roads ONCE into a child "MapLayer" Control, in metres × scale, after Douglas–Peucker
       simplification (tolerance 3 m). Per frame, only set its `position`, `rotation` and `scale` (no
       redraw). Redraw only on `set_world` or a zoom step change > 10 %. Remove `MAX_POINTS`.
     - (b) Clip with a parent Control that has `clip_contents = true`, inset inside the cut corners.
       Cull POIs and blips to that inner rect exactly.
     - (c) Zoom: 0.45 px/m (≈ 560 m across) below 80 km/h, easing to 0.25 px/m at 250 km/h.
     - (d) Hierarchy:
       - roads #9AA6C4 α 0.55, 2 px;
       - sky lanes dashed #00E5FF along their real curves (`SkyLane` is a Path3D; collect them once
         from `Game.world`);
       - player arrow with a 1 px #05060F outline and a 40° view cone at α 0.12;
       - an "N" tick on the rim.
       - If you want route or elevated styling, write a request in status.
   - Verify: a timed-subclass test using minimap.json replicated 10× with offsets (≈ 20k points) gives
     mean per-frame map cost ≤ 150 µs. In-game captures show zero map pixels outside the panel.

4. **Heat pips never blink.**
   - Wrong: the 2 Hz red/blue alternation is computed inside `heat_pips._draw()`, but `queue_redraw()`
     only fires when the level changes. Probe: level 3 held for 120 frames gives **1** `_draw` call.
     `r1demo_t9_4.jpg` and `r1demo_t9_65.jpg`, taken 0.25 s apart, both show the same B-R-B pips.
   - Do: flip a `_phase` bool every 0.25 s (accumulate delta in `_process`, only while level > 0) and
     redraw on each flip. Give lit pips a 4 px glow (α 0.35) and unlit pips a #FF3355 α 0.25 outline.
   - Verify: a test counts redraws over 1 s at level 3 → 4 ± 1; two captures 0.25 s apart differ.

5. **Flight layout drifts off-screen after short hops.**
   - Wrong: `hud.gd:167-175` tweens relative to the CURRENT position (`position.y ± 150`,
     `position.x ± 70`) and never kills the previous tween. If flight switches off less than 0.2 s after
     switching on, the clusters stop at an offset. That happens on any airtime of 0.3–0.5 s: kerbs,
     bumps, small hops. Probe: 5 short hops with 0.1 s of "flying" each move the speed cluster
     **+375 px** (off the bottom of the screen) and the N₂ cluster **+175 px**.
   - Do: store each cluster's base offsets at build time and keep a single `_layout_tween`. Kill it
     before starting a new one, and tween to ABSOLUTE targets (base, or base + named FLIGHT_SHIFT).
     Apply the same kill-before-start rule to `flight_cluster.set_active`.
   - Verify: port my `_drift_probe` (`tmp/review/hud_probe.gd`) into your tests → dy = 0, dx = 0.

6. **Race position is wrong from lap 2 onward.**
   - Wrong: `hud_events.gd:150-155` stores max(index + 1) per car. Every car caps at `total` after
     lap 1, and they tie for the rest of the race. Ties always rank the player first because the player
     is appended first. `_on_lap_completed` also ignores rivals. Probe: both cars finish lap 1, then the
     rival passes 6 more checkpoints, and the HUD still shows **"1ST"** (should be 2ND). The status says
     "checkpoint counts", but the code keeps the max index.
   - Do: track `laps_done` per vehicle from `lap_completed` for ALL vehicles. Progress =
     laps_done × total + index + 1. Break ties by the previous order, not player-first. Reset on
     `race_started`.
   - Verify: tests for the probe scenario (→ 2ND) and for the player overtaking in lap 2 (→ 1ST).

7. **The Big Hop ring shows "armed" after 0.06 s.**
   - Wrong: `hop_ring.gd:8,36` treats `charge >= 0.25` as the Big Hop threshold. But
     `CarTelemetry.hop_charge` is already normalised to the hold time: `vehicle/modules/thruster.gd:52`
     sets `hop_charge = hold / HOP_CHARGE_TIME` with HOP_CHARGE_TIME = 0.25 s (`car_tuning.gd:182`). So
     the ring turns amber at a quarter of the required hold, and releasing then gives a small hop.
   - Do: armed = `charge >= 1.0` (amber, pulse, label 大跳). Below that, a grey fill. Document the
     contract in the comment.
   - Verify: test that charge 0.5 is not armed and 1.0 is armed.

8. **Flight gauges do not match the reveal stream** (`ref/roadster/img/30_live_hud_inverted_on_ramp.jpg`,
   roadster dossier §6.4). See `captures/review/hud/flight_cmp.jpg`: photo 30 strip on top, ours below.
   - Wrong:
     - (a) Only the LAST zero is slashed, because `gauge_dial.gd:97` uses `rfind`. Probe:
       100 → "10Ø", 1000 → "100Ø", 3000 → "300Ø". The stream slashes every zero. Smiley Sans' "Ø" is
       also a wide letter O with a stroke, not a digit.
     - (b) Values are italic condensed Smiley Sans at 30 px (digit height ≈ 21 px). The stream uses an
       upright squarish techno face with digit height 0.028 H = 30 px at 1080p. Labels here are italic
       12 px.
     - (c) Ring diameter is 126 px (r = 75 − 12); the target is 0.139 H = 150 px.
     - (d) PITCH maps −180..360 (`flight_cluster.gd:73`). Level flight shows ⅓ full and 170° shows 65 %;
       the stream fills by |pitch| / 180 (170 → 94 %).
   - Do:
     - Add an OFL squarish face under `game/ui/theme/fonts/` with its OFL.txt: Oxanium or Share Tech
       Mono (roadster §6.4, art §7.2).
     - Values upright at 42 px font size (cap ≈ 30 px). Labels upright 14 px, tracking 3 px, white
       α 0.8. Units 12 px.
     - Slash EVERY zero: draw each "0", then a 1.5 px diagonal across its glyph box (x from
       `get_string_size` of the prefix). If the font has the OpenType `zero` feature, use that instead.
     - Ring radius 75 px to the stroke centre, stroke 2.5 px.
     - PITCH fill = clamp(|pitch| / 180, 0, 1); print the signed value.
     - Cache the formatted text; no key strings built per frame.
   - Verify: crops of the four gauges showing 4698 / 17Ø / 68.Ø / 1ØØØ, stacked under photo 30 like
     `flight_cmp.jpg`, with matching size and weight relationships.

9. **The attitude icon is a scribble, not the Roadster.**
   - Wrong: a 12-point hand-guessed profile. At 32° (`r1game_t3_0.jpg`) and 45° (`flight_cmp.jpg`) it
     reads as a bent coat hanger with two circles. Plume ticks are drawn straight down in SCREEN space,
     so at 170° (the stream's signature moment) they point away from the nozzles.
   - Do:
     - Build the outline from roadster dossier §4.1 (or `ref/roadster/roadster_loft.json`), Y forward /
       Z up in metres: centreline top (2.29,0.485) … (0.00,1.147) … (−2.09,0.875), then the tail face
       down to Z 0.12, the sill at Z 0.12 forward, and the nose face (2.29, 0.12 → 0.485).
     - Inner line: DLO top + beltline (§4.1).
     - Wheels at Y +1.4125 and −1.4125, centres Z 0.3425 / 0.367, radii 0.3425 / 0.367 (§2).
     - Scale by the 4.38 m length to 0.80 × the disc diameter. Body stroke 1.75 px white, wheel arcs
       1.5 px. Rotate about the car centre by −pitch.
     - Plume ticks at the P1–P4 positions in car space (front Y ≈ +1.9, sides Y ≈ ±0.3, rear Y ≈ −1.8,
       Z 0.12). Point them along car-local −Z so they rotate with the car. Length = 0.25 × disc radius
       × output, 2 px, tapering from white to α 0.
     - Disc as in photo 30: radial gradient #1A2236 → #05070D at α 0.8, a 1.5 px rim (white α 0.35),
       and a top-left highlight arc (α 0.15).
   - Verify: crops at pitch 0°, 32° and 170° with P1–P4 at 1.0.

10. **Readability over bright scenes fails (brief acceptance), and the backing discs show bands.**
    - Wrong: I captured the demo over a flat white screen and over a flat #FF2BD6 screen
      (`captures/review/hud/bright_sheet.jpg`, scene `tmp/review/hud_bright.tscn`). Over white, the N₂
      count ("126"), the speedo tick labels, "电量 85%" and the battery track vanish, and "最佳" is barely
      readable.
      - `speed_dial._draw_backing` stacks 7 alpha-stepped circles, which show as a bullseye of bands
        over white and magenta. Gauges (6 steps) and the hop ring (4 steps) have the same problem.
      - The demo backdrop never puts white or magenta behind the speedo, N₂, timer or minimap.
    - Do:
      - (a) Give every free-floating label and number a 5 px outline (#05060F α 0.9) plus a shadow
        (#000 α 0.5, offset 0,2). In `_draw` code: `draw_string_outline`, then `draw_string`.
      - (b) Replace the stepped backings with one smooth radial texture, built once and drawn with
        `draw_texture_rect`: GradientTexture2D, RADIAL, 128 px, #05060F α 0.85 at the centre → α 0 at
        the edge.
      - (c) Give the N₂ cluster a glass plate like the other clusters.
      - (d) Add `--bg=white|magenta` to `hud_demo` (a full-screen ColorRect between the backdrop and
        the HUD).
    - Verify: `captures/hud/hud_white_*.jpg` and `hud_magenta_*.jpg` with every text legible and no
      bands.

11. **Speedometer: odd scale, faint labels, flat ring.**
    - Wrong: majors every 33 km/h, labelled 0/66/132/198/264/330. Neither real dials nor the QQ dial
      (`ref/gameplay/scratch/qq_pc_sheet_s.jpg`: 0/100/200/300) use that scale. Labels are 15 px at
      α 0.38, unreadable at 1080p, and the "0" sits under the load ring. There is no minor tick ladder,
      no value-tip marker and no bezel. The speed label also calls `add_theme_color_override` every
      frame (`speed_cluster.gd:72`).
    - Do:
      - Majors every 50 km/h (0…300), labelled 0/50/100/…/300 at 16 px α 0.8 with an outline.
      - Minors every 10 km/h (1 px, α 0.3). The 300–330 band in red #FF3355.
      - Value-arc tip: a 6 px white dot with a 12 px #00E5FF α 0.35 glow.
      - Bezel: outer 2 px ring #2A3550 plus inner 1 px ring white α 0.12.
      - Keep the motor-load ring outside the labels so it never covers "0".
      - Set the speed label colour only when the boost state changes.
    - Verify: dial crops at 0, 137 and 300 km/h.

12. **Toasts: the English must be a small sub-label, and the pop-ups look flat.**
    - Wrong: "完美小喷！PERFECT BOOST" and "完美起步！PERFECT START" are single Smiley Sans strings at
      52–60 px. The brief asks for Chinese first with SMALL English sub-labels. The pop-ups are bare
      outlined text (`captures/review/hud/sheet1.jpg`).
    - Do:
      - Make ToastRow two lines: zh at 60 px Smiley Sans (outline 8 px #05060F), en at 22 px Noto Sans
        SC 500 with 2 px tracking, α 0.85.
      - Points ("+800", "+5") in amber #FFB300.
      - Behind each toast, a skewed (−12°) plate #0B0F1A α 0.55 with a 3 px accent bar on its left edge
        in the style colour.
      - Keep the 0.12 s pop, 0.8 s hold, 0.25 s fade and the scanline sweep.
      - Pass zh and en separately from `hud_events.gd`; for `Events.toast`/`stunt` text, split at the
        first ASCII letter.
    - Verify: captures of the launch, stunt, drift, near-miss and charge toasts.

13. **Panel chrome and layout need finish ("贴图纹理什么都要细化").**
    - Wrong:
      - `glass_panel.gd` is one flat fill plus a 1 px edge.
      - The timer panel is too short: "圈 1/2" crosses its bottom edge. My pixel scan finds cyan at
        y 131 against a panel bottom of 128 (1600×900) in every in-game frame; it is also visible in
        `r1demo_t1_0.jpg`.
      - The race panel is mostly empty, and "/2" floats ~45 px right of "1ST" at the top instead of
        sitting on its baseline (`detail_sheet.jpg`).
    - Do:
      - glass_panel:
        - vertical gradient (#0B0F1A α 0.80 at the top → α 0.62 at the bottom);
        - 1 px inner highlight;
        - cyan L-brackets (10 px long, 2 px wide, #00E5FF α 0.9) on the two un-cut corners;
        - a faint 3 px scanline pattern (white α 0.035, cached texture);
        - a header strip with the panel's English sub-label (RACE / TIME / MAP / PURSUIT, 11 px,
          tracking 3 px, α 0.6).
      - Timer panel ≥ 150 px tall, or a smaller lap font, so nothing touches an edge.
      - Race panel per dossier §8.3: rank at 96 px with "/6" at 40 px on the same baseline. List rows
        28 px with a position badge; the player row gets a cyan pill (#00E5FF α 0.25) and cyan text.
        Fit the panel height to the rows.
    - Verify: zoomed crops of each panel, plus a pixel check that no glyph crosses a panel edge.

14. **HUD animations run in game time.**
    - Wrong: no tween calls `set_ignore_time_scale(true)`, but dossier §3.5 says the banner timeline is
      REAL time. Under the takedown hit-stop (0.05) and slow-mo (0.30), the 0.25 s dock takes ≈ 0.9 s
      and the 2.2 s hold ≈ 5 s. Toasts stretch the same way.
    - Do: use `create_tween().set_ignore_time_scale(true)` for the banner, toasts, countdown and the
      flight/N₂ layout tweens. The race clock may stay in game time.
    - Verify: a test with `Engine.time_scale = 0.3` in which the banner's `_dock` reaches 1.0 within
      0.3 s of real time.

15. **Code rules, and an honest performance test.**
    - Wrong:
      - Cluster references are typed `Control`/`Node`/`RefCounted` with duck-typed calls
        (`hud.gd:33-50`, `hud_events.gd:10-12`), so `check` cannot catch a typo.
      - Untyped `Array`s: `_standings`, `_queue`, `_pois`, `HEAT_UNITS`.
      - Dossier numbers are inline: `hud.gd` 260.0, 12.0, 15.0, /3.0, 0.3, ±150/±70; `hud_events.gd`
        10000; minimap 0.015/0.14/1.7.
      - Per-frame allocations: format-string change keys in `gauge_dial`, `attitude_icon`,
        `pursuit_panel` and `race_panel`; `str(_plumes)`; a new Array every frame in
        `attitude_icon.set_values`; `StyleBoxFlat.new` in `n2_slot`.
      - `test_hud.gd` extends SceneTree, but CONTRACTS §3 says tests `extends Node` via test_host.
      - Its 19 µs perf check never runs the minimap (`Game.player` is null) and measures no `_draw`.
    - Do:
      - Type every member with its preloaded script (`var speed_cluster: SpeedCluster`,
        `var events: HudEvents`, `Array[Dictionary]`, `const HEAT_UNITS: Array[int]`).
      - Use named constants with a § reference for every dossier number.
      - Do change detection with numeric compares, not strings.
      - Port the test to `extends Node`. The perf test must set `Game.player`, load minimap.json,
        include `_draw` (timed subclasses, as in `tmp/review/hud_probe.gd`) and assert the total stays
        under 300 µs.
    - Verify: check clean, and the new numbers written in status.

16. **Evidence does not cover every state.**
    - Wrong: the demo never fires:
      - `Events.toast`;
      - boost kinds nitro, air_mini, landing and charge;
      - takedown streaks (the ×2 and ×5 sub-lines) or a traffic takedown;
      - pursuit search/cooldown/busted with the bars filling, or heat 1–5;
      - sky-lane `flying` or an armed Big Hop;
      - `race_finished` or `game_paused`.
      Also, `main.tscn` now opens the menu title, which covers the HUD: my first in-game capture showed
      only the title.
    - Do: extend the demo loop to fire all of the above. Keep the files ≤ 400 lines by moving the step
      table to `demo/demo_steps.gd`. Put one capture per state in `captures/hud/`, plus the white and
      magenta captures from item 10, plus in-game captures with `--stub=menu`: cruising at 3 s, and in
      the air with `--press=accelerate --pulse=hop@4.0 --times=4.45`. List every capture in
      `status/hud.md`.

## SHOULD-FIX
1. **Free roam shows race readouts.** `main.tscn` in free roam shows 时间 00'00"00 / 圈 1/2. Hide the
   time/best/lap rows when not racing. Take the lap count from the active `RaceRoute.laps` instead of
   the hard-coded 2 (request a signal from the modes unit if you need one).
2. **The clock steps backwards for a frame.** `timer_panel.format_time(59.996)` returns "00'59"00".
   Floor the centiseconds instead of rounding.
3. **Toast conditions.**
   - Show the `drift_ended` toast only when duration ≥ 1.5 s (dossier §8.4).
   - Boost kind `mini` should read "小喷！ MINI BOOST" unless a perfect flag exists. Request
     `&"perfect_mini"` and the 双喷 kinds in status.
4. **Traffic takedowns say "撞车 WRECKED" in red.** That is the dossier's text for the PLAYER wrecking.
   Show the banner (or a small "撞车 TAKEDOWN" toast) for traffic takedowns. Show "撞车 WRECKED" on
   `Events.vehicle_wrecked` when the player is the one wrecked.
5. **Toast queue.** Cap pending toasts at 4, merge repeats ("擦身而过 ×3") and drop items older than 2 s.
6. **"N₂" title.** The "₂" falls back to a tiny, low glyph. Draw "N" plus a separate "2" at 60 % size.
7. **Banner gap.** The space between "撞毁！" and "TAKEDOWN!" is too wide (full-width ！ plus 14 px);
   use 4–6 px.
8. **Minimap icons.**
   - Toll: a gate glyph (two posts and a bar), not a square.
   - Landmark: a small diamond.
   - Police blips: chevrons, per dossier §8.3.
9. **Hop prompt.** Add "跳！HOP ▲" (amber, dossier §5.7/§8.3) once the world exposes roadblock/toll
   distances; write the request in status.
10. **小喷 bar timing.** The bar runs on real time while the window runs on game time. Keep the
    `mini_window_left` request.

## Verified OK
- `check` is clean (28 files, 0 errors, 0 warnings). `test_hud.gd` passes 36/36.
- Ownership is clean. Every Write/Edit and every mutating shell command in `jobs/hud/log.jsonl` targets
  `game/ui/hud/**`, `game/ui/theme/**` or `status/hud.md` (apart from the worker's own ~/.claude memory
  notes). The largest file is `hud.gd` at 284 lines (≤ 400).
- Anchors hold at 16:9, 21:9 (2560×1080) and 16:10 (1920×1200) (`aspect_sheet.jpg`).
- Countdown 3 · 2 · 1 · GO! (cyan GO) and the 完美起步 toast.
- Toasts: max 3 visible, 0.75 → 110 % → 100 % pop, 0.8 s hold, 0.25 s fade, a single scanline sweep.
- Takedown banner: amber #FFB300 parallelogram, black text, pops at 160 % and docks top-left at y ≈ 340.
- Flight cluster: appears after airtime > 0.3 s in the demo and in game, centred at 0.091 / 0.19 /
  0.815 / 0.910 W and 0.906 H, 270° rings open at the bottom, a "SKYRUSH LIVE" bug, the N₂ cluster
  steps aside.
- The speed number turns magenta while boosting. Motor-load ring and battery % are present.
- The HUD hides on `game_paused`. The minimap is heading-up and its police blips blink (it redraws
  every frame).
- Thruster keys: String and StringName dictionary keys are interchangeable in Godot 4.7.2 (probe), so
  the `"Nozzle_P1"` reads are fine.
- Palette constants match the brief (#00E5FF / #FF2BD6 / #FFB300 / #FF3355, glass #0B0F1A @ 70 %).

## Evidence (run from /Users/minimax/m/skyrush)
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/` → `CHECK 28 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd` → 36 PASS, `HUD TESTS OK (0 failures)`,
  "costs 19 us per frame". The minimap is not exercised because `Game.player` is null.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/hud_probe.gd`:
  - `slash_zero: 100 -> 10Ø | 1000 -> 100Ø` · `format_time(59.996) = 00'59"00`
  - `heat pips: level held 120 frames -> _draw calls = 1`
  - `5 short hops: speed cluster dy=375.0 px, N2 cluster dx=175.0 px (expect 0)`
  - `lap 2: rival 6 checkpoints ahead -> HUD shows '1ST' (expect 2ND)`
  - `minimap: 5 polylines / 1959 points, scale 0.140 px/m (252 px = 1800 m)` · `mean 2684.1 us per draw`
  - String reads of StringName thruster keys work (0.9)
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/hud_probe_font.gd`:
  - `supported variations {2003265652: (100, 900, 100)}`
  - width at 40 px: `{"wght":800}` 755 (= Thin); int tag 400/500/800/900 → 798/817/853/865
  - `Fonts.text()` and `Fonts.text_bold()` both measure 755
- Demo captures: `tools/godot.sh shot --scene=res://ui/hud/demo/hud_demo.tscn --out=r1demo --outdir=$HOME/m/skyrush/captures/review/hud --times=1.0,3.3,4.9,5.6,6.2,7.0,7.6,8.4,9.4,9.65,10.6,11.4`
  → 12 frames, errors=0.
- In game: `tools/godot.sh shot --scene=res://main.tscn --out=r1game --outdir=… --times=3.0,4.45,6.5 --press=accelerate --pulse=hop@4.0 --stub=menu`.
  - `r1game_t3_0.jpg`: flight gauges in game. `r1game_t4_45.jpg`: N₂ fills from the top.
  - 95–121 out-of-panel minimap/lap pixels per frame.
  - fps 18–23 on a shared machine. The run's errors are the world unit's Jolt shapes `b_ne_*` and
    `ui/menu/menu.gd:96`, not the HUD.
- Bright test: `--scene=/Users/minimax/m/skyrush/tmp/review/hud_bright.tscn [--bg=magenta]` → `r1white_t5_4.jpg`, `r1magenta_t5_4.jpg`.
- Aspects: `--widescreen` → `r1wide_t11_0.jpg`; `--sixteen10` → `r1sixteen10_t8_2.jpg`.
- Sheets in `captures/review/hud/`:
  - `sheet1.jpg` (states), `detail_sheet.jpg` (2× crops), `game_sheet.jpg`, `bright_sheet.jpg`,
    `aspect_sheet.jpg`
  - `flight_cmp.jpg` (photo 30 above ours)

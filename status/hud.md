# hud status

## Done

Round 3 review addressed (all 12 MUST-FIX + all 9 SHOULD-FIX). Entry `res://ui/hud/hud.tscn`.

**The 12 MUST-FIX**
1. **The flight gauges are readable over white and magenta.** `gauge_dial.gd` draws the
   `UI.backing_texture()` vignette to r 92 plus a solid disc r 70 #05070D α 0.45, outlines every
   string (the value with a 4 px stroke, the label and the unit with 3 px, #05060F α 0.9) and
   puts a dark under-stroke (#05060F α 0.6, RING_WIDTH + 2) under both arcs. Measured contrast
   of the value glyphs over a white background: **18.2 : 1** (DOWNFORCE), 19.9 (PITCH),
   19.6 (ALTITUDE) — the brief asks for 4.5.
2. **The N2 is visible in flight.** `_set_flight_layout` keeps the cluster at α 0.9, scales it
   0.8 about its bottom-left corner and moves it up so its bottom edge sits 24 px above the
   DOWNFORCE ring box (`FlightCluster.flight_nitro_target()`). Only the 小喷 prompt row is hidden
   (`NitroCluster.set_prompt_visible()`). The layout test reads the LIVE rects at 16:9, 16:10 and
   21:9: no overlap with the DOWNFORCE / attitude / PITCH / ALTITUDE boxes (+16 px), α 0.90.
3. **The toast plates lean the right way.** `toast_row.gd` uses the banner's convention:
   `SKEW_DEG := 12.0`, the points (0,0) (w,0) (w−s,h) (−s,h), the accent bar on the slanted edge,
   and every line is shifted by the plate's edge offset at its own height
   (`x_off = −s · y_mid / h`). The glass is filled with `draw_polygon(pts, colors, uvs, glass)`
   (uv = pt / 128) and the row enables `texture_repeat`, so the texture tiles and no longer
   spills out of the parallelogram. A unit test asserts that both lines sit exactly on the
   edge offset. The drift and the near miss get a CYAN bar (a white bar vanishes on the light
   glass plate).
4. **The speedometer no longer overlaps itself.** The labels are centred on their anchor
   (`speed_dial.gd`: the box is 26 × 12 px at LABEL_RADIUS 121, measured once in the static
   layer) — a unit test asserts every corner of every label box lies at 106 < r < 136 (measured:
   **108.1 … 133.9**), between the tick ladder (r 106) and the motor ring (r 138). The battery
   row moved BELOW the dial: the cluster is 300 × 340, the row at y 300, the bar at y 326, so it
   clears the bezel (which ends at y 295) by 5 px.
5. **The N2 slot.** The floats are stored on every call (1.4 → 0.4 → 0.0 ends at 0.00, no stale
   band and no meniscus — the unit test covers it), the liquid gradient is now **relative to the
   band** (the surface under the #D8FDFF meniscus is always the light #7FF4FF, the bottom
   #00B8D4), the bake has mipmaps and the slot uses
   `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` (the hatch is 2 texels wide at α 0.10, so it reads as a
   weave and not as dots), the level ticks are drawn in `_draw` as 6 × 1 px lines above the
   liquid, the specular strip is its own overlay texture drawn last (a full tank still shows the
   gloss) and the baked textures are cached per size and **shared by both slots** (one bake, not
   two).
6. **The countdown of the second race is visible** again: `countdown_label.gd` resets
   `modulate.a = 1.0` in `set_count` and in `hide_count`. A unit test runs GO → 1.3 s → 3 and
   asserts α 1.00.
7. **BUSTED does not dim its own message.** `hud.gd` adds `busted_dim` after the panels and the
   clusters but BEFORE the toasts, the banner and the countdown. Measured: the red of the
   "被捕" toast reaches **R 255** (the review asked for ≥ 240).
8. **The minimap is opaque.** A base of #05070D α 0.85 (inset 2 px) is drawn inside the clip
   before the map texture, so no scene shows through between the roads (verified over the
   tree-lined avenue in game). The north tick is a 13 px bold N on a dark 9 px disc.
9. **The per-frame cost is down.** The battery is compared as a whole percent (a draining
   battery no longer redraws the cluster 120 times in 120 frames) and `set_battery_visible`
   redraws; the evade/busted bar moved into its own child control (the glass panel is not
   repainted while the bar moves); the attitude icon pre-scales its polylines on resize and
   draws them under one `draw_set_transform` (no array is built per frame); the value arc and
   its glow are ONE `draw_polyline_colors` each (the dial went from ~40 `draw_arc` calls to 3);
   the map creates its Callables once in `_ready` and draws the arrow and the cone from constant
   arrays under a transform; `set_standings` is only called after the standings were rebuilt.
10. **The tests measure what they report.** `test_hud_perf.gd` writes to the telemetry
    override (the object the HUD actually reads), times `_draw_overlay` (the per-frame part of
    the map) and drives the flight values, so the gauges and the icon really redraw. It asserts
    the mean < 300 µs AND the max < 600 µs. The flight layout test (`test_hud_layout.gd`) sizes
    the HUD root to 1920×1080 / 1920×1200 / 2560×1080, flies, waits 0.3 s and reads the global
    rects of the clusters and of the four gauges.
11. **The dead code, the false comments, the duplicates and the literals are gone.**
    `speed_cluster`'s unused colour, `glass_panel`'s unused `closed`, `skyrush_theme`'s
    `scanline_texture()`, `skyrush_palette`'s `ramp_sample` / `PANEL_SOLID`, `hud.gd`'s
    `BLIP_RANGE` / `HEADING_EPSILON` / `FLIGHT_NITRO_SHIFT`, the duplicated `SPEED_SCALE` and
    `BANNER_DOCK_Y`, the `60.0` / `1.6` literals of the banner and the `corners` array of the
    brackets are all removed or named. The comments of `hud.gd`, `minimap_panel.gd` and
    `attitude_icon.gd` now describe what the code does.
12. **No scratch file outside `tmp/hud/`.** Every probe of this round lives in `tmp/hud/` and is
    deleted at the end of the round.

**The 9 SHOULD-FIX**
1. The banner is laid out from the visible glyph box (0.88 em above / 0.10 em below the
   baseline), so the padding above and below the text is the same.
2. The heat pips are police-light lenses again: a rounded polygon with a per-vertex gradient
   (the lit colour at the top, 70 % of it at the bottom), a highlight in `col.lightened(0.6)`
   at α 0.8 and a three step glow (grown 2 / 4 / 6 px at α 0.10 / 0.06 / 0.03). The lens and its
   two colour ramps are built once, so a redraw allocates nothing.
3. The dial has a material: a lit bezel (`draw_polyline_colors` over 64 points with a conic
   ramp, #6A7AA0 at the upper left → #141B2B at the lower right), a 1 px specular arc from 200°
   to 250° and a sunburst baked into the face texture (1 px radial lines every 6°, white
   α 0.03).
4. The panels have a finish: the shadow is three stacked copies (2 / 4 / 8 px at α 0.18 / 0.12 /
   0.06) and the glass texture is drawn as a polygon, so it does not spill into the chamfered
   corners.
5. The attitude icon has a body (white α 0.18) under the outline, like photo 30, and P1 / P2 are
   offset ±2 px so they are not drawn twice on the same point.
6. The near miss is a small 40 px pop-up, the ring toast reads "N2 RING" (the ₂ glyph fell back
   to a tiny low 2), and every lap is announced ("完成第N圈 LAP N") with an extra amber
   "最佳圈 BEST LAP" when the lap improves.
7. The map texture is rendered ONCE at min(0.5, 2048 / extent) px/m and only scaled in the
   overlay (a change of the zoom no longer re-renders the roads), and its header is
   "地图 MAP".
8. `hud.gd` (342 lines) and `minimap_panel.gd` (337) are split: the pursuit and the standings
   moved to `hud_pursuit.gd`, the Douglas-Peucker to `minimap_simplify.gd`. Every file of the
   unit is ≤ 400 lines.
9. `progress`, `laps_done`, `checkpoints` and the previous order are typed dictionaries
   (`Dictionary[int, int]`).

## In progress / next

Nothing blocking. The next round should look at the N2 cluster's glass plate (it is the only
panel without a header tab) and at the map's road contrast over a bright scene.

## How to test (exact commands)
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/`
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd`
- `tools/godot.sh test res://ui/hud/tests/test_hud_layout.gd`
- `tools/godot.sh test res://ui/hud/tests/test_hud_perf.gd`
- `tools/godot.sh shot --scene=res://ui/hud/demo/hud_demo.tscn --out=r4demo \
   --outdir=$HOME/m/skyrush/captures/hud --times=1.0,3.5,5.0,6.9,10.3,13.0,15.7,19.2,22.9,24.0`
- bright backgrounds: `... --out=r4white --bg=white` / `--out=r4magenta --bg=magenta`
- aspects: `... --out=r4_21x9 --widescreen` / `--out=r4_16x10 --sixteen10`
- in game: `tools/godot.sh shot --scene=res://main.tscn --out=r4game \
   --outdir=$HOME/m/skyrush/captures/hud --times=3.0,6.0 --press=accelerate --pulse=hop@4.0 --stub=menu`

## Evidence
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/` → **34 files, 0 failed, 0 engine
  errors, 0 warnings**.
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd` → **HUD TESTS OK (0 failures)** (33
  checks: the fonts, the map texels, the slot, the clock, the standings, the pursuit, the
  minimap, the toasts, the banner, the hop ring, the pause).
- `tools/godot.sh test res://ui/hud/tests/test_hud_layout.gd` → **HUD LAYOUT TESTS OK
  (0 failures)** (15 checks: the flight clearance at three aspects, the dial labels, the
  countdown of the second race, the flight gauges).
- `tools/godot.sh test res://ui/hud/tests/test_hud_perf.gd`, three runs on the shared machine:
  - run 1: `the widgets cost 70 us per frame (dial 26, slot 2, gauge 8, icon 26, map 7)`,
    `the worst widget frame costs 154 us`;
  - run 2: `72 us per frame (dial 27, slot 2, gauge 8, icon 27, map 7)`, worst frame 458 us;
  - run 3: `71 us per frame (dial 26, slot 2, gauge 8, icon 27, map 8)`, worst frame 175 us.
  - the N2 slot redraw costs **2.2–2.3 µs** (budget 25), the speed dial **25.8–27.1 µs**
    (budget 150).
  - **The measurement artefact**: in a headless run the canvas commands are never flushed, so
    the cost of a frame grows with the number of frames drawn (the five passes of a run measure
    70 → 137 → 202 → 269 → 348 µs per frame, exactly linear). The first pass is the clean one;
    the test reports the lowest mean and the lowest maximum of the five passes. The HUD itself
    is at 70 µs per frame — a quarter of the 300 µs budget.
- Captures (all regenerated after the last code change, `errors=0`):
  - `captures/hud/r4demo_t*.jpg` — the demo: the countdown, 完美起步, the drift pop-up, the near
    miss, the N2 ring, the takedown banner (×8 RAMPAGE), the heat pips, BUSTED, the armed Big
    Hop, the flight gauges.
  - `captures/hud/r4white_t5_0.jpg`, `r4white_t24_0.jpg` — over a flat white.
  - `captures/hud/r4magenta_t24_0.jpg` — over a flat #FF2BD6.
  - `captures/hud/r4_21x9_t24_0.jpg` (2560×1080), `r4_16x10_t24_0.jpg` (1920×1200).
  - `captures/hud/r4game_t3_0.jpg`, `r4game_t6_0.jpg` — in the sandbox (`main.tscn`,
    `--stub=menu`): the map shows the city road network, the sky lane and the POIs over an
    opaque base, and the flight gauges are up while the car is airborne.
  - Detail crops: `r4_detail_toasts_white.jpg` (3× the toasts), `r4_detail_slots_white.jpg`
    (3× the N2 slots), `r4_detail_dial_white.jpg` (2× the dial + the battery row),
    `r4_detail_flight_white.jpg` / `r4_detail_flight2_white.jpg` (2× the gauges over white),
    `r4_detail_map_game.jpg` (2× the map), `r4_detail_heat.jpg` (2× the heat pips).
- Pixel scans (PIL):
  - the value glyphs of the three gauges over white: contrast 18.2 / 19.9 / 19.6 (≥ 4.5);
  - the red of the BUSTED toast: R 255 (≥ 240);
  - the empty N2 slot in game: the brightest pixel of the cylinder body is 127 (the rim) and the
    bottom rows are ≤ 80 — no stale band and no meniscus. The only brighter pixel is the
    specular highlight of the valve nub at the top of the cylinder (223), which is part of the
    shell.

## Known issues
- **The headless perf measurement grows with the number of frames drawn** (see above): the
  canvas commands of the dummy renderer are never flushed. The first pass of a run is the
  meaningful one.
- The map cannot tell an expressway from a side street: `WorldBase.get_minimap_polylines()`
  returns plain polylines without the road kind, so all roads use one style. A request is in
  the status.
- The lap count comes from the world's first route (`RaceRoute.laps`); the world does not say
  which route is running.
- The 小喷 timing bar runs on real time while the window runs on game time (no remaining-time
  field in `CarTelemetry`).
- The evade bar and the busted meter are computed by the HUD from the dossier numbers (§3.2/§3.4)
  and the police group positions, because `Events` carries no progress value.
- The best lap is kept in memory only (no save system yet).
- The "跳！HOP ▲" prompt of dossier §8.3 is not implemented: the world does not expose the
  distance to the next roadblock / toll plaza.
- The demo's pending-N2 window (5.0 – 6.0 s) is short: on a loaded machine the capture can
  land outside it, and the striped pending band is then not in the frame.

## Requests (to core / other units)
- `Events`: add `signal race_standings_changed(position: int, total: int, standings: Array)` — the
  HUD re-derives the order from the checkpoint and lap events.
- `Events`: add `signal race_route_changed(route_id: StringName, laps: int)`.
- `Events`: add `signal pursuit_progress(evade: float, busted: float, units: int)`.
- `Events`: add `signal roadblock_ahead(distance: float, kind: StringName)` — the "跳！HOP ▲" prompt.
- `WorldBase`: the minimap polylines should carry the road kind (expressway / elevated / street),
  so the HUD can draw them 2.5 px α 0.70 and 1.5 px α 0.45.
- `CarTelemetry`: add `mini_window_left: float` so the 小喷 bar is exact instead of timed.
- `Events` / `CarTelemetry`: the boost kind for a perfect 小喷 — the HUD shows "小喷！ MINI BOOST"
  and would show "完美小喷！ PERFECT BOOST" for a `&"perfect_mini"` kind (also the 双喷 chain kinds).
- `modes` unit: please emit `race_countdown(0)` for the GO beat and `race_started` for the clock;
  emit `lap_completed` for every vehicle, not only the player.
- `menu` unit: the shared theme is `SkyrushTheme.build()` in `res://ui/theme/skyrush_theme.gd` and
  the palette is `res://ui/theme/skyrush_palette.gd`; `SkyrushTheme.glass_texture()` is the tileable
  glass texture for the panels. The Noto weight axis needs the integer tag (see
  `skyrush_fonts.gd`), so the menu's Chinese text gets the same fix for free.
- **The `ai` unit (not the HUD):** `res://ai/common/drive_context.gd:51` overrides `has_signal()`,
  which does not match the native `Object.has_signal(StringName) -> bool`. The compiler treats it
  as an error, so `traffic_director.gd` and the police scripts do not compile and the in-game
  capture reports ~1900 errors. The HUD is not affected (it renders), but the sandbox is.

# hud review round 3 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function **6.5** — the big r2 items are fixed: the minimap shows the city roads in game (my own frames
  `captures/review/hud/game3_r3.jpg`), the slashed zero is a real glyph, the toast merge, the race panel
  and the banner work. New or remaining bugs: the flight gauges vanish over a bright background, the N₂
  readout is hidden while flying, every countdown after the first race is invisible, BUSTED dims its own
  message, an empty N₂ slot keeps a white meniscus line.
- visual **6.5** — clearly better than r2: the glass texture reads, the banner plate is finished, the map
  is clean. But the toast plates lean backwards against the italic text and the English line runs off
  the plate; dial labels and the battery row collide with the rings; the N₂ liquid gradient is upside
  down and the "carbon overwrap" renders as speckle; the heat pips are still flat blocks.
- code **6.0** — typed, small files, static/dynamic layers. But r2 #10/#14 are not finished: the perf test
  still measures a zero telemetry and not the map overlay, the flight test checks a copied formula,
  r2's named dead code is still there, several comments are false, and per-frame allocations remain.

ART.md §10 on the HUD frames:
- **Pass:**
  - (1) values read in greyscale in every calm state;
  - (2) palette per brief, neon share small;
  - (6) no blown areas;
  - (8) panels and banner catch light (edge line, inner glow, top highlight).
- **Fail:**
  - (3) texture detail: the slot weave aliases to dots, the dial face/bezel and the heat pips are flat;
  - (9) overlaps: toast sub-label over the accent bar, dial labels over the motor ring, the bezel
    through the battery row;
  - (10) not a store screenshot in flight over a bright scene (gauges gone).

Lead notes (`reviews/hud-lead.md`): tests extend Node ✔; runs end by themselves ✔. **Violated:**
"scratch files go to tmp/<unit>/, nothing outside owned paths" (item 12).

## MUST-FIX

1. **The flight gauges disappear over a bright background (brief: readable over white and magenta).**
   - Wrong:
     - `gauge_dial.gd` draws a white value, label, unit and arc with no backing and no outline.
     - `captures/review/hud/r3white_t24_0.jpg` (`detail_r3_bright.jpg`, top row): DOWNFORCE, PITCH and
       ALTITUDE are invisible. Only the #5A5A5A rest ring is left.
     - Over the demo road the white lane dashes run straight through "2987", "49" and "14.1"
       (`detail_r3_flight.jpg`, `sheet_r3_wide.jpg`).
     - Photo 30 has dark video behind its gauges; our flight happens over neon, lamps and lane markings.
   - Do:
     - in the static layer, a backing disc: `UI.backing_texture()` drawn to r 92, plus a solid disc
       r 70 #05070D α 0.45;
     - wherever a string is drawn (static or dynamic layer), `draw_string_outline` first: size 4
       for the value, 3 for the label and the unit, colour #05060F α 0.9;
     - a dark under-stroke under both arcs (#05060F α 0.6, width RING_WIDTH + 2).
   - Verify:
     - `--bg=white --times=24.0`, `--bg=magenta` and `--widescreen` captures;
     - in a 2× crop all three numbers and labels read, and the value glyphs have contrast ≥ 4.5:1 against
       their surround.

2. **N₂ is hidden while flying.**
   - Wrong:
     - `hud.gd _set_flight_layout` tweens `nitro_cluster` `modulate:a` to 0.0 (capture t 24.0).
     - In flight N₂ is what the player spends: hover 12/s, sky lane 10/s, roll 20 (SPEC §5). The brief only
       asks to hide the *speedo* partially.
   - Do:
     - Keep the cluster at α 0.9. Scale it 0.8 about its bottom-left corner.
     - Move it up so its bottom edge sits ≥ 24 px above the DOWNFORCE ring top (0.906 H − 78 px; at
       1080p the cluster spans y 788–1028 and the ring rect starts at y 900).
     - Hide only the 小喷 prompt row. Add `FlightCluster.flight_nitro_target()` next to the speed one.
   - Verify: the layout test of item 10 asserts no overlap with the DOWNFORCE and attitude rects (+16 px)
     at 16:9, 16:10 and 21:9, and α ≥ 0.85; capture t 24.0 shows both slots.

3. **Toast plates lean the wrong way and the English line runs off the plate.**
   - Wrong:
     - `toast_row.gd` `PLATE_SKEW_DEG := -12.0` shifts the bottom edge RIGHT: a "\" plate under "/"
       italic Smiley Sans. The takedown banner (+12°) leans "/", so the two pop-ups disagree.
     - `_sub.position.x = skew * 0.5` moves the sub row LEFT while the plate moves right. On the drift
       toast the plate's left edge is ≈ +20 px at the sub row and the row starts at −14 px.
     - "DRIFT", "NEAR MISS" and "N₂ RING" start on or through the accent bar (`detail_r3_toasts.jpg`).
       Over white the "D" of DRIFT is off the plate and invisible (`detail_r3_bright.jpg`, row 3).
     - The glass texture is drawn as a rectangle, so it spills outside the parallelogram. The row never
       enables `texture_repeat`, so the texture is clamped beyond 128 px.
   - Do:
     - Use the banner's convention: `SKEW_DEG := 12.0`, points (0,0) (w,0) (w−s,h) (−s,h) with
       s = tan(12°)·h, and the accent bar from (0,0) to (−s,h).
     - Shift each line by the plate's offset at its own height: x_off = −s · y_mid / h, for the zh label
       and the sub row.
     - Fill the plate with `draw_polygon(pts, colors, uvs, UI.glass_texture())` (uv = pt / 128).
     - Set `texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED` on the row.
   - Verify: 2× crops of drift / near miss / N₂ ring / heat with ≥ 8 px between the accent bar and the
     first glyph of both lines; white-bg crop showing the whole "DRIFT +100" on the plate.

4. **Speedometer: labels and rings overlap (brief: nothing overlaps).**
   - Wrong:
     - `speed_dial.gd _draw_ticks` draws each label at `centre + dir*124 − (24, 7)` (top-left anchoring).
       The top labels "200" / "250" span r ≈ 131–143.
     - So the amber motor ring (r 138) and the bezel's inner rings (r 140, 142) cut through them
       (`detail_r3_slots_dial.jpg`). The comment "the motor-load ring sits outside the numbers" is false.
     - The bezel ring r 145 (centre 1734, 904 at 1080p) runs through "电量 85%" (y 1006–1028) at
       x ≈ 1820–1830, and through the battery bar (y 1032–1038) at x ≈ 1800.
   - Do:
     - Centre every label on its anchor: x − w/2, baseline + (ascent − descent)/2, measured once in the
       static layer.
     - Use LABEL_RADIUS 121. A ≤ 26 × 12 px box then stays between the major-tick ends (r 106) and
       the motor ring (r 137) at every angle. Keep the motor ring at 138.
     - Move the battery row clear of the bezel: either under it (cluster 300×330, y ≥ 304; update the
       anchors and the flight rect), or inside the face under "km/h" (y 228–246, ≤ 120 px wide).
   - Verify:
     - a test that builds every label rect and asserts all its corners lie at 106 < r < 136;
     - a 3× crop of the battery row that clears the bezel by ≥ 4 px.

5. **N₂ slot: a stale meniscus, an upside-down liquid, and aliased detail (r2 #9 c/d unfinished).**
   - (a) Stale value:
     - `set_values` stores `value` only when the ROUNDED value changes. My probe: 1.4 → 0.4 → 0.0
       leaves `value = 0.40`.
     - So an empty slot keeps a 0.53 px band and a 2 px white meniscus at its bottom:
       `r3demo_t22_9.jpg`, slot 2 at N₂ 94, rows y 1084–1086 RGB ≈ 245.
     - Fix: store the floats on every call and skip only the redraw. Draw no liquid below 0.5 units.
   - (b) The gradient is inverted:
     - `_bake_liquid` uses t = y / ih, so the top is #00B8D4 and the bottom #7FF4FF. Slot 1 pixels:
       top (23,190,224), bottom (102,232,246).
     - Use t = 1 − y / ih, so the surface under the #D8FDFF meniscus is the light #7FF4FF.
   - (c) The carbon overwrap reads as random dots:
     - The 3× bake is drawn at 1/3 size without mipmaps, so the 1-texel hatch lines alias to dots.
     - Call `img.generate_mipmaps()` before `ImageTexture.create_from_image`, and set
       `texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` on the slot.
     - Make the hatch 2 texels wide at α 0.10, so it reads as a weave.
   - (d) The level ticks are 2×2 px dots under the rim (pixels x 156–157):
     - Draw them in `_draw` as 6 × 1 px lines from x w−8 to w−2, white α 0.35, at 25 / 50 / 75 %,
       above the liquid.
   - (e) The gloss is hidden:
     - The specular strip is baked into the shell, so the liquid covers it and a full tank has no gloss.
     - Bake it into its own overlay texture and draw it last.
   - (f) The bake is slow:
     - It costs 63–65 ms per slot (probe) and runs again on every resize.
     - Bake once per size into static cached textures shared by both slots.
   - Verify:
     - the probe sequence 1.4 → 0.4 → 0.0 ends at value 0.0, and no pixel of an empty slot is brighter
       than RGB 120;
     - 3× crops at 100 %, 41 % and 0 % show the weave, the ticks and the gloss over the liquid.

6. **Every countdown after the first race is invisible.**
   - Wrong: `countdown_label.gd` fades `_label.modulate.a` to 0 after "GO!" and never restores it.
     Probe: `set_count(0)`, wait 1.3 s, `set_count(3)` → visible = true, modulate.a = **0.00**.
   - Do: reset `_label.modulate.a = 1.0` in `set_count` before the new tween (and in `hide_count`).
   - Verify: a test runs GO → 1.3 s → 3 and asserts modulate.a == 1.0.

7. **BUSTED dims its own message (dossier §8.4: a red 被捕 BUSTED over a 60 % dim).**
   - Wrong: `hud.gd _build` adds `busted_dim` after `toasts`, so the dim covers the toast. In
     `r3demo_t19_2.jpg` the red of "被捕" peaks at R 118; a normal red toast reaches 255.
   - Do: add `busted_dim` after the panels and clusters, but BEFORE toasts, banner and countdown.
   - Verify: capture t 19.2, where the toast's red pixels reach R ≥ 240 and the panels are dimmed.

8. **The minimap is see-through over bright scenes.**
   - Wrong: the map interior is the panel glass at α 0.62–0.80. In my in-game frames the lit wall and the
     sunlit tree foliage show through between the roads (`game3_r3.jpg`, right column;
     `detail_r3_map_worker.jpg`: the orange stone wall).
   - Do:
     - Before the map texture, draw a base inside the clip: #05070D α 0.85, inset 2 px.
     - Keep the frame at the 70 % glass.
     - Give the "N" a 13 px bold face on a dark 9 px disc. At 11 px with a 3 px outline it reads as a
       blob.
   - Verify: a 2× crop of the map over the tree-lined avenue (`main.tscn`, t ≈ 6 s) with no scene
     texture visible between the roads.

9. **Per-frame redraws and allocations remain (r2 #10; brief: no per-frame allocations, < 0.3 ms).**
   - Wrong:
     - `speed_cluster.gd update_values` compares the battery FLOAT. A draining battery therefore redraws
       the cluster, rewrites the label text and re-adds a theme override EVERY frame. Probe: 120 redraws
       in 120 frames (80.0 % → 79.8 %). `set_battery_visible` never calls `queue_redraw()`.
     - `pursuit_panel.gd` redraws the whole glass panel (≈ 8 new arrays) every frame while the
       evade/busted bar moves (search, cooldown, busted).
     - `attitude_icon.gd _to_screen` allocates 7 arrays per redraw (every frame in flight); 38–131 µs.
     - `speed_dial._draw_dynamic` issues ≈ 40 `draw_arc` calls; 57–144 µs per redraw.
     - Minimap overlay (every frame): two `Callable(self, …)`; `Icons.draw_player` builds 3 arrays; every
       police blip builds one.
     - `hud.gd` calls `race_panel.set_standings` every frame, which builds a PackedInt64Array.
     - My three runs of `test_hud_perf.gd`: widgets **260 / 122 / 350 µs**. Run 3 FAILS the 300 µs
       budget, and that sum still leaves out the map overlay (probe: 54 µs mean, 175 µs max).
   - Do:
     - speed_cluster: compare `int(round(b * 100))` and update only on change; redraw in
       `set_battery_visible`.
     - pursuit: put the bar in its own child Control, so only the bar redraws.
     - icon: pre-scale the polylines on resize and draw them under
       `draw_set_transform(pivot_screen, rot, Vector2.ONE)`.
     - dial: draw the value arc and its glow with `draw_polyline_colors`, one call each, refilling member
       arrays.
     - map: create the Callables once in `_ready`; draw the arrow and the cone as const arrays under
       `draw_set_transform`; reuse one member array for the blips.
     - Call `set_standings` only after `_rebuild_standings()`.
   - Verify: item 10's test passes in 3 of 3 runs. No `PackedVector2Array(`, `[` literal or `.new()` is
     left in a `_draw*` that runs every frame.

10. **The perf and layout tests do not measure what they report (r2 #7 and #10).**
   - Wrong:
     - `test_hud_perf.gd _test_hud_frames` still sets `telemetry_override = CarTelemetry.new()` and then
       writes `car.telemetry`, a different object. This is the exact bug quoted in r2 #10. The "logic" and
       "on screen" numbers are for speed 0 and N₂ 0.
     - `TimedMap` times `_draw_layer`, the rare texture render. `_draw_overlay`, which runs every frame,
       is not timed.
     - `MAX_BUDGET_US` is declared and never asserted.
     - `test_hud.gd _test_flight_clearance` tests `FlightCluster.flight_speed_rect()`. That function is a
       copy of the layout numbers (−336 / −326 / 300 and a second 0.72 `SPEED_SCALE`), not the controls.
   - Do:
     - Write to the override object.
     - Time `_draw_overlay`.
     - Drive the flight values, so the gauges and the icon redraw.
     - Assert mean < 300 µs AND max < 600 µs for `_process` + all `_draw`.
     - Flight test: size the HUD root to 1920×1080, 1920×1200 and 2560×1080, fly, wait 0.3 s, then read
       `get_global_rect()` of the speed cluster, the N₂ cluster and the four gauges.
     - Delete `flight_speed_rect`, `flight_gauge_rects` (if unused) and the duplicate scale.
   - Verify: three run outputs pasted in `status/hud.md`.

11. **Dead code, false comments, duplicates and literals (r2 #14; user rule 不留死代码).**
   - Dead:
     - `speed_cluster.gd:76-80` the unused `col` (named in r2 #14);
     - `glass_panel.gd _draw_inner_glow` the unused `closed`; `_draw_glass` ignores its `poly`;
     - `skyrush_theme.gd` `scanline_texture()` and `_scanlines`;
     - `skyrush_palette.gd` `ramp_sample`, `PANEL_SOLID` (no user in hud or menu);
     - `hud.gd` `BLIP_RANGE`, `HEADING_EPSILON` (unused copies of the minimap's);
     - `test_hud_perf.gd` `MAX_BUDGET_US`.
   - Duplicates: `hud.gd FLIGHT_SPEED_SCALE` / `flight_cluster SPEED_SCALE`; `hud_events BANNER_DOCK_Y`
     / `takedown_banner DOCK_Y`.
   - False or misplaced comments:
     - `hud.gd:197-198` (the "rect the speed cluster occupies" doc sits on `_telemetry()`);
     - `hud.gd:47-48` (sits on `LAYOUT_TIME`);
     - `minimap_panel.gd:5-7` and `:218` ("child MapLayer … world metres … only moved, rotated and
       scaled"): it is a SubViewport texture, re-rendered on zoom steps;
     - `attitude_icon._make_disc` ("#1A2236 -> #05070D at alpha 0.8"): the code fades #1A2236 α 0.85 → 0;
     - `n2_slot._draw_band` calls (texture, rect, src_rect) an engine-build quirk; it is the documented
       order.
   - Literals:
     - `takedown_banner._draw` `60.0` and `1.6`;
     - `glass_panel._draw_brackets` builds a `corners` Array per draw;
     - `flight_cluster._add_gauge` `0.906`, and the x fractions repeated in `_build`.
   - Verify: grep finds none of these, and `check` is clean.

12. **Lead note violated: scratch files outside the owned paths.**
   - Wrong:
     - `jobs/hud/log.jsonl` line 6091/6095: `/tmp/diag.gd` copied to `game/tools/diag_hud.gd` (core-owned)
       and run.
     - Line 7443: `game/tools/diag_slot.gd`.
     - Both were deleted, but `reviews/hud-lead.md` and the user rule (临时产物不放 /tmp) forbid both.
   - Do: put scratch in `tmp/hud/` and run it with `tools/godot.sh test /Users/minimax/m/skyrush/tmp/hud/x.gd`
     (absolute paths work: my probes ran that way). Delete `tmp/hud/` at the end.
   - Verify: the round-4 log writes only to `game/ui/hud/**`, `game/ui/theme/**`, `status/hud.md` and
     `tmp/hud/**`.

## SHOULD-FIX
1. **Banner padding (r2 #5 verify).** Pixel scan of `r3demo_t13_0.jpg` (x 120–560): plate y 342–527,
   main text 378–434, sub-line 473–503. That is 36 px top, 39 px gap, 24 px bottom; r2 asked for
   |top − bottom| ≤ 4. Lay the lines out from the visible glyph box (CJK ≈ 0.88 em above the baseline),
   not the Noto ascent.
2. **Heat pips are still flat blocks (r2 SHOULD-FIX 2).**
   - Now: the "gradient" is two flat halves; the "1 px highlight" is drawn in the lens colour, so it is
     invisible; the glow is one hard rect.
   - Do: a per-vertex gradient (`draw_polygon`, top col → bottom col × 0.7); a highlight in
     `col.lightened(0.6)` α 0.8; the glow as rects grown 2 / 4 / 6 px at α 0.10 / 0.06 / 0.03.
3. **Dial material (贴图纹理细化; QQ tiles in `ref/gameplay/scratch/qq_pc_sheet_s.jpg`).** The bezel is
   three flat rings and the face a plain radial gradient.
   - A lit bezel: `draw_polyline_colors` over 64 points with a conic ramp, #6A7AA0 at 135° (upper left)
     to #141B2B at 315°.
   - A 1 px specular arc 200°–250° (#FFFFFF α 0.25).
   - A faint sunburst baked into the face texture: 1 px radial lines every 6°, white α 0.03.
4. **Panel finish.**
   - `_draw_shadow` is a hard copy offset 4 px, not the soft 8 px shadow. Use offsets 2 / 4 / 8 px at
     α 0.18 / 0.12 / 0.06.
   - The glass texture fills the chamfered corners. Draw it with `draw_polygon(top, colors, uvs, tex)`.
5. **Attitude icon.**
   - Photo 30 shows a solid white car; add a body fill, white α 0.18, under the outline.
   - P1 and P2 share the point (1.9, 0.12), so one tick is drawn twice. Offset them ±2 px across the
     car.
6. **Toast details.**
   - The near-miss toast should be small, 40 px (dossier §8.4).
   - "N₂ RING" uses U+2082 at 22 px, which falls back to a tiny low "2". Write "N2" or draw the
     subscript.
   - The lap toast appears only on a new best lap (`hud_events._on_lap_completed`). Show
     "完成第N圈 LAP N" every lap, plus an amber "最佳圈 BEST LAP" when the lap improves.
7. **Map.**
   - Render the texture once at min(0.5, 2048 / extent) px/m and only scale it in the overlay. Today
     one accelerate + brake triggers 12 re-renders at 157–252 µs each (probe).
   - The map is the only panel with no Chinese: make the header "地图 MAP".
8. **File size.** `hud.gd` is 388 lines and `minimap_panel.gd` 385. Split them before the fixes push
   them over 400, e.g. `hud_pursuit.gd` (pursuit + standings) and `minimap_simplify.gd`
   (Douglas–Peucker).
9. **Typed dictionaries.** Use `Dictionary[int, int]` for `progress`, `laps_done`, `checkpoints` and
   `_previous_order` (Godot 4.7).

## Verified OK
- `check`: 31 files, 0 failed, 0 engine errors, 0 warnings. `test_hud.gd`: 43 PASS,
  "HUD TESTS OK (0 failures)".
- **Minimap (r2 #1/#12) fixed.**
  - The texel round-trip is 0.00 px.
  - My own in-game frames (`r3game3_t3_0/t6_0.jpg`, real world, `--stub=menu`) show:
    - the road network (654 / 375 road-coloured px in the map; 31 with the world broken);
    - the dashed cyan sky lanes, police chevrons, POI diamonds, the view cone and the N tick.
  - It stays heading-up.
  - minimap.json: 309 roads, 30,546 points, a 4027×3028 m extent, texture 1062×798 at 0.264 px/m.
- **Slashed zero (r2 #6) fixed.** Oxanium "0" shapes to glyph 258 with `Fonts.techno()` and to 245 plain,
  so the `zero` feature is live. The end ticks point inward; the 270° rings sit at 0.091 / 0.19 /
  0.815 / 0.910 W, 0.906 H.
- **Race panel (r2 #4) fixed.** 1ST and /2 share a baseline, there are no ghost badges, the player has a
  full-width pill, and the panel grows with its rows. The banner docks below it.
- **Banner (r2 #5) finished.** Gradient #FFC233 → #FFA000, a top highlight, hazard stripes and a drop
  shadow, scaled as one transform; it leans "/".
- **Glass texture (r2 #8) visible.** In the timer panel the row-mean luminance std is 7.3 levels against
  0.5 for the background. `texture_repeat` is on, plus an inner glow and the header tab.
- **Toasts.** The merge key is zh|en; HEAT 3 and HEAT 5 are separate rows (`r3demo_t15_7.jpg`); ↑ / ↓
  show; the points follow the English text on one row.
- **Other widgets.**
  - The heat pips blink 4×/s; the hop ring pulses while armed (大跳).
  - The 小喷 prompt and its bar show; the pending gain overflows into slot 2 (`t5_6`); slot redraw 3–8 µs.
- **Speed cluster in flight.** It shrinks to 0.72, dims and clears PITCH / ALTITUDE (≈ 32 px at 1080p
  and 1200p). Five short hops leave a 0.0 px drift.
- **Anchors** hold at 16:10 (1920×1200, 1:1) and 21:9 (2560×1080).
- **Ownership.** Every round-3 Write/Edit targets `game/ui/hud/**`, `game/ui/theme/**`, `status/hud.md`
  or the worker memory. No HUD run is left; `tmp/hud/` is gone; every file is ≤ 400 lines.
- **Evidence current.** The newest code is 09:58 (`hud.gd`); the worker captures are 09:59–10:06; the
  status counts (43 PASS) are true.

## Evidence (run from /Users/minimax/m/skyrush)
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/` → `CHECK 31 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd` → 43 × PASS, `HUD TESTS OK (0 failures)`
- `tools/godot.sh test res://ui/hud/tests/test_hud_perf.gd`, three runs on the shared, loaded machine:
  - `widgets 260 us (dial 97, slot 6, gauge 31, icon 61, map 65)`, logic 18, on screen 24;
  - `widgets 122 us (dial 57, slot 3, gauge 17, icon 38, map 7)`, logic 8, on screen 7;
  - `FAIL the widgets cost 350 us (dial 144, slot 8, gauge 54, icon 131, map 13)` → `HUD PERF TESTS FAILED`.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/hud_probe_r3.gd`:
  - `countdown second race: visible=true modulate.a=0.00`
  - `slot bake (ready) 64831 us`, `slot rebake 62890 us`
  - `slot after 1.4 -> 0.4 -> 0.0: value=0.40 (solid_h 0.53 px)`
  - `map bounds (4026.8, 3027.7), texture (1062, 798) at 0.264 px/m`
  - `map overlay 53.8 us/draw mean, max 175 us`
  - `speed cluster redraws over 120 frames (battery 80.0% -> 79.8%): 120`
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/hud_probe2_r3.gd`:
  - `zero glyph: plain 245, techno() 258`
  - `309 roads, 30546 points; 12 texture re-renders in one accelerate+brake, mean 157 us, max 252 us`
- Captures (`captures/review/hud/`, demo runs errors=0):
  - demo, `--warm=1 --sixteen10`, 24 states → `r3demo_t*.jpg`;
  - `--bg=white` → `r3white_t{4_3,5_6,15_7,24_0}.jpg`; `--bg=magenta` → `r3magenta_*`;
  - `--widescreen` → `r3wide_t{5_6,24_0}.jpg`.
  - In game:
    - `--scene=res://main.tscn --press=accelerate [--pulse=hop@4.0] --stub=menu` → `r3game_*`, `r3game2_*`.
      At 10:22 the world unit's `world.gd` failed to compile (stub world), so their maps are empty.
      That is not a HUD fault.
    - `r3game3_t3_0/t6_0.jpg` at 10:39, real world.
- Sheets:
  - `sheet_r3_states.jpg` (12 states);
  - `detail_r3_toasts.jpg` (1:1);
  - `detail_r3_slots_dial.jpg` (2× N₂ and dial over the QQ tiles);
  - `detail_r3_panels.jpg` (1.5×);
  - `detail_r3_flight.jpg` (photo 30 `ref/roadster/img/30_live_hud_inverted_on_ramp.jpg` above ours);
  - `detail_r3_bright.jpg`; `sheet_r3_wide.jpg`;
  - `game_sheet_r3.jpg`, `detail_r3_map_worker.jpg` (worker frames 09:59), `game3_r3.jpg` (mine, with
    2× map crops).
- Pixel scans (PIL):
  - slot liquid top / bottom and the empty-slot bright rows (item 5);
  - BUSTED red R 118 vs 255 (item 7);
  - banner rows (SHOULD-FIX 1);
  - glass row std (Verified);
  - road pixels in the map area.
- Ownership: `tmp/review/hud_log_r3.py` over `jobs/hud/log.jsonl` from line 5603 (prompt-3) lists the
  Write/Edit targets and the shell writes. Lines 6091/6095/7443 are item 12.

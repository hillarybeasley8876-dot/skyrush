# hud review round 2 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function **6.0** — fonts, bottom-up N₂ fill, pip blink, flight drift, race position, hop threshold and
  real-time tweens are fixed. But the **minimap shows no roads in game** (the road texture is drawn
  ~2 km off). Toast text overlaps itself, a heat-level toast is swallowed by the merge logic, empty rank
  badges hang below the race panel, and in flight the speedo touches the ALTITUDE gauge.
- visual **5.0** — the HUD is cleaner than in r1 and the attitude icon now reads as the Roadster. Against
  "贴图纹理什么都要细化" it is still flat vector strokes on near-flat glass: the scanline texture is
  mathematically invisible, there is no dial face, no material on the banner and no specular on the COPV
  slots. Every zero carries a long strike-through. The in-game map is an empty dark box.
- code **6.0** — typed, small files, tests `extends Node`, ownership clean. But: dead code and false
  comments in the minimap, the perf test still times no widget `_draw` (and drives a zero telemetry),
  N₂ slot / speedo / gauges cost 130–720 µs per redraw, and per-frame string keys remain.

ART.md §10 on the HUD frames:
- **Pass:** (1) the values read in greyscale (white on dark plates, the car stays clear); (2) the
  palette and the neon share are in budget; (6) emissives are balanced.
- **Fail:**
  - (3) texture detail: the glass is flat;
  - (8) no edge or bevel catches light on any panel or dial;
  - (9) floating elements: the badges outside the race panel and the meniscus overshoot;
  - (10) not a store screenshot yet: an empty map, overlapping text and struck-through zeros.

Lead notes (`reviews/hud-lead.md`): satisfied. Tests extend Node, no runs left in the background, and
`tmp/hud/` was deleted. Fix items 1–14 below.

## MUST-FIX

1. **The minimap draws no roads in game: the road texture is offset by half its size.**
   - Wrong:
     - `minimap_panel.gd` `_draw_layer()` and `_draw_dashed_polyline()` draw every point at
       `origin + (p - _world_min) * _tex_zoom`, with `origin = _vp_layer.size * 0.5`.
     - `_draw_map_texture()` places texel `(p - _world_min) * _tex_zoom` at `p`. That is a different
       mapping.
     - My probe (`tmp/review/hud_probe_r2.gd`) on the real city gives a texture of 1791×1341 px at
       0.45 px/m. The roads land (895.5, 670.5) px = **(1990 m, 1490 m)** away from where they belong.
     - In game the car drives straight up 中山东一路 and the map is empty, apart from POIs
       (`captures/review/hud/r2game2_t2_0.jpg`, `game_sheet_r2.jpg`). The demo grid shows a single
       "L" (`detail_panels.jpg`).
     - Your own `captures/hud/hud_game_t3_0.jpg` and `hud_game_t6_5.jpg` hold **16** road-coloured
       pixels in the map area. `r1game_t3_0.jpg` holds 1,133. The status still says "the map with the
       city road network".
     - Also: the texture is drawn at `_tex_zoom` while POIs and blips use `_zoom`, so they disagree by up
       to 10 % between redraws.
     - `set_world()` first builds a 16×16 texture at zoom 0.
     - Every 200 m (`CULL_STEP`) the WHOLE map is re-rendered, although nothing is culled.
   - Do:
     - (a) Use `origin = Vector2.ZERO` in both draw functions.
     - (b) In `_draw_map_texture` scale by `k = _zoom / _tex_zoom`: `draw_set_transform(translation, _rot,
       Vector2(k, k))` with `rel = (_world_min - _player_pos) * _zoom`.
     - (c) Skip `_rebuild_texture()` while `_drawn_zoom == 0`.
     - (d) Re-render only on `set_world` or a zoom step: delete the `CULL_STEP` trigger, or implement real
       culling. Pick one, and make the comments true.
     - (e) Pre-build one `PackedVector2Array` of segment pairs in `set_world`, then call `draw_multiline`
       once per style. No allocation per redraw.
   - Verify:
     - A unit test: for 20 random road points P, the texel used by `_draw_layer` maps back to P through
       the overlay's transform within 1 px.
     - An in-game capture on 中山东一路 shows the straight road through the arrow, plus its cross streets.

2. **Toast points are drawn on top of the English sub-label.**
   - Wrong: `toast_row.gd _fit()` puts `_points` and `_en` at the same `sub_y`. The result:
     - "+100" over "DRIFT";
     - "+40" over "N₂ RING";
     - "+5 ×3" over "NEAR MISS".
     See `captures/review/hud/detail_toasts.jpg`. The brief says "nothing overlaps".
   - Do: put the points after the English text in one centred row (12 px gap, amber #FFB300, same 22 px),
     or to the right of the zh line at 36 px on its baseline. Size the plate to the widest line + 2×26 px.
   - Verify: crops of the drift (demo t 5.6), N₂ ring (t 10.3) and a near-miss ×3 with no glyph overlap.

3. **The toast merge swallows events and never refreshes the row.**
   - Wrong: `toast_stack.push()` merges on the zh line only.
     - "通缉等级 ↑ HEAT 5" merges into the visible "HEAT 3" row. The English stays "HEAT 3".
     - `add_count()` edits `_points`, which is hidden when the points were "", so nothing changes.
     - The row keeps fading (`r2demo_t15_7.jpg`: a faded "HEAT 3" while the heat is 5).
   - Do:
     - Merge key = zh + "|" + en (or an explicit kind).
     - On a merge, update en/points, show "×N" visibly in amber, and restart the row: kill the tween,
       re-pop 0.12 s, hold 0.8 s.
     - `_on_heat_changed`: "通缉等级 ↑" only when the level rises, "通缉等级 ↓" when it drops.
   - Verify: a test pushes HEAT 3, then HEAT 5 0.3 s later; at +0.5 s a row reads "HEAT 5" with
     modulate.a == 1.

4. **Race panel: empty badges hang outside it, and "/N" is not on the rank baseline (r1 #13 not done).**
   - Wrong:
     - Rows ≥ total hide only the name and the mark. The 28 px `PanelContainer` badges stay visible with
       the default stylebox: grey boxes at x 58–86, y 337–362 / 368–394 / 399–427 (1080p), below the
       panel edge at y 336 (`r2white_t5_6.jpg`, `qq_vs_ours.jpg`).
     - "/2" is `VERTICAL_ALIGNMENT_TOP` in a 44 px box. It floats ≈ 25 px above the "1ST" baseline,
       40 px to its right (`detail_panels.jpg`).
     - `set_standings` builds a name string every frame to detect changes.
   - Do:
     - Hide the whole row HBox for i ≥ total, and fit the panel height to its content (+14 px padding).
     - Draw rank + "/N" on ONE baseline with a 6 px gap: draw both in `_draw`, or put both labels in an
       HBox with bottom alignment and compensate the font descent.
     - Player row: a full-width pill #00E5FF α 0.25, radius 6, behind the badge + name.
     - Change detection: compare the player index, the count and the instance ids (ints). No strings.
   - Verify: a white-bg capture with zero non-panel pixels outside the panel rect; a 2× crop where "1ST"
     and "/2" share the baseline ±1 px.

5. **Takedown banner: the two lines touch, the padding is lopsided, and the plate is a flat fill.**
   - Wrong:
     - Pixel scan of `r2demo_t11_6.jpg` (1080p): plate y 342–505, main text y 362–420, sub-line
       y 424–456.
     - That is a **4 px gap**, so the 3 px outlines touch. The top padding is 20 px, the bottom 49 px.
     - During the 160 % pop, `int(MAIN_SIZE * s)` rasterises a new font size every frame (~40 sizes).
   - Do:
     - Lay the lines out from the font ascent/descent: 16 px top and bottom padding, a 10 px line gap,
       the block centred.
     - Draw at the fixed 64/36 px and scale the whole banner with `draw_set_transform`.
     - Finish the plate:
       - a vertical gradient #FFC233 → #FFA000;
       - a 2 px top highlight #FFE08A;
       - 45° hazard stripes on the right 48 px (#0A0A0A α 0.18, 10 px pitch);
       - a 6 px drop shadow (#000 α 0.35).
   - Verify: the same pixel scan gives a gap ≥ 10 px and |top − bottom padding| ≤ 4 px.

6. **Every slashed zero reads as a strike-through (dossier §6.4, photo 30).**
   - Wrong:
     - `gauge_dial._draw_value` draws the slash across the full advance width.
     - It runs from `get_height() * 0.72` (≈ 38 px) above the baseline to 2 px below it, while the "0"
       glyph is 29 px tall. The stroke sticks out at the top and bottom of every zero: "Ø KG",
       "Ø.Ø M", in game "-9Ø" (`flight_cmp_r2.jpg` rows 2–3). In photo 30 the slash sits INSIDE the
       counter.
     - The end ticks run r−6 → r+6, so they read as outward "legs". Photo 30 has short inward ticks.
   - Do:
     - Oxanium ships the OpenType **`zero`** feature (GSUB features: ccmp, pnum, zero; cap height
       690/1000; I parsed the font file). Set
       `opentype_features = {TextServerManager.get_primary_interface().name_to_tag("zero"): 1}` on
       `Fonts.techno()` and delete the manual slash code.
     - Draw the end ticks r−8 → r only, 2 px.
   - Verify: 2× crops of 1000 / 0 / 0.0 / 170 stacked under photo 30. The slash stays inside each 0.

7. **In flight the speedo collides with the ALTITUDE gauge (brief: "hide the speedo partially to avoid
   clutter").**
   - Wrong: after `FLIGHT_SPEED_SHIFT` (0, −150) the speed cluster spans y 604–904 at 1080p:
     - the dial bezel ends at y 900;
     - the battery bar sits at y 882–888 (x 1734–1874);
     - the radial backing (r 151) reaches y 905;
     - the ALTITUDE ring starts at y ≈ 902 (centre 1747, 978).
     That leaves 2–3 px (`game_sheet_r2.jpg` bottom-right crop).
   - Do: in flight, tween the speed cluster to scale 0.72 about its bottom-right corner, alpha 0.75, and
     hide the battery row. Place it so its rect, backing included, clears both right-hand gauges by
     ≥ 24 px. Keep the absolute targets and the single tween.
   - Verify: a test asserts that the cluster's global rect (grown by the backing) does not intersect the
     PITCH/ALTITUDE rects grown by 16 px, at 16:9, 16:10 and 21:9.

8. **Glass panels: the "texture" is invisible (贴图纹理什么都要细化).**
   - Wrong:
     - `scanline_texture()` texels are α 0.035, and `glass_panel._draw_scanlines` modulates them by
       α 0.035 again: an effective **α 0.0012**.
     - `texture_repeat` is never enabled, so the 4×3 tile is stretched, not tiled.
     - The gradient α 0.80 → 0.62 barely reads.
     - The header labels are 11 px Smiley oblique, which is 9 px in the default 1600×900 window.
   - Do: build once (cached in `skyrush_theme.gd`) a 128×128 tileable glass texture:
     - 3 px scanlines (white α 0.05 on one row of every three);
     - seeded value grain ±3 %;
     - a 16 px dot grid (white α 0.04).
     Then:
     - draw it with `texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED` and modulate 1.0;
     - add an inner edge glow (2 px #00E5FF α 0.18 just inside the edge);
     - add an outer soft shadow (8 px, #000 α 0.35);
     - make the header a filled chamfered tab (#00E5FF α 0.10, 18 px tall) with the label at ≥ 13 px.
   - Verify: a 2× crop of the race and timer panels where scanlines and grain are visible; the per-row
     luminance std-dev inside the panel is ≥ 2 levels.

9. **The N₂ COPV slots: glow and meniscus bugs, missing r1 detail, very slow redraw.**
   - (a) The full-slot glow polyline is not closed (`_capsule_outline`). There is no glow on the left
     side: pixel row y 1020 of `r2demo_t5_6.jpg` shows glow at x 102–105 and none at x 52–57. Close the
     loop.
   - (b) The meniscus is drawn 0..w even inside the dome. At 100 % a white bar sticks out 22 px on each
     side of the dome top (`detail_panels.jpg`). Clip it to `_span(top)`.
   - (c) The shell is baked at 1× with `set_pixel`: the domes are stair-stepped, and the "2 px rim" is
     1 px. Bake at 3× (132×396 px) and draw it scaled, or stroke the rim as an AA polyline.
   - (d) Still missing from r1 #2b:
     - a specular strip on the left third (white α 0.20 → 0);
     - cylindrical shading of the liquid (edges 20 % darker than the centre);
     - level ticks as 6 px HORIZONTAL lines at 25/50/75 % (now invisible 1 px vertical marks).
   - (e) Still missing from r1 #2a: the pending overflow into slot 2. `n2_slot` clamps pending to
     1 − value, and `nitro_cluster` passes all of it to slot 1.
   - (f) `_draw_stripes` makes ~300 `draw_line` and ~600 `_span` calls: **590–720 µs per redraw** (probe).
     Bake the stripe pattern and the liquid gradient once per resize into capsule-masked textures, and
     draw the two bands with `draw_texture_rect_region`.
   - Verify:
     - probe ≤ 25 µs per slot draw;
     - 2× crops at 100 %, 41 %, while drifting, and with 30 pending at n2 = 90 (overflow visible).

10. **The per-frame cost is over the 0.3 ms budget, and the perf test does not measure it (r1 #15 not
    done).**
    - Wrong:
      - Probe `_draw` per redraw (headless, load average 25–35, so treat the numbers as indicative):
        - `speed_dial`: 131–209 µs, every frame while the speed changes;
        - `gauge_dial`: 152 µs, ×3 every frame in flight (the label is re-measured letter by letter);
        - `n2_slot`: 590–720 µs.
      - `test_hud_perf` times only `hud._process`, called in a loop with no frames, so no `_draw` runs.
        It also sets `telemetry_override = CarTelemetry.new()` and then writes to `car.telemetry`, a
        different object, so the HUD it measures sees speed 0 and N₂ 0.
      - The map test is flaky: my first run printed "FAIL the map costs 653 us", the second "21 us".
    - Do:
      - Split static and dynamic layers. SpeedDial gets a static child (backing, bezel, ticks, labels,
        red band; redraw on resize only) and a dynamic child (value arc, tip, load ring).
      - GaugeDial gets a static child (rest ring, end ticks, the label with pre-measured letter offsets,
        the unit) and a dynamic child (value arc + value).
      - The speed cluster must not `queue_redraw()` every frame: only when the battery % changes.
      - Same rule for `pursuit_panel`, which redraws the whole glass panel every frame.
      - The perf test: timed subclasses as in `tmp/review/hud_probe_r2.gd` for SpeedDial, N2Slot,
        GaugeDial, AttitudeIcon and the minimap overlay.
        - Change the values EVERY frame on the object you pass in: speed +0.5, pending +0.3, flight
          values.
        - Run 600 real frames; sum `_process` + all `_draw`.
        - Assert mean < 300 µs and max < 600 µs. Report three runs.
    - Verify: the new numbers in status, with the command lines.

11. **Speedometer finish (QQ reference `ref/gameplay/scratch/qq_pc_sheet_s.jpg`, bottom tiles; user:
    贴图纹理什么都要细化).**
    - Wrong: thin strokes on a radial vignette. Next to the QQ dials (glossy face, bold rim, thick
      outline) ours reads weak and unfinished (`qq_vs_ours.jpg`).
    - Do:
      - a dial face inside r 92: radial gradient #101A2E → #05070D α 0.85;
      - a glossy highlight arc at the upper left (200°–290°, white α 0.10, 10 px, fading at the ends);
      - a glow underlay under the value arc (16 px, same ramp, α 0.18);
      - a comet trail behind the tip (the last 18°, fading);
      - micro-ticks every 2 km/h between r 94–100 (0.75 px, α 0.12);
      - the bezel as a 4 px ring with a vertical gradient #3A4766 → #141B2B and a 1 px inner highlight.
      - Everything except the arc, tip and trail goes into the static layer (item 10).
    - Verify: 2× crops at 0 / 137 / 300 km/h beside the QQ tile.

12. **Minimap readability once the roads show (brief: Game.world polylines + POIs).**
    - Do:
      - roads #9AA6C4: 2.5 px α 0.70 for expressways/elevated (if the world marks them), 1.5 px α 0.45
        for the rest;
      - a 100 m grid (white α 0.05);
      - a radial edge vignette inside the clip;
      - sky lanes dashed #00E5FF 2.5 px along their curves.
      - Heading: use the horizontal velocity, or keep the last heading, when |forward.xz| < 0.5. At
        pitch ±90° the map spins now: the "N" tick jumps to the bottom in `r2game_t6_5.jpg` and
        `r2game_t9_0.jpg`.
    - Verify: an in-game crop of the map at 2× next to the frame it belongs to.

13. **Evidence must be current and true.**
    - Wrong:
      - The status claims roads for `hud_game_*.jpg`, which contain none (item 1).
      - `hud_21x9_t1_0.jpg` and `hud_16x10_t1_0.jpg` are from 22:37: round-1 code, before prompt-2 at
        23:32.
      - The white/magenta frames (00:33) predate the 00:55–01:05 edits to the banner, minimap,
        race panel and hud.gd.
      - The status says "40 PASS"; the test prints 37.
      - `captures/hudgame_t3_0.jpg` is a stray file in the captures root.
    - Do: regenerate every capture after your last code change, open each one (2× crop), describe only
      what the image shows, and delete the stale files.
    - Verify: the capture mtimes are newer than the newest `.gd` in `game/ui/`.

14. **Dead code, false comments, untyped data (CONTRACTS §3; user rule 不留死代码).**
    - Remove:
      - in the minimap: `_apply_layer_transform()` (just `pass`), `CULL_RADIUS`, and the comments
        "ONE draw_multiline call" and "Only the roads near the player are kept";
      - in nitro_cluster: `COUNT_LABEL`;
      - unused preloads: `Palette` (n2_slot, flight_cluster) and `UI` (attitude_icon);
      - the unused local `col` in `speed_cluster.update_values`.
    - Type `CENTRELINE` / `DLO_TOP` / `BELTLINE` / `OUTLINE_EXTRA` / `PLUME_POINTS` as
      `PackedVector2Array` and `WHEELS` as `PackedVector3Array`.
    - Build the closed outline once, not an `Array` per draw.
    - Replace the literal arrays in hot loops (`[start, start + full]`, `[0.25, 0.5, 0.75]`, `corners`)
      with consts.
    - Named consts for logic numbers:
      - hud.gd `_minimap_timer = 0.25` and `9999`;
      - n2_slot `1.0 / 20.0` and `99.9`;
      - hop_ring `0.012`;
      - banner `60.0, 340.0` (dossier §8.3).
    - Verify: grep finds none of these, and `check` is clean.

## SHOULD-FIX
1. **Toast plate.**
   - It is a trapezoid: only the right edge is skewed, the left edge is vertical.
   - Make it a true −12° parallelogram, with the 3 px accent bar along the slanted left edge.
   - Fill with a gradient α 0.65 → 0.45 plus the glass texture from item 8.
2. **Heat pips look like flat rectangles.** Make them police-light lenses:
   - rounded 3 px corners;
   - a vertical gradient (lit colour → 70 %);
   - a 1 px top highlight;
   - a soft 4 px glow (the current "glow" is a hard 2 px rect).
3. **Hop ring: the armed pulse never animates.** It is computed in `_draw`, which runs only when the
   charge changes. Redraw at 20 Hz while armed.
4. **Attitude icon.**
   - It rotates about the car origin (ground, Y 0). Rotate about the bbox centre (Y 0.10, Z 0.63).
   - Add wheel hubs (r × 0.45) and a faint canopy fill (white α 0.12).
   - Add pitch ticks every 30° on the rim plus a level horizon line, so the pitch reads at a glance.
5. **`split_text` splits at digits as well**, so "第2名 FINISH" becomes "第" | "2名 FINISH". Split only
   at Latin letters.
6. **被捕 BUSTED.** Dossier §8.4 adds a 60 % full-screen dim. Request it, or implement it as a HUD
   overlay.
7. **Police blips update at 4 Hz** (`_refresh_blips` every 0.25 s), so they step across the map.
   Refresh positions at 10 Hz, or every frame for the ≤ 12 units.
8. **`Fonts.text_tracked(spacing)`** caches the first spacing only; a later call with another spacing
   gets the wrong face. Key the cache by spacing.
9. **Banner and race panel are fixed at top-left.** In race mode, check that the docked banner
   (y 340–505) does not cover a 6-row list once rows fit their content (item 4).

## Verified OK
- `check` is clean: 30 files, 0 failed, 0 engine errors, 0 warnings.
- `test_hud.gd`: **37** PASS, "HUD TESTS OK" (the status says 40).
- `test_hud_perf.gd`: passes in the 2nd run (map 21 µs, HUD 7 µs, drift 0.0 px). It failed in the 1st
  run ("map costs 653 us"); see item 10.
- r1 fixes confirmed by test and capture:
  - the Noto weights are real (817 / 853 / 865 px);
  - N₂ fills from the bottom (slot 2 at 41 %), with the stripes right above the liquid;
  - the heat pips blink 4×/s;
  - five short hops leave the clusters at 0.0 px;
  - 2ND / 1ST are correct in lap 2;
  - the Big Hop is armed only at 1.0;
  - the banner docks in real time under `time_scale` 0.3;
  - PITCH fills by |pitch| / 180;
  - the HUD hides on pause.
- Fonts and toasts:
  - Oxanium is upright at 42 px with 14 px tracked labels and its OFL.txt beside it;
  - gauge radius 75 px, stroke 2.5 px, centres at 0.091 / 0.19 / 0.815 / 0.910 W and 0.906 H;
  - toasts are two-line zh/en with amber points; countdown and 完美起步 work.
- Attitude icon: now built from the dossier §4.1 profile. It reads as the Roadster, and the plume ticks
  rotate with the car (`flight_cmp_r2.jpg`).
- Readability:
  - numbers and labels stay legible over flat white and #FF2BD6 (`r2white_*`, `r2magenta_*`);
  - the radial backing has no banding.
- Anchors hold at 16:9, 16:10 (1920×1200) and 21:9 (2560×1080) (`r2demo_*`, `r2wide_*`, `wide_sheet.jpg`).
- Ownership is clean:
  - every Write/Edit and mutating shell command in `jobs/hud/log.jsonl` targets `game/ui/hud/**`,
    `game/ui/theme/**` or `status/hud.md` (plus the worker's own memory notes);
  - `tmp/hud/` was removed;
  - largest files: `minimap_panel.gd` 384 and `hud.gd` 379 lines (≤ 400).
- Free roam hides the timer and the map moves up; the clock floors its centiseconds; a traffic takedown
  shows a "撞车 TAKEDOWN" toast; the N + 2 title renders correctly.

## Evidence (run from /Users/minimax/m/skyrush)
- `tools/godot.sh check --only=res://ui/hud/,res://ui/theme/` → `CHECK 30 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://ui/hud/tests/test_hud.gd` → 37 × PASS, `HUD TESTS OK (0 failures)`
- `tools/godot.sh test res://ui/hud/tests/test_hud_perf.gd`:
  - run 1 → `FAIL the map costs 653 us per frame …`
  - run 2 → `PASS … 21 us`, `PASS the HUD costs 7 us`
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/hud_probe_r2.gd`:
  - `MAP copies=1 tex=(1791, 1341) tex_zoom=0.450 … offset (895.5, 670.5) px`
  - `MAP copies=10 tex=(2048, 1663) … offset (1024.0, 831.5) px`
  - `DRAW speed_dial 131.1–208.8 us | n2_slot 592.5–719.8 us x74 | gauge 151.6–154.8 us`
- Font file parse: Oxanium OS/2 capHeight 690 / upm 1000; GSUB features `ccmp, pnum, zero`.
- Captures in `captures/review/hud/`, all errors=0 for the HUD scenes:
  - demo at 16:10, `--warm=1 --sixteen10` → `r2demo_t*.jpg` (18 states);
  - 16:9 → `r2d169_*`; `--bg=white` → `r2white_*`; `--bg=magenta` → `r2magenta_*`; `--widescreen` →
    `r2wide_*`;
  - in game: `--scene=res://main.tscn --press=accelerate [--pulse=hop@4.0] --stub=menu` →
    `r2game_t3_0/4_45/6_5/9_0.jpg`, `r2game2_t1_0/2_0.jpg`. The car ends nose-down in the first run;
    the shader and `playing` errors come from other units.
- Sheets:
  - `sheet_states_a.jpg`, `sheet_states_b.jpg`;
  - `detail_panels.jpg`, `detail_toasts.jpg` (1:1 crops);
  - `flight_cmp_r2.jpg` (photo 30 above ours);
  - `qq_vs_ours.jpg`, `game_sheet_r2.jpg`, `wide_sheet.jpg`.
- Pixel scans:
  - banner rows (item 5), N₂ glow row y 1020 (item 9a), race-panel ghosts (item 4);
  - road pixels in the map area: worker `hud_game_t3_0` 16, mine 6–125, r1 1,133 (item 1).

# camera review round 2 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function: **7.0**. Round-1 fixes check out on real runs: walls, takedown placement, flash, unscaled timeline,
  boost release, look-at, player swap, jitter. New defects: the blur and the speed lines keep running inside
  the takedown/focus shot and on pause; the blur centre is mirrored when the car is behind the camera; the
  shake "yaw" is a second pitch (r1 #13 not met); the focus shot overrides another unit's slow-mo.
- visual: **5.5**. The streaks are now thin, anti-aliased and subtle in the chase view, a clear step up.
  Still failing:
  - the radial blur ghosts: 12 discrete copies, about 20 px apart in N₂;
  - a takedown at 250 km/h is smeared beyond recognition (`captures/review/camera/td_fast.jpg`);
  - the streaks run on fixed rails and converge in a starburst in the hood and look-back views.
- code: **7.5**. The split, typing, named constants and 56 tests are good. Still to fix: dead constants, a dead
  signal and an orphan `.uid`; magic numbers in the preset table and the shader; a private `_t` read by
  string; duplicated reset code. `chase_camera.gd` is at 399 lines.

Lead notes (`reviews/camera-lead.md`): the tests `extends Node` ✓, the runs end by themselves ✓, scratch is
cleaned up ✓. One process slip is listed under SHOULD-FIX 6.

## MUST-FIX
`chase_camera.gd` is at 399 lines. **Split it before adding code.** For example, move `_update_boost_state`,
`_update_punch` and `_on_boost_started` into `camera_boost.gd`. Every file must stay ≤ 400 lines.

1. **The effects keep running inside the takedown/focus shot and while paused.**
   - `chase_camera.gd:104` calls `_update_effects()` every tick, even while `_takedown.active()`. The
     effects then project the *player's* car and velocity through the side camera.
   - Measured (`tmp/review/camera/probe_r2_td.gd --demo=speed --fire_at=7.5`): at 250 km/h, for the whole
     shot, `takedown_active=true speed_lines_visible=true blur=0.075`.
   - The result is the shot in `captures/review/camera/td_fast.jpg`: the car is smeared horizontally into
     12 ghost copies.
   - Pause (`tmp/review/camera/probe_r2_pause.gd`): after 1 s paused, `lines_visible=true intensity=0.75
     scroll_px=750`. Physics stops, but the shader's `TIME` keeps the streaks flowing over the pause screen.
   - Brief: "off in menus".

   Do:
   - Add a `suppressed` flag to `CameraEffects.update()`. It is true when the takedown/focus cam is active,
     when `get_tree().paused`, or when `Game.mode == &"menu"`.
   - While it is true, snap `_blur_strength` and `_blur.strength` to 0 on the cut (no fade over the shot)
     and hide the streak quad.
   - After the cut back, ramp the blur back up at λ 6 /s.
   - Connect `Events.game_paused` and hide the quad at once, because the camera does not tick while paused.
   - Replace `TIME * scroll_px` (`speed_lines.gdshader:54`) with a `uniform float scroll_phase`. Accumulate
     it in `_update_streaks` as `scroll_phase += scroll_px * delta`, so the streaks freeze with the game.
   - Compute `_blur_strength` even when `_blur == null` (headless), so the tests see the real value.

   Verify:
   - A test where a takedown starts at 250 km/h:
     - while `is_takedown_active()`, `SpeedLines.visible == false` and `blur_strength == 0`;
     - after the cut back, the blur changes by ≤ 0.02 per tick.
   - A test where `Game.set_paused(true)` hides the quad.
   - Rerun `probe_r2_td.gd` windowed and put the frame in status: the car in the shot must be sharp.

2. **The radial blur centre goes wrong when the car is behind the camera, and the blur ghosts.**
   - `camera_effects.gd:158-168`: `_screen_uv()` calls `unproject_position()` without checking
     `is_position_behind()`, so points behind the camera come back mirrored.
   - Hood view at 250 km/h (`tmp/review/camera/probe_r2_blurc.gd`): `blur_centre=(0.50, 0.18)` with
     `car_behind_camera=true`. It should be the vanishing point, about (0.50, 0.50).
   - In the takedown shot the centre is the player's car projected through the side camera. The tap offset
     `dir × strength` has no upper limit, and the victim in `td_fast.jpg` is smeared over about 260 px.
   - Ghosting comes from your copy of the snippet: `samples = 12` with no jitter (`radial_blur_effect.gd:12,50-53`).
     - In N₂ (0.25), a corner pixel samples along 960 px × 0.25 = 240 px, so it shows a copy every 20 px.
     - At 300 km/h cruise (0.15) there is a copy every 12 px.
     - You can see the copies in the tree crowns of `captures/review_camera_r2_real_t9_6.jpg` and
       `captures/review_camera_r2_real_t8_4.jpg`. The hood lane line is hatched in
       `captures/review/camera/r2_hood_streaks.jpg`.

   Do (in your copy of the GLSL):
   - (a) Centre the blur on the **motion vanishing point** (the same `_vanishing_uv()` the streaks use),
     clamped to [0.15, 0.85] on both axes. Never use a point that is behind the camera: during look-back use
     (0.5, 0.5).
   - (b) Keep the car sharp with a mask, not with the centre:
     - push `car_uv` and `car_radius` (0.16 × screen height, aspect corrected, smoothstep feather 0.08);
     - grow the push-constant block to 48 bytes;
     - set `car_radius = 0` when the car is behind the camera (hood view).
   - (c) Remove the ghosting:
     - set `samples = 24`;
     - jitter the taps per pixel: `t = (float(i) + ign(gl_GlobalInvocationID.xy)) / float(n)`, where `ign` is
       interleaved gradient noise;
     - fade the blur in with `smoothstep(0.15, 0.6, r)`, where `r` is the aspect-corrected radius from the
       centre. This keeps the inner 15 % of the screen sharp, as dossier §8.5 asks.
   - (d) Keep the brief strengths: 0.15 at 300 km/h, 0.25 in N₂.

   Verify:
   - A probe prints the centre in the hood view within 0.03 of the vanishing point, and never outside
     [0.15, 0.85].
   - A windowed real-game capture in N₂ at 300 km/h. Put two 100 % crops (640×360) in status:
     - the top-left corner, with no repeated copies of the trees or lamps;
     - the car, which must be sharp.

3. **The speed lines are a fixed sunburst of dashed rails.**
   - `speed_lines.gdshader:44-47`: `lit = step(1 - lit_ratio, hash11(index))` depends only on the lane, so
     the same ≈38 of 110 rays are lit in every frame.
   - `:54-55`: the "dash" is a sawtooth with no gap, so each lit ray is lit along about 80 % of its length.
   - The 100 % crops in `captures/review/camera/r2_streaks_100.jpg` (right column) show dashes repeating on
     the same rays at a regular pitch.
   - In the hood view at 250 km/h, the car mask lands on the mirrored point (0.5, 0.18) and the focus is
     unmasked. The streaks converge in a dense brush at the vanishing point
     (`captures/review/camera/r2_hood_streaks.jpg`).
   - In look-back the streaks still stream outwards while the scene recedes
     (`captures/review/camera/blur_near.jpg`).
   - The width is 2 px at every resolution, which is 1 px-equivalent at 4K.
   - The sky factor is a hard step at the horizon (`:62`, `0.5` hard-coded), while `STREAK_SKY_FACTOR` is
     unused.

   Do:
   - Pick a cell `c = floor((r_px - scroll_phase) / dash_len)` and hash it with the lane:
     `h = hash21(vec2(index, c))`. From `h`, choose:
     - lit or not (35 %);
     - a brightness of 0.5–1.0;
     - a length of 0.5–1.0 × `dash_len`, with the dash covering ≤ 45 % of the cell: a soft 2 px head and a
       fading tail;
     - an angular jitter of ±0.35 lane per cell.
   - Fade the streaks in with radius: alpha × `smoothstep(0.18, 0.32, r_px × SCREEN_PIXEL_SIZE.y)`. Nothing
     then converges at the focus in any view.
   - Set `car_radius = 0` when the car is behind the camera.
   - Look-back: hide the streaks (intensity 0) while `look_back` is held, or run the flow inwards.
   - Set `line_width_px = STREAK_WIDTH_PX × viewport_height / 1080`.
   - For the sky, use `mix(sky_factor, 1.0, smoothstep(horizon_y - 0.03, horizon_y + 0.03, UV.y))`, with
     `sky_factor` as a uniform fed from `STREAK_SKY_FACTOR`.
   - Name the mask feather (`0.12`, `:59`).
   - Keep the colours (`#D8F4FF` cruising, cross-fading to the ART cyan `#19E6FF` in N₂), the alphas
     (0.24 / 0.40) and the 160 → 280 km/h ramp. They are right.

   Verify:
   - `tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_streaks --demo=speed --times=8.0,8.25`.
     Put two 100 % crops (640×360 at 0,0) of the frames and their ffmpeg `blend=all_mode=difference` in
     status. The streaks must sit in different places in the two frames.
   - Hood view (`--camera_preset=bumper`) and look-back at 250 km/h: no streak within 0.18 × screen height
     of the focus.
   - `streak_metrics.py` on the demo frames: mean width ≤ 3 px, coverage ≤ 3 %.

4. **The shake "yaw" is a second pitch, so r1 #13 is not met.**
   - `chase_camera.gd:279-280` rotates both `rotation_deg.x` and `rotation_deg.y` about X (`Vector3.RIGHT`,
     then `Vector3(1, 0, 0)`).
   - The status claims "pitch and yaw only". The test (`the shake tilts the camera`) only checks the pitch.
   - Do: rotate the second one about `Vector3.UP`.
   - Verify with a test: during a 0.15 m shake, max |yaw| ≥ 0.3°, max |pitch| ≥ 0.5°, and roll stays exactly 0.

5. **The focus shot overrides the caller's slow motion** (ownership).
   - The player's wreck (`damage/wreck_flow.gd:32-33`) emits `camera_focus(car, 2.2)` and
     `slowmo_request(0.35, 2.2)`. Dossier §7.8 asks for 0.35 → 1.0.
   - Your `_start()` calls `_request_time_scale()` for focus shots too (`takedown_cam.gd:125, 131-148`). It
     re-requests (0.30, 1.24) every tick, eases, and ends with (1, 0).
   - Measured in the real game (`tmp/review/camera/probe_r2_tele.gd`): `scale=0.30` at t = 2.5 s, then 0.63
     at t = 3.0 s. Your curve replaced the damage unit's 0.35.
   - The `camera_focus` contract (`core/events.gd:59`) is only "look at target for duration seconds".
   - Do: only takedown shots touch the time scale. A focus shot never emits `slowmo_request`, not even (1, 0)
     at the end or on a skip.
   - Verify with a test: count `Events.slowmo_request` around `camera_focus(target, 2.2)` and get 0. The
     takedown timeline tests still pass.

6. **Dead code and magic numbers** (rules: no dead code, no magic numbers).
   - Unused: `SHAKE_DECAY` (`camera_math.gd:49`), `TAKEDOWN_CAM_HEIGHT` (`:96`, only named in a comment) and
     `signal flash_requested()` (`takedown_cam.gd:19`).
   - Orphan file `camera_input.gd.uid` (its `.gd` was deleted).
   - Inline numbers in the preset table: `camera_presets.gd:43-44` (`12.5, 4.6, 6.0, 1.5` and `8.0, 1.1`).
   - `get_debug_state()` reads a private member by string: `_takedown.get("_t")` (`chase_camera.gd:395`).
   - Do: delete the dead items or use them. Turn the preset numbers into named consts with a dossier §2.2
     reference. Add a typed `elapsed()` getter.
   - Verify:
     - a scan shows that every `const` is used outside comments;
     - every `.uid` has its file;
     - `wc -l` gives ≤ 400 for every file.

## SHOULD-FIX
1. **Launch / charge boosts.**
   - `vehicle/modules/boost.gd:56-71` reports `&"launch"` (完美起步) and `&"charge"` (闪充) *instead of*
     `&"nitro"` while they run (priority launch > charge > nitro). `chase_camera.gd:153-154` ignores both.
   - Result: the thruster launch gets no FOV or punch, and a charge bay taken in N₂ drops the +8° and
     releases the punch in the middle of the boost.
   - Map `launch` to N₂. Map `charge` to 小喷, but keep N₂ if N₂ was on the tick before. This matches the
     vehicle's thrust table (`car_readout.gd:76-83`).
2. **The close spot pops.** `camera_rig.gd:32-33` switches between the pulled-in spot and the spot above the
   car in one frame, with no hysteresis. Enter below 1.6 m, leave above 2.0 m, and ease between the two
   spots at λ 12 /s along a path the cast has checked.
3. **The safety pass does not re-aim.** `chase_camera.gd:109-118` moves the position only; the basis is
   still the one computed for the old spot. Use `Transform3D(_camera_basis(safe), safe)`.
4. **Duplicated reset code** in `_acquire_player()` (`:127-130`) and `_on_player_respawned()` (`:366-369`).
   Make one `_reset_follow()`.
5. **One allocation per cast.** `PhysicsShapeQueryParameters3D.new()` runs on every cast
   (`camera_rig.gd:39`, `takedown_cam.gd:216-217`), 180+ per second. Reuse one params object and one sphere.
6. **Scratch location (lead rule).** During this round, probes were written to
   `game/vehicle/camera/tests/probe_*.gd` (job log lines 5335, 6137, 7049) before being deleted. Put scratch
   only in `tmp/camera/`.
7. **Evidence quality.**
   - `cam_contact_sheet.jpg` is 2016×454, about 400 px per state, too small to judge any detail. Use tiles
     ≥ 640 px plus 100 % crops of the areas you changed.
   - The "hop apex" frame (`cam_hop_t4_0`) is after the landing. The demo hop has its apex at about 1.76 s.
   - Status line counts are wrong: `speed_lines.gdshader` is 66 lines (not 37) and `demo_car.gd` 37 (not 44).
   - "5.0 % orange (target < 5 %)" is not below 5 %.

## Verified OK
- `check --only=res://vehicle/camera/`: 20 files, 0 failed, 0 warnings. Tests: **56 checks, 0 failures**.
  No camera script errors in any of my runs; all SCRIPT ERRORs came from `audio/oneshot_pool.gd:105`.
- **Jitter (acceptance)**, real game, 1920×1080 at 60 fps, 207–216 km/h, 10 consecutive rendered frames:
  `mean_abs_dev=(0.001, 0.230) px`, steps a steady −0.10…−0.08 px/frame. **PASS.**
- **Walls (r1 #3)**, probe A: spin 0/180 ticks inside the wall, min clearance 0.364 m; respawn 0/40, first
  clear tick 0. **Shake**: no roll, the moves decay to 0.000. **Swap (#12)**: 6.3 m from the new car.
- **Takedown (r1 #4–#6)**, probe B windowed:
  - flash 0.35 at `frame_pre_draw`, on exactly one tick;
  - cut back after 2.698 s;
  - tunnel cam at (3.08, 1.02, 0.0): not inside a wall, line of sight clear;
  - time scale back to 1.00 afterwards.
- **Dossier numbers in the real game** (`probe_r2_tele.gd`):

  | state | distance back | height | vFOV | blur |
  |---|---|---|---|---|
  | rest | 6.00 m | 1.88 m | 62.0° | — |
  | 184 km/h | 6.80 m | — | 67.0° | — |
  | N₂ at 300 km/h | 7.3–7.7 m | — | 78.3° | 0.250 |
  | after N₂ | — | — | 70.3° | 0.150 |

  The N₂ state now releases with the telemetry (r1 #7 ✓).
- **Demo states**:
  - the drift framing shows the turning radius;
  - flight: higher, about 10° of bank, damped;
  - the takedown side shot frames the victim with a clear line of sight (`r2_demo_sheet.jpg`).
- **Hood view**: layer 19 is culled in BUMPER (test), and orange is now 0.0–0.1 %. The haze that is left
  belongs to fx (Notes).
- **Ownership**: in round 2, Write/Edit only touched `game/vehicle/camera/**` and `status/camera.md` (job-log
  scan). `/tmp/cm.gd` is gone. `radial_blur_effect.gd` matches the snippet apart from the provenance line.
- **Perf**: an A/B of the effects on and off at the same moments shows no camera cost. Under load the frame
  rate is set by the world: 7–46 fps both ways.

## Evidence
Commands, run from `~/m/skyrush`. Probes are in `tmp/review/camera/`; images are in `captures/` and
`captures/review/camera/`.
- `tools/godot.sh check --only=res://vehicle/camera/` → `CHECK 20 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://vehicle/camera/tests/test_camera.gd` → `TEST 56 checks, 0 failures` / `PASS`
- `probe_a.gd` (headless 120 Hz) → `A spin: 0 / 180, min clearance=0.364 m`, `B respawn: 0 / 40`,
  `E max roll=0.000000`, `F swap: 6.3 m`
- `probe_b.gd` (windowed) → `flash max alpha 0.35, physics ticks seeing alpha>0=1`, `cut back after 2.698 s`,
  `tunnel cam pos=(3.078629, 1.02, 0.0) inside_wall=false line_of_sight_blocked=false`
- `probe_c.gd --stub=menu,traffic --spawn=-1380.6,0.6,742.7,-78.5 --max-fps 60` → `mean_abs_dev=(0.001, 0.230) px`
- `probe_r2_tele.gd --nitro_at=8.6` → the numbers above. A player wreck at 2.3 s gave
  `t=2.5 fov=50.0 scale=0.30` and `t=3.0 scale=0.63` (MUST-FIX 5).
- `probe_r2_td.gd --demo=speed --fire_at=7.5` → `takedown_active=true speed=250 kmh speed_lines_visible=true
  blur=0.075` at 6 samples from t = 7.70 to 9.21 s. Frame: `td_fast.jpg`.
- `probe_r2_pause.gd` (headless) → `paused 1 s: tree_paused=true lines_visible=true intensity=0.75 scroll_px=750`
- `probe_r2_blurc.gd` → near: `(0.50, 0.59)`; near look-back: `(0.50, 0.58)`; bumper: `(0.50, 0.18)
  car_behind_camera=true`; bumper look-back: `(0.50, 0.83)`
- `probe_r2_shots.gd --camera_preset=bumper` (hood, real game), share of blown-out pixels (luma > 235):

  | t | with fx | `--stub=fx` |
  |---|---|---|
  | 1.5 s | 25.8 % | 0.1 % |
  | 3.0 s | 28.2 % | 0.1 % |
  | 6.0 s | 15.1 % | 0.2 % |
- Captures:
  - real game: `review_camera_r2_real_t{4_0,8_4,9_6}.jpg`, `review/camera/cruise_t*.jpg`, `review/camera/hood_t*.jpg`;
  - demo: `review_camera_r2_demo_{drift,hop,flight,takedown,speed,boost,hood}_*.jpg`;
  - sheets: `r2_crops_100.jpg` (100 % blur and streak crops), `r2_streaks_100.jpg`, `r2_hood_streaks.jpg`,
    `r2_lookback_pair.jpg`, `r2_demo_sheet.jpg`, `r2_ref_side.jpg` (ours at 220 km/h next to
    `ref/art/img/cp05_nfsheat_police_neon.jpg`).

## Notes for the lead (not counted against the worker)
- **Framing.** Measured car width on screen: 15.3 % at rest, 12.4 % at 184 km/h, 9.1–9.4 % in N₂. In
  `cp05_nfsheat_police_neon.jpg` the car is about 30 % (`r2_ref_side.jpg`). This is what the brief's numbers
  produce (62° vFOV, 6.0 m). Consider 56° / 5.2 m / 1.6 m.
- **N₂ punch.** The brief says "−0.6 m then +1.0 m". The code reads that as a net +0.4 m fall-back; dossier
  §2.3 says +1.0 m. This needs a decision.
- **The verified blur snippet** is 12 taps with no jitter, and it ghosts at ≥ 0.15. Its own header suggests
  0.06 cruise / 0.15 N₂. The brief uses 0.15 / 0.25; consider 0.12 / 0.18.
- **fx / fx_thrusters** use no visual layer 19 (nothing in `game/fx` or `game/vehicle` sets it), so the hood
  view is still flooded by the player's own plumes. Please add the CONTRACTS entry.
- **world**: street trees are MultiMesh without colliders (`world/build/furniture_builder.gd`). A trunk can
  sit between the camera and the car (`review_camera_r2_real_t9_6.jpg`). A trunk collider on layer 3 would
  fix it, because the camera already casts against props.
- **Other units' errors** in the real game:
  - shader compile errors in `shaders/concrete_stained.gdshader:79`, `shaders/soffit_blue.gdshader:42` and
    `INSTANCE_CUSTOM`; the soffit is the likely blue-white blow-out under the decks;
  - **vehicle**: the speed stays at 300 km/h after N₂ ends (base top speed 250).

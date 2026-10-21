# camera review round 4 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function: **6.5**. All three r3 regressions are fixed, and I re-verified each with the r3 probes:
  - blur mask: corners 98–101, car spot 0.02;
  - punch: 0.00 m 5 s after the N₂;
  - drawn camera = physics camera: 4.200 / 3.199 / 2.199.

  These are also right: the dossier numbers, the takedown timeline/skip/cooldown, walls and 74/74 tests.
  New probes found three defects in core moves:
  - a second N₂ pops the camera 0.40 m in one tick;
  - reversing swings the camera to the front of the car, with a 14.35° aim snap;
  - the hood view smears its own bodywork.
- visual: **6.5**. The blur now looks like `cp05_nfsheat_police_neon.jpg`: the periphery smears smoothly with
  no ghost copies, and the car stays sharp (the plate is readable at 240 km/h N₂, `r4_real_n2_crops.jpg`). The
  streaks are thin, subtle and turn cyan `#19E6FF` in N₂. Against that:
  - the hood view paints streaks over the white hood and smears the cowl;
  - the takedown money shot shows the victim as a black blob (mean L 6/255);
  - the evidence rig is grey-box posts.
- code: **7.0**. Clean split (max 380 lines), static typing and named constants almost everywhere. Problems:
  - the tests only fire an N₂ from punch ≈ 0 and never reverse, so two of the new defects pass;
  - dead setters remain;
  - one public getter crashes on a null player;
  - two lead-note process rules were broken this round.

Lead notes (`reviews/camera-lead.md`):
- **Not all satisfied** (MUST-FIX 4): Godot was run in the background, and `tmp/check.log` was left behind.
- The tests `extends Node` (OK).
- Ownership OK: round 4 wrote only `game/vehicle/camera/**`, `status/camera.md`, `tmp/camera/` (deleted) and
  `tmp/check.log`.

## MUST-FIX
1. **Re-igniting N₂ pops the camera by 0.40 m in one tick.**
   - The cause: `camera_boost.gd:67-73` `on_boost_started()` sets `punch = 0.0` and restarts the KICK
     whatever the state.
   - The vehicle allows it: it has 2 COPV slots, `boost.gd:159 use_nitro()` refills `_nitro_time` while an N₂
     burns, and `car_api.gd:35` emits `boost_started(nitro)` on every press. Chaining N₂ is core QQ play.
   - My probe `tmp/review/camera/probe_r4_chain.gd`:
     - 2nd N₂ during HOLD: `punch before 0.400, one tick after -0.004, worst step 0.404 m at t=2.008 s`;
     - re-ignition 0.3 s into the release: `0.287 → -0.004, worst step 0.290 m`.
   - At 7.6 m that is a 5 % jump in car size in one frame. Status says "the punch never steps more than 0.05 m";
     `_test_punch` only starts ignitions from punch ≈ 0.
   - Do: never assign `punch` on an ignition.
     - From IDLE: start the KICK as now.
     - In KICK: keep running.
     - In HOLD: stay. The N₂ just got longer; keep only the 0.04 m ignition shake.
     - In RELEASE: switch to a new state RETURN that eases from the current `punch` back to
       `PUNCH_KICK + PUNCH_RECOVER` (+0.40) over `PUNCH_TIME` with `smooth01`, then goes to HOLD.
   - Verify:
     - rerun `python3 tools/slots.py light 6 -- /opt/homebrew/bin/godot --headless --fixed-fps 120 --path game -s res://tools/test_host.gd -- --test=$HOME/m/skyrush/tmp/review/camera/probe_r4_chain.gd`;
       both lines must show `worst step ≤ 0.050 m`;
     - add cases (d) "2nd ignition in HOLD" and (e) "re-ignition 0.3 s into RELEASE" to `_test_punch`;
       the worst step must be ≤ 0.05 m over all five cases.
2. **Reversing swings the camera round to the front of the car; the aim snaps at every stop.**
   - The yaw: `chase_camera.gd:153-178` targets the velocity yaw whenever |v| > 0.6 m/s. Reversing gives
     vel_yaw = heading + π, so the target becomes heading + 0.65π, 117° off the heading.
   - The aim: `_look_point()` (`:266-280`) jumps from +4 m along the velocity to 0 below 0.6 m/s, and to
     −4 m when reversing. It is not smoothed.
   - `probe_r4_reverse.gd` (brake 10 → 0 → reverse at 5 m/s; the car's `REVERSE_TOP` is 40 km/h):
     - before: the camera is 5.86 m behind the nose;
     - after 1 s of reversing: it is **2.74 m ahead of the nose and 5.42 m to the right**, aim
       (−0.62, −0.08, 0.78), looking back at the car's front quarter;
     - **worst aim change 14.35° in one tick** (t=2.325 s, where |v| crosses 0.6 m/s).
   - `probe_r4_stop.gd` (stop, then pull away): **2.77° in one tick**.
   - Every wall crash ends in a reverse: my real-game run crashed at t ≈ 4.5 s.
   - The same raw velocity turns kinks into jitter. The demo path has a 10.6° velocity kink at t=1.942 s
     (`probe_r4_veldir.gd`): the look point moves 0.742 m in one tick. Car screen jitter there is
     `mean_abs_dev=(8.18, 0.41) px` with ±8 px steps (`probe_r3_jitter.gd --demo=boost --probe_at=2.0`),
     against 0.02 px on the straight.
   - Do:
     - (a) Reversing = `telemetry.forward_speed_kmh < -REVERSE_MIN_KMH (3)` and
       `speed_kmh <= REVERSE_CAM_MAX_KMH (45)`. While reversing, the yaw target and the look direction are
       the heading. Faster backward motion is a spin and stays velocity-led.
     - (b) In `_look_point()` use a damped `_look_dir` instead of the raw velocity: `damp_vec`, λ
       `LOOK_DIR_LAMBDA = 6 /s`, flattened and renormalised.
     - (c) Scale the look-ahead by `smoothstep(VELOCITY_MIN, LOOK_AHEAD_FULL_SPEED = 5 m/s, |v|)` so it fades
       out instead of switching.
     - Reset `_look_dir` in `_reset_follow()` and on the look-back cut. BUMPER stays rigid.
   - Verify:
     - `probe_r4_reverse.gd`: z-offset ≥ +5.5 m and |x| ≤ 0.3 m from t=3.0 to 6.0 s;
     - both probes: worst per-tick aim change ≤ 0.5°;
     - the jitter probe at `--demo=boost --probe_at=2.0`: mean_abs_dev ≤ 1.0 px;
     - turn both probes into tests in `test_camera_scene.gd`.
3. **The hood view smears the car's own bodywork and paints speed lines on it.**
   - In BUMPER the car centre is behind the camera, so `_car_uv()` returns INF and both car masks switch off
     (`camera_effects.gd:152-153` blur, `:198-199` streaks).
   - The hood is rigid with the camera, yet it gets the full radial blur and the streaks.
   - A/B, `--demo=speed --camera_preset=bumper --times=8.0`, effects on vs
     `--motion_blur=off --speed_lines=off`:
     - hood wedge (x 40–60 %, y 78–100 %): **mean|diff| 7.63, p99 149** (the streak strokes on the white hood);
     - cowl band at the bottom: 7.65 / 8.28;
     - sky: 0.40.
   - Picture: `captures/review/camera/r4_hood_ab_crop.jpg`. The cowl is smeared and white strokes sit on the
     hood; with the effects off the edges are crisp.
   - Do (simplest):
     - in BUMPER, project the nose top (car local (0, 0.95, −2.2), from the mesh AABB) with `_screen_uv()`;
       call its v `body_line_y`;
     - blur: pass it in the unused `pad.x` and multiply `falloff` by
       `1 − smoothstep(body_line_y − 0.02, body_line_y, uv.y)`;
     - streaks: a new uniform with the same factor on `alpha`.
   - Do (better): depth-mask the blur. `buffers.get_depth_layer(view)`, linearised with the inverse of
     `get_render_scene_data().get_cam_projection()` (reverse-Z); multiply `falloff` by
     `smoothstep(2.5, 3.5, depth_m)`. Use named constants `SELF_MASK_NEAR` / `SELF_MASK_FAR`.
   - Verify:
     - the same A/B: hood wedge mean|diff| ≤ 1.0 and p99 ≤ 12;
     - the chase N₂ A/B keeps left-mid and right-mid ≥ 3;
     - put both hood crops in status.
4. **Lead notes broken in round 4** (mandatory, `reviews/camera-lead.md`).
   - "No Godot/Blender in the background": broken.
     - `jobs/camera/log.jsonl` L8634 ran
       `(tools/godot.sh check --only=res://vehicle/camera/ > tmp/check.log 2>&1 &); sleep 240`.
     - Seven more Godot runs used `run_in_background` (log lines 8665, 8958, 8988, 9269, 9336, 9380, 9596).
   - "Scratch files go to tmp/<unit>/ and are deleted": `tmp/check.log` ("CHECK 21 files…", 04:15) is still
     there, outside `tmp/camera/`.
   - Do:
     - delete `tmp/check.log`;
     - run every Godot command in the foreground with the tool timeout (the slots kill at 300/600 s);
     - no `&`, no `run_in_background`.
   - Verify: `ls tmp/check.log` → no such file; the next job-log scan shows no background Godot.

## SHOULD-FIX
1. **The takedown shot lights the victim as a black blob.**
   - Victim box mean L: **17.2 / 6.6 / 5.6** at real 6.5 / 7.5 / 8.5 s (`r4_td_real_0-2.jpg`). The chase car's
     p90 is 159. ART §2 wants the car to be the brightest object.
   - Cause: `demo_cam.gd:194-202` aims the key light from the camera at the *player*, not along the view.
   - Do: `_key_light.global_basis = _camera.global_basis`.
   - Verify: victim box mean L ≥ 60.
2. **Blur cost: 0.96 ms per 1080p view.**
   - Method: 8-view amplification as in ref/tech/GODOT.md §3.1, `tmp/review/camera/probe_r4_amp.gd`, N₂ at
     0.25, runs interleaved. Off **20.79 / 20.43 / 22.79 ms**, on **28.69 / 28.33 / 30.12 ms**.
   - That is 4.8× the 0.20 ms budgeted for the verified snippet (GODOT.md §1.6 and §3.2), and it is paid above
     200 km/h, when the frame is busiest.
   - Do: blur at half resolution (downsample in the copy pass), or 12 jittered taps.
   - Verify: ≤ 0.35 ms/view, and no ghost copies on a 100 % edge crop at 0.25.
3. **The car mask is a fixed circle, radius 0.16 × screen height** (`camera_effects.gd:25`).
   - When walls pull the camera in to 3.2 m, the car is about 45 % of the screen height wide, and its sides sit
     in the feather and get smeared.
   - Do: derive `car_radius` from the projected corners of the car's AABB, plus 0.02.
4. **`get_debug_state()` crashes before a player exists.** `chase_camera.gd:273` reads `linear_velocity` on
   Nil; my probe hit it. It is a public overlay API, so guard `_look_point()` when `_player == null`.
5. **Dead code and magic numbers.**
   - Dead: `CameraConfig.set_speed_lines`, `set_camera_shake` and `signal changed` have no callers.
   - Test-only: `CameraMath.punch_release()` is used only by a test.
   - Literals to name: `0.05` (`camera_rig.gd:60`), `0.001` (`camera_effects.gd:178-179`), `< 1`
     (`takedown_cam.gd:185`), and the GLSL `smoothstep(0.15, 0.6, r)` (`radial_blur_effect.gd:77`). Use named
     constants or push constants.
6. **The evidence rig is grey-box** (ART §8; the user asked for "贴图纹理什么都要细化").
   - Each post is two flat `BoxMesh`es (`demo_cam.gd:218-243`).
   - Use the textured `res://assets/props/street/lamp_street.glb` every 30 m (instance it, never edit it), so
     every speed-cue frame shows real material detail.
7. **Status accuracy.**
   - `check` now reports 23 files, not 21.
   - Request 5 is stale: `arcade_car.gd:278` now emits `Events.boost_ended`.
   - "Never steps more than 0.05 m" is untrue (MUST-FIX 1).
   - `crop_mask_diff.jpg` is listed but does not exist.

## Verified OK
- r3 MUST-FIX 1, the blur mask, is fixed. `probe_r3_blurmask.gd` + `mask_regions.py`, mean |on − off|:
  - corners **100.92 / 98.43 / 98.30 / 100.90**;
  - mid-edges 100.51 / 100.50 / 90.21;
  - centre 0.00, car spot **0.02**.

  In game (N₂ at t=3.0, speed lines off in both): left-mid 6.89, right-mid 4.74. A 100 % zoom shows the car
  sharp with the plate readable (`r4_car_ab_zoom.jpg`, `r4_real_n2_crops.jpg`). The r3 "car ≤ 0.5" box
  includes blurred road (2.68); the masked probe is the authoritative number.
- r3 MUST-FIX 2, the punch release, is fixed. `probe_r3_punch.gd`: 0.40 during the N₂, then 0.30 / 0.20 /
  0.10 / **0.00** over 1.0 s; 0.00 m 5 s later.
- r3 MUST-FIX 3, the double pull-in, is fixed. `probe_r3_pull.gd`, physics = drawn for every wall:

  | wall face | physics z | drawn z |
  |---|---|---|
  | none (99.0) | 6.000 | 6.000 |
  | 4.5 m | 4.200 | 4.200 |
  | 3.5 m | 3.199 | 3.199 |
  | 2.5 m | 2.199 | 2.199 |
- r3 MUST-FIX 4, the demo N₂, is fixed. `probe_r3_demo.gd --demo=boost`:
  - t=3.0: `v=300 nitro=true fov=78.3 blur=0.250 punch=0.40`;
  - t=4.5: `v=250 nitro=false fov=72.0 blur=0.105 punch=0.29`;
  - t=5.5: punch 0.00.

  The lamp posts are present, and the key light makes the Roadster read white in the chase frames.
- r3 MUST-FIX 5, the dash: head = 0.45 · length_h of a 146.9 px cell at 1600×900, so the dash is ≤ 66 px and the
  gap ≥ 81 px by construction. The head is soft, the tail fades, and `scroll_px` is gone.
- r3 SHOULD-FIX 1, 2, 4 and 5 are done: the velocity vanishing point, sky factor 0.18, the look-back rear mount
  (0, 1.1, 2.3), and the constant uniforms set in `setup()`.
- Steady-state jitter (10 frames at `--max-fps 60`):
  - 250 km/h: `mean_abs_dev=(0.002, 0.019) px`;
  - drift: `(0.003, 0.001) px`.
- Takedown (`probe_r4_td.gd`):
  - active from real 6.0 to about 8.7 s (2.7 s);
  - camera to victim 8.88 → 7.52 m (the 1.5 m dolly);
  - vFOV 50;
  - time scale 0.30, then 0.51 / 0.79 / 0.98 / 1.00 across the ease.

  Over 322 frames of the shot: 0 frames with speed lines, blur 0.000. Skip (`probe_r4_skip.gd`): a tap at 0.3 s
  is ignored and a tap at 0.6 s skips. Cooldown: a 2nd takedown 1.6 s later is refused, a 3rd 4.6 s later plays.
- Real game (`--stub=menu,traffic`): 0 errors, 48–61 fps. At rest the camera is back 6.00 m, up 1.89 m, vFOV
  62.0; at 168 km/h back 6.77, vFOV 66.5. The N₂ periphery smear matches cp05 (`r4_ref_side.jpg`).
- Files ≤ 400 lines (max `chase_camera.gd` 380). Static typing everywhere. The tests `extends Node`.

## Evidence
- `tools/godot.sh check --only=res://vehicle/camera/` → `CHECK 23 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://vehicle/camera/tests/test_camera.gd` → `TEST 74 checks, 0 failures` / `PASS`.
- New probes, all in `tmp/review/camera/`, run headless at 120 Hz through `res://tools/test_host.gd`:
  - `probe_r4_chain.gd`, `probe_r4_reverse.gd`, `probe_r4_stop.gd`, `probe_r4_veldir.gd`, `probe_r4_wobble.gd`;
  - `probe_r4_td.gd` with `--demo=speed --takedown_at=6.0`;
  - `probe_r4_skip.gd`.
- Windowed probes: `probe_r4_td_shots.gd`, `probe_r4_gpu.gd`, `probe_r4_amp.gd` (`--always-on-top`,
  1920×1080, `--motion_blur=on|off`, interleaved).
- Re-run r3 probes: `probe_r3_punch/pull/demo/blurmask/jitter.gd`.
- Captures (`tools/godot.sh shot` / `tools/capture.gd`), `captures/review_camera_r4_*`:
  - real game: `real_t5_0`, `real_t8_6`, `real_t9_6`, `real_t12_0`;
  - demo states: `speed_t8_0/8_25`, `n2_t3_0`, `n2off_t3_0`, `abON/abOFF_t3_0`, `drift_t4_0`, `hop_t1_76`,
    `flight_t4_0`, `hood_t8_0`, `hoodclean_t8_0`, `far_t8_0`, `lookback_t8_0`;
  - takedown: `td_t6_*`, `tdc_t*`.
- Sheets and crops in `captures/review/camera/`: `r4_real_sheet.jpg`, `r4_demo_sheetA.jpg`, `r4_demo_sheetB.jpg`,
  `r4_n2_crops_100.jpg`, `r4_car_ab_zoom.jpg`, `r4_hood_ab_crop.jpg`, `r4_td_real_strip.jpg`, `r4_ref_side.jpg`
  (cp05 next to the real N₂ frame).
- A/B tool: `python3 tmp/review/camera/ab_diff.py <on> <off> <diff>`.

## Notes for the lead (not counted against the worker)
- Framing: with the brief's 62° / 6.0 m / 1.9 m the car is 12.5–15.3 % of the frame width (real game). In
  `cp05_nfsheat_police_neon.jpg` it is about 30 %, and the bottom ~45 % of every chase frame is empty road. A
  lower camera (1.3–1.5 m) or a 5.0 m distance would read much closer to the reference.
- car_model: `Camera_Hood` is still inside the shell (`blender/car/details.py:71`, Blender (0, 1.0, 1.05)).
- core: `Settings.motion_blur` still lives in `user://skyrush_camera.cfg`. Visual layer 19 for the player's own
  FX is still not in CONTRACTS.

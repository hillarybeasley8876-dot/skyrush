# camera review round 3 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function: **6.0**. These still work: follow, FOV ramp, jitter, wall pull-in, takedown timeline, focus
  shot, and suppressing the effects in the shot and on pause.
  Three new defects break the brief's numbers and "never clips":
  - the radial blur is inverted: it blurs only the car;
  - the N₂ punch never releases;
  - the `_process` safety pass pulls the camera in a second time.
- visual: **5.5**. The streaks are now right: thin, varied, moving, subtle. But:
  - the blur smears the car (the game's star) and leaves the rest of the screen sharp. That is the
    opposite of `cp05_nfsheat_police_neon.jpg`, where the car is sharp and the periphery is blurred;
  - the demo "N₂" frames show no N₂;
  - the evidence frames show the white Roadster as a dark silhouette.
- code: **7.0**. Good split (max 374 lines), static typing everywhere, named constants, 67 tests, clean
  ownership. Problems:
  - none of the tests saw the three regressions;
  - new dead code: the `scroll_px` uniform and a duplicate `"speed"` branch;
  - one doc comment does not match its code (`_vanishing_uv`);
  - three status claims are not true (MUST-FIX 6).

Lead notes (`reviews/camera-lead.md`) are met:
- the tests `extends Node`;
- every run ended by itself (the Godot/Blender processes still running belong to roads/environment);
- `tmp/camera/` was deleted;
- round 3 wrote only `game/vehicle/camera/**` and `status/camera.md` (job-log scan from line 7328).

## MUST-FIX
1. **The radial blur mask is inverted: only the car is blurred, the rest of the screen gets zero blur.**
   - `radial_blur_effect.gd:79` is `float car_mask = 1.0 - smoothstep(p.car_radius, p.car_radius + p.feather, length(cd));`.
     It is 1 on the car and 0 everywhere else, and `falloff *= car_mask` (`:80`) then turns the blur
     off everywhere except the car spot.
   - Measured with my isolated probe `tmp/review/camera/probe_r3_blurmask.gd`: your effect on a
     full-screen checkerboard, strength 0.25, car_uv (0.5, 0.75), radius 0.16. Mean |on − off|:
     - all four corners, the left/right/top mid-edges and the centre: **0.00**;
     - the car spot: **22.95** (22.3 % of its pixels change by > 16).
     - Picture: `captures/review/camera/r3_mask_sheet.jpg`. A sharp checkerboard with one smeared disc
       where the car would be.
   - Your `crop_blur_corner.jpg` (4 KB of flat sky) and `crop_blur_car.jpg` could not show this.
   - Do: `float car_mask = smoothstep(p.car_radius, p.car_radius + p.feather, length(cd));` (0 on the
     car, 1 away from it). Leave the rest of the GLSL as it is.
   - Verify:
     - rerun the probe: `python3 tools/slots.py heavy 4 -- /opt/homebrew/bin/godot --path game
       --windowed --resolution 1600x900 -s res://tools/test_host.gd --
       --test=$HOME/m/skyrush/tmp/review/camera/probe_r3_blurmask.gd`, then
       `python3 tmp/review/camera/mask_regions.py captures/review/camera/r3_mask_on.png
       captures/review/camera/r3_mask_off.png`;
     - the four corners must read ≥ 5 and the car spot ≤ 1.0;
     - put both numbers in status, with the windowed A/B of MUST-FIX 4.

2. **The N₂ punch never returns: after every N₂ the camera stays +0.40 m further back for good.**
   - `camera_boost.gd:33` starts the release only `if was_nitro and not nitro and _punching`.
     `_punching` turns false 0.4 s into the boost (`:40-41`), and an N₂ lasts 3.0 s, so the release
     never runs.
   - Measured (`tmp/review/camera/probe_r3_punch.gd`, headless, `boost_kind=&"nitro"` for 3.0 s, then `&""`):
     punch `0.40` from t = 0.5 s on, still **0.40 m 5 s after the N₂ ended**.
   - Dossier §2.3: "return over 1.0 s after N₂ ends". `&"launch"` latches the same way.
   - Do: whenever no N₂ is running and the kick is over (or the N₂ ended during the kick), ease
     `punch` from its **current** value to 0 over `PUNCH_RELEASE_TIME`. Store `_release_from` and do
     not assume +0.4. `_reset_follow()` also resets `_boost`.
   - Verify with tests in `test_camera.gd`:
     - (a) nitro for 3.0 s, then `&""`: punch = 0.40 ± 0.01 at 2.9 s, and |punch| ≤ 0.01 at 4.05 s;
     - (b) `boost_started(nitro)` with `boost_kind` never nitro: |punch| ≤ 0.01 by 1.5 s;
     - (c) nitro for 0.2 s only: |punch| ≤ 0.01 by 1.3 s, and the per-tick step is ≤ 0.05 m in all
       three cases.
   - Rerun `probe_r3_punch.gd` and quote its line in status.

3. **The `_process` safety pass pulls the camera in a second time.** The drawn frame comes out
   1.3–1.5 m closer than the wall allows.
   - `chase_camera.gd:110` calls `_rig.resolve(…, dt=0, from=anchor, to=current)`.
   - `camera_rig.gd:35-41` keeps the stored `scale` (fraction ≥ scale, damp with dt 0) and returns
     `from.lerp(current, scale)`. The physics result gets scaled twice (scale²).
   - Measured (`tmp/review/camera/probe_r3_pull.gd`, a wall face behind the car), z at the end of
     physics vs **z drawn** (end of `_process`):

     | wall at | physics end | drawn |
     |---|---|---|
     | 4.5 m | 4.200 | **2.940** |
     | 3.5 m | 3.199 | **1.706** (y 1.18) |
     | 2.5 m | 2.199 | 2.199 |
     | no wall | 6.000 | 6.000 |

   - At 1.71 m behind the origin and 1.18 m up, the camera sits on the rear deck of the 4.4 m Roadster.
     That fails "never clips".
   - The pass also flips `_close` / `_spot` from a dt = 0 call. In BUMPER, a `scale` left over from the
     chase view can pull the hood mount, or send it to the stale `_spot`.
   - Do:
     - add a stateless `CameraRig.clamp_to_clear(space, from, to) -> Vector3`, which returns
       `from.lerp(to, cast_fraction(...))` and never touches `scale`, `_close` or `_spot`;
     - use it in `_process`;
     - skip the safety pass in BUMPER;
     - keep the re-aim.
   - Verify:
     - `probe_r3_pull.gd` prints drawn = physics (4.20 / 3.20 / 2.20 ± 0.02);
     - add a test whose sampler node has `process_priority = 1000` (it reads after `_process`): wall
       at 3.5 m, camera z ≥ 3.15 m on every frame.

4. **The demo "boost" is not N₂, so every N₂ frame in status shows a cruise at 250 km/h.**
   - `demo_cam.gd:129-134` emits `boost_started` but never sets `telemetry.boost_kind`.
   - `_speed = V_BOOST` is clamped back to `V_TOP` on the next tick (`:130`).
   - Measured (`tmp/review/camera/probe_r3_demo.gd --demo=boost`), from t = 1.5 s to 9.0 s:
     `v=250 kmh boost_kind='' nitro=false fov=68.9 blur=0.075 punch=0.40`.
   - Expected in N₂: 300 km/h, vFOV ≈ 78.3°, blur → 0.25, streaks cross-fading to `#19E6FF` at α 0.40.
   - `cam_blur_n2_t4_0.jpg` and the "N₂" tile of `cam_contact_sheet.jpg` show none of this.
   - Do:
     - in the boost state, set `boost_kind = &"nitro"` for 3.0 s and hold 300 km/h, then clear it and
       return to 250 km/h;
     - delete the unreachable second `"speed": pass` branch (`:156`);
     - the sandbox corners are flat sky and flat road, so nothing can show blur there. Add two rows of
       thin posts at ±8 m every 30 m along the demo lane (0.15 × 3 m, emissive cap `#D9E8FF`).
       Dossier §2.3/§8.5: lamp posts every 30–40 m are the strongest speed cue.
   - Verify:
     - the probe prints `nitro=true fov≈78.3 blur→0.250` in the boost, then punch 0 by 1 s after;
     - a windowed A/B at the same time: `--motion_blur=off --speed_lines=off` vs `--speed_lines=off`;
     - `python3 tmp/review/camera/ab_diff.py <on> <off> <diff>`: the mid-edges ≥ 3 and the car ≤ 0.5;
     - two 640×360 crops: an edge with posts (smeared), and the car (sharp).

5. **The speed-line dash fills the whole cell and has a hard head** (r2 MUST-FIX 3 asked for ≤ 45 %).
   - `speed_lines.gdshader:64-66`: `t = clamp(phase / dash_frac)` makes `dash` = 1 for every
     `phase > dash_frac`. A lit cell is therefore lit for 55–100 % of its 147 px (1600×900), and it
     ends in a 1-px cut. Status claims "the length (≤ 45 % of the cell)".
   - The uniform `scroll_px` (`:15`) is now unused, but `camera_effects.gd:182` still sets it.
   - Do:
     - `float head = 0.45 * length_h;`
     - `float dash = smoothstep(0.0, head, phase) * (1.0 - smoothstep(head - 2.0 / dash_len, head, phase));`
       This gives a fading tail and a soft 2 px head at the outer end.
     - Delete `scroll_px` from the shader and from `camera_effects.gd`.
   - Verify: on a 100 % crop of `--demo=speed --times=8.0`, 10 measured dashes are ≤ 70 px long, with
     gaps ≥ 80 px on the same ray. `streak_metrics.py` stays ≤ 3 px / ≤ 3 %.

6. **Evidence must be measured, not asserted.** Three claims in `status/camera.md` are untrue:
   - "crop_blur_corner.jpg (no ghost copies)": there is no blur at all (MUST-FIX 1);
   - "N₂ with the blur": the demo is not in N₂ (MUST-FIX 4);
   - "dash ≤ 45 %" (MUST-FIX 5).

   Do: for every effect claim, add an on/off A/B at the same game time, with the region numbers from
   `ab_diff.py` / `mask_regions.py`, plus the probe lines. Re-capture the contact sheet after 1–5.

## SHOULD-FIX
1. **The vanishing point uses the camera's forward, not the velocity.**
   - `camera_effects.gd:206-217` is documented as "along its velocity", but it uses `-camera.basis.z`.
   - In a 30° drift the camera looks 10.5° off the motion, so the streak and blur focus sits about
     0.076 × width (≈ 120 px) away from where the world flows from.
   - Pass `_player.linear_velocity` into `update()`. Use it (flattened) when |v| > `VELOCITY_MIN`;
     otherwise use the camera forward.
2. **Sky streaks.** `STREAK_SKY_FACTOR` 0.5 turns the empty sky into a hyperspace star field in the
   near and hood views (`captures/review/camera/r3_ref_side.jpg` against `cp05`, where the sky is calm
   and the speed reads from the road). The sky is at infinity and does not move. Use 0.15–0.2.
3. **Demo lighting.**
   - The only light is a 0.7-energy moon from behind the car, so the Ano White Roadster (`#ECEDEF`)
     reads as a dark grey-blue mass, and the takedown victim as a black block (`r3_td_sheet.jpg`).
     ART §1–2: the car is the cleanest bright object.
   - Add a key light from the camera side: a DirectionalLight3D at about 0.6 energy, `#D9E8FF`.
4. **Hood mount.**
   - `Camera_Hood` is at local (0, 1.05, −1.0), inside the Roadster shell (mesh AABB y 0–1.54, every
     mesh on layer 1). The hood view therefore shows no hood, and look-back from it looks through the
     backface-culled body.
   - Ask car_model to put the marker 0.10–0.15 m above the hood skin.
   - For look-back in BUMPER, use a rear mount, e.g. (0, 1.1, +2.3).
5. Set the constant streak uniforms (lanes, lit_ratio, dash_ratio, feather, sky_factor) once in
   `setup()`, not every frame.

## Verified OK
- `check --only=res://vehicle/camera/` → `CHECK 21 files, 0 failed, 0 engine errors, 0 warnings`.
- `test` → `TEST 67 checks, 0 failures` / `PASS`.
- **Jitter (acceptance)**: 10 rendered frames at `--max-fps 60` (`probe_r3_jitter.gd`), in the demo.
  The real game is broken by other units.
  - 250 km/h: `mean_abs_dev=(0.026, 0.246) px`, steady steps of 0.08–0.11 px.
  - drift: `(0.027, 0.005) px`.
  - **PASS.**
- Streaks: mean width 1.4 / 0.9 px and coverage 0.5 / 0.6 % (t 8.0), 0.9 / 1.0 px and 0.5 / 0.4 % (t 8.25).
  - They sit in different places 0.25 s apart (`r3_streaks_100.jpg`).
  - None in look-back; they fade out near the focus.
- Takedown at 250 km/h (`r3_td_sheet.jpg`):
  - a side shot, the victim centred and sharp;
  - no streaks or blur in the shot;
  - back to the chase cam by t = 7.2 s.
- Shake about world up and the right axis, with roll 0. The focus shot asks for no slow motion. The
  pause hides the streaks. All by tests.
- Files ≤ 400 lines (max `chase_camera.gd` 374). No untyped vars or functions. Every `const` is used.
- Perf: the demo ran at 278 fps with the blur on and 280 fps with it off.

## Evidence
- Probes, all in `tmp/review/camera/`:
  - `probe_r3_pull.gd`, `probe_r3_punch.gd`, `probe_r3_demo.gd`, `probe_r3_hood.gd`: headless,
    `tools/test_host.gd`;
  - `probe_r3_blurmask.gd`, `probe_r3_jitter.gd`: windowed;
  - `ab_diff.py`, `mask_regions.py`: the analysis scripts.
- Captures: `captures/review_camera_r3_*` (blurON/blurOFF/blurONnl, speed, hood, hoodback, lookback,
  drift, flight, far, td, real) and the sheets `captures/review/camera/r3_*.jpg`.
- Real game (`--stub=menu,traffic`):
  - **broken by other units**: `vehicle/modules/car_dynamics.gd:185` (`Identifier "speed" not
    declared`) makes `arcade_car.gd` fail; `fx/thrusters/thruster_rig.gd:246` has a parse error;
  - 1926 script errors; the first run crashed (signal 5, reflection-probe atlas index −1);
  - **0 errors from `vehicle/camera/`**.

## Notes for the lead (not counted against the worker)
- Real-game verification of N₂ and framing was impossible this round (vehicle and fx compile errors).
- Framing: as noted in r2, the car is 12–15 % of the frame width, against about 30 % in `cp05`. The
  brief's 62° / 6.0 m produce this.

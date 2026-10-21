# camera review round 1 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- function: **5.0** (follow, FOV and jitter are right, and the 44 tests pass. Failing: the camera goes into walls, the takedown cam goes into walls, the flash never draws, the boost state never clears, there is a drift sign bug, the look-at is not as specified, and a new player car is not picked up)
- visual: **4.5** (framing, drift, hop and flight look right. Failing: the speed lines are wide flat bars, the radial blur jumps at N₂ ignition, and the hood view in the real game is 58 % orange FX haze)
- code: **6.0** (small single-job files and a pure math module are good. Failing: a lead rule is broken (the test extends SceneTree), the rotation shake is dead code, magic numbers sit in the logic, and a scratch file is left in /tmp)

The lead notes (`reviews/camera-lead.md`) are NOT all met: items 1 and 2 below.

## MUST-FIX

1. **Lead rule: tests must `extends Node`.** `game/vehicle/camera/tests/test_camera.gd:1` is `extends SceneTree`, so it runs on the "legacy" path of `tools/godot.sh test`.
   Do: rewrite it as an `extends Node` test (template: `game/core/tests/test_core_smoke.gd`, run by `res://tools/test_host.gd`). Use `Events`/`Game`/`VehicleBase` by name. Delete `_autoload()` and `_wait_wall()`. Delete status Request #2, because core already solved that with test_host.
   Verify: `tools/godot.sh test res://vehicle/camera/tests/test_camera.gd` goes through test_host and prints PASS. `grep -n "extends SceneTree" game/vehicle/camera -r` finds nothing.

2. **Lead rule: scratch files.** `/tmp/cm.gd` (111 B, 22:08) is yours (job log: `cd /tmp && cat > cm.gd`) and is still there.
   Do: delete it. Scratch goes only to `tmp/camera/` and is deleted when you are done. Every Godot run must end by itself.
   Verify: `ls /tmp/cm.gd` reports "No such file".

3. **The camera goes inside walls for 6–8 frames ("never clips" fails).** In `chase_camera.gd:239-241` the pull-in is smoothed at 30 /s, so the camera only reaches the safe distance about 11 ticks after a wall comes between the car and the camera.
   Measured (`tmp/review/camera/probe_a.gd`):
   - Spin-out, wall face 2.25 m in front of the car, car yaw flipped 180°: 16 of 180 ticks with the near plane inside the wall. Minimum clearance **−0.282 m** (the camera centre is inside the wall).
   - Respawn with the car's back to a wall: the first **12 ticks are behind the wall, up to 3.75 m deep**.
   Do:
   - When `frac < _collision_scale`, set `_collision_scale = frac` at once. Keep the 10 /s ease only for pulling back out.
   - Delete the `MIN_PULL_IN` 0.2 floor. It pushes the camera back into the wall, and it puts the camera inside the 4.4 m car. Instead, when `frac × length < 1.6 m`, re-cast to a high close spot (car + 3.2 m up, 1.0 m back) and use it if it is clear.
   - Clamp the shake offset to ≤ 0.2 m so the shake cannot push the camera through the 0.3 m sphere margin.
   Verify, with new tests in test_camera.gd:
   - (a) the spin-out case above: on **every** tick, camera z ≥ −2.25 + 0.25.
   - (b) respawn with the back to a wall: from the first tick on, the camera is ≥ 0.25 m in front of the wall face.
   - (c) the current check `cam_pos.z < 1.9` (line 170) passes a camera that is inside the wall, because the wall face is at **1.75**. Change it to `< 1.75 - 0.25`.

4. **The takedown cam is placed inside walls and cannot see the victim.** `takedown_cam.gd:138-180` always puts the camera at 9 m. The free-space ray starts at the victim's origin, which is at road level (Roadster `body_center_y` is 0.62), so it grazes the road. Nothing checks line of sight. In a 9 m tunnel (walls at x = ±4.5), the camera ended at **(8.59, 1.02, 0)**, behind the wall, with **line of sight blocked** (`probe_b.gd`). The 延安东路 tunnel, ramps and 1.1 m parapets on the decks all hit this.
   Do: in `_place()`, try these positions in order:
   - distance [9.0, 7.0, 5.0] m × height [1.0, 2.2, 3.5] m × side [the open side, the other side];
   - start from the victim centre (origin + 0.6 m up);
   - accept the first position where a sphere cast (r 0.3, mask world + props) from the victim centre is clear **and** a ray from the camera to victim + 0.5 m is clear;
   - if none is clear, use a high shot 6 m above and 4 m behind the victim;
   - also cast the 1.5 m dolly path.
   Verify, with tests:
   - Tunnel (floor, walls at ±4.5 with inner faces at ±4.25, ceiling 5.5 m): at t = 0.06 s and t = 1.30 s, |cam.x| ≤ 4.0 and line of sight is clear.
   - Deck with 1.1 m parapets at x = ±6: the camera has |x| ≤ 5.7, or y ≥ 2.0 with line of sight clear.

5. **The hit-stop white flash is never drawn.** `camera_overlay.gd:42-53` sets alpha 0.35 during the physics step. `_process` clears it in the same main-loop pass, which runs before drawing.
   Measured, windowed: **519 `frame_pre_draw` calls, flash alpha 0.00 in every one** (dossier §3.5: one frame at alpha 0.35).
   Do: in `flash_frame()`, set the alpha, then `RenderingServer.frame_post_draw.connect(_clear_flash, CONNECT_ONE_SHOT)`. Delete `_flash_frames`.
   Verify: a windowed check that records `Overlay/Flash.color.a` at `frame_pre_draw` (same method as `tmp/review/camera/probe_b.gd`) sees exactly one frame at 0.35.

6. **The takedown timeline uses the wall clock instead of unscaled game time.** `takedown_cam.gd:60-65, 117, 121` use `Time.get_ticks_usec()` and ignore the `dt` that `advance(dt)` receives. Under `--fixed-fps` (tests and `tools/godot.sh movie`), the cut back to the chase camera happened after **390 s of unscaled game time** (headless, 120 Hz). Recorded movies would therefore show a cam of the wrong length. The dossier asks for ignore-time-scale timing (`create_timer(.., true, false, true)`), which means unscaled delta, not the wall clock.
   Do:
   - Add `_t += dt` in `advance()`. The rig already passes unscaled seconds.
   - Use `_t` in `can_skip()`.
   - Count the cooldown down with the same `dt`.
   Verify: a fixed-fps test with no wall-clock waits.
   - The cut back happens on the tick where `_t ≥ 2.70` (± 1/120 s).
   - The 0.30× slow-mo request goes out at 0.06 s.
   - The time scale eases over 1.30–2.40 s.

7. **The boost state latches on forever, and the blur jumps.** `chase_camera.gd:309-331` waits for `Events.boost_ended`, but **nothing emits it** (`grep -rn "boost_ended.emit" game/` finds 0 hits; `vehicle/arcade_car.gd:252,258` emit only `boost_started`). After the first N₂ the camera keeps +8° FOV and 0.25 blur, and after the first 小喷 it keeps +4°, for good. `blur_strength()` also returns 0.25 at any speed in N₂: it jumps from 0 to 0.25 at ignition and blurs the screen at 50 km/h.
   Do:
   - Read `_player.telemetry.boost_kind` every tick. It is set by `vehicle/modules/car_readout.gd:55`. `&"nitro"` means N₂; `&"mini"`, `&"air_mini"` and `&"landing"` mean 小喷.
   - Use `boost_started` only for the one-time punch and the 0.04 m shake. Start the punch release when `boost_kind` stops being `&"nitro"`.
   - Blur = ramp(200 → 300 km/h) × (0.25 in N₂, else 0.15), smoothed at λ 6 /s.
   Verify, with a test:
   - `boost_kind = &"nitro"` for 1 s, then `&""`: after 1.5 s the FOV is within 0.3° of 62 + 0.1·v.
   - Blur changes by at most 0.02 per tick.
   - Blur is 0 at 150 km/h in N₂.

8. **The speed lines are wide flat bars, not subtle cyan-white streaks** (brief: "cyan-white, subtle"; user: "贴图纹理什么都要细化").
   Measured with `python3 tmp/review/camera/streak_metrics.py`:
   - `captures/review/camera/rv_real_t9_6.jpg`: mean streak width **19.9 px** (max 33.4) at r = 0.30 w, arc coverage **9.3 %**.
   - `cam_nitro_t7_6.jpg`: widths up to 24 px, coverage 8.7 %.
   The 100 % crop (`captures/review/camera/sheet3.jpg`, left) shows hard-edged, banded, wedge-shaped strips. They fill the empty sky like a hyperspace effect and run over the car.
   Causes in `speed_lines.gdshader`:
   - each lane is a full angular wedge, so streaks get wider towards the edges, with no anti-aliasing;
   - UV is not corrected for aspect ratio;
   - the focus is fixed at (0.5, 0.55);
   - `scroll` does not change with speed;
   - there is no N₂ colour.
   Do (rewrite the shader; feed the uniforms from `camera_effects.gd` each frame):
   - Line core 1.5–2.5 px at 1080p, measured in **pixels** (angular distance × r × `1/SCREEN_PIXEL_SIZE`), with `fwidth`/smoothstep AA edges.
   - Tapered dash (bright head, fading tail), 6–12 % of the half-diagonal long.
   - 90–140 lanes, about 35 % of them lit.
   - Focus = the motion vanishing point: `camera.unproject_position(cam_pos + velocity_dir * 100)` converted to UV.
   - No streaks inside an aspect-corrected radius of 0.35 around the car's screen position.
   - Alpha 0.22 when cruising, 0.40 in N₂ (dossier §8.5). Colour `#D8F4FF`, cross-fading to ART cyan `#19E6FF` in N₂ (λ 6 /s).
   - Alpha × 0.5 above the horizon line.
   - Scroll speed proportional to km/h.
   - `visible = false` on the ColorRect while intensity < 0.001 (today a full-screen pass runs every frame).
   Verify:
   - `streak_metrics.py` on your 250 km/h and N₂ real-game frames: mean width ≤ 3 px and coverage ≤ 3 % at both radii.
   - Put a 100 % crop (800×450 from the top-left) of each frame in status.
   - A crop around the car shows no streaks over it.

9. **The hood/bumper view in the real game is filled with orange FX haze.**
   - `captures/review/camera/rv_bumper_t2_5.jpg`: **58 % of pixels orange** (R > 120, R > 1.15 G, G > 1.3 B), centre mean RGB (169, 121, 68).
   - Same run with `--stub=fx`: 0 %.
   The player's own thruster/ground clouds sit in front of the `Camera_Hood` marker (at (0, 1.05, −1.0) in `roadster.glb`).
   Do:
   - In BUMPER, clear one render layer from `_camera.cull_mask`: `SELF_FX_LAYER := 19` (named const), restored in the other presets.
   - Add Requests in status: to the lead, a CONTRACTS entry "visual layer 19 = player self-FX, hidden in the hood view"; to fx / fx_thrusters, put the player car's clouds and puffs on that layer.
   Verify:
   - A test that the cull mask leaves out bit 18 only in BUMPER.
   - Once fx has done its part: `tools/godot.sh shot --scene=res://main.tscn --out=cam_bumper_real --stub=menu --camera_preset=bumper --press=accelerate --times=2.5` gives < 5 % orange pixels.

10. **Drift detection has a sign bug, and the yaw rate switches abruptly.** `chase_camera.gd:189` tests `tele.slip_angle_deg > 15.0`, but β is **signed** (`core/contracts/car_telemetry.gd:18`). Left slides never get 4.5 /s, and `&"recover"` is ignored. The λ jump 7 → 4.5 is a hard switch; dossier §2.3 says assists "should fade in/out, never switch binary".
   Do:
   - Drifting = `drift_state in [&"drift", &"recover"]` or `absf(slip_angle_deg) > CameraMath.DRIFT_SLIP_DEG` (15).
   - Blend the rate: `_yaw_lambda = damp(_yaw_lambda, target, YAW_LAMBDA_BLEND = 4.0, dt)`.
   Verify, with a test: `slip_angle_deg = -30`, `drift_state = &"grip"` → the effective λ reaches 4.5 ± 0.1 within 0.75 s and never changes by more than 0.2 per tick.

11. **The look-at point is not used as specified.** `chase_camera.gd:254-264` uses the look point only for pitch. The horizontal aim is `_yaw`, so in a 30° drift the camera points about 4° away from car + 1.2 m up + vel_dir × 4 m (the brief's look-at).
   Do: `var b := Basis.looking_at(_look_point() - pos, Vector3.UP)`, then the flight bank, then the shake.
   Verify, with a test: velocity (−10, 0, −17.3) with heading −Z and shake off → the angle between the camera's −Z and (look_point − cam_pos) is ≤ 0.1°.

12. **A new player car is never picked up.** `_acquire_player()` (`chase_camera.gd:132-137`) keeps the old car for as long as it is valid. Measured: after `Game.player = car2` plus `player_respawned`, the camera was **294 m from the new car and 6.3 m from the old one** (`probe_a.gd`, case F).
   Do: switch whenever `_player != Game.player`, and reset `_started` and `_collision_scale` when you do.
   Verify, with a test: second car at z = 400 → within 1 s the camera is within 8 m of it.

13. **Camera shake: rotation is dead code, and the shake pops at the end.**
   - `camera_shake.gd:52`: `update(dt, out_rotation: Vector2)` gets a Vector2 by value, so `_shake_rot` stays (0, 0). Measured: maximum roll component **0.000000** during a 0.15 m shake. `ROT_SCALE` 0.35 °/m would be invisible anyway.
   - The shake is cut off while it still has 64 % amplitude: the last tick moves **0.065 m**, then 0 (`probe_a.gd`, case E2).
   - The landing shake `0.10 × v/10` has no upper limit (0.4 m at 40 m/s).
   Do:
   - Expose `rotation_deg: Vector2` as a member that the rig reads, as pitch/yaw only (never roll), at about 6° per metre of amplitude. Or delete the rotation entirely; no dead code.
   - Envelope: amplitude × (1 − elapsed/duration)².
   - Limit the landing shake to ≤ 0.25 m.
   Verify, with a test:
   - The last 3 ticks of a shake each move ≤ 0.01 m.
   - Pitch moves ≥ 0.5° during a 0.15 m shake.
   - A landing at 60 m/s gives an amplitude ≤ 0.25 m.

14. **The flight bank jumps.** `chase_camera.gd:259-261` uses the raw `roll_deg`, which is `asin()`, so ±90°. In a 0.7 s barrel roll the clamped bank flips from +10° to −10° within 20° of roll (about 40 ms, 2–3 frames). It also drops from 10° to 0 in one frame when flight ends.
   Do: `_bank = damp(_bank, target, BANK_LAMBDA = 4.0, dt)`, with target 0 when not flying.
   Verify, with a test:
   - Roll 0 → 360° in 0.7 s while flying: the bank changes by ≤ 1.0° per tick.
   - At flight exit the bank fades out over time instead of dropping in one tick.

15. **Magic numbers in the logic** (rule: no magic numbers). Move each one to a named const in `camera_math.gd` with a reference to the dossier:
   - `chase_camera.gd`: 65 `0.08`, 66 `4000.0`, 171/276 `0.6`, 189 `15.0`, 248 `0.9`, 257 `0.5`, 318 `0.04, 0.2`, 337 `0.10 … 10.0, 0.3`, 344 `8000.0`, 346 `0.15, 0.25`;
   - `takedown_cam.gd`: 79 `0.6`, 149 `1.0`, 175/179 `12.0`, 189 `0.5`, 190 `0.2`.
   Verify: `grep -nE "[^A-Z_][0-9]+\.[0-9]+" chase_camera.gd takedown_cam.gd` shows numbers only in `const` lines.

## SHOULD-FIX
1. **The velocity feed-forward makes the camera rigid in translation.** The error obeys de/dt = −λe whatever v(t) is, so the camera never lags when the car speeds up or crashes. The status claim "still lags on acceleration" is therefore wrong; please correct it. To get Criterion "momentum" back, feed forward a low-passed velocity instead (`_v_ff = damp(_v_ff, v, 3.0, dt)`; `desired += _v_ff / λ`). Then an instant stop from 250 km/h pulls the camera ≥ 1.0 m closer within 0.3 s, and it returns to 6.0 m within 1.5 s.
2. **Change Engine.time_scale only through `Events.slowmo_request`.** `takedown_cam.gd:89,123,198,203` write the global directly, and `Game` owns slow-mo. For the hit-stop send (0.05, 0.06), then (0.30, 1.24), then the eased values each tick; on skip send (1.0, 0).
3. **Keep the car sharp in the radial blur.** The blur centre stays at (0.5, 0.55) while the car sits at y ≈ 0.73 (probe C), so the car gets about 12 % of the blur. Set `_blur.center` each frame to the car's screen UV, or to the vanishing point.
4. **`look_back` should cut instantly** (snap yaw and position on press and on release), not swing through the side view over about 0.6 s at λ 7.
5. **Scale the wall-hit shake with the impulse** (0.08 m at 8 000 N·s up to 0.15 m at ≥ 30 000 N·s). Also shake on car-to-car hits ≥ 12 000 N·s; police rams currently give no shake at all.
6. **Small code fixes:**
   - typed preset objects (an inner class) instead of `Dictionary` + `float(preset["dist"])`;
   - rename the shadowing locals `name` (`chase_camera.gd:94`) and `basis` (`:258`);
   - `_toward_victim` points away from the victim, so rename it;
   - null-check `_takedown` in `_ready`.
7. **Evidence quality.** The demo rig's car is untextured flat boxes (ART.md §5), and its bumper frame shows two blown-out white lamp boxes. The real Roadster is in the repo now (`game/assets/cars/roadster/roadster.glb`, with `Camera_Hood`). Use it in the rig, and shoot all round-2 evidence in the real game too (`--scene=res://main.tscn --stub=menu`), as a ffmpeg contact sheet.

## Verified OK
- `check --only=res://vehicle/camera/`: 16 files, 0 failed, 0 warnings. Tests: 44 checks, 0 failures.
- Ownership: the job log shows writes only to `game/vehicle/camera/**` and `status/camera.md`, apart from `/tmp/cm.gd` (MUST-FIX 2). Every file is ≤ 400 lines (largest: `chase_camera.gd`, 377).
- Dossier numbers:
  - FOV 62 + 0.10·v + 8 + 4, clamped at 84, λ 4. In game: 62.00° at rest, 65.12° at about 117 km/h.
  - Rest pose (0, 1.9, 6.0); 6.35 m at 72 km/h.
  - Yaw target vel + 0.35·(head − vel). Speed lines 160 → 280 km/h, blur 200 → 300 km/h.
  - Takedown: 9 m / 1.0 m / 50° / 0.30× / hit-stop 0.05. In open space the cut back came at **2.716 s** (windowed). Traffic takedowns get no cam; 4 s cooldown (code).
- **Jitter (acceptance), real game, real Roadster:** 10 consecutive rendered frames at 60 fps (`probe_c.gd`). `mean_abs_dev = (0.000, 0.493) px`; the frame-to-frame steps are an even −0.21…−0.18 px drift from the speed-dependent distance, with no jitter. **PASS.**
- The horizon never rolls in drift or hop frames. The flight bank is ≤ 10° (`cam_flight_t3_0.jpg`). Drift framing shows the turning radius (`cam_drift_t4_0.jpg`).
- `radial_blur_effect.gd` is a byte-identical copy of the verified snippet, plus one provenance line.
- The `motion_blur` toggle works through the unit's own config and the CLI, and `ui/menu/bridge.gd` reaches `set_motion_blur` on the Effects node.

## Evidence
- `tools/godot.sh check --only=res://vehicle/camera/` → `CHECK 16 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://vehicle/camera/tests/test_camera.gd` → `TEST 44 checks, 0 failures` / `PASS`
- Reviewer probes. Run with `python3 tools/slots.py light 6 -- godot --headless --fixed-fps 120 --path game -s res://tools/test_host.gd -- --test=/Users/minimax/m/skyrush/tmp/review/camera/<probe>.gd`, or windowed with the `heavy` slot.
  - `probe_a.gd`:
    - `A spin: ticks with near plane inside wall=16 / 180, min clearance=-0.282 m`
    - `B respawn: ticks behind/inside wall=12 / 40, worst depth=3.750 m, first clear tick=12`
    - `E shake: max roll component=0.000000`
    - `E2 per-tick moves: 0.158 … 0.010, 0.065, 0.000…`
    - `F swap: dist to new car=294.0 m, to old car=6.3 m`
  - `probe_b.gd`, windowed:
    - `flash max alpha seen at frame_pre_draw = 0.00; pre_draw calls=519`
    - `cut back after 2.716 s`
    - `tunnel takedown cam pos=(8.59, 1.02, 0.0) inside_wall=true line_of_sight_blocked=true`
    - headless at a fixed 120 fps: `cut back after 2.700 s wall clock; unscaled game time at the cut = 390.09 s`
  - `probe_c.gd`, windowed `--max-fps 60 --stub=menu`: `body mean=(960.0, 653.6) mean_abs_dev=(0.000, 0.493) px`
  - `probe_d.gd`, real game N₂: the camera's N₂ stays on (`cam_nitro=true fov=83.23 blur=0.250` at 12 s). The vehicle's own N₂ also never ended in this run (`boost_time_left=3.00`, 482 km/h), so this run cannot show the camera releasing; the 0-emitter grep is the evidence for item 7.
- My captures (`captures/review/camera/`):
  - `rv_real_t5_0 / t7_9 / t8_6 / t9_6.jpg`, sheet `rv_real_sheet.jpg`: real game, 195 → 308 km/h, N₂;
  - `rv_bumper_t2_5.jpg` (58 % orange) and `rv_bumper_nofx_t2_5.jpg` (0 %);
  - `rv_ref_side.jpg`: ours compared with `ref/art/img/cp04_nfs2015_wet_night.jpg` and `cp05_nfsheat_police_neon.jpg`;
  - `sheet3.jpg`: 100 % crop of the streaks;
  - `worker_real.jpg` / `worker_demo.jpg`: your frames as contact sheets.
- `python3 tmp/review/camera/streak_metrics.py captures/review/camera/rv_real_t9_6.jpg` → `r=0.30w mean_width=19.9px max_width=33.4px coverage=9.3%`

## Notes for the lead (not counted against the worker)
- **Framing compared with the reference.** At speed the car is about 12–15 % of the frame width (`rv_real_t7_9.jpg`). In the NFS Heat chase frame (`ref/art/img/cp05_nfsheat_police_neon.jpg`) it is about 30 %. In N₂ at 300 km/h the vFOV is 78°, i.e. about 110° horizontal. This follows the brief's numbers; consider a 56° base vFOV or a 5.2 m distance.
- **N₂ blur.** At 0.25 the radial blur smears the city badly (`cam_nitro_t7_6.jpg`). Consider 0.12 for cruise and 0.18 for N₂.
- **Core:** `Game` slow-mo uses the wall clock (`Time.get_ticks_msec`), which is wrong under `--fixed-fps` / `--write-movie`. Also, the capture tool's `_t` scales with time_scale.
- **Vehicle:** nothing emits `boost_ended`. In probe D the N₂ never ended (stuck at 3.00 s left, 482 km/h, above the 330 cap).
- **Menu and camera** each save `motion_blur` (`skyrush_menu.cfg` and `skyrush_camera.cfg`). Move it to `Settings`.
- **fx / fx_thrusters:** `ground_cloud.gd:71` currently has parse errors, and their clouds fill the hood view (MUST-FIX 9 needs their cooperation).

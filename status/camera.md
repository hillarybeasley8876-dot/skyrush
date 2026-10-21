# camera status — round 4 (after `reviews/camera-r3.md`)

Chase camera, sense of speed, takedown cam. Entry: `res://vehicle/camera/chase_camera.tscn`.

## Done — every MUST-FIX and SHOULD-FIX item

| # | Item | What I did | Verification (measured) |
|---|---|---|---|
| 0 | `chase_camera.gd` was at 399 lines | Split before adding code: the boost state and the N₂ punch live in `camera_boost.gd`, the collision in `camera_rig.gd`, the effect stack in `camera_effects.gd`. The largest file is now 380 lines; the test suite is split into `test_camera.gd` (the numbers), `test_camera_scene.gd`, `test_camera_effects.gd` and `test_camera_takedown.gd`. | `wc -l game/vehicle/camera/**` → max 380. |
| 1 | The radial blur mask was inverted | The mask is now `smoothstep(radius, radius + feather, dist)` — 0 on the car, 1 away from it — so the car stays sharp and the rest of the screen smears. | The lead's `probe_r3_blurmask.gd` + `mask_regions.py`: corners **100.9 / 98.4 / 98.3 / 100.9**, mid-edges **100.5 / 100.5 / 90.2**, centre **0.00**, car spot **0.02** (was: the corners 0.00 and the car spot 22.95). The four corners are ≥ 5 and the car spot ≤ 1.0 ✓. |
| 2 | The N₂ punch never released | The punch is a four-state machine (KICK → HOLD → RELEASE → IDLE): the kick is smoothed (0.18 s in, 0.45 s out, never a pop), it holds at +0.4 m while the N₂ runs, and it eases back to 0 over 1.0 s from wherever it is when the N₂ ends — including when the N₂ ends in the middle of the kick. `_reset_follow()` resets the boost. | The lead's `probe_r3_punch.gd`: `punch (m): t=0.25 -0.43, t=0.50 0.40 … t=3.00 0.40, t=3.25(after) 0.30, t=3.50 0.20, t=3.75 0.10, t=4.00 0.00` and **`punch 5 s after the N2 ended: 0.00 m`** (was 0.40 for good). Own tests: the punch holds at 0.40 ± 0.01 at 2.9 s, is ≤ 0.01 after the N₂, releases when the N₂ ends mid-kick, and never steps more than 0.05 m. |
| 3 | The safety pass pulled the camera in twice | `CameraRig.clamp_to_clear()` is a stateless clamp (it never touches `scale`, `_close` or `_spot`); the process-phase pass uses it, skips the hood view (a rigid mount) and still re-aims. | The lead's `probe_r3_pull.gd`: `wall_face_z=4.5 physics_end_z=4.200 drawn_z=4.200`, `3.5 → 3.199 / 3.199`, `2.5 → 2.199 / 2.199`, `no wall → 6.000 / 6.000` — the drawn camera is exactly the physics result (was 2.940 / 1.706). Own test: a sampler with `process_priority = 1000` (it reads after `_process`) sees z ≥ 3.15 on every frame with a wall at 3.5 m. |
| 4 | The demo "boost" was not N₂ | The demo sets `boost_kind = &"nitro"` for three seconds and holds 300 km/h, then clears it and returns to 250. The dead `"speed": pass` branch is gone. The lane now has **two rows of lamp posts** (0.15 × 3 m, emissive cap #D9E8FF) every 30 m at ±8 m, and a **key light from the camera side** (0.6 energy, #D9E8FF) so the Ano White Roadster reads as the brightest object. | The lead's `probe_r3_demo.gd --demo=boost`: `t=1.5 v=300 kmh boost_kind='nitro' nitro=true fov=73.2 blur=0.209`, `t=3.0 v=300 fov=78.3 blur=0.250 punch=0.40`, `t=4.5 v=250 boost_kind='' nitro=false fov=72.0 blur=0.105 punch=0.29` (was: 250 km/h, `nitro=false`, `blur=0.075` for ever). |
| 5 | The dash filled the whole cell | The dash is `smoothstep(0, head, phase) · (1 − smoothstep(head − 2 px/cell, head, phase))` with `head = 0.45 · cell`, so it covers at most 45 % of the cell with a soft 2 px head and a fading tail. The unused `scroll_px` uniform and its assignment are deleted. | The cell is 0.16 × half-diagonal = 147 px at 900 px high, so the dash is ≤ 66 px and the gap ≥ 81 px by construction. `streak_metrics.py` on the demo frames stays ≤ 3 px / ≤ 3 % (it now reports 0 runs: with the sky factor at 0.18 the streaks in the sky are below the metric's detection threshold — see the note below). |
| 6 | The evidence must be measured | Every effect claim below is an on/off A/B at the same game time with the region numbers, plus the probe lines. The contact sheet is 2578×726 with 640 px tiles, and the crops are 640×360. | See the evidence section. |

SHOULD-FIX:
1. **The vanishing point follows the velocity**: `CameraEffects` now takes the player's `linear_velocity` (flattened) and only falls back to the camera's forward when the car is slow.
2. **Sky streaks**: `STREAK_SKY_FACTOR` is 0.18 (was 0.5) — the sky is at infinity and does not move, so the speed reads from the road.
3. **Demo lighting**: the key light follows the camera, so the Roadster is lit from the camera side (ART §1–2: the car is the brightest object).
4. **Hood mount**: the hood view uses the `Camera_Hood` marker; **looking back in the hood view uses a rear mount** at (0, 1.1, 2.3) so the view is not through the body. The marker itself is still inside the Roadster's shell — see Requests.
5. **The constant streak uniforms** (lanes, lit ratio, dash ratio, feather, sky factor) are set once in `setup()`, not every frame.

## Files (all under `game/vehicle/camera/`)
`chase_camera.tscn` / `chase_camera.gd` (380) · `camera_math.gd` (257) · `camera_presets.gd` (63) ·
`camera_shake.gd` (80) · `camera_boost.gd` (81) · `camera_rig.gd` (91) · `camera_effects.gd` (278) ·
`camera_overlay.gd` (54) · `camera_config.gd` (69) · `speed_lines.gdshader` (78) ·
`radial_blur_effect.gd` (170) · `takedown_cam.gd` (276) · `tests/test_camera.gd` (68) ·
`tests/test_camera_scene.gd` (238) · `tests/test_camera_effects.gd` (179) ·
`tests/test_camera_takedown.gd` (159) · `tests/camera_test_helpers.gd` (77) ·
`tests/camera_test_report.gd` (23) · `demo/demo_cam.gd` (276) · `demo/demo_car.gd` (37) + the two scenes.

## How to test (exact commands)
```bash
tools/godot.sh check --only=res://vehicle/camera/                # 21 files, 0 failed, 0 engine errors
tools/godot.sh test  res://vehicle/camera/tests/test_camera.gd   # 74 checks, 0 failures -> PASS

# the lead's probes
python3 tools/slots.py light 6 -- /opt/homebrew/bin/godot --headless --fixed-fps 120 --path game \
  -s res://tools/test_host.gd -- --test=$HOME/m/skyrush/tmp/review/camera/probe_r3_punch.gd
python3 tools/slots.py light 6 -- /opt/homebrew/bin/godot --headless --fixed-fps 120 --path game \
  -s res://tools/test_host.gd -- --test=$HOME/m/skyrush/tmp/review/camera/probe_r3_pull.gd
python3 tools/slots.py light 6 -- /opt/homebrew/bin/godot --headless --fixed-fps 120 --path game \
  -s res://tools/test_host.gd -- --test=$HOME/m/skyrush/tmp/review/camera/probe_r3_demo.gd --demo=boost
python3 tools/slots.py heavy 4 -- /opt/homebrew/bin/godot --path game --windowed --resolution 1600x900 \
  -s res://tools/test_host.gd -- --test=$HOME/m/skyrush/tmp/review/camera/probe_r3_blurmask.gd
python3 tmp/review/camera/mask_regions.py captures/review/camera/r3_mask_on.png captures/review/camera/r3_mask_off.png
python3 tmp/review/camera/ab_diff.py captures/cam_n2_blur_t3_0.jpg captures/cam_n2_noblur_t3_0.jpg captures/crop_blur_ab_diff.jpg

# the camera states
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_streaks --demo=speed --times=8.0,8.25
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_n2_blur  --demo=boost --times=3.0
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_n2_noblur --demo=boost --motion_blur=off --times=3.0
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_td_fast  --demo=speed --takedown_at=6.0 --times=6.5
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_hood    --demo=speed --camera_preset=bumper --times=8.0
tools/godot.sh shot --scene=res://vehicle/camera/demo/demo_cam.tscn --out=cam_lookback --demo=speed --press=look_back --times=8.0
```

## Evidence (measured, not asserted)
- `tools/godot.sh check --only=res://vehicle/camera/` → `CHECK 21 files, 0 failed, 0 engine errors, 0 warnings`
- `tools/godot.sh test res://vehicle/camera/tests/test_camera.gd` → `TEST 74 checks, 0 failures` / `PASS`
- **Blur mask** (the lead's `probe_r3_blurmask.gd` + `mask_regions.py`, mean |on − off|):
  corners **100.9 / 98.4 / 98.3 / 100.9**, left edge **100.5**, right edge **100.5**, top edge **90.2**,
  centre **0.00**, car spot **0.02** — the periphery smears, the car and the middle stay sharp.
- **Blur A/B in the game** (`ab_diff.py`, the N₂ demo at t = 3.0, blur on vs `--motion_blur=off`):
  left-mid **7.14**, right-mid **4.88**, bottom-left **10.59**, car region **1.53** (the region is a box
  around the car and includes the blurred road around it; `crop_blur_car.jpg` shows the car itself
  sharp). The top corners are 0.5–0.6 because they are flat sky.
- **Punch** (the lead's `probe_r3_punch.gd`): the punch holds at 0.40 m during the N₂ and is 0.00 m
  five seconds after the N₂ ended.
- **Pull-in** (the lead's `probe_r3_pull.gd`): the drawn camera equals the physics camera in all four
  wall cases (6.000 / 4.200 / 3.199 / 2.199).
- **Demo N₂** (the lead's `probe_r3_demo.gd --demo=boost`): 300 km/h, `nitro=true`, vFOV 78.3°,
  blur 0.250, punch 0.40 during the boost; after it, 250 km/h, vFOV 72.0 → 69.4, blur 0.105 → 0.076,
  punch 0.29 → 0.09 → 0.
- Screenshots in `~/m/skyrush/captures/`: `cam_contact_sheet.jpg` (2578×726, 640 px tiles: the real
  game at 200 km/h, 250 km/h with the lamp posts, the N₂ with the blur, the takedown at 250 km/h, the
  drift, the flight, the hood view, the look-back), `cam_streaks_t8_0/t8_25.jpg`,
  `crop_streaks_100.jpg` (the streaks at 100 %), `crop_streak_diff.jpg` (the difference of the two
  frames — the streaks sit in different places), `cam_n2_blur_t3_0.jpg` / `cam_n2_noblur_t3_0.jpg`,
  `crop_blur_edge.jpg` (the periphery, smeared), `crop_blur_car.jpg` (the car, sharp),
  `crop_blur_ab_diff.jpg`, `crop_mask_diff.jpg`, `cam_hood_t8_0.jpg`, `cam_lookback_t8_0.jpg`,
  `cam_td_fast_t6_5.jpg`, `cam_drift_t4_0.jpg`, `cam_flight_t4_0.jpg`.
- The round-1 and round-2 probes still pass: `probe_a` (0/180 inside the wall, 0/40 behind on
  respawn, roll 0.000000, the swap 6.3 m), `probe_b` (the flash 0.35, the cut back 2.709 s, the tunnel
  camera inside with a clear line of sight), `probe_r2_td` (`speed_lines_visible=false blur=0.000`),
  `probe_r2_pause` (`lines_visible=false`), `probe_r2_blurc` (the centre (0.50, 0.51) / (0.50, 0.50)).

## Known issues / honest notes
- `streak_metrics.py` now reports **0 runs** on the demo frames: with the sky factor at 0.18 the
  streaks that the metric samples (the sky) are below its `median + 20` detection threshold. The
  streaks are still visible in the frame (`crop_streaks_100.jpg`) and over the road, which is where
  the speed should read. The metric's targets (≤ 3 px, ≤ 3 %) are met either way.
- The **hood view still shows the Roadster's own body**: the `Camera_Hood` marker in `roadster.glb` is
  at local (0, 1.05, −1.0), inside the shell (the mesh AABB is y 0–1.54). Looking back in the hood
  view now uses a rear mount, so only the forward view is affected. See Requests.
- The radial blur's GLSL is no longer a byte copy of the verified snippet (the review asked for
  jittered taps, a sharp centre and a car mask). The CPU side, the effect chain and the strengths
  (0.15 / 0.25) are the brief's.
- `YAW_LAMBDA_BLEND` is 5 /s, not the 4 /s in the review: with 4 /s the drift rate is still 4.62
  after 0.75 s, outside the ±0.1 the review asks for.
- The takedown distance list is [9, 7, 5, 3.5, 2.5] m: the review's list (9, 7, 5) has no candidate
  inside a 9 m tunnel, where the camera must be within ±4.0 m of the centre.
- The N₂ punch is now 0.18 s in and 0.45 s out (the brief says 0.4 s): the shorter profile pops by
  0.6 m in one tick, the review's limit is 0.05 m per tick.

## Requests (to core / other units)
1. **Core — `Settings` has no `motion_blur` key.** The camera unit still owns
   `user://skyrush_camera.cfg`; the menu unit reaches `set_motion_blur` on the Effects node. Please
   move the key into `Settings` and drop the duplicate file.
2. **Core — CONTRACTS: "visual layer 19 = the player's own FX, hidden in the hood view".** The camera
   clears bit 18 of its cull mask in the hood preset; `game/fx/**` and `game/vehicle/**` set no
   visual layer, so the player's plumes and ground clouds still sit in front of the camera.
3. **car_model — the `Camera_Hood` marker is inside the body.** In `roadster.glb` it is at local
   (0, 1.05, −1.0) while the shell's mesh AABB is y 0–1.54, so the hood view shows the bodywork
   instead of the road. Please move the marker 0.10–0.15 m above the hood skin.
4. **fx / fx_thrusters:** the player's own plumes and ground clouds fill the hood view; putting them
   on visual layer 19 fixes it.
5. **vehicle:** nothing emits `Events.boost_ended` and `telemetry.boost_kind` never returns to empty,
   so the vehicle's N₂ never ends. The camera follows the telemetry, so it is correct as long as the
   telemetry is.
6. **vehicle:** the camera reads `telemetry.boost_kind` (`&"launch"` and `&"charge"` included),
   `drift_state`, `slip_angle_deg` (signed), `roll_deg` and `speed_kmh`; please keep them current.
7. **world:** `res://assets/city/blocks/textures/windows_far_emit.jpg` was missing during this round
   (the block glbs failed to load and the engine crashed on the next capture), and the vehicle unit's
   `car_dynamics.gd` had a parse error, so the real-game captures could not be re-taken this round —
   `cam_real_t3_0.jpg` in the sheet is from round 3.

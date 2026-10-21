# vehicle review round 2 — VERDICT: FAIL

Reviewer: lead/art director (Opus), 2026-10-20. Every number below was measured by me on the
current files. Probe scripts (Node tests — copy what you need into your own tests):
`tmp/review/veh2/probe_e.gd` … `probe_p.gd`, run with
`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/veh2/probe_e.gd`; logs in `tmp/review/veh2/*.log`.

## Scores (0-10)
- function: **5** — the R1 fixes are real (289/289 checks pass, lead notes 1 and 3 work, the AI API is
  documented), but the player's nitro key never fires the nitro, tyre grip depends on the compass
  heading, a nitro inside a sky lane holds `boost_ended` back by 8.9 s (lead note V-INT1 again) and a
  sky-lane early exit drops the car 21 m.
- visual/feel: **5** — wheels, calipers and wing are right now; but every hop with W held nose-dives
  (−44° / −70° at touchdown), the sky-lane "bank" is a nose dip, buses/trucks sit on their bump stops
  with the tyres 14–19 cm inside the arches, every parked car takes ~5 s to settle, the red light
  bar is dimmed to half its authored glow, and most events pop up 2–3 duplicate toasts.
- code: **6** — clean module split, all files ≤ 400, typed; but a float→bool edge bug, an upward
  "ground" ray, a call to a method that does not exist, R1-listed magic numbers still there, a
  397/400-line tuning file, and Godot started in the background again.

## MUST-FIX
Order: 8e (split the tuning file, separate step) → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9. Every fix ships
with its test (drive the InputMap path where the player uses keys); re-run all tests + feel_report.

1. **The nitro key never fires the nitro — every press is a free launch.** `car_input.gd:24-26` tries
   `api.request_launch()` first and `car_api.gd:72-77` only checks N₂ ≥ 50 (no standstill, no
   throttle, no ground check). Probe E (player car, 165 km/h, N₂ 150, nitro key):
   `events=[&"launch"] kind='launch' n2 150.0 -> 150.0 cap=250.0 km/h`; 5 more presses → 5 free
   boosts, N₂ still 150. In `main.tscn` the debug overlay reads `boost launch` at 207 km/h
   (`captures/review/vehicle/review_vehicle_r2_main_t4_0.jpg`; log stack `request_launch ← handle ←
   _sample_input`). AI: `request_launch()` at 149 km/h → `true`. The player can never reach
   300 km/h, never spends N₂, and the HUD shows 完美起步 on every press.
   Do: launch only when |forward speed| < `LAUNCH_MAX_KMH` (5 km/h, tuning) AND ≥ 3 wheels grounded
   AND accelerate held (player) / throttle > `THROTTLE_ON` (AI) AND N₂ ≥ 50 (brief); otherwise the
   nitro. `request_launch()` applies the same rule (false at speed); fix its doc comment too.
   Verify (`Input.action_press`, not the API): nitro key at 150 km/h with 150 N₂ → one
   `boost_started(&"nitro")`, N₂ 50, cap 300 km/h (from 250 km/h: 300 ± 8 km/h); a 2nd press → refused;
   standstill + accelerate + nitro → `launch`, 0-100 0.9 ± 0.2 s; `request_launch()` at 150 km/h → false.

2. **Throttle held in the air nose-dives the car; motor and brakes push in the air.**
   `car_dynamics.gd:303-304` turns throttle/brake into air pitch every tick, and `:93-100` apply the
   drive and brake forces with no wheel contact. Probe H (120 km/h, W held — what every keyboard
   player does): hop → pitch −44° at touchdown, `wobble` (−15 % speed, no 落地喷); Big Hop → −70°,
   `crash`, then two bounces. Drive log `tmp/review/veh2/hopw.csv`: 135.5 → 152.1 km/h during 0.8 s
   airborne with no boost (free motor thrust), then −25 km/h on the wobble. Probe G: brake held →
   +61° nose-up. `test_hop.gd` never sets a throttle, so it passes.
   Do: (a) drive force × (driven wheels in contact / driven wheels) via `spec.is_driven(i)`, brake
   force × (wheels in contact / 4) → both 0 in the air (the 空喷 is the only air speed source).
   (b) Air pitch only from a FRESH press after take-off: latch accelerate/brake at take-off; a key
   held through the take-off does not pitch until released and pressed again, and a fresh W pitches
   only after it is held ≥ 0.25 s (a re-press tap is the 空喷 and must not dive the nose); the
   auto-level keeps full strength until then (dossier §4.8 "never fights the player").
   Verify (add to test_hop): hop and Big Hop from 120 km/h with W held → |pitch| ≤ 8° at touchdown,
   quality `clean`, 落地喷 window open, air speed change within ±1 m/s of the no-throttle case;
   release W, then press and hold it ≥ 0.25 s in the air → the nose still pitches down (≥ 1.2 rad/s).

3. **Tyre grip depends on the compass heading.** `wheel.gd:106` `v_long = vel_at_point.dot(
   Vector3.FORWARD)` uses the WORLD −Z axis, so the slip angle (→ `grip_factor`) is wrong for every
   car not facing north/south. Probe O (120 km/h, throttle 0.35, steer 0.6, last 1 s): heading 0° and
   180° → 1.27 g; −45° → 1.02 g; −90° → 1.06 g (−18…−20 % grip driving east/west; 延安高架 runs E–W).
   All tests drive along −Z, so none caught it.
   Do: pass the steered wheel forward (`up.cross(wheel_right)` or `-basis.z` rotated by the steer)
   into `lateral_force()`. Also interpolate `GRIP_CURVE` linearly — today it steps 1.00 → 0.92 →
   0.80 (brief pitfall: no binary switches in feel code).
   Verify: new `tests/test_heading.gd`: the probe-O corner at 0, −45, −90, 180° → lateral g within
   ±2 % of each other; a 3 s drift heading east vs north → β within ±1°, gauge within ±2 N₂.

4. **The parked car cannot settle, and heavy presets sit on their bump stops.**
   a. The park rule (`car_dynamics.gd:106-109`) sets the WHOLE velocity to zero every tick below
      0.5 m/s, including the vertical part, so the suspension creeps < 1 mm per tick. Probe Q (roadster
      spawned 0.3 m above the road, no input): 1.0 s → y 0.136, wheel loads 1 388 N of 18 639 N (the
      car hangs in the air); 2.5 s → 9 781 N; 5.0 s → 18 072 N. Dossier §10 step 1: "settles at
      0.067 m sag ± 0.01 in < 1.0 s". Every spawn/respawn hovers for seconds and every stop freezes
      the brake-dive pitch. Do: zero only the ground-plane velocity (or a static-friction force);
      never touch the vertical velocity or the pitch/roll rates.
   b. `SPRING_K` 70 000 N/m is one value for every car, but `STATIC_SAG` 0.0666 m is only true for
      1 900 kg; the bus (12 000 kg) would need 0.42 m of sag > `REST_LEN` 0.41. Probe N2 (parked 6 s;
      settled visual wheel centre minus the glb `Wheel_*` position, + = tyre pushed up into the
      arch): bus +0.167/+0.188 m, truck +0.144/+0.167 m (tyres inside the arches, bump stops), heavy_suv
      +0.023, van +0.018, hatch_ev −0.019, sedan −0.015, roadster ≤ 0.004. `test_specs.gd` compares the
      generator with its own formula, so it cannot see this. Do: per-car suspension in `CarSpec`
      (written by `gen_specs.gd`): `spring_k = mass·g / 4 / STATIC_SAG`, dampers scaled by √(k·m)
      relative to the roadster's `DAMP_BUMP/REBOUND`, ARB, `BUMPSTOP_K`, `SUSP_MAX` scaled by the
      k ratio; `wheel.gd` reads them from the spec.
   Verify: a physics test that spawns every preset 0.3 m above the road → within 1.0 s all 4 wheels
   carry ≥ 95 % of the weight, |settled wheel centre − glb wheel| ≤ 0.02 m, |v_y| < 0.02 m/s; plus a
   side capture of bus + truck + hatch_ev parked (tyres just inside the arches).

5. **Sky lane flight (dossier §5.6) — four bugs.**
   a. Bank and pitch are swapped: `sky_flight.gd:172-173` rotates the bank about `Vector3.RIGHT`
      (= pitch) and the pitch about `Vector3.FORWARD` (= roll), the opposite of its own comment.
      Probe P: steer +1, lateral 9.0 m/s → roll 0.0°, pitch −23.1° (the nose dips instead of banking).
   b. An early exit (F) high in the lane ends the flight in mid-air after `LANE_EXIT_MAX_TIME` 2 s
      and `car_flight.gd:57-65` emits `Events.landed` right there. Probe F (exit at 29.2 m):
      `landed alt=20.9 air=0.00 v=0.0 clean`, then `alt=0.2 v=29.3` (21 m free fall at 2 g) +
      `硬着陆 HARD LANDING`, then a bounce landing. The FX puff plays 21 m above the road.
   c. No 落地喷 window after the lane exit: the thruster never sees the touchdown (it is not ticked
      in flight). Dossier: "auto-descend 3 m/s to the deck, puff, 落地喷 window".
   d. **Lead note V-INT1:** `boost_ended` is emitted in `_integrate_forces` AFTER the flight early
      return (`arcade_car.gd:247-250` vs `:278-280`). Probe J: nitro fired in the lane at t 2.06 s →
      `boost_ended` at 10.92 s (= flight end) instead of 5.06 s; the camera keeps its N₂ FOV and blur
      for the whole flight.
   Do: (a) bank about the car's forward axis, pitch about its right axis. (b) Early exit = the
   dossier's glide: leave the rails, gravity 0.35 g, keep the speed, the P1–P4 cushion holds the sink
   rate ≤ 4 m/s in the last 3 m; `landed` comes only from the normal wheel touchdown (never from the
   flight code in the air); at the lane end over a road keep the 3 m/s descent. (c) Open the 落地喷
   window on that touchdown. (d) Emit `boost_ended` from `_physics_process` right after
   `boost.tick()` (one place for every state).
   Verify in `test_sky_lane.gd`: (a) steer +1 → roll 29–34° toward the move, |pitch − lane slope| ≤ 2°;
   (b) F at the crest → exactly 1 `landed`, altitude < 0.5 m when it fires, impact ≤ 6 m/s, no HARD
   LANDING toast; (c) `telemetry.mini_window` true after the touchdown; (d) nitro in flight →
   `boost_ended` at +3.0 ± 0.05 s.

6. **One event = one pop-up; no HARD LANDING on every Big Hop.** The HUD already shows takedown
   (banner), near miss, drift, 闪充 and 完美起步 itself (`ui/hud/hud_events.gd:94-150`), and the damage
   unit sends `Events.stunt(&"takedown", 50 + 25·(n−1), label)`. The car adds toasts for the same
   events: `rewards.gd:38` (takedown → 3 pop-ups), `rewards.gd:46` (near miss → 2),
   `car_events.gd:67` (charge → 3 with `charge_finished`), `:80` (launch → 2; with item 1 that is on
   every nitro press), `:114` (drift → 2). Delete those five toasts. Keep the trick reward but send it
   as `Events.stunt(&"trick", 15, "特技 TRICK!")` so the HUD shows "+15" once.
   `car_events.gd:96-97`: a Big Hop always lands at ~16–17.5 m/s (dossier Δv_y 17.5 m/s), so probe F
   shows `["硬着陆 HARD LANDING", "特技 TRICK!"]` on a clean Big Hop — and `test_rewards.gd` asserts both.
   Do: the car's own hop/Big Hop landing is a cushioned landing (no hard-landing toast or report);
   preferably make the P1–P4 cushion physical (brake the descent to ≤ 10 m/s in the last 2 m — the
   reveal car "brought itself to a soft landing"). Real drops > 14 m/s keep the toast.
   Verify: player Big Hop → exactly one pop-up (TRICK +15); takedown / near miss / drift / charge /
   launch → 0 toasts from `game/vehicle`; a roll-off from the 9 m sandbox deck at 20 km/h without a
   hop → one HARD LANDING.

7. **Brake lights (brief: LightBar_Rear / brake light 4 → 10 on braking) — texture/emission detail.**
   a. `car_visual.gd:116-117` calls `set_instance_shader_parameter` on a `ShaderMaterial`; the method
      only exists on GeometryInstance3D (probe I: `ShaderMaterial.has_method = false`,
      `MeshInstance3D = true`) → a runtime error the day a bar uses an `SH_` shader. Call it on
      `brake_light` (the shader needs an `instance uniform`) or use a per-car duplicate.
   b. The glb authors `M_LightBarRear` at emissive strength 8 (same as the front bar `M_LightBarFront`);
      idle 4.0 halves it, so the hero red bar is dimmer than the DRL. ART §2: the light bar is the
      brightest accent (refs `ref/roadster/img/19_rear_lightbar_night_driving.jpg`,
      `34_rear_lightbar_glow_wing.jpg`; mine `captures/review/vehicle/r2_airbrake_crops.jpg` and
      `r2_static_vs_ref.jpg`: a thin dim line). Idle = the authored strength, braking = 2.5 × authored
      (keep the brief's 4:10 ratio as a tuning constant).
   c. `Brake_Light` (`M_BrakeLight`, emission off in the glb) is never driven: enable its emission
      (#FF1A2E, the braking level) while braking, off otherwise.
   d. The NPC glbs have no `LightBar_Rear`/`Brake_Light`; 8 of the 11 NPC cars have an
      `NPC_lamp_brake` surface (on `Lamp_R`): bind it per car so traffic and police brake lights flare
      on the wet road; for bus/truck/van brighten `NPC_lamp_rear` and file a request to npc_cars.
   Verify: test_visual: roadster bar 8 → 20, `Brake_Light` dark → lit → dark; sedan `NPC_lamp_brake`
   energy rises only while braking; one night rear capture while braking (`--rearcam`).

8. **Code rules (CONTRACTS §3, brief, lead rules).**
   a. `arcade_car.gd:139` `_prev_throttle = new_throttle` stores a float in a `bool` → any throttle
      > 0 counts as "held". Probe E: AI throttle 0.3, then 1.0 → `pressed_at -100.000 -> -100.000`
      (the AI 完美起步 edge is lost). Use `new_throttle > Tuning.THROTTLE_ON`.
   b. `car_flight.gd:89` `from - Vector3.DOWN * Tuning.ALTITUDE_RAY_LENGTH` casts the fallback ray
      UP. Probe E (`Game.world` null, car at y 20): `ground_y = 20.00` (ground at 0) → altitude 0 m.
   c. Magic numbers still in logic files (several were listed in R1 18b): `power.gd:16` 0.05;
      `boost.gd:269` 6, `:276` 4.0; `drift.gd:149` 3.6, `:221` 66.0; `car_dynamics.gd:103/106` 0.05,
      `:183` 0.05, `:199` 1.0, `:204` 0.01; `car_readout.gd:98-102` 0.6/0.5/0.3 (nozzle levels);
      `drive.gd:53` 0.5; `sky_flight.gd:74/95` 3.6 (use `Tuning.KMH`); `car_visual.gd:231-241,
      259-260, 306-307` (placeholder sizes and colours — see SHOULD-FIX).
   d. Dead/stale: `car_dynamics.gd:156` still says "applied at the height of the centre of mass" (R1
      cited it; the code applies at the contact patch); empty section headers `arcade_car.gd:299-303`;
      `player_input.gd:132 gamepad_active()` is never read (and is wrong: a key gives axis 1.0, takes
      the stick branch and sets it true) — while `drive.update_steer()` ramps the stick at 4/s too
      (dossier §4.5: the ramp is keyboard only; the stick uses s·|s| directly; tell them apart by
      the joypad axis, not by the magnitude); `var hopped` declared at the very end of `car_dynamics.gd:355` (put it with the
      other result fields).
   e. `tuning/car_tuning.gd` is 397/400 lines: split it by theme (e.g. `drive_tuning.gd`,
      `air_tuning.gd`, `lane_tuning.gd`, `visual_tuning.gd`) as a separate first step, before this
      round adds constants.
   f. Round 2 started Godot in the background again (job log, session 3–4:
      `(tmp/vehicle/run_all.sh > /dev/null 2>&1 &)`, `(tools/godot.sh test res://vehicle/tests/
      probe_drift.gd > tmp/vehicle/drift.log 2>&1 &); sleep 110`, `(tmp/vehicle/run_everything.sh …
      &)`, and a `run_in_background` loop over all tests). Forbidden (R1 18f, lead rule): run every
      Godot command in the foreground and let it end by itself.

9. **Status and evidence must be true (R1 #19 again).** Wrong in `status/vehicle.md` / result:
   a. "the Jolt space state ignores a ray query with the default collision mask" — false. Probe E:
      the default mask `0xFFFFFFFF` hits the sandbox ground at y 0.0, exactly like mask 1. Your
      altitude bug was the upward ray of 8b. Withdraw that request to core.
   b. "car_paint.gdshader / glass_gold.gdshader do not compile → flat white" — outdated:
      `check --only=res://shaders/` → `CHECK 43 files, 0 failed, 0 engine errors`.
   c. "every magic number in the logic files replaced" — see 8c.
   d. feel_report prints `drift gauge (hold +1.0) 139 N2 | 95 .. 105 N2` — outside its own target
      while the report says "104 N₂". The dossier band (§10 step 3, "3.0 s drift held at β ≈ 35°")
      applies at β ≈ 35°; deeper drifts earn more gauge by design (§1.3). Print the ±1.0
      rows as info (target "—"), or tune; no row may sit outside its printed target.
   e. Re-shoot the evidence after the fixes: nitro at speed with `--debug` (overlay `boost nitro`,
      300 km/h), Big Hop with W held (side view, level touchdown), sky-lane bank (chase view), bus +
      truck parked side view, night rear braking. Name them in the status with what each one proves.

## SHOULD-FIX
- Wing pose hold (`car_visual.gd:176-189`): `_pose_hold` only counts down while a different pose is
  wanted, so every change waits 0.25 s even after minutes in a pose; the air brake is fully up only
  ~0.5 s after the brake (my capture at +0.3 s: wing still flat). Count the dwell from the last change.
- Placeholder (`car_visual.gd:228-247`) — probe L (sedan spec, missing glb): body 2.42 × 0.80 × 4.38
  (roadster numbers) for a 1.90 × 1.31 × 4.78 spec, `normals=false uvs=false` → black flat facets,
  no paint flake. Build it from `spec.body_size` / `body_center_y`, generate normals and box UVs
  (SurfaceTool), tyres from the library material (ART §5: no flat untextured surface).
- Sky lane edge: with steer held the car rides the 7.5 m hard clamp (test: exactly 7.50 m). Fade the
  lateral input by `1 − over / LANE_EDGE_MARGIN` so the 30 m/s²/m spring wins before the clamp.
- `demo/preset_lineup.gd`: rows 5.4 m apart → the bus and truck intersect their neighbours
  (`captures/review/vehicle/r2_presets_sheet.jpg`) and all cars are frozen 0.2 m above the ground.
  Space the slots by `spec.body_size.z`, let the cars settle on the ground, then shoot.
- `test_air_boosts.gd`: the detail `"= %.2f s"` is printed literally and the log has
  `ERROR: String formatting error: a number is required`.
- `vehicle_test.keep_on_ground()` teleports the car every 0.5 s, also during test_stability's
  tunnelling check — run that check on a stretch without teleports.
- The air 小喷 gives +6.1 m/s at once and +3.9 m/s more over the 0.5 s `MINI_ACCEL` (probe G:
  15.95 → 22.07 → 25.94 m/s): fine if intended — write it in the status.

## Verified OK
- `check --only=res://vehicle/` (root files + camera): `CHECK 88 files, 0 failed, 0 engine errors,
  0 warnings`; the status command (owned dirs only): 60 files, 0 failed.
- All 22 tests + feel_report: **289 checks, 0 failures**. Numbers: 0-100 2.42 s, launch 0.80 s, top
  250.0 km/h, N₂ 300.4 km/h, after the nitro 250.0, battery cap 180.0; caps W 272.0 / C 300.0 /
  CW 306.6 / WCW 308.8 / CWW 317.6 / WCWW 319.8; brake 24.4 m (test) / 27.4 m (report); drift
  β 26.4° (−1) / 32.2° (−0.5) / 47.4° (+1), no spin (≤ 2.12 rad/s), gauge 104 N₂ at 32°; roll 360°
  in 0.700 s for 20 N₂, lands upright; 8 m drop at 150 km/h: 0.000 m lateral; 300 km/h lane
  changes: 2.3° roll; charge bay 200 N₂ / 1.0 / +20 HP / `charge`; head-on 51 517 N·s, 15° glance
  keeps 102 %, 1 report per hit; CPU 30 µs (`_integrate_forces`) + 37 µs (`_physics_process`) per
  tick (budget 250).
- Player key path (probe K): tap → `hop` apex 3.28 m; 0.40 s hold → `big_hop` 7.58 m; hover held
  1.0 s → `hover_changed(true)`, −11.2 N₂.
- R1 items closed: 1 (timer end incl. blocked nitro), 2, 3 (menu + paused, no phantom boost), 4
  (costs/events; API documented in `arcade_car.gd` + status), 5 (+50/+75/+50, +5, +15), 6, 7 (空喷
  +6.12 m/s, 落地喷 window), 8 (impulse from the pre-hit velocity, glance torque applied, floor
  filter), 9 (held throttle → no launch), 11, 12a-c/e (front wheels turn right in my capture,
  calipers at the wheel centre, wing 60° from `extras.poses`, edge up), 13, 14, 15 (altitude 0.12 m
  on the deck, g 1.6), 16 (groups, flight ends on respawn, roof respawn 1.54 s), 17 (12 presets
  from their glbs; all 12 drive as AI cars, probe M), 18a/18e, scratch deleted (`tmp/vehicle/` empty).
- Lead notes 1 (menu/paused) and 3 (takedown +50, +25 per streak step, 10 s window = the damage
  unit's `STREAK_WINDOW`) are satisfied; note 2 is satisfied except the launch rule (MUST-FIX 1);
  V-INT1 is satisfied on the road but not in a sky lane (MUST-FIX 5d).
- `main.tscn` with the real units: the player car drives (207 km/h at 4 s, 222 km/h at 9 s),
  the HUD reads the telemetry, **0** errors originate in `res://vehicle/` (4 717 error lines from
  hud, traffic, police and world).
- Ownership: the job log has 52 edited files, all in `game/vehicle/**` (not `camera/`) or
  `status/vehicle.md`; no shell writes outside owned paths. Jolt flags and `can_sleep = false` set.

## Evidence
- The machine had 25 queued imports, so I ran the identical Godot commands of `tools/godot.sh`
  under the same slot pools without the queued import step:
  `python3 tools/slots.py light 6 -- godot --headless --path game -s res://tools/check_all.gd --
  --only=res://vehicle/` and `tmp/review/veh2/run_test.sh <test> <name>` (= `godot.sh test`).
- Probe E: `nitro key at 165 km/h: events=[&"launch"] kind='launch' n2 150.0 -> 150.0 cap=250.0`;
  `5 more nitro presses: 5 boost events, n2 now 150.0`; `AI request_launch at 149 km/h -> true`;
  `AI edge after throttle 0.3: _prev_throttle(bool)=true pressed_at -100.000 -> -100.000`;
  `ray default mask 0xFFFFFFFF hit=true y=(0.0, 0.0, 400.0) | mask 1 hit=true`;
  `fallback ground_y at car y 20.0 = 20.00`.
- Probe F: `exit_early at alt 29.2 m` → `landed: alt=20.9 air=0.00 v=0.0 clean, alt=0.2 air=1.28
  v=29.3 clean, alt=0.5 v=8.5`; `Big Hop … toasts: ["硬着陆 HARD LANDING", "特技 TRICK!"]`;
  `brake light node=LightBar_Rear material=StandardMaterial3D energy=4.0`.
- Probe G: `Big Hop throttle held: fwd 114.0 -> 22.1 km/h, pitch -70`; `brake held: pitch 61`;
  `air mini (no throttle): 15.95 -> 22.07 m/s after 3 ticks`. Probe H: `hop with W held: pitch at
  touchdown -44 deg` (`wobble`), `Big Hop with W held: -70 deg` (`crash`).
- Probe I: `ShaderMaterial.has_method(set_instance_shader_parameter)=false`, MeshInstance3D true.
- Probe J: `nitro in the lane fired at t=2.06` → `boost_ended at [10.92], flight ended at 10.91`.
- Probes N/N2/Q (ride height, settling), O (heading: 1.27 / 1.02 / 1.06 / 1.27 g), P (`steer +1: lateral
  9.0 m/s -> roll 0.0 deg, pitch -23.1 deg`) — numbers quoted in MUST-FIX 3–5.
- glb JSON: `M_LightBarRear` / `M_LightBarFront` emissive strength 8; `M_BrakeLight` no emission;
  NPC `NPC_lamp_brake` in hatch_ev, police ×3, robotaxi, sedan_ev, suv_ev, taxi.
- Captures (`captures/review/vehicle/`): `r2_worker_sheet.jpg` (your 8 shots);
  `review_vehicle_r2_front34/rear34/wheel.jpg` + `r2_static_vs_ref.jpg` (vs `03_front_3q_low.jpg`,
  `34_rear_lightbar_glow_wing.jpg`); `review_vehicle_r2_airbrake_t6_3/t7_0.jpg`,
  `r2_airbrake_crops.jpg` (vs `08_rear_straight_daylight_wing_deployed.jpg`),
  `r2_wing_wheel_vs_ref.jpg`; `review_vehicle_r2_main_t4_0/t9_0.jpg` (`r2_main_sheet.jpg`);
  `review_vehicle_r2_hopW_t3_9/t4_3.jpg`; `review_vehicle_r2_presets_lineup/close.jpg`.

## Notes for the lead (other units, not counted against vehicle)
- car_model/shaders: the canopy reads light gold and see-through with interior facets instead of the
  black arrowhead canopy (`r2_static_vs_ref.jpg` vs `03_front_3q_low.jpg`); the `Brake_Light` box lies
  inside the `LightBar_Rear` box (y 0.845–0.855 within 0.843–0.857), so lighting it may not show.
- hud: `hud_events.gd:119` `push` on Nil and 1 822 `hud.gd:194` errors in `main.tscn`.

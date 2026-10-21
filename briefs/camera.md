# Brief: camera — chase camera, sense of speed, takedown cam

## Goal
A vehicle-led sprung chase camera that sells speed and weight (Criterion "camera = handling"),
plus the screen-space speed effects and the Burnout-style takedown cam.

## You own
`game/vehicle/camera/**`. Entry (Modules unit `camera`): `res://vehicle/camera/chase_camera.tscn`.

## Read first
`ref/gameplay/DOSSIER.md` §2.2–2.3 (numbers table — implement it), §3.5 (takedown cam timeline),
§5.6 (flight), `ref/tech/GODOT.md` §3.5 + VERIFIED `ref/tech/snippets/radial_blur_effect.gd`,
`core/events.gd` (`camera_shake`, `camera_focus`, `slowmo_request`, `takedown`, `flight_changed`,
`landed`, `boost_started`), `core/contracts/car_telemetry.gd`, `core/game.gd`.

## Spec
- Follows `Game.player` (re-acquire on `player_respawned`). Position follow λ 14/s, yaw follow
  λ 7/s grip / 4.5/s drifting, yaw target = velocity dir + 0.35·(heading − velocity dir); look-at
  = car + 1.2 m up + velocity_dir × 4 m. vFOV 62° → +0.10°/(m/s) → +8° N₂ → +4° 小喷, clamp 84°,
  smoothed λ 4/s. Distance 6.0 m / height 1.9 m at rest, +1.2 m back at top speed, N₂ "punch"
  (−0.6 m then +1.0 m over 0.4 s). Never roll the horizon with the car.
- Presets via `camera_toggle`: near (default), far, bumper/hood (use marker `Camera_Hood` if present).
  `look_back` holds a rear view. Flight (`flight_changed` true): looser follow, +2 m up, +1.5 m back,
  slight bank with the car (max 10°).
- Collision: spherecast from car to camera; never clip into walls/decks (elevated roads!).
- Shake: low-frequency noise (8–12 Hz), presets from §2.3 table; `Events.camera_shake`.
- **Radial blur** CompositorEffect (copy the verified snippet into your folder): 0 below 200 km/h →
  0.15 at 300 km/h, 0.25 in N₂, off in menus; respects a settings toggle (`Settings` key
  `motion_blur`, default on — add to your own config if missing and request it in status).
- **Speed lines**: screen-space streaks (shader on a full-screen quad or particles in camera space)
  from 160 km/h, full at 280 km/h, cyan-white, subtle.
- **Takedown cam** (§3.5 table exactly): on `Events.takedown` (and `camera_focus`), hit-stop, cut to
  a side camera 9 m from the victim, 0.30× slow-mo via `Events.slowmo_request`, dolly, hard cut back
  at 2.7 s; skippable after 0.5 s; cooldown 4 s. Player input stays live.
- Uses `Engine.time_scale`-independent timing for the cam (real time).

## Tests / evidence
`vehicle/camera/tests/test_camera.gd` (headless: follow math, FOV ramp values, collision pull-in
against a wall box), windowed captures in the sandbox: rest, 250 km/h, N₂, drift, hop apex,
flight, takedown cam frames (`--press`/`--pulse` options of capture). Evidence in status.

## Acceptance
Smooth (no jitter at 120 Hz physics/60 Hz render — check by capturing 10 consecutive frames and
measuring car screen-position variance), numbers per dossier, never clips, takedown cam timeline
matches, check clean.

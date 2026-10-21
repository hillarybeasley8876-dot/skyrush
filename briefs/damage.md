# Brief: damage — crash physics, deformation, detachable parts, wrecks, takedowns

## Goal
Realistic, spectacular crashes: every car (player, rivals, police, traffic) takes damage from real
Jolt impacts, dents visibly, sheds panels as rigid-body debris, smokes/burns by tier, wrecks, and
the player's kills become Burnout-style takedowns.

## You own
`game/damage/**`. Entry (Modules unit `damage`): `res://damage/damage_director.tscn`.

## Read first
`ref/gameplay/DOSSIER.md` §3.3 + §3.5 (takedown rules, streaks, rewards), §7 (all: impact
classification, HP formula and table, tiers, vertex-shader dents §7.5 A, detachable parts §7.6,
budgets, wreck → respawn flow §7.8); `core/events.gd` (`vehicle_collided` — emitted by the vehicle
unit with impulse/point/normal; `vehicle_damaged`, `vehicle_wrecked`, `takedown`, `slowmo_request`,
`camera_shake`, `camera_focus`, `player_respawned`), `core/contracts/vehicle_base.gd`
(`apply_damage`, `wreck`, `repair`, `get_marker`), `CONTRACTS.md` §6 (detachable part names:
`Bumper_F/R`, `Hood`, `Door_*`, `Wing`, `Skirt_L/R`, `Diffuser`, `Wheel_*`), the vehicle unit's
`game/vehicle/` (read-only: how cars are built, `CarSpec` HP/mass), `status/vehicle.md`.

## Deliverables
1. `damage_director.gd`: listens to `Events.vehicle_collided`; classifies per dossier §7.2 using the
   bodies' velocities (not Jolt impulse estimates); computes HP per §7.3 incl. k_mass and the
   front-ram ×0.5 rule; calls `vehicle.apply_damage()`; wreck rules (HP 0, head-on v_n ≥ 30 m/s,
   vertical landing on a roof); tracks the player's last contact per victim (2.0 s credit) and emits
   `Events.takedown(victim, kind)` + streaks (10 s window) + `Events.stunt` rewards (+50 N₂ handled by
   the vehicle unit listening to takedown? — no: emit `Events.stunt(&"takedown", points, "撞毁！")`
   and let HUD/vehicle react; request in status if the vehicle unit must add N₂).
2. **Dents**: a `next_pass` or material-swap vertex-shader approach per §7.5 A applied to each car's
   `Body` mesh at runtime (works with `SH_car_paint`/`SH_car_paint_npc` — if the base material is a
   ShaderMaterial you can't edit, use a dedicated dent shader that includes the same paint look, or
   coordinate via a request to the environment unit for `dent_pos/dent_dir` uniforms in the car paint
   shaders). 8 dents ring buffer, paint-scrape mask (512²) blending to primer/carbon.
3. **Detachable parts** per §7.6 using the glb's named nodes: hide part, spawn pooled RigidBody3D
   debris (layer 5 "debris", collides with world only), pool 32, 8 s lifetime + fade; hanging bumper
   (hinge 25°) at the heavy tier; wheels off on violent wrecks.
4. **Tiers** per §7.4 (smoke/sparks/flicker via the fx unit's effects — call its API if it exposes
   one, otherwise request it; you may implement simple local emitters inside `game/damage/` until
   then). Player EV heavy state = white smoke + blue electrical arcs.
5. **Wreck flow**: AI cars stay 6 s then fade/despawn signal; player: `Events.camera_focus` crash cam,
   `slowmo_request(0.35, 2.2, car)`, banner via `Events.toast("撞车 WRECKED", &"danger")`, then
   respawn per §7.8 (nearest lane 30 m back via `Game.world.nearest_road_transform`, 70 % speed,
   HP 60, 2 s ghost) and emit `player_respawned`.
6. Tests (sandbox, headless physics): `test_damage_formula.gd` (§7.3 examples), `test_takedown.gd`
   (player rams a parked/stub car at 25 m/s → victim wrecked, takedown emitted), `test_parts.gd`
   (front hit 23 m/s detaches Bumper_F as debris), `test_pool.gd` (100 crashes, ≤ 32 debris alive,
   no errors), `test_respawn.gd`. Windowed captures of a crash sequence (frames at 0, 0.2, 0.5,
   1.0 s) in `captures/damage/`.

## Acceptance
Tests pass; crash captures read clearly (dent visible at 6 m, flying parts, sparks/smoke);
performance ≤ 0.3 ms/frame damage logic with 20 cars; `check --only=res://damage/` clean.

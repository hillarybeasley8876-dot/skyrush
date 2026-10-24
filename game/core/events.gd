extends Node
## Global signal bus (autoload "Events"). Core-owned contract: units emit and listen here instead of
## holding references to each other. Add new signals only through the lead (status/<unit>.md Requests).

# --- vehicles -------------------------------------------------------------------------------------
## Any physical hit between a vehicle and something else (impulse in N·s, world-space point/normal).
signal vehicle_collided(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3, normal: Vector3)
signal vehicle_damaged(vehicle: VehicleBase, amount: float, source: Node3D)
## A vehicle knocked a street lamp down (world/build/prop_breaker.gd): the sound of the hit and of the glass of its head.
signal prop_broken(vehicle: VehicleBase, kind: StringName, point: Vector3, speed: float)
signal vehicle_wrecked(vehicle: VehicleBase, source: Node3D)
## A pooled AI car (traffic, police) was taken out of its pool and put back into play: every unit that keeps state per
## car forgets it (the damage unit restores the health, the paint, the parts and the visibility of a car that was wrecked).
signal vehicle_recycled(vehicle: VehicleBase)
## The player caused a wreck. kind: &"police", &"rival", &"traffic".
signal takedown(victim: VehicleBase, kind: StringName)

# --- player abilities (ref/gameplay/DOSSIER.md §4.6-§5.7) -----------------------------------------
## kind: &"nitro", &"mini" (小喷), &"air_mini" (空喷), &"landing" (落地喷), &"launch", &"charge".
signal boost_started(vehicle: VehicleBase, kind: StringName)
signal boost_ended(vehicle: VehicleBase)
signal drift_started(vehicle: VehicleBase, direction: int)
## clean = ended without a wall hit (小喷 window opened); n2_gained = units committed.
signal drift_ended(vehicle: VehicleBase, duration: float, clean: bool, n2_gained: float)
## kind: &"hop", &"big_hop".
signal hop(vehicle: VehicleBase, kind: StringName)
signal hover_changed(vehicle: VehicleBase, active: bool)
## direction: -1 = left, +1 = right.
signal barrel_roll(vehicle: VehicleBase, direction: int)
## quality: &"clean", &"wobble", &"crash".
signal landed(vehicle: VehicleBase, airtime: float, impact_speed: float, quality: StringName)
signal sky_lane_launch(vehicle: VehicleBase, lane: SkyLane)
## The player pressed the horn (H / R3). The audio unit plays it; the traffic around may react to it.
signal horn(vehicle: VehicleBase)
signal flight_changed(vehicle: VehicleBase, active: bool, lane: SkyLane)
signal n2_ring(vehicle: VehicleBase, lane: SkyLane)
## Traffic passed within 1.2 m at ≥ 60 km/h relative.
signal near_miss(vehicle: VehicleBase, other: VehicleBase)
## Score events with a ready-made HUD label, e.g. (&"fly_over_gas", 800, "飞跃加油站!").
signal stunt(kind: StringName, points: int, label: String)
signal charge_started(vehicle: VehicleBase, station: Area3D)
## amount 0..1 of a full refill granted by the station (闪充 = instant full refill).
signal charge_finished(vehicle: VehicleBase, station: Area3D, amount: float)

# --- race / pursuit -------------------------------------------------------------------------------
signal race_countdown(seconds_left: int)
signal race_started()
signal checkpoint_passed(vehicle: VehicleBase, index: int, total: int)
signal lap_completed(vehicle: VehicleBase, lap: int, lap_time: float)
## results: Array of Dictionary {name: String, time: float, position: int, is_player: bool}
signal race_finished(results: Array)
signal heat_changed(level: int)
## Player offences that start/raise a pursuit. kind: &"toll_evaded", &"speeding", &"hit_police",
## &"hit_traffic", &"reckless".
signal infraction(vehicle: VehicleBase, kind: StringName)
## state: &"none", &"chase", &"search", &"cooldown", &"escaped", &"busted".
signal pursuit_state_changed(state: StringName)

# --- presentation ---------------------------------------------------------------------------------
## World/asset loading progress 0..1 with a short label (menu shows a loading screen).
signal loading_progress(fraction: float, label: String)
## style: &"info", &"good", &"great", &"danger", &"police". HUD shows it as a QQ飞车-style pop-up.
signal toast(text: String, style: StringName)
## The state of the running mode, for the HUD: the modes unit emits it (on every change and at least every
## 0.5 s while the mode runs), the HUD only draws it. `kind` and `data`:
##   &"free"    {"score": int}
##   &"race"    {"lap": int (1 based), "laps": int, "position": int (1 = first), "racers": int,
##               "route": String (the route id), "next_gate": int (index of the next checkpoint of the player, -1 = home), "gates": int}
##   &"pursuit" {"takedowns": int, "target": int (0 = no goal), "time_left": float (s, -1.0 = no limit)}
##   &"none"    {} (no mode: nothing to show)
signal mode_status(kind: StringName, data: Dictionary)
signal slowmo_request(time_scale: float, duration: float, focus: Node3D)
signal camera_shake(strength: float, duration: float)
## Crash cam: look at target for duration seconds (real time), then return to the chase cam.
signal camera_focus(target: Node3D, duration: float)
signal player_respawned()
signal game_paused(paused: bool)

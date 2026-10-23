extends RefCounted
## The handlers of the core event bus for one car: the sky lane launch, the charge bay, the race
## start (完美起步), the takedowns, the near misses and the drift state.
##
## The car body owns this helper: it wires the modules and keeps the clock and the throttle press
## time up to date, so the launch window is measured against the same clock as the input.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const RewardTuning := preload("res://vehicle/tuning/reward_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const PowerMod := preload("res://vehicle/modules/power.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")
const RewardsMod := preload("res://vehicle/modules/rewards.gd")
const ApiMod := preload("res://vehicle/modules/car_api.gd")

var car: VehicleBase = null
var boost: BoostMod = null
var power: PowerMod = null
var drift: DriftMod = null
var thruster: ThrusterMod = null
var dynamics: DynamicsMod = null
var rewards: RewardsMod = null
var api: ApiMod = null
## The clock of the car (seconds since the start).
var clock: float = 0.0
## The moment the throttle was pressed the last time (the 完美起步 window).
var throttle_pressed_at: float = BodyTuning.TIME_NEVER


## Wires the helper to the car and its modules and connects the event bus.
func setup(vehicle: VehicleBase, boost_module: BoostMod, power_module: PowerMod,
		drift_module: DriftMod, thruster_module: ThrusterMod, dynamics_module: DynamicsMod,
		rewards_module: RewardsMod, api_module: ApiMod) -> void:
	car = vehicle
	boost = boost_module
	power = power_module
	drift = drift_module
	thruster = thruster_module
	dynamics = dynamics_module
	rewards = rewards_module
	api = api_module
	Events.sky_lane_launch.connect(on_sky_lane_launch)
	Events.charge_finished.connect(on_charge_finished)
	Events.race_started.connect(on_race_started)
	Events.takedown.connect(on_takedown)
	Events.near_miss.connect(on_near_miss)


## The sky lane take-off: the car enters the lane when it is fast enough.
func on_sky_lane_launch(vehicle: VehicleBase, lane: SkyLane) -> void:
	if vehicle != car:
		return
	api.try_flight(car, lane)


## The charge bay: the tank, the battery and the health are refilled.
func on_charge_finished(vehicle: VehicleBase, _station: Area3D, _amount: float) -> void:
	if vehicle != car:
		return
	boost.n2 = BoostTuning.N2_MAX
	power.charge()
	car.health = minf(car.max_health, car.health + BoostTuning.CHARGE_HP)
	car.telemetry.health_norm = car.health / car.max_health
	boost.start_charge()
	Events.boost_started.emit(car, &"charge")


## The race start: 完美起步 when the throttle was pressed inside the window before the start.
func on_race_started() -> void:
	if clock - throttle_pressed_at <= BoostTuning.START_WINDOW:
		start_launch()


## The thruster launch: a 0.9 s burst that gets the car to 100 km/h in under a second.
func start_launch() -> void:
	boost.start_launch()
	Events.boost_started.emit(car, &"launch")


## A takedown: the N2 reward of the player (dossier 5.2).
func on_takedown(victim: VehicleBase, kind: StringName) -> void:
	rewards.on_takedown(car, kind)


## A near miss: the N2 reward of the player (dossier 5.2).
func on_near_miss(vehicle: VehicleBase, _other: VehicleBase) -> void:
	rewards.on_near_miss(vehicle)


## The landing of the car: the event and the report of a hard landing (dossier 4.8).
func report_landing(airtime: float, impact: float, quality: StringName) -> void:
	Events.landed.emit(car, airtime, impact, quality)
	if impact > AirTuning.LAND_VERTICAL_SAFE:
		Events.toast.emit("硬着陆 HARD LANDING", &"info")


## The drift state changed: the start, the end and the gauge of the drift.
func on_drift_state_changed() -> void:
	if drift.state == &"drift":
		Events.drift_started.emit(car, drift.dir)
		return
	if drift.state != &"recover":
		return
	var gained: float = 0.0
	if drift.exit_gauge > 0.0:
		gained = boost.commit_gauge(drift.exit_gauge)
	drift.exit_gauge = 0.0
	Events.drift_ended.emit(car, drift.time, drift.exit_clean, gained)
	if drift.exit_clean:
		boost.open_mini_window()


## A clean landing after a Big Hop or a barrel roll is worth 15 N2 (dossier 5.2 and 5.4: the
## roll has to end 0.15 s before the touchdown).
##
## The trick is evaluated once per jump: every landing consumes the hop and the roll, so a
## plain hop or a road crest never pays out the trick of an earlier jump.
func check_trick() -> void:
	var hop: StringName = thruster.last_hop
	var roll_end: float = thruster.roll_end_time
	thruster.last_hop = &""
	thruster.roll_end_time = -1.0
	# A one tick wheel loss is not a landing (dossier 4.8: the airborne rule).
	if dynamics.landing_airtime < AirTuning.LAND_AIRTIME_MIN:
		return
	if dynamics.landing_quality != &"clean":
		return
	if hop == &"big_hop":
		rewards.on_trick(car)
		return
	if roll_end < 0.0:
		return
	if thruster.clock - roll_end >= RewardTuning.TRICK_ROLL_CLEARANCE:
		# The trick comes from the roll: the roll showed its own pop-up.
		rewards.on_trick(car, true)

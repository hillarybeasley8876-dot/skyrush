class_name ArcadeCar
extends VehicleBase
## The arcade car: a RigidBody3D with four ShapeCast3D wheel probes, QQ-style assisted drifting,
## N2 boosts, thruster moves and sky lane flight. Every car in the game is this class with a
## different CarSpec (player, rivals, police, traffic).
##
## The work is split into modules: car_dynamics.gd applies the forces, car_readout.gd writes the
## telemetry and moves the visual, car_api.gd is the AI facing API, rewards.gd holds the N2
## rewards and the drive/drift/boost/thruster modules hold the rules.
##
## THE AI FACING API (the rivals, the police and the traffic use only this):
##   set_controls(throttle, brake, steer, handbrake) -> void
##       The driving input: throttle 0..1, brake 0..1, steer -1..1 (+1 = right), handbrake
##       (unused, the drift button is set_drift). Costs nothing, raises no event.
##   set_drift(on: bool) -> void
##       The drift button (QQ style). The drift needs a speed of 15 m/s, a steer of at least
##       0.3 and three wheels on the ground. Costs nothing, raises no event; the start and
##       the end of the drift raise Events.drift_started / Events.drift_ended.
##   use_nitro() -> bool
##       The nitro: costs a full slot (100 N2), burns 3 s and lifts the speed cap to
##       300 km/h. Refused when the tank holds less than 100 N2.
##       Raises Events.boost_started(vehicle, &"nitro").
##   request_hop(big: bool = false) -> bool
##       A hop (25 N2) or a Big Hop (50 N2). The impulse fires after the spool (0.08 s /
##       0.15 s). Refused when the car has fewer than two wheels on the ground, when the hop
##       cooldown (0.6 s) has not passed, when the tank is too empty or when there is less
##       than 3 m of clearance above the car.
##       Raises Events.hop(vehicle, &"hop" / &"big_hop").
##   request_roll(direction: int) -> bool
##       A barrel roll (20 N2): 360 degrees in 0.70 s. Only in the air, at most twice per
##       jump, and refused when the tank is too empty.
##       Raises Events.barrel_roll(vehicle, direction).
##   request_launch() -> bool
##       The standing launch (完美起步): 0.9 s of +20 m/s^2, so 0-100 km/h in under a second.
##       It costs no N2, but it needs a standstill (under 5 km/h), at least three wheels on
##       the ground, the throttle held (above THROTTLE_ON) and half a tank (50 N2).
##       Raises Events.boost_started(vehicle, &"launch").
##   get_n2() -> float
##       The N2 left in the tank (0..200). Costs nothing, raises no event.
## Every call that spends N2 raises exactly one event on the Events bus.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const DriveMod := preload("res://vehicle/modules/drive.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")
const PowerMod := preload("res://vehicle/modules/power.gd")
const ImpactMod := preload("res://vehicle/modules/impact.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")
const AirMod := preload("res://vehicle/modules/car_air.gd")
const ReadoutMod := preload("res://vehicle/modules/car_readout.gd")
const ApiMod := preload("res://vehicle/modules/car_api.gd")
const RewardsMod := preload("res://vehicle/modules/rewards.gd")
const StuntsMod := preload("res://vehicle/modules/stunts.gd")
const PlayerInputMod := preload("res://vehicle/player_input.gd")
const SetupMod := preload("res://vehicle/modules/car_setup.gd")
const InputMod := preload("res://vehicle/modules/car_input.gd")
const EventsMod := preload("res://vehicle/modules/car_events.gd")
const FlightMod := preload("res://vehicle/modules/car_flight.gd")
const IncidentRecorder := preload("res://vehicle/incident_recorder.gd")

## The vehicle data. Assign it before the car enters the tree.
@export var spec: CarSpec = null
## True for the car that reads the player input.
@export var player_controlled: bool = false
## True for a car that turns itself back onto its wheels when it lies on its side or on its roof (BodyTuning.RIGHTING_*). The car
## of the player always does. An AI car does not: a police unit on its roof is disabled (dossier 6.3), a turned over rival is out.
@export var self_righting: bool = false
## True for a car whose full wheel is the angle where the front tyres give the most (DriveTuning.STEER_GRIP_*). The car of the
## player always has it; the tests of the steering switch it on for their cars.
@export var steering_assist: bool = false

var wheels: Array[WheelMod] = []
var drive: DriveMod = DriveMod.new()
var drift: DriftMod = DriftMod.new()
var boost: BoostMod = BoostMod.new()
var thruster: ThrusterMod = ThrusterMod.new()
var sky: SkyFlightMod = SkyFlightMod.new()
var power: PowerMod = PowerMod.new()
var impact: ImpactMod = ImpactMod.new()
var dynamics: DynamicsMod = DynamicsMod.new()
## The air part: the thrusters, the landing cushion and the air control.
var air: AirMod = AirMod.new()
var readout: ReadoutMod = ReadoutMod.new()
var api: ApiMod = ApiMod.new()
var rewards: RewardsMod = RewardsMod.new()
## The stunts of the car: the long airtime, the barrel roll and the drift chain.
var stunts: StuntsMod = StuntsMod.new()
var input: PlayerInputMod = PlayerInputMod.new()
## Builds the body, the wheel probes and the module wiring from the spec.
var setup: SetupMod = SetupMod.new()
## Turns the input snapshot into car actions.
var actions: InputMod = InputMod.new()
## The handlers of the core event bus (the charge bay, the race start, the rewards).
var events: EventsMod = EventsMod.new()
## The sky lane flight.
var flight: FlightMod = FlightMod.new()

## The last measured physics cost of this car in microseconds.
var cpu_usec: float = 0.0
## The physics cost of all the cars together since the start (usec): the frame probe reads it (tools/frame_probe.gd).
static var cpu_total_usec: float = 0.0
## The last measured cost of the work of the physics tick outside the force integration (the probes, the input, the modules) in
## microseconds.
var frame_cpu_usec: float = 0.0

var _visual: Node3D = null
var _clock: float = 0.0
var _throttle_pressed_at: float = BodyTuning.TIME_NEVER
var _prev_throttle: bool = false
var _prev_drift_state: StringName = &"grip"
## True while the gamepad stick drives the steering (the keyboard is ramped instead).
var _steer_gamepad: bool = false
var _prev_hovering: bool = false

# --- the input of this tick -----------------------------------------------------------------------
var _in_throttle: float = 0.0
var _in_brake: float = 0.0
var _in_steer: float = 0.0
var _in_drift: bool = false
var _in_flight: bool = false
var _in_reset: bool = false


func _ready() -> void:
	super._ready()
	if spec == null:
		spec = load("res://vehicle/specs/roadster.tres") as CarSpec
	if spec == null:
		push_error("ArcadeCar has no CarSpec")
		return
	add_to_group(&"vehicles")
	if player_controlled:
		add_to_group(&"player")
	_visual = get_node_or_null(^"Visual") as Node3D
	setup.spec = spec
	setup.drive = drive
	setup.drift = drift
	setup.boost = boost
	setup.thruster = thruster
	setup.sky = sky
	setup.power = power
	setup.impact = impact
	setup.dynamics = dynamics
	setup.air = air
	setup.readout = readout
	setup.api = api
	setup.rewards = rewards
	setup.visual = _visual
	actions.boost = boost
	actions.thruster = thruster
	actions.dynamics = dynamics
	actions.api = api
	events.setup(self, boost, power, drift, thruster, dynamics, rewards, api)
	stunts.setup(self, sky, thruster)
	setup.apply_spec(self)
	setup.build_body(self)
	setup.build_wheels(self)
	wheels = setup.wheels
	flight.setup(self, sky, drive, boost, readout, dynamics, api, thruster, wheels)
	setup.wire(self)
	if _visual != null and _visual.has_method("setup"):
		_visual.call("setup", spec, player_controlled)
	if player_controlled and OS.is_debug_build():
		# the last seconds of the car go to the log when it hangs in the air or stays on its side (vehicle/incident_recorder.gd)
		var recorder := IncidentRecorder.new()
		recorder.name = "IncidentRecorder"
		add_child(recorder)


# --- the AI facing API ---------------------------------------------------------------------------

func set_controls(throttle: float, brake: float, steer: float, _handbrake: bool) -> void:
	var new_throttle: float = clampf(throttle, 0.0, 1.0)
	if new_throttle > DriveTuning.THROTTLE_ON and not _prev_throttle:
		_throttle_pressed_at = _clock
		events.throttle_pressed_at = _throttle_pressed_at
	_prev_throttle = new_throttle > DriveTuning.THROTTLE_ON
	_in_throttle = new_throttle
	_in_brake = clampf(brake, 0.0, 1.0)
	_in_steer = clampf(steer, -1.0, 1.0)


func set_drift(on: bool) -> void:
	_in_drift = on


## The nitro: a full slot of N2, 3 s of burn, 300 km/h.
func use_nitro() -> bool:
	return api.use_nitro(self)


## A hop (25 N2) or a Big Hop (50 N2).
func request_hop(big: bool = false) -> bool:
	return api.request_hop(self, big)


## A barrel roll (20 N2), only in the air.
func request_roll(direction: int) -> bool:
	return api.request_roll(self, direction)


## The standing launch (完美起步): the throttle and the nitro together from a standstill.
## It needs a standstill (under 5 km/h), three wheels on the ground, the throttle held and
## half a tank of N2; at speed the request is refused (the nitro key is the nitro).
func request_launch() -> bool:
	return api.request_launch(self)


## An obstacle of a sky lane hit the car (dossier 5.6): 15 HP and 30 % of the speed, never a wreck.
## Only counts while the car flies in a lane, once per second. True when the hit counted.
func flight_hit() -> bool:
	return api.flight_hit(self)


## The N2 left in the tank.
func get_n2() -> float:
	return api.get_n2()


# --- the tick -------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_clock += delta
	events.clock = _clock
	boost.tick(delta)
	# The boost end is emitted here, not in _integrate_forces: during a sky lane flight the
	# integrate step returns early and the event would be held back until the flight ends.
	if boost.ended:
		boost.ended = false
		Events.boost_ended.emit(self)
	# The self-filling compressor: +3 N2 per second while the car is grounded and idle.
	boost.self_refill(delta, dynamics.grounded > 0,
			thruster.hovering or thruster.rolling or boost.kind != &"")
	rewards.tick(delta)
	stunts.tick(delta)
	_update_probes()
	if player_controlled or Game.player == self:
		_sample_input()
	_push_input_to_modules()
	dynamics.tick_effects(delta)
	frame_cpu_usec = Time.get_ticks_usec() - t0


## The visual (the wheels on the suspension, their spin and steer, the wing, the lamps) follows the car once a frame: in the physics
## tick it was set 2-4 times a frame and only the last was ever drawn (17 us a car a tick).
func _process(delta: float) -> void:
	readout.flying = sky.flying
	readout.update_visual(delta, telemetry.speed_kmh, _in_brake > DriveTuning.BRAKE_ON)


## The wheel probes are cast outside the physics step: a shape cast inside _integrate_forces
## re-enters the physics server and the simulation stalls. The probe data is one tick old when
## the forces are applied.
func _update_probes() -> void:
	var up: Vector3 = global_transform.basis.y
	for w in wheels:
		w.update_probe(w.probe.global_position, up)


## Copies the input into the dynamics helper.
func _push_input_to_modules() -> void:
	dynamics.throttle = _in_throttle
	dynamics.brake = _in_brake
	dynamics.steer = _in_steer
	dynamics.drift_held = _in_drift
	dynamics.steer_ramp = not _steer_gamepad


## Reads the InputMap into the input fields.
func _sample_input() -> void:
	var s: PlayerInputMod.Snapshot = input.sample()
	_in_throttle = s.throttle
	_in_brake = s.brake
	_in_steer = s.steer
	_steer_gamepad = s.steer_gamepad
	_in_drift = s.drift_held
	thruster.hop_held = s.hop_held
	thruster.hop_pressed = s.hop_pressed
	thruster.hop_released = s.hop_released
	_in_flight = s.flight_pressed
	_in_reset = s.reset_pressed
	if s.throttle > DriveTuning.THROTTLE_ON and not _prev_throttle:
		_throttle_pressed_at = _clock
		events.throttle_pressed_at = _throttle_pressed_at
	_prev_throttle = s.throttle > DriveTuning.THROTTLE_ON
	actions.handle(self, s)
	# Leaving the sky lane early.
	if _in_flight and sky.flying:
		sky.exit_early()
	# The reset key puts the player back on the road.
	if _in_reset and Game.player == self:
		Game.respawn_player()
	_end_input_edges()


## Clears the one-frame edges.
func _end_input_edges() -> void:
	_in_flight = false
	_in_reset = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var t0: int = Time.get_ticks_usec()
	var dt: float = state.step
	if sky.flying:
		flight.tick(state, dt, _in_steer, _in_throttle, _in_brake)
		# The speed of the lane is not a contact: the impact module starts again when the lane ends.
		impact.reset()
		cpu_usec = Time.get_ticks_usec() - t0
		cpu_total_usec += cpu_usec
		return
	# The height of the ground under the car. The ray has to be cast inside the physics step:
	# Jolt only answers the queries while the space is locked. The landing cushion needs it.
	readout.ground_y = flight.ground_y()
	dynamics.ground_y = readout.ground_y
	dynamics.righting = self_righting or player_controlled or Game.player == self
	# the steering assist is a driver aid of the player (the AI drivers were tuned with the linear fall of the wheel angle)
	drive.assist = steering_assist or player_controlled or Game.player == self
	dynamics.apply(state, dt)
	if dynamics.hopped:
		Events.hop.emit(self, thruster.last_hop)
	if dynamics.landed:
		# A single tick without a wheel is not a landing (dossier 4.8: the airborne rule).
		if dynamics.landing_airtime >= AirTuning.LAND_AIRTIME_MIN:
			events.report_landing(dynamics.landing_airtime, dynamics.landing_impact,
					dynamics.landing_quality)
		events.check_trick()
	if actions.air_mini_impulse > 0.0:
		state.apply_central_impulse(-state.transform.basis.z * spec.mass * actions.air_mini_impulse)
		actions.air_mini_impulse = 0.0
	if drift.state != _prev_drift_state:
		events.on_drift_state_changed()
		_prev_drift_state = drift.state
	if thruster.hovering != _prev_hovering:
		_prev_hovering = thruster.hovering
		Events.hover_changed.emit(self, thruster.hovering)
	impact.tick(dt, self, state, spec.mass, drift, dynamics.ground_normal(), dynamics.own_kick())
	power.tick(dt, _in_throttle)
	# written when it changes: a write is a call into the physics server
	var gravity: float = AirTuning.AIR_GRAVITY_SCALE if dynamics.air_gravity else 1.0
	if gravity_scale != gravity:
		gravity_scale = gravity
	readout.write_telemetry(telemetry, state.transform, state.linear_velocity)
	_check_upside_down(state, dt)
	_check_stuck(state, dt)
	cpu_usec = Time.get_ticks_usec() - t0
	cpu_total_usec += cpu_usec


## The player car that is stuck goes back on the road (BodyTuning.STUCK_*): off its wheels or leaning on a wall, and standing still,
## for 2 s. Only the player: the AI has its own rescue (the rival marshal, the police and the traffic pools).
func _check_stuck(state: PhysicsDirectBodyState3D, dt: float) -> void:
	if Game.player != self or is_wrecked:
		return
	var grounded: int = 0
	for w in wheels:
		if w.contact:
			grounded += 1
	var tilt: float = rad_to_deg(acos(clampf(global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
	var stuck: bool = state.linear_velocity.length() < BodyTuning.STUCK_SPEED \
			and (grounded < 2 or tilt > BodyTuning.STUCK_TILT_DEG) \
			and not thruster.hovering and not thruster.rolling and not sky.flying
	if setup.stuck_time(stuck, dt) < BodyTuning.STUCK_TIME:
		return
	setup.reset_state()
	Game.respawn_player()
	Events.toast.emit("车辆卡住 已复位（随时按 R 复位） STUCK — RESET (R)", &"info")


## The car on its roof for 1.5 s respawns (dossier 4.7). The car lies still and touches
## something, so a car that tumbles in the air does not respawn.
func _check_upside_down(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var up_dot: float = global_transform.basis.y.dot(Vector3.UP)
	var resting: bool = absf(state.linear_velocity.y) < BodyTuning.UPSIDE_DOWN_REST_SPEED \
			and state.get_contact_count() > 0
	if setup.upside_down_time(up_dot, resting, dt) >= BodyTuning.UPSIDE_DOWN_TIME:
		setup.reset_state()
		if Game.player == self:
			Game.respawn_player()
		else:
			reset_to(Transform3D(Basis(), global_position))


## Puts the car back on the road: the flight, the roll, the hover, the drift and the boost timers
## are cleared, so nothing carries over into the new position.
func reset_to(xform: Transform3D) -> void:
	super.reset_to(xform)
	setup.reset_state()
	impact.reset()
	actions.air_mini_impulse = 0.0

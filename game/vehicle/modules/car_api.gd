extends RefCounted
## The AI facing API of a car: the boosts, the thrusters and the sky lane take-off.
## The car (ArcadeCar) exposes thin wrappers around this module, so the rivals, the police and
## the traffic never touch the internals of the car.
##
## Every call that spends N2 raises the matching event on the Events bus, so the FX, the audio
## and the HUD see the same thing the player sees.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")

var boost: BoostMod = null
var thruster: ThrusterMod = null
var sky: SkyFlightMod = null


func setup(boost_module: BoostMod, thruster_module: ThrusterMod, sky_module: SkyFlightMod) -> void:
	boost = boost_module
	thruster = thruster_module
	sky = sky_module


## The N2 left in the tank (0..200).
func get_n2() -> float:
	return boost.n2 if boost != null else 0.0


## The nitro: costs a full slot (100 N2), burns for 3 s and raises the speed cap to 300 km/h.
## Raises Events.boost_started(vehicle, &"nitro"). False when the tank is too empty.
func use_nitro(vehicle: VehicleBase) -> bool:
	if boost == null or not boost.use_nitro():
		return false
	Events.boost_started.emit(vehicle, &"nitro")
	return true


## A hop: 25 N2 (a Big Hop 50 N2). The impulse fires after the spool (0.08 s / 0.15 s) and
## raises Events.hop(vehicle, kind). False when the car cannot hop, the tank is too empty or
## there is a ceiling above the car (dossier 5.3: no hop under a bridge).
func request_hop(vehicle: VehicleBase, big: bool = false) -> bool:
	if thruster == null:
		return false
	if not _clear_above(vehicle):
		return false
	return thruster.begin_spool(big, vehicle.telemetry.grounded_wheels)


## True when there is room above the car for the hop.
func _clear_above(vehicle: VehicleBase) -> bool:
	var space: PhysicsDirectSpaceState3D = vehicle.get_world_3d().direct_space_state
	# The ray starts inside the car (the car itself is excluded) and ends at the hop height.
	var from: Vector3 = vehicle.global_position + Vector3.UP * AirTuning.HOP_CEILING_START
	var to: Vector3 = vehicle.global_position + Vector3.UP * AirTuning.HOP_CEILING_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, VisualTuning.GROUND_RAY_MASK)
	query.exclude = [vehicle.get_rid()]
	return space.intersect_ray(query).is_empty()


## A barrel roll: 20 N2, 0.70 s in the air. Raises Events.barrel_roll(vehicle, direction).
## False when the car is not in the air or the tank is too empty.
func request_roll(vehicle: VehicleBase, direction: int) -> bool:
	if thruster == null or not thruster.request_roll(direction):
		return false
	Events.barrel_roll.emit(vehicle, 1 if direction >= 0 else -1)
	return true


## The standing launch (完美起步): the throttle and the nitro together from a standstill.
## Costs no N2, gives 0.9 s of +20 m/s^2. Raises Events.boost_started(vehicle, &"launch").
##
## It is a standing start, not a free boost: it needs a standstill (under LAUNCH_MAX_KMH), at
## least LAUNCH_MIN_WHEELS wheels on the ground, the throttle held and half a tank of N2. At
## speed the request is refused, so the nitro key stays the nitro.
## throttle_held: the throttle level of the caller; -1 asks the telemetry (the AI path).
func request_launch(vehicle: VehicleBase, throttle_held: float = -1.0) -> bool:
	if boost == null:
		return false
	var throttle: float = throttle_held
	if throttle <= BoostTuning.THROTTLE_FROM_TELEMETRY:
		throttle = vehicle.telemetry.throttle
	if throttle <= DriveTuning.THROTTLE_ON:
		return false
	if absf(vehicle.telemetry.forward_speed_kmh) > BoostTuning.LAUNCH_MAX_KMH:
		return false
	if vehicle.telemetry.grounded_wheels < BoostTuning.LAUNCH_MIN_WHEELS:
		return false
	if get_n2() < BoostTuning.LAUNCH_N2_MIN:
		return false
	boost.start_launch()
	Events.boost_started.emit(vehicle, &"launch")
	return true


## Takes off into a sky lane. False when the car is too slow or the tank is too empty.
## Raises Events.flight_changed(vehicle, true, lane).
func try_flight(vehicle: VehicleBase, lane: SkyLane) -> bool:
	if sky == null or lane == null:
		return false
	var speed_kmh: float = vehicle.get_speed_kmh()
	if not sky.can_enter(lane, speed_kmh, boost.n2):
		return false
	sky.enter(lane, speed_kmh / DriveTuning.KMH, boost.speed_cap, vehicle.global_transform)
	Events.flight_changed.emit(vehicle, true, lane)
	return true


## Leaves the sky lane. Raises Events.flight_changed(vehicle, false, lane).
func end_flight(vehicle: VehicleBase) -> void:
	if sky == null or not sky.flying:
		return
	var lane: SkyLane = sky.lane
	sky.flying = false
	Events.flight_changed.emit(vehicle, false, lane)

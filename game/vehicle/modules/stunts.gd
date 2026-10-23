extends RefCounted
## The stunts of the player (SPEC section 3): the long airtime (滞空), the barrel roll (桶滚)
## and the drift chain (连续漂移). The module watches the event bus and raises Events.stunt;
## the N2 of the stunts is paid by the rewards module.
##
## Only the player's car stunts: the AI cars have no tank to fill and no score to add.

const RewardTuning := preload("res://vehicle/tuning/reward_tuning.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")

var car: VehicleBase = null
var sky: SkyFlightMod = null
var thruster: ThrusterMod = null
## The clock of the module (seconds).
var clock: float = 0.0
## The number of the long drifts of the chain so far.
var _chain: int = 0
## The moment the last drift of the chain ended.
var _chain_last: float = -1.0
## The number of the rolls the thruster has finished.
var _rolls_seen: int = 0


## Wires the module to the car and to the event bus.
func setup(vehicle: VehicleBase, sky_module: SkyFlightMod, thruster_module: ThrusterMod) -> void:
	car = vehicle
	sky = sky_module
	thruster = thruster_module
	if not Events.landed.is_connected(on_landed):
		Events.landed.connect(on_landed)
	if not Events.drift_ended.is_connected(on_drift_ended):
		Events.drift_ended.connect(on_drift_ended)


## Advances the clock and pays the barrel rolls that ended.
func tick(dt: float) -> void:
	clock += dt
	if thruster.rolls_done == _rolls_seen:
		return
	_rolls_seen = thruster.rolls_done
	if not _is_player():
		return
	Events.stunt.emit(&"barrel_roll", RewardTuning.BARREL_ROLL_POINTS, "桶滚 BARREL ROLL")


## The landing of the car: a long flight is the long airtime stunt.
func on_landed(vehicle: VehicleBase, airtime: float, _impact: float, _quality: StringName) -> void:
	if vehicle != car or not _is_player():
		return
	# The sky lane has its own rules: the flight in the tube is not a jump.
	if sky.flying or sky.transitioning:
		return
	if airtime < RewardTuning.AIRTIME_MIN:
		return
	Events.stunt.emit(&"airtime", int(airtime * 100.0), "滞空 AIRTIME %.1f s" % airtime)


## The end of a drift: three long drifts in a row are a chain.
func on_drift_ended(vehicle: VehicleBase, duration: float, _clean: bool, _gained: float) -> void:
	if vehicle != car or not _is_player():
		return
	if duration < RewardTuning.DRIFT_CHAIN_MIN_DURATION:
		return
	# The chain window ran out: the count starts again.
	if _chain > 0 and clock - _chain_last > RewardTuning.DRIFT_CHAIN_WINDOW:
		_chain = 0
	_chain += 1
	_chain_last = clock
	if _chain < RewardTuning.DRIFT_CHAIN_COUNT:
		return
	_chain = 0
	Events.stunt.emit(&"drift_chain", RewardTuning.DRIFT_CHAIN_POINTS, "连续漂移 DRIFT CHAIN")


## True when this car is the player's car.
func _is_player() -> bool:
	return car != null and Game.player == car

extends RefCounted
## Turns the input snapshot of one tick into car actions: the nitro, the mini boosts (小喷, 空喷,
## 落地喷), the barrel roll, the sky lane exit and the reset. The car body owns one of these and
## hands it the modules, so the car body stays small.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")
const ApiMod := preload("res://vehicle/modules/car_api.gd")
const PlayerInputMod := preload("res://vehicle/player_input.gd")

var boost: BoostMod = null
var thruster: ThrusterMod = null
var dynamics: DynamicsMod = null
var api: ApiMod = null
## The forward impulse of an air mini boost (空喷), applied by the car body.
var air_mini_impulse: float = 0.0


## The nitro, the mini boosts, the roll, the flight exit and the reset.
func handle(vehicle: VehicleBase, s: PlayerInputMod.Snapshot) -> void:
	# The nitro: from a standstill the throttle and the nitro together buy a thruster launch.
	# At speed the key is the nitro (the launch is a standing start, not a free boost).
	if s.nitro_pressed:
		if not api.request_launch(vehicle, s.throttle):
			api.use_nitro(vehicle)
	# The mini boost: the key, the QQ style re-press of the throttle, or the air and landing
	# windows (空喷 and 落地喷).
	if s.mini_pressed or s.throttle_repressed:
		_fire_mini(vehicle)
	# The barrel roll.
	if s.roll_left:
		api.request_roll(vehicle, -1)
	elif s.roll_right:
		api.request_roll(vehicle, 1)


## The 小喷: the drift window, the air boost (空喷) or the landing boost (落地喷).
func _fire_mini(vehicle: VehicleBase) -> void:
	if thruster.airborne and thruster.air_mini_available():
		if boost.use_air_mini():
			thruster.mark_air_mini_used()
			air_mini_impulse = AirTuning.AIR_MINI_IMPULSE
			Events.boost_started.emit(vehicle, &"air_mini")
		return
	if thruster.landing_window_open():
		if boost.use_landing_mini():
			Events.boost_started.emit(vehicle, &"landing")
		return
	if boost.mini_window > 0.0:
		var perfect: bool = boost.mini_is_perfect()
		if boost.use_mini():
			Events.boost_started.emit(vehicle, &"mini")
			if perfect:
				dynamics.perfect_kick = BoostTuning.MINI_PERFECT_KICK

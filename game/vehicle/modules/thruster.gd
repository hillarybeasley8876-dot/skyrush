extends RefCounted
## Thruster moves: hop, Big Hop, hover, barrel roll and the landing window (dossier 5.3, 5.4).
## Pure logic: it decides *when* a move fires and how strong it is; the car body applies the
## impulses and the forces.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")

## 0..1 charge of the hop key (the Big Hop ring on the HUD).
var hop_charge: float = 0.0
## True while the car is off the ground.
var airborne: bool = false
## Seconds since the car left the ground.
var airtime: float = 0.0
## True while the hover thrusters are running.
var hovering: bool = false
## True during a barrel roll.
var rolling: bool = false
## -1 = left, +1 = right.
var roll_dir: int = 1
## Seconds the roll has been running.
var roll_time: float = 0.0
## Accumulated roll angle in radians (the roll is a full 2*PI).
var roll_angle: float = 0.0
## Seconds left of the landing mini-boost window (落地喷).
var landing_window: float = 0.0
## Pending hop impulse in m/s (consumed by the car body).
var pending_impulse_vy: float = 0.0
## The kind of hop that fired: &"hop" or &"big_hop".
var last_hop: StringName = &""
## The clock of the thruster (seconds).
var clock: float = 0.0
## The moment the last barrel roll ended (-1 when there was none).
var roll_end_time: float = -1.0
## The number of the barrel rolls that finished. It is a lifetime counter: a respawn does not
## reset it, so the stunts module sees every roll of the car.
var rolls_done: int = 0
## The hop key edges of this tick, written by the car body.
var hop_held: bool = false
var hop_pressed: bool = false
var hop_released: bool = false

var _hold_time: float = 0.0
var _spool: float = 0.0
var _spool_vy: float = 0.0
var _cooldown: float = 0.0
var _hover_time: float = 0.0
var _rolls_this_air: int = 0
var _air_mini_used: bool = false
## The N2 tank the thrusters spend from.
var boost: BoostMod = null


## Advances the thruster state.
## hop_held: the hop key is down. hop_pressed / hop_released: edges of that key.
## grounded: number of wheels on the ground. v_y: vertical speed (m/s).
## touching: the body touches something (a car on its roof is not flying).
func tick(dt: float, grounded: int, v_y: float, touching: bool) -> void:
	clock += dt
	_cooldown = maxf(_cooldown - dt, 0.0)
	var held: float = _hold_time
	if hop_held:
		_hold_time += dt
		hop_charge = clampf(_hold_time / AirTuning.HOP_CHARGE_TIME, 0.0, 1.0)
	else:
		_hold_time = 0.0
		hop_charge = 0.0
	if hop_pressed:
		_hold_time = 0.0
	# The ground state.
	var was_airborne: bool = airborne
	airborne = grounded == 0 and not touching
	if not airborne:
		if was_airborne:
			# Touchdown: the airtime is still valid here, it is reset below.
			_land(airtime)
		airtime = 0.0
		_rolls_this_air = 0
		_air_mini_used = false
		_hover_time = 0.0
	else:
		if not was_airborne:
			airtime = 0.0
		airtime += dt
	# The hop fires on release: a tap is a hop, a hold of 0.25 s or more is a Big Hop.
	if hop_released and _spool <= 0.0:
		begin_spool(held >= AirTuning.HOP_CHARGE_TIME, grounded)
		_hold_time = 0.0
	if _spool > 0.0:
		_spool = maxf(_spool - dt, 0.0)
		if _spool == 0.0:
			pending_impulse_vy = _spool_vy
	# Hover: hold the hop key in the air after the apex.
	var want_hover: bool = airborne and hop_held and v_y <= AirTuning.HOVER_MAX_VY \
			and _hover_time < AirTuning.HOVER_MAX_TIME
	hovering = want_hover
	if want_hover:
		_hover_time += dt
	# The barrel roll.
	if rolling:
		roll_time += dt
		roll_angle += roll_rate() * dt
		if roll_time >= AirTuning.ROLL_TIME:
			rolling = false
			roll_time = 0.0
			roll_end_time = clock
			rolls_done += 1
	if landing_window > 0.0:
		landing_window = maxf(landing_window - dt, 0.0)


## Starts the hop spool and charges the N2 (25, or 50 for a Big Hop). Returns false when the
## hop is not allowed: the car is airborne, on cooldown or the tank is too empty.
func begin_spool(big: bool, grounded: int) -> bool:
	if _cooldown > 0.0 or grounded < 2:
		return false
	var cost: float = AirTuning.BIG_HOP_COST if big else AirTuning.HOP_COST
	if boost == null or not boost.spend_n2(cost):
		return false
	_spool = AirTuning.BIG_HOP_SPOOL if big else AirTuning.HOP_SPOOL
	_spool_vy = AirTuning.BIG_HOP_VY if big else AirTuning.HOP_VY
	_cooldown = AirTuning.HOP_COOLDOWN
	last_hop = &"big_hop" if big else &"hop"
	return true


## Clears the thruster state (a respawn).
func reset() -> void:
	airborne = false
	airtime = 0.0
	hovering = false
	rolling = false
	roll_time = 0.0
	roll_angle = 0.0
	landing_window = 0.0
	pending_impulse_vy = 0.0
	hop_charge = 0.0
	last_hop = &""
	roll_end_time = -1.0
	_hold_time = 0.0
	_spool = 0.0
	_cooldown = 0.0
	_hover_time = 0.0
	_rolls_this_air = 0
	_air_mini_used = false


## Tries to start a barrel roll in the given direction (-1 left, +1 right).
func request_roll(dir: int) -> bool:
	if not airborne or rolling or _rolls_this_air >= AirTuning.ROLL_MAX_PER_AIR:
		return false
	if boost == null or not boost.spend_n2(AirTuning.ROLL_COST):
		return false
	rolling = true
	roll_dir = 1 if dir >= 0 else -1
	roll_time = 0.0
	roll_angle = 0.0
	_rolls_this_air += 1
	return true


## Angular velocity about the car's forward axis during a roll (rad/s).
func roll_rate() -> float:
	var t: float = clampf(roll_time, 0.0, AirTuning.ROLL_TIME)
	if t < AirTuning.ROLL_RAMP:
		return AirTuning.ROLL_PEAK * t / AirTuning.ROLL_RAMP
	if t < AirTuning.ROLL_TIME - AirTuning.ROLL_RAMP:
		return AirTuning.ROLL_PEAK
	var d: float = (AirTuning.ROLL_TIME - t) / AirTuning.ROLL_RAMP
	return AirTuning.ROLL_PEAK * maxf(d, 0.0)


## Called on touchdown. Returns the landing quality: &"clean", &"wobble" or &"crash".
func _land(air: float) -> StringName:
	hovering = false
	if air < AirTuning.LAND_MIN_AIRTIME:
		return &"clean"
	landing_window = AirTuning.LAND_WINDOW
	return &"clean"


## The car body reports the alignment quality after a touchdown (&"clean", &"wobble", &"crash").
func report_landing(quality: StringName) -> void:
	if quality != &"clean":
		landing_window = 0.0


## True when the air mini boost (空喷) may still be used in this jump.
func air_mini_available() -> bool:
	return airborne and not _air_mini_used


func mark_air_mini_used() -> void:
	_air_mini_used = true


## True while the landing mini-boost window is open.
func landing_window_open() -> bool:
	return landing_window > 0.0

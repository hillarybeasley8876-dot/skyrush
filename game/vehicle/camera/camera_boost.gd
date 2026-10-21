extends RefCounted
## The camera's boost state: the N2 and 小喷 flags and the N2 punch.
##
## The state comes from the car's telemetry every tick, because nothing emits
## `Events.boost_ended`: a latched N2 would keep the +8 deg FOV and the N2 blur forever.
## The vehicle reports `&"launch"` (完美起步) and `&"charge"` (闪充) while they run, so both
## are mapped: a launch counts as N2, a charge bay counts as 小喷 (but it does not cancel an
## N2 that was already running).

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

## The punch: a 0.4 s kick on the ignition, then it eases back to neutral over 1.0 s once
## the N2 is over (dossier, speed-feel table).
enum Punch { IDLE, KICK, HOLD, RELEASE }

## True while the N2 (or the thruster launch) is running.
var nitro: bool = false
## True while a 小喷 (mini, air or landing boost) or a charge boost is running.
var mini: bool = false
## The N2 punch offset in metres (negative: the camera punches towards the car).
var punch: float

var _state: Punch = Punch.IDLE
var _timer: float
var _release_from: float


## Reads the car's telemetry. `dt` is real seconds: the punch is a cinematic beat and must
## not stretch when the game is in slow motion.
func update(telemetry: CarTelemetry, dt: float) -> void:
	var kind := telemetry.boost_kind
	var was_nitro := nitro
	nitro = kind == &"nitro" or kind == &"launch"
	if kind == &"charge" and was_nitro:
		nitro = true
	mini = kind == &"mini" or kind == &"air_mini" or kind == &"landing" or kind == &"charge"
	match _state:
		Punch.KICK:
			_timer += dt
			punch = CameraMath.punch_offset(_timer)
			if _timer >= CameraMath.PUNCH_TIME:
				_state = Punch.HOLD
				_timer = 0
			if not nitro:
				# The N2 ended during the kick: release from where we are.
				_release_from = punch
				_state = Punch.RELEASE
				_timer = 0
		Punch.HOLD:
			if not nitro:
				_release_from = punch
				_state = Punch.RELEASE
				_timer = 0
		Punch.RELEASE:
			_timer += dt
			punch = CameraMath.punch_release_from(_release_from, _timer)
			if _timer >= CameraMath.PUNCH_RELEASE_TIME:
				_state = Punch.IDLE
				punch = 0
				_timer = 0
		_:
			pass


## The N2 (or the thruster launch) just started: punch the camera. Returns true when the
## caller should also shake (the 0.04 m ignition shake).
func on_boost_started(kind: StringName) -> bool:
	if kind != &"nitro" and kind != &"launch":
		return false
	punch = 0.0            # the kick is smoothed, it never pops
	_timer = 0
	_state = Punch.KICK
	return true


## Forgets the boost state (a new car or a respawn).
func reset() -> void:
	_state = Punch.IDLE
	_timer = 0
	_release_from = 0
	punch = 0
	nitro = false
	mini = false

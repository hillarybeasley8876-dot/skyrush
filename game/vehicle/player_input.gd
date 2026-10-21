extends RefCounted
## Reads the InputMap actions into a snapshot for one physics tick (dossier 4.5, 8.2).
## The car body owns one of these; AI cars write the same values directly.
##
## Keyboard steering is a digital axis: it is ramped by the drive module. Gamepad sticks use
## the squared response curve with a 0.12 dead zone.
##
## While the game is in the menu (or paused) the snapshot is zeroed, so the menu can use the
## same keys for its navigation without driving the car under the title screen.

const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")

## One tick of player input.
class Snapshot extends RefCounted:
	var throttle: float = 0.0
	var brake: float = 0.0
	## Raw steering target in [-1, 1] (+1 = right).
	var steer: float = 0.0
	var drift_held: bool = false
	var drift_pressed: bool = false
	var nitro_pressed: bool = false
	var mini_pressed: bool = false
	## True when the throttle was released and pressed again (the QQ 小喷 re-press).
	var throttle_repressed: bool = false
	var hop_held: bool = false
	var hop_pressed: bool = false
	var hop_released: bool = false
	var roll_left: bool = false
	var roll_right: bool = false
	var flight_pressed: bool = false
	var look_back: bool = false
	var reset_pressed: bool = false
	var horn_pressed: bool = false
	var camera_pressed: bool = false
	## True when the steering comes from the gamepad stick (the keyboard is ramped instead).
	var steer_gamepad: bool = false
	## True when the input was ignored (the game is in the menu).
	var locked: bool = false


## The snapshot of the last tick.
var snapshot: Snapshot = Snapshot.new()

var _prev_accelerate: bool = false
var _prev_hop: bool = false
var _prev_drift: bool = false
## True while the gamepad stick (not the keyboard) drives the steering.
var _steer_gamepad: bool = false


## Samples the InputMap. Call once per physics tick.
func sample() -> Snapshot:
	var s: Snapshot = snapshot
	if _locked():
		_clear(s)
		return s
	s.locked = false
	s.throttle = Input.get_action_strength(&"accelerate")
	s.brake = Input.get_action_strength(&"brake")
	s.steer = _read_steer()
	s.steer_gamepad = _steer_gamepad
	var accelerate_down: bool = Input.is_action_pressed(&"accelerate")
	s.throttle_repressed = accelerate_down and not _prev_accelerate
	_prev_accelerate = accelerate_down
	s.drift_held = Input.is_action_pressed(&"drift")
	s.drift_pressed = s.drift_held and not _prev_drift
	_prev_drift = s.drift_held
	s.nitro_pressed = Input.is_action_just_pressed(&"nitro")
	s.mini_pressed = Input.is_action_just_pressed(&"mini_boost")
	var hop_down: bool = Input.is_action_pressed(&"hop")
	s.hop_held = hop_down
	s.hop_pressed = hop_down and not _prev_hop
	s.hop_released = not hop_down and _prev_hop
	_prev_hop = hop_down
	# The roll keys are edges: holding Q must not start a second roll.
	s.roll_left = Input.is_action_just_pressed(&"roll_left")
	s.roll_right = Input.is_action_just_pressed(&"roll_right")
	s.flight_pressed = Input.is_action_just_pressed(&"flight")
	s.look_back = Input.is_action_pressed(&"look_back")
	s.reset_pressed = Input.is_action_just_pressed(&"reset_car")
	s.horn_pressed = Input.is_action_just_pressed(&"horn")
	s.camera_pressed = Input.is_action_just_pressed(&"camera_toggle")
	return s


## True while the menu owns the input.
func _locked() -> bool:
	if Game.mode == &"menu":
		return true
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree != null and tree.paused


## Zeroes the snapshot and forgets the edges, so no phantom press fires when the game starts.
func _clear(s: Snapshot) -> void:
	s.locked = true
	s.throttle = 0.0
	s.brake = 0.0
	s.steer = 0.0
	s.steer_gamepad = false
	s.drift_held = false
	s.drift_pressed = false
	s.nitro_pressed = false
	s.mini_pressed = false
	s.throttle_repressed = false
	s.hop_held = false
	s.hop_pressed = false
	s.hop_released = false
	s.roll_left = false
	s.roll_right = false
	s.flight_pressed = false
	s.reset_pressed = false
	s.horn_pressed = false
	s.camera_pressed = false
	_prev_accelerate = false
	_prev_hop = false
	_prev_drift = false


## Steering: the gamepad stick uses s*|s| with a dead zone, the keyboard is digital.
## The two are told apart by the joypad axis (not by the magnitude): a key gives the axis 1.0,
## so a magnitude test would send the keyboard down the stick branch.
func _read_steer() -> float:
	var axis: float = Input.get_axis(&"steer_left", &"steer_right")
	var joy: float = _joy_steer()
	if absf(joy) > DriveTuning.GAMEPAD_DEADZONE:
		var magnitude: float = (absf(joy) - DriveTuning.GAMEPAD_DEADZONE) \
				/ (1.0 - DriveTuning.GAMEPAD_DEADZONE)
		_steer_gamepad = true
		return signf(joy) * magnitude * magnitude
	_steer_gamepad = false
	# Keyboard: the drive module ramps this towards +/-1.
	return signf(axis)


## The raw left stick of the connected gamepads (-1..1).
func _joy_steer() -> float:
	for device: int in Input.get_connected_joypads():
		var value: float = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(value) > 0.0:
			return value
	return 0.0

extends RefCounted
## Registers every input action at startup (keyboard + gamepad) so units never edit project.godot.
## Action names are a core contract (see CONTRACTS.md §Input).

const KEYS: Dictionary = {
	&"accelerate": [KEY_W, KEY_UP],
	&"brake": [KEY_S, KEY_DOWN],
	&"steer_left": [KEY_A, KEY_LEFT],
	&"steer_right": [KEY_D, KEY_RIGHT],
	&"drift": [KEY_SHIFT],
	&"nitro": [KEY_CTRL, KEY_J],
	&"mini_boost": [KEY_K],
	&"hop": [KEY_SPACE],
	&"flight": [KEY_F],
	&"roll_left": [KEY_Q],
	&"roll_right": [KEY_E],
	&"look_back": [KEY_C],
	&"camera_toggle": [KEY_V],
	&"horn": [KEY_H],
	&"reset_car": [KEY_R],
	&"pause": [KEY_ESCAPE, KEY_P],
}
const BUTTONS: Dictionary = {
	&"drift": [JOY_BUTTON_RIGHT_SHOULDER],
	&"nitro": [JOY_BUTTON_A],
	&"mini_boost": [JOY_BUTTON_B],
	&"hop": [JOY_BUTTON_X],
	&"camera_toggle": [JOY_BUTTON_Y],
	&"look_back": [JOY_BUTTON_LEFT_SHOULDER],
	&"roll_left": [JOY_BUTTON_DPAD_LEFT],
	&"roll_right": [JOY_BUTTON_DPAD_RIGHT],
	&"flight": [JOY_BUTTON_LEFT_STICK],
	&"horn": [JOY_BUTTON_RIGHT_STICK],
	&"reset_car": [JOY_BUTTON_BACK],
	&"pause": [JOY_BUTTON_START],
}
## action: [axis, direction]
const AXES: Dictionary = {
	&"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	&"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	&"steer_left": [JOY_AXIS_LEFT_X, -1.0],
	&"steer_right": [JOY_AXIS_LEFT_X, 1.0],
}


## Idempotent: actions that already exist (e.g. registered by a tool script first) are left alone.
static func register_actions() -> void:
	if InputMap.has_action(&"accelerate"):
		return
	for action: StringName in KEYS:
		_ensure(action)
		for key: int in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
	for action: StringName in BUTTONS:
		_ensure(action)
		for button: int in BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button as JoyButton
			InputMap.action_add_event(action, ev)
	for action: StringName in AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = AXES[action][0] as JoyAxis
		ev.axis_value = AXES[action][1]
		InputMap.action_add_event(action, ev)


static func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

extends RefCounted
## The menu's navigation actions and the input state machine behind them.
##
## Core owns the driving actions; the front end needs its own because Godot's built-in `ui_*`
## actions are not gamepad-complete: `ui_accept` has Enter/Space only (no JOY_BUTTON_A) and
## `ui_cancel` has Escape only (no JOY_BUTTON_B). Gamepad-only navigation is an acceptance item.
##
## The direction actions are polled by *strength* (the stick axis, the d-pad and the arrow keys
## all feed the action strength), so a stick that is pushed once produces exactly one move:
##   press  — the strength crosses 0.5
##   release — the strength falls below 0.3
##   repeat — after 0.40 s, every 0.12 s while it is held
##
## `pause` (core: Esc / P / JOY_BUTTON_START) is NOT redefined here: the menu root handles it as
## "back / pause", so Esc and Start always mean the same thing.

const KEYS: Dictionary = {
	&"menu_up": [KEY_UP, KEY_W],
	&"menu_down": [KEY_DOWN, KEY_S],
	&"menu_left": [KEY_LEFT, KEY_A],
	&"menu_right": [KEY_RIGHT, KEY_D],
	&"menu_accept": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
	&"menu_cancel": [KEY_BACKSPACE],
}

const BUTTONS: Dictionary = {
	&"menu_up": [JOY_BUTTON_DPAD_UP],
	&"menu_down": [JOY_BUTTON_DPAD_DOWN],
	&"menu_left": [JOY_BUTTON_DPAD_LEFT],
	&"menu_right": [JOY_BUTTON_DPAD_RIGHT],
	&"menu_accept": [JOY_BUTTON_A],
	&"menu_cancel": [JOY_BUTTON_B],
}

## action: [axis, direction]
const AXES: Dictionary = {
	&"menu_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"menu_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"menu_left": [JOY_AXIS_LEFT_X, -1.0],
	&"menu_right": [JOY_AXIS_LEFT_X, 1.0],
}

const ACTIONS: Array[StringName] = [&"menu_up", &"menu_down", &"menu_left", &"menu_right",
	&"menu_accept", &"menu_cancel"]

## The directions are the actions that repeat; accept and cancel are single shots.
const DIRECTIONS: Array[StringName] = [&"menu_up", &"menu_down", &"menu_left", &"menu_right"]

## The strength at which a direction counts as pressed / released.
const PRESS_THRESHOLD := 0.5
const RELEASE_THRESHOLD := 0.3
## The delay before a held direction repeats, and the repeat interval.
const REPEAT_DELAY := 0.40
const REPEAT_INTERVAL := 0.12

## The device the player is using (the hints follow it).
static var last_device: StringName = &"keyboard"

var _held: Dictionary = {}
var _repeat_left: Dictionary = {}


## Registers the actions (idempotent).
static func register() -> void:
	for action: StringName in ACTIONS:
		_ensure(action)
		for key: int in KEYS[action]:
			var ev := InputEventKey.new()
			ev.keycode = key as Key
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
		for button: int in BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button as JoyButton
			InputMap.action_add_event(action, ev)
		if AXES.has(action):
			var spec: Array = AXES[action]
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(spec[0]) as JoyAxis
			motion.axis_value = float(spec[1])
			InputMap.action_add_event(action, motion)


static func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


## A digital press (a key or a d-pad button) was seen: the direction is held from now on.
func note_press(action: StringName) -> void:
	if not DIRECTIONS.has(action):
		return
	_held[action] = true
	_repeat_left[action] = REPEAT_DELAY


## A digital release was seen.
func note_release(action: StringName) -> void:
	if not DIRECTIONS.has(action):
		return
	_held[action] = false


## Remembers the device of an event (the hint bars follow it).
static func note_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		last_device = &"gamepad"
	elif event is InputEventKey:
		last_device = &"keyboard"


## The menu action of an event ("" when the event is not one of them).
static func action_of(event: InputEvent) -> StringName:
	for action: StringName in ACTIONS:
		if event.is_action_pressed(action) or event.is_action_released(action):
			return action
	return &""


## The actions that fired this frame: the new presses and the repeats of the held directions.
func poll(delta: float) -> Array[StringName]:
	var fired: Array[StringName] = []
	for action: StringName in DIRECTIONS:
		var strength := Input.get_action_strength(action)
		var held := bool(_held.get(action, false))
		if strength >= PRESS_THRESHOLD and not held:
			# The stick crossed the threshold: one press, not one per motion event.
			_held[action] = true
			_repeat_left[action] = REPEAT_DELAY
			fired.append(action)
		elif strength < RELEASE_THRESHOLD and held:
			_held[action] = false
			continue
		if not bool(_held.get(action, false)):
			continue
		var left := float(_repeat_left.get(action, REPEAT_DELAY)) - delta
		if left <= 0.0:
			left = REPEAT_INTERVAL
			fired.append(action)
		_repeat_left[action] = left
	return fired


## True while the action is held (the hint bar shows the device that is in use).
func is_held(action: StringName) -> bool:
	return bool(_held.get(action, false))

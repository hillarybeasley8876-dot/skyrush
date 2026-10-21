extends Node
## The shared helpers of the menu tests: the scripted input, the menu factory and the
## expectations.
##
## The test scripts extend this file (they must `extends Node`).

## The preferences file of the tests (the player's own file is never touched).
const TEST_PREFS := "user://test_skyrush_menu.cfg"

## Counts the engine errors of a stretch of the run (a screen that connects a signal twice
## raises one).
class ErrorCounter extends Logger:
	var errors: int = 0
	var first: PackedStringArray = []

	func _log_error(_function: String, file: String, line: int, code: String, _rationale: String,
			_editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		errors += 1
		if first.size() < 5:
			first.append("%s:%d %s" % [file, line, code])

var _fails: int = 0
## The menu under test.
var _menu: Node = null


## A menu instance with the given screen open.
func _make_menu(screen: StringName) -> Node:
	var packed := load("res://ui/menu/menu.tscn") as PackedScene
	var menu := packed.instantiate()
	menu.set("demo_screen", screen)
	menu.set("prefs_path", TEST_PREFS)
	get_tree().root.add_child(menu)
	return menu


## What is on the stacks of a menu.
func _state_of(menu: Node) -> Dictionary:
	return menu.call("debug_state")


## The screens of the front stack of the menu under test.
func _front() -> Array:
	return _state_of(_menu)["front"] as Array


## The screens of the overlay stack of the menu under test.
func _overlay() -> Array:
	return _state_of(_menu)["overlay"] as Array


## The index of the highlighted row.
func _selection() -> int:
	return int(_state_of(_menu)["selection"])


## Presses and releases a key, then lets one frame pass (the response must be in that frame).
func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## Presses and releases a gamepad button.
func _button(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## One motion event of a stick axis (the value is the strength of the axis).
func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await get_tree().process_frame


## The number of frames to wait.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## The number of hint bars that are visible (one per visible screen).
func _visible_hint_bars(layer: Node) -> int:
	var count := 0
	if layer == null:
		return count
	for node in _all_children(layer):
		if node is Control and node.get_script() != null:
			var script := node.get_script() as Script
			if script != null and String(script.resource_path).ends_with("hint_bar.gd"):
				if (node as Control).is_visible_in_tree():
					count += 1
	return count


## Every child of a node, depth first.
func _all_children(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_children(child))
	return out


## An expectation of the test.
func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_fails += 1
		print("FAIL ", label)


## The number of failures so far.
func _failure_count() -> int:
	return _fails

extends RefCounted
## Bridges from the menu to the other units, without editing their files.
##
## The units are found by their group (`audio`, `weather`, `environment`) or by a duck-typed
## method (the camera's public `set_motion_blur`). Every bridge is optional: when a unit is
## missing or still a stub the menu degrades quietly instead of breaking.

const AUDIO_GROUP := &"audio"
const WEATHER_GROUP := &"weather"

## The camera node that owns the motion-blur toggle (cached).
static var _camera_effects: Node = null


## The first node under `root` that has the method (the duck-typed unit lookup).
static func find_by_method(root: Node, method: StringName) -> Node:
	if root == null:
		return null
	if root.has_method(method):
		return root
	for child in root.get_children():
		var found := find_by_method(child, method)
		if found != null:
			return found
	return null


## The first node under `root` that uses the given script.
static func find_by_script(root: Node, script_path: String) -> Node:
	if root == null:
		return null
	var script := root.get_script() as Script
	if script != null and String(script.resource_path) == script_path:
		return root
	for child in root.get_children():
		var found := find_by_script(child, script_path)
		if found != null:
			return found
	return null


## The first node of a group (null when the unit is not loaded).
static func group_node(group: StringName) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(group)


## Plays a UI sound through the audio unit (`ui_hover`, `ui_click`, `ui_confirm`, `ui_back`,
## `ui_whoosh`).
static func ui_sound(id: StringName) -> bool:
	var audio := group_node(AUDIO_GROUP)
	if audio == null or not audio.has_method("play_sfx"):
		return false
	audio.call("play_sfx", id)
	return true


## The sound of a menu action (the hover, the click, the confirm).
static func ui_sound_for(action: StringName) -> void:
	match action:
		&"menu_up", &"menu_down":
			ui_sound(&"ui_hover")
		&"menu_left", &"menu_right":
			ui_sound(&"ui_click")
		&"menu_accept":
			ui_sound(&"ui_confirm")


## Switches the music bed ("menu", "cruise", "race", "pursuit").
static func set_music(state: StringName) -> bool:
	var audio := group_node(AUDIO_GROUP)
	if audio == null or not audio.has_method("set_music_state"):
		return false
	audio.call("set_music_state", state)
	return true


## Rain on/off through the environment unit's weather controller.
static func set_rain(active: bool) -> bool:
	var weather := group_node(WEATHER_GROUP)
	if weather == null or not weather.has_method("set_rain"):
		return false
	weather.call("set_rain", active)
	return true


## True when it is raining right now.
static func is_raining() -> bool:
	var weather := group_node(WEATHER_GROUP)
	if weather == null or not weather.has_method("is_raining"):
		return false
	return bool(weather.call("is_raining"))


## Motion blur through the camera unit's public toggle.
static func set_motion_blur(enabled: bool) -> bool:
	var node := _camera_node()
	if node == null:
		return false
	node.call("set_motion_blur", enabled)
	return true


## The state of the motion-blur toggle.
static func motion_blur_enabled() -> bool:
	var node := _camera_node()
	if node == null or not node.has_method("motion_blur_enabled"):
		return true
	return bool(node.call("motion_blur_enabled"))


## The camera node with the public `set_motion_blur` (the camera unit's effect stack).
static func _camera_node() -> Node:
	if _camera_effects != null and is_instance_valid(_camera_effects):
		return _camera_effects
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_camera_effects = find_by_method(tree.root, &"set_motion_blur")
	return _camera_effects

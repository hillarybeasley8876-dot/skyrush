class_name PoliceLink
extends RefCounted
## The link to the police unit.
##
## The police unit is optional: a game without it still runs the modes. The director is found
## through the group `police_director`; until the police unit ships that group, the fallback
## looks for the node that has both `force_heat` and `remove_all_units` (the audio director has
## a `set_heat` of its own, so a single method name is not enough).

const GROUP := &"police_director"
const HEAT_METHOD := &"force_heat"
const UNITS_METHOD := &"remove_all_units"
const SPAWN_FLAG := &"spawn_enabled"


## The police director of the game (null when the police unit is not loaded).
static func director(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	var grouped := tree.get_first_node_in_group(GROUP)
	if grouped != null:
		return grouped
	return _search(tree.root)


## The depth-first search for the node that has both methods.
static func _search(node: Node) -> Node:
	if node.has_method(HEAT_METHOD) and node.has_method(UNITS_METHOD):
		return node
	for child in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


## Starts a pursuit at a given heat (the police unit has `start_at` for the modes unit).
static func start_pursuit(police: Node, heat: int) -> bool:
	if police == null:
		return false
	var pursuit: Object = police.get("pursuit")
	if pursuit == null:
		return false
	if not pursuit.has_method("start_at"):
		return false
	pursuit.call("start_at", heat)
	return true


## Sets the heat of the pursuit.
static func set_heat(police: Node, heat: int) -> bool:
	if police == null:
		return false
	if police.has_method(HEAT_METHOD):
		police.call(HEAT_METHOD, heat)
		return true
	if police.has_method(&"set_heat"):
		police.call(&"set_heat", heat)
		return true
	return false


## Switches the spawning of the police units on or off.
static func set_spawn_enabled(police: Node, enabled: bool) -> bool:
	if police == null:
		return false
	police.set(SPAWN_FLAG, enabled)
	if not enabled and police.has_method(UNITS_METHOD):
		police.call(UNITS_METHOD)
	return true


## Stops the pursuit: the heat goes back to zero and the units leave the road.
##
## The police unit is optional: without a director nothing happens.
static func stop_pursuit(police: Node) -> bool:
	if police == null:
		return false
	var pursuit: Object = police.get("pursuit")
	if pursuit != null and pursuit.has_method("reset"):
		pursuit.call("reset")
	if police.has_method(UNITS_METHOD):
		police.call(UNITS_METHOD)
	return true

extends Node
## Unit registry (autoload "Modules"). Instantiates each unit's entry scene; falls back to the core
## stub when the scene is missing, fails to load/instantiate, or is forced with --stub=a,b.
## Units own the scenes at the paths below (CONTRACTS.md §Units); core owns the stubs.

const UNITS: Dictionary = {
	&"world": "res://world/world.tscn",
	&"environment": "res://world/env/environment.tscn",
	&"player_car": "res://vehicle/player_car.tscn",
	&"camera": "res://vehicle/camera/chase_camera.tscn",
	&"hud": "res://ui/hud/hud.tscn",
	&"menu": "res://ui/menu/menu.tscn",
	&"fx": "res://fx/fx_director.tscn",
	&"audio": "res://audio/audio_director.tscn",
	&"damage": "res://damage/damage_director.tscn",
	&"traffic": "res://ai/traffic/traffic_director.tscn",
	&"police": "res://ai/police/police_director.tscn",
	&"rivals": "res://ai/rivals/rival_director.tscn",
	&"modes": "res://modes/mode_director.tscn",
}
const STUBS: Dictionary = {
	&"world": "res://core/sandbox/sandbox.tscn",
	&"environment": "res://core/stubs/stub_environment.tscn",
	&"player_car": "res://core/stubs/stub_car.tscn",
	&"camera": "res://core/stubs/stub_camera.tscn",
}
const EMPTY_STUB := "res://core/stubs/empty_stub.tscn"

## unit -> "real" | "stub", for the debug overlay and tests.
var loaded: Dictionary = {}


func instantiate(unit: StringName) -> Node:
	var path := String(UNITS.get(unit, ""))
	if not _forced_stub(unit) and path != "" and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		var node: Node = packed.instantiate() if packed != null else null
		if node != null and _script_ok(packed, node):
			loaded[unit] = "real"
			return node
		if node != null:
			node.free()
		push_warning("[modules] %s: %s failed to load (scene or root script broken), using stub" % [unit, path])
	loaded[unit] = "stub"
	var stub := load(String(STUBS.get(unit, EMPTY_STUB))) as PackedScene
	var stub_node := stub.instantiate()
	stub_node.name = String(unit).to_pascal_case() + "Stub"
	return stub_node


## A unit mid-edit can leave its root script unparsable: the scene still instantiates but does nothing.
func _script_ok(packed: PackedScene, node: Node) -> bool:
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"script":
			var script := node.get_script() as Script
			return script != null and script.can_instantiate()
	return true


func _forced_stub(unit: StringName) -> bool:
	var forced := Game.option("stub").split(",", false)
	return forced.has(String(unit)) or forced.has("all")

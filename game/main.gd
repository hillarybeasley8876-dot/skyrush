extends Node
## Boot (core-owned): assembles the game from units via Modules, in dependency order, and wires the
## player car into Game. Every unit is replaceable by its stub (--stub=unit,... or automatic fallback).
## Options: --mode=free|race|pursuit (default from the menu), --spawn=x,y,z[,yaw_deg] (debug teleport).

const ORDER: Array[StringName] = [&"environment", &"world", &"player_car", &"camera", &"damage", &"fx",
		&"audio", &"traffic", &"police", &"rivals", &"modes", &"hud", &"menu"]
const DebugOverlay := preload("res://core/debug_overlay.gd")


func _ready() -> void:
	for unit in ORDER:
		var node := Modules.instantiate(unit)
		add_child(node)
		match unit:
			&"world":
				_wire_world(node)
			&"player_car":
				_wire_player(node)
	add_child(DebugOverlay.new())
	print("[main] units: ", Modules.loaded)


func _wire_world(node: Node) -> void:
	if Game.world == null and node is WorldBase:
		Game.world = node as WorldBase
	if Game.world == null:
		push_error("[main] world unit did not provide a WorldBase; using the sandbox")
		var sandbox := (load(Modules.STUBS[&"world"]) as PackedScene).instantiate()
		add_child(sandbox)


func _wire_player(node: Node) -> void:
	var car := node as VehicleBase
	if car == null:
		push_error("[main] player_car unit is not a VehicleBase; using the stub car")
		node.queue_free()
		car = (load(Modules.STUBS[&"player_car"]) as PackedScene).instantiate() as VehicleBase
		add_child(car)
	car.team = VehicleBase.Team.PLAYER
	car.display_name = "Roadster"
	Game.player = car
	if Game.option("spawn") != "" or Game.world_built():
		car.reset_to(_spawn_transform())
		return
	# The real world builds over several seconds: hold the car frozen until it is built, then place
	# it on its spawn lane (asking earlier returns the fallback origin: no lanes or city data yet).
	car.freeze = true
	await Game.world_ready()
	if is_instance_valid(car):
		car.reset_to(_spawn_transform())
		car.freeze = false


func _spawn_transform() -> Transform3D:
	var spec := Game.option("spawn").split(",", false)
	if spec.size() >= 3:
		var yaw := deg_to_rad(float(spec[3])) if spec.size() >= 4 else 0.0
		return Transform3D(Basis(Vector3.UP, yaw), Vector3(float(spec[0]), float(spec[1]), float(spec[2])))
	return Game.world.get_spawn_transform(&"player", 0)

extends RefCounted
## The assets of the fx demo (game/fx/demo/fx_demo.gd): the environment, the car and the traffic
## car. They are loaded at runtime, so a unit that is mid-edit cannot take the demo down: every
## loader has a fallback.

const ROADSTER_GLTF := "res://assets/cars/roadster/roadster.glb"
const TRAFFIC_SCENE := "res://ai/traffic/traffic_car.tscn"
const ENVIRONMENT_SCENE := "res://world/env/environment.tscn"
const STUB_CAR := "res://core/stubs/stub_car.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"


## The real Roadster of the vehicle unit (the core stub car is the fallback).
func make_player_car() -> VehicleBase:
	for path in [PLAYER_CAR, STUB_CAR]:
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var car := packed.instantiate() as VehicleBase
		if car != null:
			return car
	return null


## The Roadster mesh, so the demo shows the real car even on the stub physics.
func add_roadster_visual(car: Node3D) -> void:
	if car.get_node_or_null(^"Visual") != null:
		return
	if not ResourceLoader.exists(ROADSTER_GLTF):
		return
	var packed := load(ROADSTER_GLTF) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		return
	model.name = "Model"
	car.add_child(model)
	MaterialLibrary.apply(model)


## The environment of the environment unit, with a minimal fallback.
func make_environment() -> Node:
	if ResourceLoader.exists(ENVIRONMENT_SCENE):
		var packed := load(ENVIRONMENT_SCENE) as PackedScene
		if packed != null:
			var node := packed.instantiate()
			if node != null:
				node.name = "Environment"
				return node
	return _fallback_environment()


## The traffic car of the traffic unit (a simple box car is the fallback).
func make_traffic_car() -> VehicleBase:
	if ResourceLoader.exists(TRAFFIC_SCENE):
		var packed := load(TRAFFIC_SCENE) as PackedScene
		if packed != null:
			var car := packed.instantiate() as VehicleBase
			if car != null:
				return car
	return _box_car()


## The bodywork of the traffic car: the traffic unit builds it at runtime, the demo has to add
## it itself, or the car is an invisible box. The traffic unit is sometimes mid-edit (its car
## script does not compile), so the demo falls back to a box of its own when the car has no
## mesh at all.
func add_traffic_visual(car: Node3D) -> void:
	if car == null:
		return
	if _has_mesh(car):
		return
	var visual := Node3D.new()
	visual.name = "DemoVisual"
	car.add_child(visual)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.28, 0.38)
	mat.roughness = 0.45
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.9, 1.0, 4.2)
	body.mesh = box
	body.material_override = mat
	body.position = Vector3(0.0, 0.75, 0.0)
	visual.add_child(body)
	var roof := MeshInstance3D.new()
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.7, 0.7, 2.0)
	roof.mesh = cabin
	roof.material_override = mat
	roof.position = Vector3(0.0, 1.55, -0.1)
	visual.add_child(roof)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.06)
	for x: float in [-0.95, 0.95]:
		for z: float in [-1.4, 1.4]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.34
			cylinder.bottom_radius = 0.34
			cylinder.height = 0.24
			wheel.mesh = cylinder
			wheel.material_override = wheel_mat
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			wheel.position = Vector3(x, 0.34, z)
			visual.add_child(wheel)


## True when the car already has a body (a mesh of its own).
func _has_mesh(car: Node3D) -> bool:
	for child in car.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			return true
	return false


## The sandbox has no weather stub of its own; the environment unit's controller owns the rain.
func turn_on_rain(environment: Node) -> void:
	if environment == null:
		return
	for child in environment.get_children():
		if child.has_method(&"set_rain"):
			child.set_rain(true)


func _fallback_environment() -> Node:
	var fallback := Node3D.new()
	fallback.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.34)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	fallback.add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.9)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	fallback.add_child(moon)
	return fallback


func _box_car() -> VehicleBase:
	# The traffic unit is sometimes mid-edit (its car script does not compile, so the scene
	# loads without it). The stub car of the core is a real VehicleBase with a body of its own.
	var packed := load("res://core/stubs/stub_car.tscn") as PackedScene
	if packed != null:
		var car := packed.instantiate() as VehicleBase
		if car != null:
			return car
	return null

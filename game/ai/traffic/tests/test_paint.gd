extends Node
## The traffic cars wear the colours of the palette.
##
##   tools/godot.sh test res://ai/traffic/tests/test_paint.gd
##
## The colour of a car is the instance uniform `base_color_override` of the car paint shader, so
## every paint surface of the car has to carry it.

const COLOURS := ["e8e8e6", "9da3a8", "0e0f11", "5a5f63", "1f3a5f"]
const PAINT_SHADER := "car_paint.gdshader"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	var world_scene := load("res://core/sandbox/sandbox.tscn") as PackedScene
	var world := world_scene.instantiate()
	add_child(world)
	await get_tree().physics_frame
	var director_scene := load("res://ai/traffic/traffic_director.tscn") as PackedScene
	var director := director_scene.instantiate()
	add_child(director)
	await get_tree().physics_frame
	for hex: String in COLOURS:
		var colour := Color(hex)
		var car: TrafficCar = director.spawn_car_at(0, 10.0, &"sedan_ev", colour)
		var surfaces := 0
		var wrong := 0
		var visual: Node3D = car.get_visual_root()
		for mi in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi as MeshInstance3D
			if not _is_paint(mesh):
				continue
			surfaces += 1
			var override: Variant = mesh.get_instance_shader_parameter(&"base_color_override")
			if override == null:
				wrong += 1
				continue
			if not (override as Color).is_equal_approx(Color(colour.r, colour.g, colour.b, 1.0)):
				wrong += 1
		_check(surfaces > 0, "the car #%s has paint surfaces (%d)" % [hex, surfaces])
		_check(wrong == 0, "every paint surface of the #%s car carries the colour (%d wrong)"
				% [hex, wrong])
	print("PAINT TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## True when one of the surfaces of the mesh uses the car paint shader.
func _is_paint(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_surface_override_material(i)
		if material == null:
			material = mesh.mesh.surface_get_material(i)
		var shader_material := material as ShaderMaterial
		if shader_material != null and shader_material.shader != null \
				and shader_material.shader.resource_path.ends_with(PAINT_SHADER):
			return true
	return false

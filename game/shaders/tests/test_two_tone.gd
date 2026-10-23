extends Node
## The two-tone Roadster: the white paint takes the colour of a car (a rival's racing colour is the
## instance uniform `base_color_override`), the gloss black panels keep their black. The switch is
## the plain uniform `allow_override` of the paint shader, and it has to survive the damage unit,
## which swaps every painted surface for a dent paint copy.
## Run: python tools/gd.py test res://shaders/tests/test_two_tone.gd

const GLB := "res://assets/cars/roadster/roadster.glb"
const DentMaterials := preload("res://damage/dent_materials.gd")

var _failures: int = 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("  " + detail if detail != "" else ""))
	if not ok:
		_failures += 1


## True when a paint material lets the car colour through (an unset parameter is the default, true).
func _lets_colour_through(material: Material) -> bool:
	var value: Variant = (material as ShaderMaterial).get_shader_parameter(&"allow_override")
	return value == null or bool(value)


func _ready() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		_check(false, "the hero glb loads")
		get_tree().quit(1)
		return
	var car := packed.instantiate()
	add_child(car)
	MaterialLibrary.apply(car)
	var white: Array[Material] = []
	var black: Array[Material] = []
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var name := mi.mesh.surface_get_material(i).resource_name.get_slice(".", 0)
			var bound := mi.get_active_material(i)
			if name == "SH_car_paint" and not white.has(bound):
				white.append(bound)
			elif name == "SH_car_paint_black" and not black.has(bound):
				black.append(bound)
	_check(white.size() > 0 and black.size() > 0, "the car has both paints",
		"(white %d, black %d)" % [white.size(), black.size()])
	var white_open := true
	for m in white:
		white_open = white_open and m is ShaderMaterial and _lets_colour_through(m)
	_check(white_open, "the white paint takes the colour of the car")
	var black_shut := true
	for m in black:
		black_shut = black_shut and m is ShaderMaterial and not _lets_colour_through(m)
	_check(black_shut, "the black paint keeps its colour whatever the car wears")
	# the damage unit replaces every painted surface by a copy of its paint
	var copy_white := DentMaterials.make(white[0] as ShaderMaterial) if white.size() > 0 else null
	var copy_black := DentMaterials.make(black[0] as ShaderMaterial) if black.size() > 0 else null
	_check(copy_white != null and _lets_colour_through(copy_white), "the dented white paint still takes the colour")
	_check(copy_black != null and not _lets_colour_through(copy_black), "the dented black paint still keeps its black")
	print("TWO TONE TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

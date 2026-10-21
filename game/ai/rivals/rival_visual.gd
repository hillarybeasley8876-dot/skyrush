class_name RivalVisual
extends RefCounted
## The look of a rival car: the Roadster body of the hero car, repainted in the racer's
## colour.
##
## The paint shader takes the colour of a car as an instance uniform, so every rival wears
## its own colour on ONE shared material (the same trick the traffic uses).

## The instance uniform the paint shader uses for the colour of the car.
const OVERRIDE_UNIFORM := "base_color_override"
const LEGACY_UNIFORM := "base_color"

static var _paint_shaders: Dictionary = {}


## Paints every surface of the car that uses the car paint shader.
static func apply_paint(root: Node, colour: Color) -> int:
	var painted := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			var uniform := _paint_uniform(mat)
			if uniform.is_empty():
				continue
			mi.set_instance_shader_parameter(uniform, Color(colour.r, colour.g, colour.b, 1.0))
			painted += 1
	return painted


## The instance uniform of a car paint material ("" when the material is not car paint).
##
## The instance uniforms are not in `get_shader_uniform_list()`, so the shader code is
## searched for the name instead.
static func _paint_uniform(mat: Material) -> String:
	var shader_mat := mat as ShaderMaterial
	if shader_mat == null or shader_mat.shader == null:
		return ""
	var shader := shader_mat.shader
	var key := shader.get_instance_id()
	if _paint_shaders.has(key):
		return String(_paint_shaders[key])
	var found := ""
	if shader.code.contains(OVERRIDE_UNIFORM):
		found = OVERRIDE_UNIFORM
	elif shader.code.contains(LEGACY_UNIFORM):
		found = LEGACY_UNIFORM
	_paint_shaders[key] = found
	return found

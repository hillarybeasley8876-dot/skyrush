class_name MaterialLibrary
extends RefCounted
## Runtime material swap for imported glTF scenes (core-owned mechanism, content owned by the
## shaders unit). Any surface material named "SH_<name>" (Blender duplicates like "SH_x.001" too)
## is replaced by res://shaders/materials/SH_<name>.tres when that file exists.
## If the library material is a ShaderMaterial with uniforms `albedo_texture`, `normal_texture`,
## `roughness_texture` or `emission_texture`, the imported material's textures are copied into a
## per-source duplicate, so one shader serves many differently textured assets.
## Call MaterialLibrary.apply(root) once after instancing an imported scene.

const DIR := "res://shaders/materials/"
const TEXTURE_UNIFORMS: Dictionary = {
	&"albedo_texture": BaseMaterial3D.TEXTURE_ALBEDO,
	&"normal_texture": BaseMaterial3D.TEXTURE_NORMAL,
	&"roughness_texture": BaseMaterial3D.TEXTURE_ROUGHNESS,
	&"emission_texture": BaseMaterial3D.TEXTURE_EMISSION,
}

static var _library: Dictionary = {}  # "SH_x" -> Material or null
static var _bound: Dictionary = {}  # source material instance id -> bound Material


## Returns the number of surfaces swapped.
static func apply(root: Node) -> int:
	var swapped := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		swapped += _apply_mesh(node as MeshInstance3D)
	return swapped


static func lookup(material_name: String) -> Material:
	if not material_name.begins_with("SH_"):
		return null
	var key := material_name.get_slice(".", 0)
	if not _library.has(key):
		var path := DIR + key + ".tres"
		_library[key] = load(path) as Material if ResourceLoader.exists(path) else null
	return _library[key] as Material


static func _apply_mesh(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var count := 0
	for i in mi.mesh.get_surface_count():
		var source := mi.get_active_material(i)
		if source == null:
			continue
		var bound := _bind(source)
		if bound != null:
			mi.set_surface_override_material(i, bound)
			count += 1
	return count


static func _bind(source: Material) -> Material:
	var sid := source.get_instance_id()
	if _bound.has(sid):
		return _bound[sid] as Material
	var lib := lookup(source.resource_name)
	var result: Material = lib
	var shader_mat := lib as ShaderMaterial
	var base := source as BaseMaterial3D
	if shader_mat != null and base != null:
		result = _with_textures(shader_mat, base)
	_bound[sid] = result
	return result


static func _with_textures(lib: ShaderMaterial, base: BaseMaterial3D) -> ShaderMaterial:
	var uniforms: Array[StringName] = []
	for u in lib.shader.get_shader_uniform_list():
		uniforms.append(StringName(u["name"]))
	var copy: ShaderMaterial = null
	for uniform: StringName in TEXTURE_UNIFORMS:
		var tex := base.get_texture(TEXTURE_UNIFORMS[uniform] as BaseMaterial3D.TextureParam)
		if tex == null or not uniforms.has(uniform):
			continue
		if copy == null:
			copy = lib.duplicate() as ShaderMaterial
		copy.set_shader_parameter(uniform, tex)
	return copy if copy != null else lib

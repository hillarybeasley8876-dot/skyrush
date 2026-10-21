extends RefCounted
## The materials of the damage unit (dossier §7.5 A): the damage paint of a painted surface
## and the generic damage surface of a BaseMaterial3D.
##
## The uniform lists of the shaders are cached here: `get_shader_uniform_list()` parses the
## shader and costs 0.7 ms, which no hit can pay.

const DENT_PAINT := preload("res://damage/dent_paint.gdshader")
const DENT_BASIC := preload("res://damage/dent_basic.gdshader")

## The bare substrate of the cars: the carbon twill of the Roadster, the steel of the traffic.
const CARBON := Color(0.082, 0.090, 0.106)   ## #15171B
const STEEL := Color(0.620, 0.639, 0.658)    ## #9EA3A8

## The uniform lists of the shaders, by the id of the shader.
static var _uniform_lists: Dictionary = {}
## The material every surface had before the damage unit replaced it (the debris wears it: a
## flying part must not carry the dent field of the car it came from).
static var _clean: Dictionary = {}


## Reads the uniform lists of the shaders (the director does it when it starts, so the first
## hit does not pay for the parsing).
static func warm_up() -> void:
	uniforms_of(DENT_PAINT)
	uniforms_of(DENT_BASIC)


## A mesh that wears the damage materials, so the rendering server builds them (and their
## shaders) before the first crash: the first hit of a game must not pay for it.
static func warm_up_meshes() -> Array[Node]:
	var out: Array[Node] = []
	for shader in [DENT_PAINT, DENT_BASIC]:
		var material := ShaderMaterial.new()
		material.shader = shader
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.1, 0.1, 0.1)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		out.append(node)
	return out


## The material a surface had before the damage unit replaced it.
static func clean_of(source: Material) -> Material:
	if source == null:
		return null
	return _clean.get(source.get_instance_id(), source) as Material


## The damage material of a surface: the damage paint for a painted surface, the generic
## damage surface for a BaseMaterial3D. Null when the surface cannot be reproduced (a glass
## shader of its own), so it keeps its material and does not move.
static func make(source: Material) -> ShaderMaterial:
	var key := source.get_instance_id()
	if _clean.has(key):
		return null
	# A surface that already wears a damage material is not wrapped a second time: the
	# dent field of the car would be copied into a copy of itself.
	if source is ShaderMaterial:
		var shader := (source as ShaderMaterial).shader
		if shader == DENT_PAINT or shader == DENT_BASIC:
			return null
	var result: ShaderMaterial = null
	if source is ShaderMaterial:
		var shader_material := source as ShaderMaterial
		if shader_material.shader != null and is_car_paint(shader_material.shader):
			result = make_paint(shader_material)
	elif source is BaseMaterial3D:
		result = make_basic(source as BaseMaterial3D)
	if result != null:
		_clean[key] = source
	return result


## The damage paint: the look of the shared paint (its uniforms and its instance uniforms)
## plus the damage layer of dossier §7.5 A.
static func make_paint(source: ShaderMaterial) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DENT_PAINT
	copy_uniforms(source, material)
	copy_instance_uniforms(source, material)
	return material


## The generic damage surface: the look of the BaseMaterial3D it replaces.
static func make_basic(source: BaseMaterial3D) -> ShaderMaterial:
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# A transparent surface cannot be reproduced by the generic shader.
		return null
	var material := ShaderMaterial.new()
	material.shader = DENT_BASIC
	material.set_shader_parameter("base_color", source.albedo_color)
	if source.albedo_texture != null:
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("use_albedo_map", 1.0)
	material.set_shader_parameter("uv1_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	material.set_shader_parameter("uv1_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	material.set_shader_parameter("metallic", source.metallic)
	if source.metallic_texture != null:
		material.set_shader_parameter("metallic_texture", source.metallic_texture)
		material.set_shader_parameter("use_metallic_map", 1.0)
	material.set_shader_parameter("metallic_channel", int(source.metallic_texture_channel))
	material.set_shader_parameter("roughness", source.roughness)
	if source.roughness_texture != null:
		material.set_shader_parameter("roughness_texture", source.roughness_texture)
		material.set_shader_parameter("use_roughness_map", 1.0)
	material.set_shader_parameter("roughness_channel", int(source.roughness_texture_channel))
	if source.normal_enabled and source.normal_texture != null:
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("use_normal_map", 1.0)
		material.set_shader_parameter("normal_strength", source.normal_scale)
	if source.emission_enabled:
		material.set_shader_parameter("emission_color", source.emission)
		material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
		if source.emission_texture != null:
			material.set_shader_parameter("emission_texture", source.emission_texture)
			material.set_shader_parameter("use_emission_map", 1.0)
	if source.vertex_color_use_as_albedo:
		material.set_shader_parameter("use_vertex_color", 1.0)
	return material


## Copies the plain uniforms of a material that the damage material also has.
##
## A uniform is only written when the damage material does not have the value yet: every
## write is a call to the rendering server, and a hit must not pay for forty of them.
static func copy_uniforms(source: ShaderMaterial, target: ShaderMaterial) -> void:
	var mine := uniforms_of(target.shader)
	var theirs := uniforms_of(source.shader)
	for name: StringName in theirs:
		if not mine.has(name) or mine[name] != theirs[name]:
			continue
		var value: Variant = source.get_shader_parameter(name)
		if value == null:
			continue
		if target.get_shader_parameter(name) == value:
			continue
		target.set_shader_parameter(name, value)


## Copies the instance uniforms of a material (the paint colour of a car is one of them).
static func copy_instance_uniforms(source: ShaderMaterial, target: ShaderMaterial) -> void:
	var mine := uniforms_of(target.shader)
	for name in instance_uniforms(source.shader):
		if not mine.has(name):
			continue
		var value: Variant = source.get_instance_shader_parameter(name)
		if value != null:
			target.set_instance_shader_parameter(name, value)


## Sets a uniform of a material, when the material's shader has it.
static func set_uniform(material: ShaderMaterial, name: StringName, value: Variant) -> void:
	if not uniforms_of(material.shader).has(name):
		return
	material.set_shader_parameter(name, value)


## The uniform list of a shader, by name and type. The list is cached: reading it parses the
## shader and costs 0.7 ms.
static func uniforms_of(shader: Shader) -> Dictionary:
	var id := shader.get_instance_id()
	if _uniform_lists.has(id):
		return _uniform_lists[id] as Dictionary
	var list: Dictionary = {}
	for u in shader.get_shader_uniform_list():
		list[StringName(u["name"])] = u["type"]
	_uniform_lists[id] = list
	return list


## The instance uniforms of a shader (they are not in the uniform list).
static func instance_uniforms(shader: Shader) -> Array[StringName]:
	var id := shader.get_instance_id()
	if _uniform_lists.has(id) and _uniform_lists[id].has("__instance"):
		return _uniform_lists[id]["__instance"] as Array[StringName]
	var names: Array[StringName] = []
	for line in shader.code.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("instance uniform"):
			continue
		var parts := text.split(" ", false)
		if parts.size() < 4:
			continue
		names.append(StringName(parts[3]))
	var list := uniforms_of(shader) as Dictionary
	list["__instance"] = names
	return names


## The car paint is recognised by its plain uniforms (the instance uniforms are not listed
## by `get_shader_uniform_list`).
static func is_car_paint(shader: Shader) -> bool:
	var names := uniforms_of(shader)
	return names.has("grime_amount") and names.has("panel_normal_strength")


## The bare substrate of the car under the paint: the carbon twill of the Roadster, the bare
## steel of the traffic (dossier §7.4 / the art bible).
static func set_substrate(material: ShaderMaterial, hero: bool) -> void:
	if hero:
		material.set_shader_parameter("substrate_color", CARBON)
		material.set_shader_parameter("substrate_metallic", 0.25)
		material.set_shader_parameter("substrate_roughness", 0.30)
		material.set_shader_parameter("substrate_twill", 1.0)
		return
	material.set_shader_parameter("substrate_color", STEEL)
	material.set_shader_parameter("substrate_metallic", 1.0)
	material.set_shader_parameter("substrate_roughness", 0.35)
	material.set_shader_parameter("substrate_twill", 0.0)

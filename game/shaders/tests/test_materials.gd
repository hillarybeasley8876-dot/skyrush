extends Node
## Shaders unit test: every SH_ material exists, loads, points at the right shader and carries the
## uniforms the art dossier requires.
##
##   tools/godot.sh test res://shaders/tests/test_materials.gd

const DIR := "res://shaders/materials/"

## material -> [shader file, {uniform: expected plain-uniform value}]
const EXPECTED: Dictionary = {
	"SH_wet_asphalt": ["road_wet.gdshader", {"albedo_mul": 0.5, "tile_m": 3.0, "puddle_amount": 0.24, "detail_strength": 0.5}],
	"SH_road_marking_white": ["road_marking.gdshader", {"paint_color": Color("e9e7df")}],
	"SH_road_marking_yellow": ["road_marking.gdshader", {"paint_color": Color("e8b520")}],
	"SH_facade_office": ["facade_windows.gdshader", {"floor_h": 3.9, "lit_ratio": 0.15, "window_energy": 1.0}],
	"SH_facade_residential": ["facade_windows.gdshader", {"floor_h": 2.95, "lit_ratio": 0.22, "tv_ratio": 0.05}],
	"SH_neon": ["neon_tube.gdshader", {"core_whiten": 0.12, "dropout_rate": 0.015, "emission_energy": 5.0}],
	"SH_hologram": ["hologram_billboard.gdshader", {"scan_lines": 220.0, "glitch_rate": 0.08}],
	"SH_car_paint": ["car_paint.gdshader", {"base_roughness": 0.12, "clearcoat_amount": 1.0, "grime_height_m": 0.3}],
	"SH_car_paint_black": ["car_paint.gdshader", {"base_color": Color("0b0c0e"), "base_roughness": 0.1, "clearcoat_amount": 1.0, "allow_override": false}],
	"SH_car_paint_npc": ["car_paint.gdshader", {"base_roughness": 0.42, "clearcoat_amount": 0.8, "grime_amount": 0.45}],
	"SH_car_paint_police": ["car_paint.gdshader", {"base_color": Color("f2f4f5"), "base_roughness": 0.35, "clearcoat_rough": 0.06}],
	"SH_car_paint_taxi": ["car_paint.gdshader", {"base_color": Color("1e8c8a"), "base_roughness": 0.38}],
	"SH_glass_smoke": ["glass_canopy.gdshader", {"tint_color": Color("0a0b0c"), "roughness_value": 0.04}],
	"SH_glass_tinted": ["glass_tinted.gdshader", {"tint_color": Color("0a0e12"), "base_alpha": 0.72}],
	"SH_water": ["water_river.gdshader", {"water_color": Color("0b1016"), "roughness_value": 0.08}],
	"SH_soffit_blue": ["soffit_blue.gdshader", {"wash_color": Color("2357f3"), "wash_energy": 0.9, "wash_falloff": 0.45, "strip_energy": 4.5, "strip_width_m": 0.05, "joint_spacing_m": 1.2}],
	"SH_concrete_pier": ["concrete_stained.gdshader", {"base_color": Color("7a7874"), "splash_height_m": 0.6}],
	"SH_concrete_barrier": ["concrete_stained.gdshader", {"base_color": Color("7a7874"), "splash_height_m": 0.35}],
	"SH_granite_bund": ["concrete_stained.gdshader", {"base_color": Color("9c9b95"), "uv_scale": 0.5555555, "normal_scale": 0.5, "course_height_m": 0.42}],
	"SH_sidewalk": ["concrete_stained.gdshader", {"base_color": Color("6e6c68"), "splash_factor": 0.0}],
	"SH_kerb": ["concrete_stained.gdshader", {"base_color": Color("8e8c86"), "splash_height_m": 0.18}],
	"SH_tactile": ["concrete_stained.gdshader", {"base_color": Color("c9b43a"), "splash_height_m": 0.03}],
}

## Shaders that must react to the weather globals: shader -> [reads wetness, reads rain].
const WEATHER_SHADERS: Dictionary = {
	"road_wet": [true, true],
	"road_marking": [true, true],
	"car_paint": [true, true],
	"glass_canopy": [true, true],
	"glass_tinted": [true, true],
	"concrete_stained": [true, false],   # rain does not change concrete, the wetness does
	"sky_night_city": [false, true],      # a rain sky is overcast, the road wetness is irrelevant
}

## Uniforms that must exist and must be instance-scoped (per-object variety).
const INSTANCE_UNIFORMS: Dictionary = {
	"neon_tube": ["neon_color", "neon_energy", "neon_seed", "faulty", "is_flat_strip"],
	"car_paint": ["base_color_override", "panel_offset_y"],
	"hologram_billboard": ["mode", "energy", "tint"],
	"facade_windows": ["building_seed"],
	"concrete_stained": ["tint_override", "splash_override", "base_y"],
}

## The samplers that are deliberately empty. The first group is filled at runtime from the
## imported material (MaterialLibrary forwards the imported texture); the tactile strip's scan
## has no AO map at all, so its ao stays empty (the shader reads white).
const EMPTY_SAMPLERS: Dictionary = {
	"SH_car_paint": ["albedo_texture", "roughness_texture", "normal_texture", "livery_tex"],
	"SH_car_paint_black": ["albedo_texture", "roughness_texture", "normal_texture", "livery_tex"],
	"SH_car_paint_npc": ["albedo_texture", "roughness_texture", "normal_texture", "livery_tex"],
	"SH_car_paint_police": ["albedo_texture", "roughness_texture", "normal_texture", "livery_tex"],
	"SH_car_paint_taxi": ["albedo_texture", "roughness_texture", "normal_texture", "livery_tex"],
	"SH_glass_smoke": ["albedo_texture"],
	"SH_glass_tinted": ["albedo_texture"],
	"SH_neon": ["emission_texture", "albedo_texture"],
	"SH_road_marking_white": ["mask_texture"],
	"SH_road_marking_yellow": ["mask_texture"],
	"SH_tactile": ["ao_texture"],
}

var _failed: int = 0


func _ready() -> void:
	for name: String in EXPECTED:
		_check_material(name)
	for shader_name: String in WEATHER_SHADERS:
		_check_weather(shader_name)
	for shader_name: String in INSTANCE_UNIFORMS:
		_check_instance_uniforms(shader_name)
	_check_library_lookup()
	_check_no_stray_materials()
	_check_import_forwarding()
	_check_samplers_are_bound()
	_check_detail_textures()
	_check_lookdev_uses_every_material()
	print("TEST_MATERIALS %d failed" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)


func _check_material(name: String) -> void:
	var path := DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		_fail("%s: %s does not exist" % [name, path])
		return
	var mat := load(path) as ShaderMaterial
	if mat == null:
		_fail("%s: does not load as a ShaderMaterial" % name)
		return
	if mat.shader == null:
		_fail("%s: has no shader" % name)
		return
	var spec: Array = EXPECTED[name]
	var want_shader: String = spec[0]
	var got_shader := mat.shader.resource_path.get_file()
	if got_shader != want_shader:
		_fail("%s: uses %s, expected %s" % [name, got_shader, want_shader])
		return
	for uniform: String in spec[1]:
		var want: Variant = spec[1][uniform]
		var got: Variant = mat.get_shader_parameter(uniform)
		if not _close(got, want):
			_fail("%s: uniform %s is %s, expected %s" % [name, uniform, str(got), str(want)])
			return
	_pass("%s -> %s" % [name, want_shader])


func _check_weather(shader_name: String) -> void:
	var path := "res://shaders/%s.gdshader" % shader_name
	var shader := load(path) as Shader
	if shader == null:
		_fail("%s: does not load" % path)
		return
	var code := shader.code
	var wants: Array = WEATHER_SHADERS[shader_name]
	if bool(wants[0]) and not code.contains("global uniform float skyrush_wetness"):
		_fail("%s: does not read the global skyrush_wetness" % shader_name)
		return
	if bool(wants[1]) and not code.contains("global uniform float skyrush_rain"):
		_fail("%s: does not read the global skyrush_rain" % shader_name)
		return
	_pass("%s reads the weather globals" % shader_name)


func _check_instance_uniforms(shader_name: String) -> void:
	var path := "res://shaders/%s.gdshader" % shader_name
	var shader := load(path) as Shader
	if shader == null:
		_fail("%s: does not load" % path)
		return
	for uniform: String in INSTANCE_UNIFORMS[shader_name]:
		if not shader.code.contains("instance uniform") or not shader.code.contains(uniform):
			_fail("%s: %s is not an instance uniform" % [shader_name, uniform])
			return
	_pass("%s instance uniforms ok" % shader_name)


func _check_library_lookup() -> void:
	for name: String in EXPECTED:
		var found := MaterialLibrary.lookup(name)
		if found == null:
			_fail("MaterialLibrary.lookup(%s) returned null" % name)
			return
	_pass("MaterialLibrary finds all %d materials" % EXPECTED.size())


func _check_no_stray_materials() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".tres"):
			continue
		if not EXPECTED.has(file.get_basename()):
			_fail("unexpected material file %s" % file)


## An imported glTF material named SH_neon.001 keeps its own albedo TEXTURE: MaterialLibrary
## forwards it into the shader's emission_texture. (The imported COLOUR needs core to forward
## emission_color as well - see the request in status/environment.md.)
func _check_import_forwarding() -> void:
	var source := StandardMaterial3D.new()
	source.resource_name = "SH_neon.001"
	source.albedo_texture = _test_texture()
	source.albedo_color = Color("19e6ff")
	source.emission_enabled = true
	source.emission = Color("19e6ff")
	source.emission_energy_multiplier = 4.0
	var mesh := BoxMesh.new()
	mesh.surface_set_material(0, source)   # the imported material sits on the mesh surface
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	MaterialLibrary.apply(self)
	var bound := mi.get_surface_override_material(0) as ShaderMaterial
	if bound == null:
		_fail("the imported SH_neon.001 did not become a ShaderMaterial")
		return
	if bound.get_shader_parameter("albedo_texture") != source.albedo_texture:
		_fail("the imported albedo texture was not forwarded into albedo_texture")
		return
	if not bound.shader.code.contains("uniform sampler2D emission_texture"):
		_fail("the neon shader has no emission_texture (the imported emission map would be lost)")
		return
	# The shader must be ready for the colour forwarding that core still has to add.
	if not bound.shader.code.contains("uniform vec4 emission_color"):
		_fail("the neon shader does not declare emission_color (the imported colour would be lost)")
		return
	_pass("the imported texture is forwarded into the SH_ material")
	mi.queue_free()


## Every sampler the recipe sets must be bound to a real texture in the saved .tres. An unbound
## sampler is Godot's white (or black) default and the detail layer silently does nothing.
func _check_samplers_are_bound() -> void:
	for name: String in EXPECTED:
		var mat := load(DIR + name + ".tres") as ShaderMaterial
		if mat == null or mat.shader == null:
			continue
		var optional: Array = EMPTY_SAMPLERS.get(name, [])
		for sampler: String in _sampler_names(mat.shader):
			if optional.has(sampler):
				continue
			var value: Variant = mat.get_shader_parameter(sampler)
			if value == null:
				_fail("%s: the sampler %s is not bound to a texture" % [name, sampler])
				return
			if not (value is Texture2D):
				_fail("%s: the sampler %s holds a %s, not a texture" % [name, sampler, typeof(value)])
				return
	_pass("every sampler of every material is bound to a texture")


## The sampler names of a shader, parsed from its source.
func _sampler_names(shader: Shader) -> PackedStringArray:
	var names := PackedStringArray()
	for line in shader.code.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("uniform sampler2D "):
			continue
		var rest := text.substr(len("uniform sampler2D "))
		var space := rest.find(" ")
		names.append(rest.substr(0, space) if space > 0 else rest)
	return names


## The detail textures the dossier names: the drip sheet, the dust sheet and the stain sheet have
## to be the maps that actually exist (r3 review: three maps did not exist or were the wrong map).
func _check_detail_textures() -> void:
	var expect := {
		"SH_concrete_pier": {"drip_texture": "Leaking004_opacity"},
		"SH_concrete_barrier": {"drip_texture": "Leaking004_opacity"},
		"SH_granite_bund": {"detail_texture": "granite_tile_03_diff"},
		"SH_soffit_blue": {"stain_texture": "Leaking004_opacity"},
		"SH_car_paint": {"clearcoat_roughness_map": "SurfaceImperfections001_opacity"},
		"SH_car_paint_npc": {"clearcoat_roughness_map": "SurfaceImperfections001_opacity"},
		"SH_car_paint_police": {"clearcoat_roughness_map": "SurfaceImperfections001_opacity"},
		"SH_car_paint_taxi": {"clearcoat_roughness_map": "SurfaceImperfections001_opacity"},
	}
	for name: String in expect:
		var mat := load(DIR + name + ".tres") as ShaderMaterial
		if mat == null:
			_fail("%s does not load" % name)
			return
		for uniform: String in expect[name]:
			var tex := mat.get_shader_parameter(uniform) as Texture2D
			if tex == null:
				_fail("%s: %s is not bound" % [name, uniform])
				return
			if not tex.resource_path.contains(String(expect[name][uniform])):
				_fail("%s: %s is %s, expected %s" % [name, uniform, tex.resource_path,
					String(expect[name][uniform])])
				return
	_pass("the detail maps are the ones the dossier names")


## Every SH_*.tres of the library has to appear in the look-dev scene (the acceptance item).
func _check_lookdev_uses_every_material() -> void:
	var scene := load("res://world/env/lookdev.tscn") as PackedScene
	if scene == null:
		_fail("the look-dev scene does not load")
		return
	var node := scene.instantiate()
	add_child(node)
	var used: Dictionary = {}
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			# The library material (the surface override) or the imported glTF material, whose
			# resource_name is the SH_ contract name.
			var override := mesh.get_surface_override_material(i)
			if override != null:
				used[override.resource_path.get_file().get_basename()] = true
			var active := mesh.get_active_material(i)
			if active != null:
				used[active.resource_path.get_file().get_basename()] = true
				used[active.resource_name.get_slice(".", 0)] = true
			var source := mesh.mesh.surface_get_material(i)
			if source != null:
				used[source.resource_name.get_slice(".", 0)] = true
	for file: String in DirAccess.get_files_at(DIR):
		var mat_name := file.get_basename()
		if not used.has(mat_name):
			_fail("the look-dev scene does not use " + mat_name)
			return
	_pass("the look-dev scene uses all %d materials" % used.size())
	node.queue_free()


func _test_texture() -> Texture2D:
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	return tex


func _close(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return absf(float(a) - float(b)) < 0.001
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	return a == b


func _pass(msg: String) -> void:
	print("PASS ", msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL ", msg)

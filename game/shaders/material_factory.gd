extends Node
## Regenerates every res://shaders/materials/SH_*.tres from the recipes in the art dossier
## (ref/art/DOSSIER.md section 4, ART.md section 5). The .tres files are the deliverable; this
## script is how they are built, so the whole library can be re-tuned from one place.
##
##   tools/godot.sh test res://shaders/material_factory.gd
##
## The recipes live in three files so no file grows past the 400 line limit:
##   recipes_street.gd  - the asphalt, the paint and the concrete family
##   recipes_vehicle.gd - the car paint and the glass
##   recipes_light.gd   - the neon, the hologram, the soffit, the water and the facades
##
## NOTE: only PLAIN uniforms are written to the .tres. A material-level value for an INSTANCE uniform
## is ignored by the Godot renderer (verified by shaders/tests/instance_uniform_probe.gd), so the
## per-object values (neon colour, car colour, building seed, concrete tint) live in the shader
## source as compile-time defaults and are overridden per instance at runtime.

const OUT_DIR := "res://shaders/materials/"
const RECIPES := preload("res://shaders/recipes_all.gd")
const COMMON := preload("res://shaders/recipes_common.gd")


func _ready() -> void:
	var mats: Dictionary = RECIPES.build_all()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := 0
	for name: String in mats:
		var mat := mats[name] as ShaderMaterial
		if mat == null or mat.shader == null:
			printerr("MATERIAL FAIL (no shader) ", name)
			failed += 1
			continue
		var path := OUT_DIR + name + ".tres"
		var err := ResourceSaver.save(mat, path)
		if err != OK:
			printerr("MATERIAL FAIL ", name, " err=", err)
			failed += 1
			continue
		# The saved file must still carry the parameters: a shader that does not compile drops
		# them on save and the material would render with the shader's defaults.
		if _parameter_count(path) < 1:
			printerr("MATERIAL FAIL ", name, " lost its parameters on save")
			failed += 1
			continue
		print("MATERIAL ", name, " -> ", path)
	# A missing texture is FATAL: the material would render with a black or white sampler and the
	# detail layer would be a silent no-op.
	for path: String in COMMON.missing_textures():
		printerr("MATERIAL FAIL missing texture ", path)
		failed += 1
	print("MATERIALS %d written, %d failed" % [mats.size() - mini(failed, mats.size()), failed])
	get_tree().quit(1 if failed > 0 else 0)


## How many shader parameters the saved .tres carries. A material whose shader does not compile
## is saved without any of them.
static func _parameter_count(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	return text.count("shader_parameter/")

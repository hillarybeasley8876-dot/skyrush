extends Node3D
## Preview scene for the generated city blocks (buildings unit).
##
## Loads every res://assets/city/blocks/blocks_<tx>_<tz>.gltf, places it at its tile
## origin (512 m grid) and adds the shared night environment plus a ground plane.
## Used with:  tools/godot.sh shot --scene res://assets/city/blocks/preview_blocks.tscn

const TILE_M := 512.0
var BLOCKS_DIR := "res://assets/city/blocks"
var dir_override := ""
const ENV_SCENE := "res://world/env/environment.tscn"
const MaterialLibrary := preload("res://core/materials/material_library.gd")

## Preview-only street lighting (the props unit owns the real lamps).
const LAMP_SPACING := 30.0
const LAMP_RANGE := 14.0
const LAMP_ENERGY := 3.0
const NEAR_RANGE := 400.0
const FAR_RANGE := 350.0


func _ready() -> void:
	_apply_dir_override()
	_add_environment()
	_add_ground()
	_add_tiles()
	_add_street_lights()


func _add_street_lights() -> void:
	## A row of sodium-ish lamps along the test city's main street so the street level
	## reads at night. Preview only - the world unit places the real lamps.
	for row in [-8.0, -20.0, 100.0]:
		for i in range(-11, 12):
			var x := float(i) * LAMP_SPACING
			var light := OmniLight3D.new()
			light.name = "PreviewLamp_%d" % i
			light.position = Vector3(x, 7.0, row)
			light.light_color = Color(1.0, 0.79, 0.55)
			light.light_energy = LAMP_ENERGY
			light.omni_range = LAMP_RANGE
			light.shadow_enabled = false
			add_child(light)


func _apply_dir_override() -> void:
	## "--dir=res://..." lets the capture tool point the preview at another tile folder.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir_override = arg.substr(6)
			BLOCKS_DIR = dir_override


func _add_environment() -> void:
	if not ResourceLoader.exists(ENV_SCENE):
		return
	var packed := load(ENV_SCENE) as PackedScene
	if packed == null:
		return
	add_child(packed.instantiate())


func _add_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(6000.0, 6000.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.055, 0.065)
	mat.roughness = 0.6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	add_child(mi)


func _add_tiles() -> void:
	var dir := DirAccess.open(BLOCKS_DIR)
	if dir == null:
		push_warning("preview_blocks: no %s" % BLOCKS_DIR)
		return
	for file_name in dir.get_files():
		# the tiles are .gltf + .bin with the images in res://assets/city/_tex/
		if not file_name.begins_with("blocks_") or not file_name.ends_with(".gltf"):
			continue
		var is_far := file_name.ends_with("_far.gltf")
		var stem := file_name.trim_suffix(".gltf")
		if is_far:
			stem = stem.trim_suffix("_far")
		var parts := stem.trim_prefix("blocks_").split("_")
		if parts.size() != 2:
			continue
		var path := "%s/%s" % [BLOCKS_DIR, file_name]
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("preview_blocks: cannot load %s" % path)
			continue
		var node := packed.instantiate()
		node.name = stem
		add_child(node)   # the tiles are exported in world coordinates
		# the SH_* facade materials are replaced by the shared shader library
		MaterialLibrary.apply(node)
		# the same visibility ranges the world unit uses (near 400 m / far from 350 m)
		for child in node.get_children():
			var geo := child as GeometryInstance3D
			if geo == null:
				continue
			if is_far:
				geo.visibility_range_begin = FAR_RANGE
				geo.visibility_range_end = 0.0
			else:
				geo.visibility_range_begin = 0.0
				geo.visibility_range_end = NEAR_RANGE

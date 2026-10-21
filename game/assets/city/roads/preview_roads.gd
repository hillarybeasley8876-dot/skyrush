extends Node3D
## Preview scene for the generated road tiles.
##
## Loads every roads_<tx>_<tz>.gltf in this folder, applies the shared shader materials
## (MaterialLibrary replaces every SH_* material with the runtime shader) and adds a
## dark ground plane so the surface roads do not float. Used with:
##
##   tools/godot.sh shot --scene=res://assets/city/roads/preview_roads.tscn \
##       --cams="deck:100,11.1,63:300,11.1,63" --out=roads

const DIR := "res://assets/city/roads/"


func _ready() -> void:
	_add_ground()
	for path in _tiles():
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("preview_roads: cannot load " + path)
			continue
		var node := packed.instantiate()
		add_child(node)
		MaterialLibrary.apply(node)
		_hide_collision(node)


## The "-colonly" meshes are collision only (CONTRACTS §2): keep them out of the render.
func _hide_collision(node: Node) -> void:
	for child in node.get_children():
		if child is VisualInstance3D and child.name.ends_with("-colonly"):
			(child as VisualInstance3D).visible = false
		_hide_collision(child)


## The tiles of the folder: the .gltf tiles (with the shared textures) win over the .glb ones.
func _tiles() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var gltf: Dictionary = {}
	for file in dir.get_files():
		if file.begins_with("roads_") and file.ends_with(".gltf"):
			gltf[file.get_basename()] = DIR + file
	for file in dir.get_files():
		if not file.begins_with("roads_") or not file.ends_with(".glb"):
			continue
		if gltf.has(file.get_basename()):
			continue
		out.append(DIR + file)
	for key in gltf.keys():
		out.append(String(gltf[key]))
	out.sort()
	return out


func _add_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(8000.0, 8000.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.045, 0.046, 0.052)
	mat.roughness = 0.92
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, -0.08, 0.0)
	add_child(mi)

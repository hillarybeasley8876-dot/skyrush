extends RefCounted
## Finds and instantiates the city glb files produced by the roads / buildings / bund / landmarks /
## props units, applies the shared material library, sets the per-building shader seed and the
## visibility ranges used for the HLOD hand-off. Missing files are skipped with one warning each.

const ROADS_DIR := "res://assets/city/roads/"
const BLOCKS_DIR := "res://assets/city/blocks/"
const BUND_DIR := "res://assets/bund/"
const LANDMARKS_DIR := "res://assets/landmarks/"
const PROPS_DIR := "res://assets/props/"

const NEAR_VISIBILITY_END := 400.0
const FAR_VISIBILITY_BEGIN := 350.0
const FAR_SUFFIX := "_far"

var warned: Dictionary = {}
## The collision shapes that were moved into a merged body (they have to stay alive).
var _kept_shapes: Array[Shape3D] = []


## Instantiates every `<prefix>*.glb` in `dir_path`. Returns the instances (never null).
## `bounded` gives the tiles a visibility range (the landmarks and the Bund have none: they have
## to be seen from the other side of the river).
func instantiate_dir(dir_path: String, prefix: String, far: bool = false,
		bounded: bool = true) -> Array[Node3D]:
	var out: Array[Node3D] = []
	# A near tile is only culled when the directory has a far tile to take over from it.
	var has_far := _has_far(dir_path, prefix)
	for path in find_glbs(dir_path, prefix):
		var is_far := path.get_file().get_basename().ends_with(FAR_SUFFIX)
		if is_far != far:
			continue
		var node := instantiate_glb(path)
		if node == null:
			continue
		if bounded:
			prepare_instance(node, is_far, has_far)
		out.append(node)
	return out


## True when the directory holds a far tile for the prefix.
func _has_far(dir_path: String, prefix: String) -> bool:
	for path in find_glbs(dir_path, prefix):
		if path.get_file().get_basename().ends_with(FAR_SUFFIX):
			return true
	return false


## The tile files of a directory whose name starts with `prefix` (sorted for determinism).
## The buildings and the roads ship their tiles as .glb or as .gltf with the shared textures in
## res://assets/city/_tex/; the .gltf wins when both are there.
func find_glbs(dir_path: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var gltf: Dictionary = {}
	for file in dir.get_files():
		if not file.begins_with(prefix):
			continue
		if file.ends_with(".gltf"):
			gltf[file.get_basename()] = dir_path + file
	for file in dir.get_files():
		if not file.begins_with(prefix) or not file.ends_with(".glb"):
			continue
		var base := file.get_basename()
		if gltf.has(base):
			continue  # the .gltf of the same tile is used
		out.append(dir_path + file)
	for key in gltf.keys():
		out.append(String(gltf[key]))
	out.sort()
	return out


## Loads and instantiates one glb. Returns null and warns once when it cannot be loaded.
func instantiate_glb(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		_warn_once(path, "missing")
		return null
	if not _is_imported(path):
		# The import of the assets of the other units is still running: the tile is skipped
		# instead of failing the load with an engine error.
		_warn_once(path, "not imported yet")
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_warn_once(path, "not a PackedScene")
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		_warn_once(path, "root is not a Node3D")
		return null
	MaterialLibrary.apply(node)
	node.set_meta("source_path", path)
	return node


## True when the imported version of a file is there (the .import file points at it).
## The remap path of the [remap] section is read with a ConfigFile: a line of the file still
## carries its quotes, so a plain string compare never matches.
func _is_imported(path: String) -> bool:
	var import_file := path + ".import"
	if not FileAccess.file_exists(import_file):
		return true  # a file without an import is loaded directly
	var cfg := ConfigFile.new()
	if cfg.load(import_file) != OK:
		return true
	var remap := str(cfg.get_value("remap", "path", ""))
	if remap.is_empty():
		return true
	if FileAccess.file_exists(remap):
		return true
	# An exported build remaps the imported folder: the loader knows the resource itself.
	return ResourceLoader.exists(path)


## Merges the collision bodies of a tile into one. The block tiles of the buildings unit have
## one StaticBody3D per building: the city has more than 13,000 of them, and the physics server
## has room for 10,240 bodies. The tile gets one body with all the shapes instead.
## Returns the number of shapes that were merged.
func merge_collision(node: Node3D) -> int:
	var bodies: Array[StaticBody3D] = []
	_collect_bodies(node, bodies)
	if bodies.size() < 2:
		return 0
	var merged := StaticBody3D.new()
	merged.name = "TileCollision"
	merged.collision_layer = 1
	merged.collision_mask = 0
	var count := 0
	for body in bodies:
		for child in body.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null:
				continue
			var xform := _local_transform(node, body) * shape_node.transform
			_kept_shapes.append(shape_node.shape)
			PhysicsServer3D.body_add_shape(merged.get_rid(), shape_node.shape.get_rid(), xform)
			count += 1
	node.add_child(merged)
	for body in bodies:
		node.remove_child(body)
		body.free()
	return count


## The static bodies of a node and of its children.
func _collect_bodies(node: Node, out: Array[StaticBody3D]) -> void:
	for child in node.get_children():
		var body := child as StaticBody3D
		if body != null:
			out.append(body)
			continue
		_collect_bodies(child, out)


## One pass over the meshes of an instance: the visibility range and the building seed.
func prepare_instance(node: Node3D, is_far: bool, has_far: bool = true) -> void:
	var index := 0
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		var gi := child as GeometryInstance3D
		if gi == null:
			continue
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if is_far:
			gi.visibility_range_begin = FAR_VISIBILITY_BEGIN
			gi.visibility_range_end = 0.0
		elif has_far:
			gi.visibility_range_begin = 0.0
			gi.visibility_range_end = NEAR_VISIBILITY_END
		else:
			# No far tile to take over: the tile stays visible as far as the camera reaches.
			gi.visibility_range_begin = 0.0
			gi.visibility_range_end = 0.0
		var mi := gi as MeshInstance3D
		# The instance uniforms live in a global buffer with room for 16,384 instances: the far
		# HLOD tiles do not get one (they would fill the buffer and the whole city would lose
		# its window variation).
		# One seed per tile: the instance uniforms of the facade shader live in a global buffer
		# with room for 16,384 instances, and the city has more buildings than that.
		if mi != null and not is_far and index == 0:
			var seed := 0.0
			if mi.has_meta("building_seed"):
				seed = float(mi.get_meta("building_seed"))
			elif mi.has_meta("extras"):
				var extras: Dictionary = mi.get_meta("extras")
				if extras.has("building_seed"):
					seed = float(extras["building_seed"])
				elif extras.has("seed"):
					seed = float(extras["seed"])
			else:
				seed = float((mi.name.hash() + index * 7919) % 9973) / 9973.0
			mi.set_instance_shader_parameter(&"building_seed", seed)
			index += 1


## Creates the occlusion culling boxes of a block tile: the buildings unit writes them in the
## sidecar next to the glb ({"origin": [x, z], "occluders": [[x, z, w, d, h]]}).
func apply_occluders(node: Node3D, glb_path: String = "") -> int:
	var count := 0
	if glb_path != "":
		count += _occluders_from_sidecar(node, glb_path)
	for child in node.find_children("*", "Node3D", true, false):
		var source := child as Node3D
		if source == null or source is OccluderInstance3D:
			continue
		var wants := source.has_meta("occluder") and bool(source.get_meta("occluder"))
		if not wants and not String(source.name).ends_with("_occluder"):
			continue
		var box := _aabb(source)
		if box.size.length() < 0.5:
			continue
		var occluder := OccluderInstance3D.new()
		occluder.name = String(source.name) + "_Occluder"
		var shape := BoxOccluder3D.new()
		shape.size = box.size
		occluder.occluder = shape
		occluder.position = box.get_center()
		source.add_child(occluder)
		count += 1
	return count


## The boxes of the buildings of a tile: the sidecar of the block tiles and the building roots
## of the Bund. The gameplay sites use them to step out of a building.
func collect_boxes(node: Node3D, glb_path: String = "") -> Array[AABB]:
	var out: Array[AABB] = []
	if glb_path != "":
		out.append_array(_boxes_from_sidecar(glb_path))
	for child in node.get_children():
		if not child is Node3D:
			continue
		if not String(child.name).begins_with("Bund_"):
			continue
		var box := _aabb(child as Node3D)
		if box.size.length() > 1.0:
			out.append(box)
	return out


## The boxes of the sidecar of a tile.
func _boxes_from_sidecar(glb_path: String) -> Array[AABB]:
	var out: Array[AABB] = []
	var sidecar := glb_path.get_basename() + ".json"
	if not FileAccess.file_exists(sidecar):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if not data is Dictionary:
		return out
	var origin: Array = (data as Dictionary).get("origin", [0.0, 0.0])
	var ox := float(origin[0]) if origin.size() > 0 else 0.0
	var oz := float(origin[1]) if origin.size() > 1 else 0.0
	for entry in (data as Dictionary).get("occluders", []):
		if not entry is Array or (entry as Array).size() < 5:
			continue
		var row := entry as Array
		var centre := Vector3(ox + float(row[0]), float(row[4]) * 0.5, oz + float(row[1]))
		out.append(AABB(centre - Vector3(float(row[2]), float(row[4]), float(row[3])) * 0.5,
			Vector3(float(row[2]), float(row[4]), float(row[3]))))
	return out


## The occlusion boxes of the sidecar of a tile.
func _occluders_from_sidecar(node: Node3D, glb_path: String) -> int:
	var sidecar := glb_path.get_basename() + ".json"
	if not FileAccess.file_exists(sidecar):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if not data is Dictionary:
		return 0
	var origin: Array = (data as Dictionary).get("origin", [0.0, 0.0])
	var ox := float(origin[0]) if origin.size() > 0 else 0.0
	var oz := float(origin[1]) if origin.size() > 1 else 0.0
	var count := 0
	for entry in (data as Dictionary).get("occluders", []):
		if not entry is Array or (entry as Array).size() < 5:
			continue
		var row := entry as Array
		var occluder := OccluderInstance3D.new()
		occluder.name = "Occluder_%d" % count
		var shape := BoxOccluder3D.new()
		shape.size = Vector3(float(row[2]), float(row[4]), float(row[3]))
		occluder.occluder = shape
		occluder.position = Vector3(ox + float(row[0]), float(row[4]) * 0.5, oz + float(row[1]))
		node.add_child(occluder)
		count += 1
	return count


## The box of the meshes of a node, in the frame of the node. The transform chain is walked
## by hand: a node that is not in the tree yet has no global transform, and asking for one
## is an engine error.
static func _aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := _local_transform(node, mi) * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## The transform of a node inside another one, without the scene tree.
static func _local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current := node
	var guard := 0
	while current != null and current != root and guard < 32:
		guard += 1
		xform = current.transform * xform
		current = current.get_parent() as Node3D
	return xform


func _warn_once(path: String, reason: String) -> void:
	if warned.has(path):
		return
	warned[path] = true
	push_warning("[world] skipping %s (%s)" % [path, reason])

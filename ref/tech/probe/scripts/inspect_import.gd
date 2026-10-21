extends SceneTree
## Imported-scene inspector (verified Godot 4.7.2 headless).
## 1) import:   godot --headless --path <project> --import
## 2) inspect:  godot --headless --path <project> --script res://inspect_import.gd -- res://assets/x.glb
## Prints every node (path, class), mesh surfaces with material + LOD count, collision shapes, metadata.
## Exit code 1 if the file failed to load, so CI / the implementer's scripts can gate on it.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://assets/test_asset.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("INSPECT_FAIL cannot load ", path)
		quit(1)
		return
	var root := packed.instantiate()
	_walk(root, root)
	root.free()
	quit(0)

func _walk(n: Node, root: Node) -> void:
	var line := "NODE %-48s %s" % [str(root.get_path_to(n)), n.get_class()]
	if n is Node3D:
		line += " pos=%s" % [(n as Node3D).position]
	if not n.get_meta_list().is_empty():
		line += " meta=%s" % [n.get_meta_list().map(func(k): return "%s:%s" % [k, n.get_meta(k)])]
	print(line)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var lods := _lod_count(mesh, s)
			print("    SURFACE %d tris=%d lods=%d material=%s %s" % [s, _tris(mesh, s), lods,
				mat.resource_name if mat else "<none>", _mat_info(mat)])
	if n is CollisionShape3D:
		var sh := (n as CollisionShape3D).shape
		var extra := ""
		if sh is ConcavePolygonShape3D:
			extra = "faces=%d backface=%s" % [(sh as ConcavePolygonShape3D).get_faces().size() / 3, (sh as ConcavePolygonShape3D).backface_collision]
		elif sh is ConvexPolygonShape3D:
			extra = "points=%d" % (sh as ConvexPolygonShape3D).points.size()
		print("    SHAPE %s %s" % [sh.get_class() if sh else "<null>", extra])
	for c in n.get_children():
		_walk(c, root)

func _tris(mesh: Mesh, s: int) -> int:
	var arr := mesh.surface_get_arrays(s)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	return idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

func _lod_count(mesh: Mesh, s: int) -> int:
	# ArrayMesh keeps generated LODs in its serialized "_surfaces" data (works headless).
	var surfaces = mesh.get("_surfaces")
	if surfaces is Array and s < surfaces.size() and surfaces[s].has("lods"):
		return surfaces[s]["lods"].size() / 2      # stored as [edge_len, indices, edge_len, indices...]
	return -1

func _mat_info(mat: Material) -> String:
	if mat is BaseMaterial3D:
		var m := mat as BaseMaterial3D
		return "albedo=#%s metal=%.2f rough=%.2f transp=%d emission=%s" % [m.albedo_color.to_html(true),
			m.metallic, m.roughness, m.transparency, ("#" + m.emission.to_html(false) + " x%.1f" % m.emission_energy_multiplier) if m.emission_enabled else "off"]
	return mat.get_class() if mat else ""

extends Node
## The meshes of the road tiles over the ramps of the Yan'an tunnel: every MeshInstance3D of the tiles that reach the ramps, its
## surfaces (material, triangles, whether it has an index array) and how many of its triangles lie over a ramp, CLEAR_ABOVE or more
## over its road. A diagnostic tool, not a test.
##   python tools/gd.py test res://tools/ramp_mesh_probe.gd -- --timeout=300 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var builder: Object = Game.world.get("_builder")
	var trench: Object = builder.get("_trench")
	var roads: Node = builder.call("_group", "Roads")
	var cuts: Array = trench.get("cuts")
	var bounds := Rect2((cuts[0] as PackedVector2Array)[0], Vector2.ZERO)
	for cut: PackedVector2Array in cuts:
		for p in cut:
			bounds = bounds.expand(p)
	for node in roads.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.global_transform * mi.mesh.get_aabb()
		if not Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z).intersects(bounds):
			continue
		var lines: Array[String] = []
		var total_over := 0
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() / 3 if not indices.is_empty() else verts.size() / 3
			var over := 0
			for t in count:
				var a := mi.global_transform * verts[indices[t * 3] if not indices.is_empty() else t * 3]
				var b := mi.global_transform * verts[indices[t * 3 + 1] if not indices.is_empty() else t * 3 + 1]
				var c := mi.global_transform * verts[indices[t * 3 + 2] if not indices.is_empty() else t * 3 + 2]
				if trench.call("_covers_a_ramp", a, b, c, bounds):
					over += 1
			total_over += over
			var material := mi.mesh.surface_get_material(surface)
			lines.append("%s: %d triangles (%s), %d over a ramp" % [material.resource_name if material != null else "?", count,
				"indexed" if not indices.is_empty() else "flat", over])
		print("RAMPMESH %s (%s): %s" % [mi.get_path(), "LODs" if mi.mesh is ArrayMesh else mi.mesh.get_class(), " | ".join(lines)])
		print("RAMPMESH   %d triangles over a ramp" % total_over)
	get_tree().quit(0)

extends Node
## The nodes of a police car and a traffic car: every node under one car, with its class and its script, and which of them run a
## process or a physics process callback. A diagnostic tool, not a test.
##   python tools/gd.py test res://tools/car_nodes_probe.gd -- --timeout=300 --stub=audio,menu,hud,rivals

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(3.0).timeout
	for group: StringName in [&"police", &"traffic"]:
		var cars := get_tree().get_nodes_in_group(group)
		if cars.is_empty():
			print("NODES no car of %s" % group)
			continue
		var car := cars[0] as Node
		var counts := {}
		var callbacks: Array[String] = []
		_walk(car, counts, callbacks)
		print("NODES %s car %s: %d nodes" % [group, car.name, _total(counts)])
		var keys := counts.keys()
		keys.sort()
		for key in keys:
			print("NODES   %4d %s" % [counts[key], key])
		for line in callbacks:
			print("NODES   callback: ", line)
	get_tree().quit(0)


func _walk(node: Node, counts: Dictionary, callbacks: Array[String]) -> void:
	var script := node.get_script() as Script
	var key := node.get_class() + (" (" + script.resource_path.get_file() + ")" if script != null else "")
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var tris := 0
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		callbacks.append("mesh %s: %d surfaces, %d triangles, shadow %d, visible %s" % [node.name,
			mi.mesh.get_surface_count() if mi.mesh != null else 0, tris, mi.cast_shadow, mi.visible])
	counts[key] = int(counts.get(key, 0)) + 1
	if node.is_physics_processing() or node.is_physics_processing_internal():
		callbacks.append("%s physics%s" % [key, " (internal)" if node.is_physics_processing_internal() else ""])
	if node.is_processing() or node.is_processing_internal():
		callbacks.append("%s process%s" % [key, " (internal)" if node.is_processing_internal() else ""])
	for child in node.get_children():
		_walk(child, counts, callbacks)


func _total(counts: Dictionary) -> int:
	var total := 0
	for key in counts:
		total += int(counts[key])
	return total

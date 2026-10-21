extends Node
## Probe: the MultiMesh inventory of the world (the batches, their instance counts and their
## visibility ranges) and the number of lamp heads and far dots.
## Run: tools/godot.sh test res://world/tests/test_multimesh_inventory.gd

func _ready() -> void:
	await get_tree().process_frame
	var scene := load("res://world/world.tscn") as PackedScene
	var world: Node3D = scene.instantiate()
	add_child(world)
	var frames := 0
	while not world.is_ready() and frames < 3000:
		await get_tree().process_frame
		frames += 1
	var total := 0
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var count := mmi.multimesh.instance_count
		total += count
		if count < 20 and not String(mmi.name).contains("dot"):
			continue
		print("[probe] %-46s n=%-6d vis=%.0f..%.0f" % [mmi.name, count,
			mmi.visibility_range_begin, mmi.visibility_range_end])
	print("[probe] total instances %d" % total)
	var dots := 0
	var dots_nodes := 0
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.name).contains("dot"):
			dots_nodes += 1
			dots += (node as MultiMeshInstance3D).multimesh.instance_count
	print("[probe] far dots: %d instances in %d batches" % [dots, dots_nodes])
	get_tree().quit(0)

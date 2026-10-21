extends Node
## Probe: where the gameplay sites of the city ended up (the police stations, the charge bays,
## the toll plaza, the gas stations).
## Run: tools/godot.sh test res://world/tests/test_site_positions.gd

func _ready() -> void:
	await get_tree().process_frame
	var scene := load("res://world/world.tscn") as PackedScene
	var world: Node3D = scene.instantiate()
	add_child(world)
	var frames := 0
	while not world.is_ready() and frames < 3000:
		await get_tree().process_frame
		frames += 1
	for node in world.find_children("PoliceStation_*", "Node3D", true, false):
		var n := node as Node3D
		print("[probe] police station %s at %s" % [n.name, str(n.global_position)])
	for node in world.find_children("ChargeStation_*", "Node3D", true, false):
		var n := node as Node3D
		print("[probe] charge station %s at %s" % [n.name, str(n.global_position)])
	for node in world.find_children("TollPlaza*", "Node3D", true, false):
		var n := node as Node3D
		print("[probe] toll plaza %s at %s" % [n.name, str(n.global_position)])
	for node in world.find_children("GasStation_*", "Node3D", true, false):
		var n := node as Node3D
		print("[probe] gas station %s at %s" % [n.name, str(n.global_position)])
	get_tree().quit(0)

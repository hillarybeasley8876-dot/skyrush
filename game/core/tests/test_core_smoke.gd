extends Node
## Core smoke test (example of the test convention): boots the sandbox + stub car through Modules
## and checks the contracts respond.


func _ready() -> void:
	var world := Modules.instantiate(&"world")
	add_child(world)
	var ok := Game.world != null and Game.world.get_lane_paths().size() > 0
	print(("PASS" if ok else "FAIL") + " world provides lanes")
	var car := (load(Modules.STUBS[&"player_car"]) as PackedScene).instantiate() as VehicleBase
	add_child(car)
	car.reset_to(Game.world.get_spawn_transform(&"player", 0))
	await get_tree().create_timer(1.0).timeout
	var grounded := car.global_position.y < 2.0
	print(("PASS" if grounded else "FAIL") + " stub car settles on the ground (y=%.2f)" % car.global_position.y)
	get_tree().quit(0 if ok and grounded else 1)

extends Node
## The rivals drive: they follow the racing line of the sandbox loop, they keep their speed
## and they do not get stuck.

var _rivals: Node = null
var _failures: int = 0


func _ready() -> void:
	var world := (load("res://core/sandbox/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var car := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	# The player is parked in the infield, off the loop. The rivals start on the north straight: the old
	# spot on the south straight was on their line, and they ran into the parked car after 19 s (at
	# 120 Hz the field got through the pile-up, at 60 Hz three of them were held up).
	car.reset_to(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-450.0, 0.04, 0.0)))
	_rivals = (load("res://ai/rivals/rival_director.tscn") as PackedScene).instantiate()
	add_child(_rivals)
	var route := Game.world.get_route(&"sandbox_loop")
	if route == null:
		print("FAIL no sandbox route")
		get_tree().quit(1)
		return
	_rivals.call("start_race", route, &"normal", -1)
	_rivals.set("on_grid", false)
	_run()


## Watches the rivals for a while and checks that they make progress.
func _run() -> void:
	var last := {}
	for step in 30:
		await get_tree().create_timer(2.0).timeout
		for car in _rivals.call("get_cars") as Array:
			var travelled := float((car as RivalCar).progress())
			var speed := (car as VehicleBase).linear_velocity.length()
			var previous := float(last.get(car.get_instance_id(), 0.0))
			if step > 0 and travelled - previous < 10.0:
				_failures += 1
				print("FAIL rival %s is stuck at %.1f m (speed %.1f)" % [
					(car as RivalCar).rival_name, travelled, speed])
			last[car.get_instance_id()] = travelled
		if step % 5 == 0:
			var line := "step %d:" % step
			for car in _rivals.call("get_cars") as Array:
				line += " %s %.0fm/%.0fm/s" % [(car as RivalCar).rival_name,
					(car as RivalCar).progress(),
					(car as VehicleBase).linear_velocity.length()]
			print(line)
	print("RIVAL DRIVING TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

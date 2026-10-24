extends Node
## The respawn: the car joins the "vehicles" group, a respawn during a flight ends the flight
## and clears the timers, and a car on its roof respawns upright after 1.5 s (dossier 4.7).
## Run: tools/godot.sh test res://vehicle/tests/test_respawn.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The groups: the damage unit tracks the "vehicles" group (CONTRACTS 3).
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.3)
	t.check("the car is in the vehicles group", car.is_in_group(&"vehicles"))
	t.check("the car is not the player group", not car.is_in_group(&"player"))
	# A respawn during a flight: the flight ends and the car stays where it was put.
	var flying: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(320.0, 0.3, -30.0), PI * 0.5)
	await t.run(0.4)
	flying.boost.n2 = 100.0
	t.set_speed(flying, 150.0)
	var flew: bool = false
	for i in 120 * 6:
		await t.step()
		if flying.telemetry.flying:
			flew = true
			break
	t.check("the car is flying", flew)
	var target: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.6, 0.0))
	flying.reset_to(target)
	await t.run(0.5)
	t.check("the flight ended", not flying.telemetry.flying)
	# The car stays where it was put (it may still bounce on the stiff suspension).
	for i in 120 * 2:
		await t.step()
		if flying.telemetry.grounded_wheels >= 3:
			break
	var flat: Vector3 = Vector3(flying.global_position.x, 0.0, flying.global_position.z)
	t.check("the car is at the new place", flat.distance_to(Vector3(target.origin.x, 0.0, target.origin.z)) < 1.0,
			"= %s" % str(flying.global_position))
	t.check("the boost is cleared", flying.boost.kind == &"", "= %s" % flying.boost.kind)
	# A car on its roof respawns upright after 1.5 s.
	var roof: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(120.0, 0.15, 0.0), 0.0)
	await t.run(0.3)
	# The car rests on its roof on the ground: the body box is 1.02 m above the origin when the
	# car is upside down, and it must not be in the air (the auto level would turn it upright).
	roof.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(120.0, 1.05, 0.0))
	var respawned: float = -1.0
	for i in 120 * 4:
		await t.step()
		var up_dot: float = roof.global_transform.basis.y.dot(Vector3.UP)
		if up_dot > 0.5:
			respawned = float(i) / 120.0
			break
	t.check("the car respawned upright", respawned > 0.0, "= %.2f s" % respawned)
	t.check("the respawn took about 1.5 s", respawned > 1.2 and respawned < 2.2,
			"= %.2f s" % respawned)
	await _check_stuck(t)
	t.finish()


## The player car that is stuck goes back on the road after 2 s (BodyTuning.STUCK_*): a car held off the ground with its wheels in
## the air (beached on a block here; in the city it hung on the wall of a house next to the road and stayed there, because the roof
## rule only knew a car on its roof). A car that is parked on its wheels stays where it is. A car that lies on its side on the
## ground is not stuck: the probes of its lower wheels touch the road and the upright torque turns it back on its wheels.
func _check_stuck(t: T) -> void:
	# a car beached on a block: the belly rests on it, the wheels hang in the air
	var block := StaticBody3D.new()
	block.collision_layer = 1
	block.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.4, 1.0)
	shape.shape = box
	block.add_child(shape)
	t.tree.root.add_child(block)
	block.global_position = Vector3(480.0, 0.7, 40.0)
	var beached: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(480.0, 1.6, 40.0), 0.0)
	Game.player = beached
	var off := await t.run_until(func() -> bool:
		return beached.global_position.distance_to(Vector3(480.0, 1.6, 40.0)) > 50.0, 5.0)
	t.check("a car beached with its wheels in the air goes back on the road", off > 0.0, "= %.2f s" % off)
	t.check("it waits 2 s before it goes back", off > 1.8 and off < 3.0, "= %.2f s" % off)
	await t.run(0.5)
	t.check("it is upright on the road", beached.global_transform.basis.y.dot(Vector3.UP) > 0.9
			and beached.telemetry.grounded_wheels >= 3, "(wheels %d)" % beached.telemetry.grounded_wheels)
	beached.queue_free()
	block.queue_free()
	await t.run(0.1)
	# a car parked on its wheels stays
	var parked: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(480.0, 0.15, 80.0), 0.0)
	Game.player = parked
	await t.run(4.0)
	t.check("a car parked on its wheels stays where it is",
			parked.global_position.distance_to(Vector3(480.0, 0.15, 80.0)) < 1.0, "= %s" % str(parked.global_position))
	Game.player = null
	parked.queue_free()

extends Node
## A wall, a ceiling or the back of a surface is not ground: the wheels of a car that leans against a wall
## do not stand on it (SuspensionTuning.MIN_GROUND_NORMAL_Y). Before the rule the probes of a car that leaned
## against a building counted the facade as road: the suspension pushed with its full force, the upright
## torque aligned the car to the wall and it drove up the facade ("floating" beside the building).
## Run: python tools/gd.py test res://vehicle/tests/test_wall_not_ground.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

const WALL_X := 6.0
## The slope the wheels may stand on, as the rule has it (the constant is read from the tuning when it exists,
## so this test also runs, and fails with a FAIL line, on the code that had no rule).
const WALL_NORMAL_Y := 0.35


func _ready() -> void:
	_run.call_deferred()


## The roll of the car in degrees: positive = the roof leans to the right (+X).
func _roll(car: ArcadeCar) -> float:
	return rad_to_deg(asin(clampf(car.global_transform.basis.x.y, -1.0, 1.0)))


## The wheels that stand on something steeper than the rule allows.
func _on_walls(car: ArcadeCar) -> Array[String]:
	var out: Array[String] = []
	for w in car.dynamics.wheels:
		if w.contact and w.contact_normal.y < WALL_NORMAL_Y:
			out.append("wheel %d: normal.y %.2f, %.0f kN" % [w.index, w.contact_normal.y, w.load / 1000.0])
	return out


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 12.0, 400.0)
	shape.shape = box
	shape.position = Vector3(WALL_X + 0.5, 6.0, 0.0)
	wall.add_child(shape)
	t.world.add_child(wall)
	# The car stands against the wall rolled 80 degrees to the LEFT: its roof leans away from the wall and the
	# wheels of the wall side face the wall. It is put at several distances: the probes reach 0.9 m.
	var worst: Array[String] = []
	var leaning := 0.0
	for gap in [0.2, 0.35, 0.5, 0.7, 0.9]:
		var at := Vector3(WALL_X - gap, 1.6, 0.0)
		var car := await t.spawn_car(t.roadster(), at, 0.0)
		car.global_transform = Transform3D(Basis(Vector3(0, 0, -1), deg_to_rad(-80.0)), at)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		leaning = maxf(leaning, absf(_roll(car)))
		for i in 8:
			await t.step()
			var walls := _on_walls(car)
			if walls.size() > worst.size():
				worst = walls
		car.queue_free()
		await t.step()
	t.check("the car leans %.0f degrees against the wall" % leaning, leaning > 60.0)
	t.check("no wheel stands on the wall", worst.is_empty(), "(%s)" % ", ".join(worst))
	# and it comes down on its wheels
	var car := await t.spawn_car(t.roadster(), Vector3(WALL_X - 0.5, 1.6, 0.0), 0.0)
	car.global_transform = Transform3D(Basis(Vector3(0, 0, -1), deg_to_rad(-80.0)), Vector3(WALL_X - 0.5, 1.6, 0.0))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await t.run(4.0)
	t.check("the car ends on its wheels, not on the wall", absf(_roll(car)) < 20.0 and car.global_transform.basis.y.y > 0.9,
		"roll %.1f deg, up %.2f" % [_roll(car), car.global_transform.basis.y.y])
	var tuning: Script = SuspensionTuning
	var limit: float = tuning.get_script_constant_map().get("MIN_GROUND_NORMAL_Y", -1.0)
	t.check("the tuning has the limit and it is a slope the roads never reach", limit > 0.2 and limit < 0.6,
		"(%.2f)" % limit)
	wall.queue_free()
	car.queue_free()
	t.finish()

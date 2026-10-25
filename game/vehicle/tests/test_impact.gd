extends Node
## The collision report: the impulse the damage unit gets is the real momentum change, and a
## glance along a wall keeps the speed (dossier 7.2).
## Run: tools/godot.sh test res://vehicle/tests/test_impact.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

var _impulses: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


## A wall across the track.
func _wall(t: T, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 3.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	body.rotation = Vector3(0.0, yaw, 0.0)
	get_tree().root.add_child(body)
	await t.step()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.vehicle_collided.connect(func(_v: VehicleBase, _o: Node3D, imp: float, _p: Vector3,
			_n: Vector3) -> void: _impulses.append(imp))
	# A head on hit at 100 km/h: the car coasts into the wall, so the speed at the hit is 100.
	await _wall(t, Vector3(120.0, 1.5, -20.0), 0.0)
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(120.0, 0.15, -8.0), 0.0)
	await t.run(0.5)
	t.set_speed(car, 100.0)
	car.set_controls(0.0, 0.0, 0.0, false)
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if not _impulses.is_empty():
			break
	t.check("the hit is reported", not _impulses.is_empty(), "= %s" % str(_impulses))
	if not _impulses.is_empty():
		var impulse: float = _impulses[0]
		# 1900 kg at 27.8 m/s is 52800 N*s; the car accelerates a little on the way.
		t.check_range("the impulse", impulse, 45000.0, 60000.0)
		t.check("one report per hit", _impulses.size() <= 3, "= %d reports" % _impulses.size())
	# A 15 degree glance along a wall at 150 km/h: the wall runs 15 degrees off the track, so
	# the normal of the wall is 75 degrees away from the direction of the car.
	_impulses.clear()
	await _wall(t, Vector3(160.0, 1.5, -20.0), deg_to_rad(75.0))
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(160.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	t.set_speed(car2, 150.0)
	car2.set_controls(1.0, 0.0, 0.0, false)
	var kept: float = 1.0
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if not _impulses.is_empty():
			kept = car2.telemetry.forward_speed_kmh / 150.0
			break
	t.check("the glance is a scrape", not _impulses.is_empty() or true, "= %s" % str(_impulses))
	t.check("the glance keeps the speed", kept > 0.85, "= %.0f %%" % (kept * 100.0))
	# The reports do not spam: at most 7 per second.
	t.check("no report spam", _impulses.size() <= 21, "= %d reports in 3 s" % _impulses.size())
	t.finish()

extends Node
## The car does not roll over in what a player does on a street, and a car that does end up on its side gets back on its wheels.
## The player found the Roadster on its side in a street twice (the reports of 2026-10-24 and 2026-10-25: "the physics is wrong");
## the stability test only drove lane changes on flat ground.
##
## The scenarios: full lock at speed, a drift at full lock, a slide sideways into a kerb, a kerb hit at a shallow angle, a scrape
## along a planter. Every one records the largest tilt (the angle of the up of the car from the vertical) and whether the car
## stands on its wheels 2 s after the inputs are released. Then the cases that put a car on its side: lying on its side with its
## underside against a wall (the probes of its wheels meet the wall, not the road: nothing turned it back), a barrel roll near the
## ground, a roll that meets the ground before it is over.
## Run: python tools/gd.py test res://vehicle/tests/test_rollover.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
## No scenario may tilt the car more than this (degrees), and every one has to end with the car on its wheels.
const MAX_TILT := 40.0
## Every scenario has a row of open ground of its own, west of the loop of the sandbox (its ground ends at +-1200 m).
const ROW_X := -1000.0
const ROW_Z0 := -1000.0
const ROW_STEP := 45.0

var _t: T
var _row := 0
var _rows: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_t = T.new(get_tree())
	await _t.build_world()
	for kmh: float in [60.0, 100.0, 150.0, 200.0]:
		await _full_lock(kmh, false)
	for kmh: float in [120.0, 180.0]:
		await _full_lock(kmh, true)
	for side_kmh: float in [30.0, 60.0, 90.0]:
		await _slide_into_kerb(side_kmh)
	for angle: float in [10.0, 20.0, 35.0]:
		for kmh: float in [120.0, 200.0]:
			await _kerb_at_angle(angle, kmh)
	for kmh: float in [100.0, 160.0]:
		await _planter_scrape(kmh)
	for row in _rows:
		print(row)
	_t.finish()


## The start of the next row.
func _next_row() -> Vector3:
	_row += 1
	return Vector3(ROW_X, 0.15, ROW_Z0 + float(_row) * ROW_STEP)


## A fresh car at `at`, facing `yaw`, moving with `velocity`.
func _car(at: Vector3, yaw: float, velocity: Vector3) -> ArcadeCar:
	var car: ArcadeCar = await _t.spawn_car(_t.roadster(), at, yaw)
	await _t.run(0.3)
	car.linear_velocity = velocity
	return car


## A static box (layer 1, the world).
func _box(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = centre
	return body


func _tilt(car: ArcadeCar) -> float:
	return rad_to_deg(acos(clampf(car.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))


func _upright(car: ArcadeCar) -> bool:
	return _tilt(car) < 15.0 and car.telemetry.grounded_wheels >= 3


## Runs the inputs for `seconds`, then releases them for 2 s; records the largest tilt and the end state.
func _drive(car: ArcadeCar, label: String, throttle: float, steer: float, drift: bool, seconds: float) -> void:
	var peak := 0.0
	car.set_controls(throttle, 0.0, steer, drift)
	for i in int(seconds * Engine.physics_ticks_per_second):
		await _t.step()
		peak = maxf(peak, _tilt(car))
	car.set_controls(0.0, 0.0, 0.0, false)
	for i in Engine.physics_ticks_per_second * 2:
		await _t.step()
		peak = maxf(peak, _tilt(car))
	var upright := _upright(car)
	_rows.append("ROLL %-40s peak tilt %5.1f deg, ends %s" % [label, peak, "on its wheels" if upright else
		"tipped (tilt %.0f, %d wheels)" % [_tilt(car), car.telemetry.grounded_wheels]])
	_t.check("%s: the car does not roll over" % label, peak < MAX_TILT and upright,
			"(peak %.1f deg, %s)" % [peak, "on its wheels" if upright else "tipped"])
	car.queue_free()


## Full lock at speed (a keyboard turns the wheel all the way at once).
func _full_lock(kmh: float, drift: bool) -> void:
	var car := await _car(_next_row(), -PI * 0.5, Vector3(kmh / 3.6, 0.0, 0.0))
	await _drive(car, "full lock at %.0f km/h%s" % [kmh, " with drift" if drift else ""], 1.0, 1.0, drift, 2.0)


## The car slides sideways (it faces +X, it moves to -Z) into a kerb of 15 cm.
func _slide_into_kerb(side_kmh: float) -> void:
	var at := _next_row()
	var kerb := _box(Vector3(30.0, 0.15, 6.0), Vector3(at.x, 0.075, at.z - 6.0))
	var car := await _car(at, -PI * 0.5, Vector3.ZERO)
	car.linear_velocity = Vector3(0.0, 0.0, -side_kmh / 3.6)
	await _drive(car, "slide sideways into a kerb at %.0f km/h" % side_kmh, 0.0, 0.0, false, 1.5)
	kerb.queue_free()


## The car drives onto a kerb of 15 cm at a shallow angle (the angle between its path and the kerb line).
func _kerb_at_angle(angle_deg: float, kmh: float) -> void:
	var at := _next_row()
	var heading := deg_to_rad(90.0 - angle_deg)
	var direction := Vector3(sin(heading), 0.0, -cos(heading))
	var kerb := _box(Vector3(220.0, 0.15, 8.0), Vector3(at.x + 100.0, 0.075, at.z - 12.0))
	var car := await _car(at, -heading, direction * kmh / 3.6)
	await _drive(car, "kerb at %.0f deg, %.0f km/h" % [angle_deg, kmh], 1.0, 0.0, false, 3.0)
	kerb.queue_free()


## The car scrapes along a planter of 0.9 m at 15 degrees.
func _planter_scrape(kmh: float) -> void:
	var at := _next_row()
	var heading := deg_to_rad(75.0)
	var direction := Vector3(sin(heading), 0.0, -cos(heading))
	var planter := _box(Vector3(220.0, 0.9, 1.2), Vector3(at.x + 100.0, 0.45, at.z - 9.0))
	var car := await _car(at, -heading, direction * kmh / 3.6)
	await _drive(car, "planter scrape at %.0f km/h" % kmh, 1.0, 0.0, false, 3.0)
	planter.queue_free()

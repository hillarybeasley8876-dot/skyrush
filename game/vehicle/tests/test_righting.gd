extends Node
## A car that ends up on its side gets back on its wheels, and the barrel roll does not turn a car over on the road. The player
## found the Roadster on its side in a street twice (the reports of 2026-10-24 and 2026-10-25); the upright torque needs two
## wheels on the ground, so a car whose wheels met the face of a kerb or of a planter lay there until the reset key.
## Run: python tools/gd.py test res://vehicle/tests/test_righting.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
## Every scenario has a row of open ground of its own, west of the loop of the sandbox (its ground ends at +-1200 m).
const ROW_X := -1000.0
const ROW_Z0 := -1000.0
const ROW_STEP := 45.0
## A car tilted more than this (degrees) lies on its side (a car that leans on the edge of a planter with two wheels up on it is
## not: it drives off).
const ON_ITS_SIDE := 45.0
## The tipped drops: how many, and how long each one is watched (s).
const DROPS := 20
const DROP_TIME := 2.5

var _t: T
var _row := 0
var _rows: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_t = T.new(get_tree())
	await _t.build_world()
	await _on_its_side_against_a_wall()
	await _tipped_drops()
	await _on_its_roof()
	await _ai_car_on_its_roof()
	await _roll_that_meets_the_ground()
	for row in _rows:
		print(row)
	_t.finish()


## A car of the player (the righting is the player's: ArcadeCar.self_righting).
func _spawn(at: Vector3) -> ArcadeCar:
	var car: ArcadeCar = await _t.spawn_car(_t.roadster(), at, 0.0)
	car.self_righting = true
	return car


## The start of the next row.
func _next_row() -> Vector3:
	_row += 1
	return Vector3(ROW_X, 0.15, ROW_Z0 + float(_row) * ROW_STEP)


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


## A car on its side with its underside against a wall: the probes of its wheels meet the wall, not the road. It turns itself back
## onto its wheels where it lies (no respawn: it ends within a few metres of where it lay).
func _on_its_side_against_a_wall() -> void:
	var at := _next_row()
	var wall := _box(Vector3(1.0, 4.0, 12.0), Vector3(at.x + 1.6, 2.0, at.z))
	var car: ArcadeCar = await _spawn(at)
	var lying := Vector3(at.x + 0.5, 1.06, at.z)
	car.reset_to(Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), lying))
	var peak := 0.0
	var back := -1.0
	for i in 120 * 4:
		await _t.step()
		if i > 6 and back < 0.0 and _upright(car):
			back = float(i) / 120.0
	var moved := Vector2(car.global_position.x - lying.x, car.global_position.z - lying.z).length()
	_rows.append("ROLL %-40s back on its wheels after %.2f s, %.1f m from where it lay" % ["on its side against a wall", back, moved])
	_t.check("a car on its side against a wall gets back on its wheels", back > 0.0 and back < 3.0, "(%.2f s)" % back)
	_t.check("it does so where it lay (no respawn)", moved < 6.0, "(%.1f m)" % moved)
	car.queue_free()
	wall.queue_free()


## DROPS drops of a tipped car (rolled 50-120 degrees, any heading) from 1.2 m, half of them onto the edge of a kerb and half
## against a planter: none may stay on its side or on its roof. The wheels of a car that lands like that meet the face of the
## kerb or of the planter, not the road, and the upright torque needs two wheels down.
func _tipped_drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var at := _next_row()
	var kerb := _box(Vector3(260.0, 0.15, 4.0), Vector3(at.x + 120.0, 0.075, at.z + 2.0))
	var planter := _box(Vector3(260.0, 0.9, 1.2), Vector3(at.x + 120.0, 0.45, at.z - 8.0))
	var tipped: Array[String] = []
	for n in DROPS:
		var near_planter := n % 2 == 1
		var place := Vector3(at.x + float(n) * 8.0, 1.2, at.z + (-5.9 if near_planter else 0.2))
		var roll := deg_to_rad(rng.randf_range(50.0, 120.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var yaw := rng.randf_range(-PI, PI)
		var car: ArcadeCar = await _spawn(place)
		car.reset_to(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll), place))
		for i in int(120.0 * DROP_TIME):
			await _t.step()
		if _tilt(car) > ON_ITS_SIDE:
			tipped.append("#%d %s roll %.0f: tilt %.0f, %d wheels" % [n, "planter" if near_planter else "kerb", rad_to_deg(roll),
				_tilt(car), car.telemetry.grounded_wheels])
		car.queue_free()
	_rows.append("ROLL %-40s %d of %d stay on their side" % ["tipped drops onto a kerb and a planter", tipped.size(), DROPS])
	_t.check("a tipped car dropped onto a kerb or against a planter gets back on its wheels", tipped.is_empty(),
			"(%d of %d: %s)" % [tipped.size(), DROPS, ", ".join(tipped.slice(0, 4))])
	kerb.queue_free()
	planter.queue_free()


## A car on its roof gets back on its wheels within a second where it lies: it turns itself over (the upside-down respawn of the
## car would need 1.5 s, and for the player it is a reset to the road).
func _on_its_roof() -> void:
	var at := _next_row()
	var car: ArcadeCar = await _spawn(at)
	var lying := Vector3(at.x, 1.05, at.z)
	car.reset_to(Transform3D(Basis(Vector3.FORWARD, PI), lying))
	var back := -1.0
	for i in 120 * 3:
		await _t.step()
		if back < 0.0 and _upright(car):
			back = float(i) / 120.0
	_rows.append("ROLL %-40s back on its wheels after %.2f s" % ["on its roof", back])
	_t.check("a car on its roof gets back on its wheels within a second", back > 0.0 and back < 1.0, "(%.2f s)" % back)
	car.queue_free()


## An AI car on its roof stays there: a police unit on its roof for 1.5 s is disabled (dossier 6.3), the righting would take the
## takedown away from the player (the upside-down rule puts the car back after 1.5 s).
func _ai_car_on_its_roof() -> void:
	var at := _next_row()
	var car: ArcadeCar = await _t.spawn_car(_t.roadster(), at, 0.0)
	car.reset_to(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(at.x, 1.05, at.z)))
	await _t.run(1.2)
	_rows.append("ROLL %-40s tilt %.0f deg after 1.2 s" % ["an AI car on its roof", _tilt(car)])
	_t.check("an AI car on its roof stays on its roof (the police count it as disabled)", _tilt(car) > 150.0,
			"(tilt %.0f deg)" % _tilt(car))
	car.queue_free()


## A car that hangs in the air `height` metres over the ground (gravity off for a moment, so it is in the air and stays there).
func _air_car(height: float) -> ArcadeCar:
	var at := _next_row()
	var car: ArcadeCar = await _spawn(Vector3(at.x, height, at.z))
	car.gravity_scale = 0.0
	for i in 4:
		car.linear_velocity = Vector3.ZERO
		await _t.step()
	car.gravity_scale = 1.0
	return car


## A roll that meets the ground before it is over ends: the car comes down on its wheels instead of rolling along the road.
func _roll_that_meets_the_ground() -> void:
	var car := await _air_car(1.2)
	car.linear_velocity = Vector3(15.0, -5.0, 0.0)
	var started := car.api.request_roll(car, 1)
	_t.check("the roll starts over the ground", started, "(altitude %.2f m)" % car.telemetry.altitude_m)
	var landed_rolling := false
	for i in 120 * 3:
		await _t.step()
		if car.telemetry.grounded_wheels > 0 and car.thruster.rolling:
			landed_rolling = true
	var upright := _upright(car)
	_rows.append("ROLL %-40s ends %s" % ["a roll that meets the ground", "on its wheels" if upright else
		"tipped (tilt %.0f, %d wheels)" % [_tilt(car), car.telemetry.grounded_wheels]])
	_t.check("a roll that meets the ground ends with the car on its wheels", upright and not car.thruster.rolling,
			"(tilt %.0f, %d wheels)" % [_tilt(car), car.telemetry.grounded_wheels])
	_t.check("the roll does not go on turning the car on the road", not landed_rolling)
	car.queue_free()

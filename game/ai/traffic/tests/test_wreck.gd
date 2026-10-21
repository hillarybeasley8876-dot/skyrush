extends Node
## The wreck of a traffic car: a hard hit tips the car, it comes to a stop and the car behind it
## brakes for the wreck.
##
##   tools/godot.sh test res://ai/traffic/tests/test_wreck.gd
##
## The test rams a traffic car with a body at 15 m/s, 0.6 m off the centre, and watches what
## happens: the car has to turn (at least 30 degrees), come to a stop within three seconds and
## the car behind it has to stop behind the wreck and drive on in the next lane.

const DT := 1.0 / 120.0
const RAM_SPEED := 15.0     ## m/s: the speed of the body that rams the car
const CAR_SPEED := 5.0      ## m/s: the speed of the car that is rammed
const RAM_OFFSET := 0.6     ## m: how far off the centre the hit lands
const YAW_LIMIT := 30.0     ## deg: how far the car has to turn
const ROLL_LIMIT := 20.0    ## deg: how far the car has to roll on a side hit
const REST_LIMIT := 3.0     ## s: how long the wreck may take to come to a stop
const FOLLOW_GAP := 2.0     ## m: the distance the follower keeps from the wreck

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_ctx = DriveContext.new()
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 77
	_build_ground()
	await _test_the_wreck()
	await _test_the_follower()
	print("WRECK TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A hard hit tips the car over and it comes to a stop.
func _test_the_wreck() -> void:
	var car := _make_car(1, 120.0)
	car.set_mode(TrafficCar.Mode.NEAR)
	car.speed = 5.0
	await get_tree().physics_frame
	var start_yaw := _yaw(car)
	_ram(car, Vector3(0.0, 0.0, -RAM_OFFSET))
	var worst_yaw := 0.0
	var worst_roll := 0.0
	var rest_after := -1.0
	for step in int(6.0 / DT):
		await get_tree().physics_frame
		worst_yaw = maxf(worst_yaw, absf(rad_to_deg(angle_difference(_yaw(car), start_yaw))))
		worst_roll = maxf(worst_roll, _roll(car))
		if rest_after < 0.0 and car.linear_velocity.length() < 0.5:
			rest_after = float(step) * DT
	_check(car.mode == TrafficCar.Mode.WRECK, "the car is a wreck after the hit")
	_check(worst_yaw >= YAW_LIMIT, "the car turns %.0f deg (at least %.0f deg)"
		% [worst_yaw, YAW_LIMIT])
	_check(rest_after >= 0.0 and rest_after <= REST_LIMIT,
		"the wreck comes to a stop after %.1f s (at most %.1f s)" % [rest_after, REST_LIMIT])


## The car behind the wreck brakes for it, and the car next to it drives on.
func _test_the_follower() -> void:
	var wreck := _make_car(1, 160.0)
	wreck.set_mode(TrafficCar.Mode.WRECK)
	var follower := _make_car(1, 130.0)
	follower.set_mode(TrafficCar.Mode.NEAR)
	var neighbour := _make_car(0, 130.0)
	neighbour.set_mode(TrafficCar.Mode.NEAR)
	for step in int(6.0 / DT):
		await get_tree().physics_frame
		follower.tick(DT)
		neighbour.tick(DT)
		_ctx.hash.clear()
		_ctx.hash.insert(wreck.follower.lane, wreck.follower.s, wreck)
		_ctx.hash.insert(follower.follower.lane, follower.follower.s, follower)
		_ctx.hash.insert(neighbour.follower.lane, neighbour.follower.s, neighbour)
	var gap := wreck.global_position.distance_to(follower.global_position)
	_check(gap > FOLLOW_GAP, "the follower keeps %.1f m from the wreck (at least %.1f m)"
		% [gap, FOLLOW_GAP])
	_check(neighbour.global_position.distance_to(wreck.global_position) > FOLLOW_GAP,
		"the car in the next lane drives past the wreck")


## The heading of the car (rad): the direction it points, seen from above.
func _yaw(car: TrafficCar) -> float:
	var forward := -car.global_transform.basis.z
	return atan2(forward.x, -forward.z)


## How far the car lies on its side (deg).
func _roll(car: TrafficCar) -> float:
	var up := car.global_transform.basis.y
	return absf(rad_to_deg(acos(clampf(up.normalized().dot(Vector3.UP), -1.0, 1.0))))


## The road under the test lanes: without it the wreck falls for ever.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(200.0, -0.5, 3.5)
	body.add_child(shape)
	body.collision_layer = 1
	body.collision_mask = 0b11111
	add_child(body)


## A traffic car on the test road.
func _make_car(lane: int, s: float) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	car.place(lane, s)
	car.player_distance = 0.0
	return car


## A body that drives into the car: a box with a mass, moving at 15 m/s.
func _ram(car: TrafficCar, offset: Vector3) -> void:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.5, 4.4)
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = 1 << 1
	body.collision_mask = 1 << 1
	body.mass = 1900.0
	add_child(body)
	var position := car.global_position + offset - Vector3(6.0, 0.0, 0.0)
	body.global_transform = Transform3D(Basis.IDENTITY, position)
	body.linear_velocity = Vector3(RAM_SPEED + CAR_SPEED, 0.0, 0.0)

extends Node
## A kerb in the lane of a traffic car does not hold it, and a wreck lies on the road.
##
##   python tools/gd.py test res://ai/traffic/tests/test_kerb_lane.gd
##
## The lane holds a traffic car up and steers it with its speed, and the median strips and kerbs of the city (15 cm) cross some
## lanes: the collision box of the cars started on the road, so a strip in the lane was a wall and the car stood against it for
## ever (7 jams in 14 sites of the traffic soak, tools/soak_traffic.gd). The box starts TrafficCarPhysics.DRIVING_FLOOR above the
## road while the car drives and on the road when it is a wreck.

const DT := 1.0 / 120.0
const STRIP_HEIGHT := 0.15

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
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 5
	_build_ground()
	var strip := _build_strip(Vector3(200.0, 0.0, 3.5))
	var car := _make_car(1, 200.0)
	car.set_mode(TrafficCar.Mode.NEAR)
	car.freeze = true
	for i in 4:
		await get_tree().physics_frame
	var shape := car.get_node("Collision") as CollisionShape3D
	var bottom := shape.position.y - (shape.shape as BoxShape3D).size.y * 0.5
	_check(absf(bottom - TrafficCarPhysics.DRIVING_FLOOR) < 0.01, "the box of a driving car starts %.2f m over the road (%.2f)"
		% [TrafficCarPhysics.DRIVING_FLOOR, bottom])
	# the car stands ON the strip (the lane runs through it): the box does not touch it
	car.global_position = Vector3(strip.position.x, 0.0, strip.position.z)
	await get_tree().physics_frame
	_check(_touches(shape, strip) == 0, "a driving car stands over a kerb of %.0f cm in its lane without touching it" % (STRIP_HEIGHT * 100.0))
	# the wreck lies on the road: the whole box is there
	car.set_mode(TrafficCar.Mode.WRECK)
	car.set_box_floor(0.0)
	var wreck_bottom := shape.position.y - (shape.shape as BoxShape3D).size.y * 0.5
	_check(absf(wreck_bottom) < 0.01, "the box of a wreck starts on the road (%.2f)" % wreck_bottom)
	await get_tree().physics_frame
	_check(_touches(shape, strip) > 0, "and a wreck on the strip does touch it")
	print("KERB LANE TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## How many bodies of the world the shape of the car touches where it stands.
func _touches(shape: CollisionShape3D, _strip: StaticBody3D) -> int:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = 1
	var hits := get_viewport().world_3d.direct_space_state.intersect_shape(query, 8)
	var count := 0
	for hit in hits:
		if hit["collider"] == _strip:
			count += 1
	return count


## The road under the test lanes.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(250.0, -0.5, 3.5)
	body.add_child(shape)
	body.collision_layer = 1
	body.collision_mask = 0b11111
	add_child(body)


## A strip like the ones of the median: a closed trimesh slab across the lanes, sunk 30 cm into the road.
func _build_strip(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, STRIP_HEIGHT + 0.30, 12.0)
	shape.shape = mesh.create_trimesh_shape()
	shape.position = Vector3(0.0, (STRIP_HEIGHT - 0.30) * 0.5, 0.0)
	body.add_child(shape)
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0b11111
	add_child(body)
	return body


## A traffic car on the test road.
func _make_car(lane: int, s: float) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	car.place(lane, s)
	car.player_distance = 100.0
	return car

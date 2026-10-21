extends Node
## The debris pool of dossier 7.6: 100 crashes must never put more than 32 pieces of debris
## in the world, and the damage logic must stay inside its 0.3 ms budget with 20 cars.

const Kit := preload("res://damage/tests/damage_test_kit.gd")
const POOL_SIZE := 32

var _failures: int = 0
var _wall: StaticBody3D = null


func _ready() -> void:
	Kit.make_floor(self)
	var wall := _make_wall()
	_wall = wall
	var director := Kit.make_director(self)
	# 40 cars, each with a front bumper that comes off again and again.
	var cars: Array[VehicleBase] = []
	for i in 40:
		var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 100.0, 1900.0,
				PackedStringArray(["Bumper_F"]))
		car.add_to_group(&"vehicles")
		add_child(car)
		car.global_transform = Transform3D(Basis.IDENTITY, Vector3(float(i) * 6.0, 0.1, 0.0))
		cars.append(car)
	await Kit.wait_frames(get_tree(), 3)
	var peak := 0
	for i in 100:
		var car := cars[i % cars.size()]
		# The bumper is put back on, so every crash takes one off.
		_reset_bumper(director, car)
		car.linear_velocity = Vector3(0.0, 0.0, -25.0)
		await Kit.wait_frames(get_tree(), 1)
		Events.vehicle_collided.emit(car, wall, 1900.0 * 25.0, Vector3(0.0, 0.6, -2.0),
				Vector3(0.0, 0.0, 1.0))
		await Kit.wait_frames(get_tree(), 1)
		peak = maxi(peak, director.debris_count())
	_expect("the pool never holds more than 32 pieces", peak <= POOL_SIZE)
	_expect("the pool is full after 100 crashes", director.debris_count() == POOL_SIZE)
	var pool := director.get_node("DebrisPool")
	_expect("the pool has 32 bodies", pool.get_child_count() == POOL_SIZE)
	var flying := 0
	for body: Node in pool.get_children():
		if (body as RigidBody3D).visible:
			flying += 1
	_expect("32 pieces are in the world", flying == POOL_SIZE)
	# A car that took three 25 m/s hits is in the heavy tier and smokes (dossier 7.4).
	var state = director.call("state_of", cars[0])
	_expect("a crashed car is in the heavy tier", state.tier == 2)
	_expect("the heavy tier smokes", state.fx.smoke_running())
	# The budget of dossier 7.7: the damage logic stays under 0.3 ms with 20 cars.
	await Kit.wait_frames(get_tree(), 10)
	var cost: float = director.cpu_usec
	_expect("the damage logic is under 0.3 ms a frame (%.3f ms)" % (cost / 1000.0),
			cost < 300.0)
	await _test_no_leak(director, cars)
	print(("FAIL" if _failures > 0 else "PASS") + " pool (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The state of a car must not leak: 200 cars that are hit and freed leave nothing behind.
func _test_no_leak(director: Node, cars: Array) -> void:
	# The cars of the first part of the test leave the world as well.
	for car: VehicleBase in cars:
		car.queue_free()
	await Kit.wait_frames(get_tree(), 3)
	for i in 200:
		var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 100.0, 1500.0)
		car.add_to_group(&"vehicles")
		add_child(car)
		car.global_transform = Transform3D(Basis.IDENTITY, Vector3(float(i % 20) * 6.0, 0.1, 20.0))
		await Kit.wait_frames(get_tree(), 1)
		car.linear_velocity = Vector3(0.0, 0.0, -20.0)
		Events.vehicle_collided.emit(car, _wall, 1900.0 * 20.0, Vector3(0.0, 0.6, -2.0),
				Vector3(0.0, 0.0, 1.0))
		await Kit.wait_frames(get_tree(), 1)
		car.queue_free()
		await Kit.wait_frames(get_tree(), 1)
	_expect("the states of the cars are gone", director.tracked_count() == 0)
	_expect("the velocities of the cars are gone", director.velocity_entries() == 0)
	_expect("the contacts of the cars are gone", director.pair_entries() == 0)


## Puts the bumper back on the car and forgets that it came off.
func _reset_bumper(director: Node, car: VehicleBase) -> void:
	var bumper := car.get_visual_root().find_child("Bumper_F", true, false) as MeshInstance3D
	if bumper != null:
		bumper.visible = true
	var state = director.call("state_of", car)
	if state != null:
		state.detached.clear()


## The wall every car runs into.
func _make_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, -30.0))
	return wall


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)

extends Node
## The detachable parts of dossier 7.6: a front hit at 23 m/s takes the front bumper, a rear
## hit takes the wing, a violent wreck takes a wheel.

const Kit := preload("res://damage/tests/damage_test_kit.gd")

var _failures: int = 0
var _car: VehicleBase
var _bumper: MeshInstance3D
var _wing: MeshInstance3D
var _wheel: MeshInstance3D
var _wall: StaticBody3D


func _ready() -> void:
	Kit.make_floor(self)
	_wall = _make_wall()
	var director := Kit.make_director(self)
	_car = Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0,
			PackedStringArray(["Bumper_F", "Wing", "Wheel_FL"]))
	_car.add_to_group(&"vehicles")
	add_child(_car)
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0))
	_bumper = _car.get_visual_root().find_child("Bumper_F", true, false) as MeshInstance3D
	_wing = _car.get_visual_root().find_child("Wing", true, false) as MeshInstance3D
	_wheel = _car.get_visual_root().find_child("Wheel_FL", true, false) as MeshInstance3D
	await Kit.wait_frames(get_tree(), 3)

	# A light touch takes nothing off.
	await _hit(8.0, Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)
	_expect("a light hit takes nothing off", director.debris_count() == 0)
	_expect("the bumper is still on the car", _bumper.visible)

	# A front hit at 23 m/s takes the front bumper (dossier 7.6).
	await _hit(23.0, Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)
	_expect("the front bumper came off", not _bumper.visible)
	var state = director.call("state_of", _car)
	_expect("the car carries a dent", state.painter.dent_count() >= 1)
	_expect("the paint scrape is on the mask", state.painter.mask_coverage() > 0.0)
	_expect("one piece of debris is flying", director.debris_count() == 1)
	_expect("the wing is still on the car", _wing.visible)

	# A rear hit at 19 m/s takes the wing.
	await _hit(19.0, Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	_expect("the wing came off", not _wing.visible)
	_expect("two pieces of debris are flying", director.debris_count() == 2)

	# A violent wreck takes a wheel off.
	_car.wreck(null)
	await Kit.wait_frames(get_tree(), 2)
	_expect("the wheel came off", not _wheel.visible)
	_expect("three pieces of debris are flying", director.debris_count() == 3)

	# The debris flies: it has a velocity and it lives on the debris layer.
	var debris := director.get_node("DebrisPool") as Node
	var bodies := debris.get_children()
	_expect("the pool holds the debris", bodies.size() == 32)
	var flying := 0
	for body: Node in bodies:
		var rigid := body as RigidBody3D
		if rigid == null or not rigid.visible:
			continue
		flying += 1
		if rigid.collision_layer != 16:
			_failures += 1
			print("FAIL the debris is not on the debris layer (5)")
			break
	_expect("the three parts are in the world", flying == 3)

	await _test_mesh_without_uvs(director)
	print(("FAIL" if _failures > 0 else "PASS") + " parts (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A body mesh without a UV channel must not break the painter (lead note D-INT1): the dents
## still work, the paint mask has nowhere to go and is skipped.
func _test_mesh_without_uvs(director: Node) -> void:
	var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 100.0, 1900.0)
	var body := car.get_visual_root().find_child("Body", true, false) as MeshInstance3D
	body.mesh = _mesh_without_uvs()
	add_child(car)
	car.add_to_group(&"vehicles")
	await Kit.wait_frames(get_tree(), 2)
	car.linear_velocity = Vector3(0.0, 0.0, -20.0)
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(car, _wall, 1900.0 * 20.0, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)
	var state = director.call("state_of", car)
	_expect("a mesh without UVs still takes a dent",
			state.painter != null and state.painter.dent_count() >= 1)
	_expect("a mesh without UVs still gets the paint mask", state.painter.mask_coverage() > 0.0)


## A panel of vertices and normals, without a UV channel.
func _mesh_without_uvs() -> Mesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := 10
	for z in steps + 1:
		for x in steps + 1:
			verts.append(Vector3(-1.0 + 2.0 * float(x) / float(steps), 0.0,
					-2.0 + 4.0 * float(z) / float(steps)))
			normals.append(Vector3.UP)
	for z in steps:
		for x in steps:
			var i := z * (steps + 1) + x
			indices.append_array(PackedInt32Array([i, i + 1, i + steps + 2, i,
				i + steps + 2, i + steps + 1]))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A head-on hit of the car into a wall in front of it.
func _hit(speed: float, normal: Vector3) -> void:
	_car.linear_velocity = -normal * speed
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(_car, _wall, 1900.0 * speed, Vector3(0.0, 0.6, -2.0), normal)
	await Kit.wait_frames(get_tree(), 1)
	# Two hits of the same pair are only resolved once (the dedupe window), so the test
	# waits it out between the crashes.
	await get_tree().create_timer(0.2, true, false, true).timeout


## The wall the car runs into.
func _make_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, -12.0))
	return wall


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)

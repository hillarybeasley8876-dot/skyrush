extends Node
## The parts on the real cars (the Roadster and the police car): one debris body per part, the
## right side only, the box on the mesh and the materials of every surface.

const Kit := preload("res://damage/tests/damage_test_kit.gd")

var _failures: int = 0
var _roadster: VehicleBase = null
var _wall: StaticBody3D = null


func _ready() -> void:
	Kit.make_floor(self)
	_wall = _make_wall()
	var director := Kit.make_director(self)
	_roadster = (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	_roadster.set("player_controlled", false)
	add_child(_roadster)
	_roadster.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
	_roadster.add_to_group(&"vehicles")
	await Kit.wait_frames(get_tree(), 4)
	if _roadster.get_visual_root() == null:
		print("FAIL the real Roadster has no visual")
		get_tree().quit(1)
		return

	# A front hit at 25 m/s: the front bumper comes off, and only it.
	await _hit(25.0, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.6, -2.0))
	var state = director.call("state_of", _roadster)
	var detached: Array = state.detached.keys()
	_expect("the front bumper came off", detached.has(&"Bumper_F"))
	_expect("only one part came off", detached.size() == 1)
	_expect("no child mesh came off",
			not _has_prefix(detached, "Bumper_F_") and not _has_prefix(detached, "Wing_")
			and not _has_prefix(detached, "DoorCard"))
	_expect("one piece of debris is in the world", director.debris_count() == 1)
	_check_debris_box(director)
	_check_debris_materials(director)

	# A hit on the right side: only the right side comes off.
	await _hit(20.0, Vector3(-1.0, 0.0, 0.0), Vector3(0.9, 0.6, 0.0))
	var state2 = director.call("state_of", _roadster)
	var detached2: Array = state2.detached.keys()
	_expect("the right side took the hit", not detached2.is_empty())
	_expect("no left side part came off", not _has_prefix(detached2, "Skirt_L")
			and not _has_prefix(detached2, "Door_L") and not _has_prefix(detached2, "Mirror_L"))

	await _test_wheels(director)
	await _test_scrape_wreck(director)
	await _test_debris_colour(director)
	await _test_door_spring(director)
	print(("FAIL" if _failures > 0 else "PASS") + " parts on the real cars (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A door springs open OUTWARDS, and it opens once: two hits do not turn it twice.
func _test_door_spring(director: Node) -> void:
	var car := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	car.set("player_controlled", false)
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 40.0))
	car.add_to_group(&"vehicles")
	await Kit.wait_frames(get_tree(), 4)
	var door := car.get_visual_root().find_child("Door_L", true, false) as MeshInstance3D
	if door == null:
		_expect("the Roadster has a door", false)
		return
	var before := _trailing_edge(car, door)
	for i in 2:
		car.linear_velocity = Vector3(-20.0, 0.0, 0.0)
		await Kit.wait_frames(get_tree(), 2)
		Events.vehicle_collided.emit(car, _wall, 1900.0 * 20.0, Vector3(-0.95, 0.6, 0.3),
				Vector3(1.0, 0.0, 0.0))
		await Kit.wait_frames(get_tree(), 2)
		await get_tree().create_timer(0.25, true, false, true).timeout
	var angle := rad_to_deg(door.transform.basis.get_euler().y)
	_expect("the door opened 15 degrees (%.1f)" % angle, absf(angle) > 10.0 and absf(angle) < 20.0)
	var after := _trailing_edge(car, door)
	_expect("the trailing edge of the door moved out by %.3f m (at least 0.15 m)"
		% (after - before), after - before >= 0.15)


## The |x| of the trailing edge of the door, in the space of the car.
func _trailing_edge(car: VehicleBase, door: MeshInstance3D) -> float:
	if door.mesh == null:
		return 0.0
	var box := door.mesh.get_aabb()
	# The corner of the door that is the farthest from the front of the car.
	var corner := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z)
	var world := door.global_transform * corner
	var local := car.global_transform.affine_inverse() * world
	return absf(local.x)


## A violent wreck takes exactly ONE wheel off, the one nearest the hit, and the debris of a
## wheel is a cylinder that lies down (dossier §7.6).
func _test_wheels(director: Node) -> void:
	# A fresh car: a head-on at 32 m/s, on the front left. The car is wrecked and the front
	# left wheel comes off.
	var car := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	car.set("player_controlled", false)
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 20.0))
	car.add_to_group(&"vehicles")
	# The car is on a slippery floor: a 32 m/s head-on does not kill it, so the test gives it
	# less health than a full car.
	car.max_health = 40.0
	car.health = 40.0
	await Kit.wait_frames(get_tree(), 4)
	car.linear_velocity = Vector3(0.0, 0.0, -32.0)
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(car, _wall, 1900.0 * 32.0, Vector3(-0.7, 0.35, 18.1),
			Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)
	var state = director.call("state_of", car)
	var detached: Array = state.detached.keys()
	var wheels: Array[StringName] = []
	for name: StringName in detached:
		if String(name).begins_with("Wheel"):
			wheels.append(name)
	_expect("the violent wreck took exactly one wheel (%s)" % str(wheels), wheels.size() == 1)
	_expect("the wheel is the front left one (%s)" % str(wheels),
			wheels.size() == 1 and wheels[0] == &"Wheel_FL")
	_check_wheel_cylinder(director)


## The debris of a wheel is a cylinder that lies down: its height is the width of the wheel.
func _check_wheel_cylinder(director: Node) -> void:
	var pool := director.get_node("DebrisPool") as Node
	for body: Node in pool.get_children():
		var rigid := body as RigidBody3D
		if rigid == null or not rigid.visible:
			continue
		for child in rigid.get_children():
			if not (child is CollisionShape3D):
				continue
			var cylinder := (child as CollisionShape3D).shape as CylinderShape3D
			if cylinder == null:
				continue
			_expect("the debris of the wheel is a cylinder of %.3f m (0.25 to 0.35 m)"
					% cylinder.height, cylinder.height >= 0.25 and cylinder.height <= 0.35)
			return
	_expect("the wreck left a cylinder of debris", false)


## A car that dies of scrapes keeps its wheels: only a violent wreck takes them off.
func _test_scrape_wreck(director: Node) -> void:
	var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 60.0, 1500.0)
	car.add_to_group(&"vehicles")
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 30.0))
	await Kit.wait_frames(get_tree(), 4)
	# A long scrape against a wall: the health goes down, the impact ratio stays low.
	for i in 12:
		car.linear_velocity = Vector3(0.0, 0.0, -9.0)
		await Kit.wait_frames(get_tree(), 2)
		Events.vehicle_collided.emit(car, _wall, 1900.0 * 9.0, Vector3(0.0, 0.5, -1.5),
				Vector3(0.0, 0.0, 1.0))
		await Kit.wait_frames(get_tree(), 1)
		await get_tree().create_timer(0.25, true, false, true).timeout
	var state = director.call("state_of", car)
	var detached: Array = state.detached.keys()
	var wheels := 0
	for name: StringName in detached:
		if String(name).begins_with("Wheel"):
			wheels += 1
	_expect("a wreck by scrapes takes no wheel off (%d wheels, hp %.1f)" % [wheels, car.health],
			wheels == 0)


## The debris wears the colour of the car it came from.
func _test_debris_colour(director: Node) -> void:
	var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 100.0, 1500.0,
			PackedStringArray(["Bumper_F"]))
	car.add_to_group(&"vehicles")
	add_child(car)
	await Kit.wait_frames(get_tree(), 2)
	# The traffic unit paints every surface of the car, so the debris wears the colour. The
	# instance uniforms only exist on a node that is in the tree.
	for node in car.get_visual_root().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		if mesh.get_material_override() == null:
			mesh.material_override = load("res://shaders/materials/SH_car_paint.tres").duplicate()
		mesh.set_instance_shader_parameter(&"base_color_override", Color("#D81E2C"))
	# The instance uniforms reach the server on the next frame.
	await Kit.wait_frames(get_tree(), 2)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 60.0))
	await Kit.wait_frames(get_tree(), 4)
	car.linear_velocity = Vector3(0.0, 0.0, -25.0)
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(car, _wall, 1900.0 * 25.0, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)
	await get_tree().create_timer(0.25, true, false, true).timeout
	var pool := director.get_node("DebrisPool") as Node
	var found := false
	for body: Node in pool.get_children():
		var rigid := body as RigidBody3D
		if rigid == null or not rigid.visible:
			continue
		for child in rigid.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var colour: Variant = mesh.get_instance_shader_parameter(&"base_color_override")
			if colour == null:
				continue
			var c := Color(colour)
			# The default of the paint is a transparent black: only the debris of the car
			# that was just hit wears a colour.
			if c.a <= 0.0:
				continue
			found = true
			_expect("the debris wears the colour of the car (%s)" % c.to_html(false),
					c.is_equal_approx(Color("#D81E2C")))
	_expect("the debris carries the instance colour of the car", found)


## The collision box of the debris sits on the mesh it carries.
func _check_debris_box(director: Node) -> void:
	var pool := director.get_node("DebrisPool") as Node
	for body: Node in pool.get_children():
		var rigid := body as RigidBody3D
		if rigid == null or not rigid.visible:
			continue
		var shape: CollisionShape3D = null
		for child in rigid.get_children():
			if child is CollisionShape3D:
				shape = child as CollisionShape3D
				break
		if shape == null:
			continue
		# The box must hold every mesh of the part.
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var half := box.size * 0.5
		var worst := 0.0
		var meshes := 0
		for child in rigid.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			meshes += 1
			var aabb := mesh.transform * mesh.mesh.get_aabb()
			# The centre of the mesh must be inside the box.
			var outside := Vector3(
				maxf(absf(aabb.get_center().x - shape.position.x) - half.x, 0.0),
				maxf(absf(aabb.get_center().y - shape.position.y) - half.y, 0.0),
				maxf(absf(aabb.get_center().z - shape.position.z) - half.z, 0.0))
			worst = maxf(worst, outside.length())
		_expect("the box holds the %d meshes of the part (%.3f m out)" % [meshes, worst],
				meshes > 0 and worst <= 0.05)
		return


## Every surface of the debris keeps the material of the car.
func _check_debris_materials(director: Node) -> void:
	var pool := director.get_node("DebrisPool") as Node
	var found := false
	for body: Node in pool.get_children():
		var rigid := body as RigidBody3D
		if rigid == null or not rigid.visible:
			continue
		for child in rigid.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			found = true
			for i in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(i)
				_expect("the surface %d of the debris has its material" % i, material != null)
		if found:
			return
	_expect("the debris has a mesh", found)


## A hit of the car at a speed, with the given normal and point.
func _hit(speed: float, normal: Vector3, point: Vector3) -> void:
	_roadster.linear_velocity = -normal * speed
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(_roadster, _wall, 1900.0 * speed, point, normal)
	await Kit.wait_frames(get_tree(), 2)
	await get_tree().create_timer(0.2, true, false, true).timeout


## True when one of the names starts with the prefix.
func _has_prefix(names: Array, prefix: String) -> bool:
	for name: StringName in names:
		if String(name).begins_with(prefix):
			return true
	return false


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

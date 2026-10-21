extends Node
## The paint-scrape mask of a car (dossier §7.5 A): the scrape must reach the GPU, it must
## stay in the region of the panel it belongs to, and the atlas must cover every painted
## panel of the car.

const Kit := preload("res://damage/tests/damage_test_kit.gd")

var _failures: int = 0
var _wall: StaticBody3D = null


func _ready() -> void:
	Kit.make_floor(self)
	_wall = _make_wall()
	var director := Kit.make_director(self)
	var car := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	car.set("player_controlled", false)
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
	car.add_to_group(&"vehicles")
	await Kit.wait_frames(get_tree(), 4)

	# A hit on the left rear: the scrape must not touch the region of the right side.
	await _hit(car, 20.0, Vector3(1.0, 0.0, 0.0), Vector3(-0.95, 0.6, 1.6))
	var state = director.call("state_of", car)
	var painter = state.painter
	# The mask is uploaded at most ten times a second, so the test waits for it.
	await get_tree().create_timer(0.3, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 2)
	_expect("the scrape reached the GPU (%d uploads)" % painter.upload_count(),
			painter.upload_count() >= 1)
	_check_regions(painter)
	_check_right_region(painter)
	print(("FAIL" if _failures > 0 else "PASS") + " mask (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Every corner of every painted panel of the car must fall inside its own region of the
## atlas, and inside the box of the car.
func _check_regions(painter: Object) -> void:
	var mask = painter.get("_mask")
	if mask == null:
		_expect("the car has a mask", false)
		return
	var car_min: Vector3 = mask.car_min
	var car_size: Vector3 = mask.car_size
	var rects: Array = mask.rects
	var outside := 0
	var wrong_region := 0
	var panels: Array = painter.get("_panels")
	for panel: Object in panels:
		if not panel.get("painted"):
			continue
		var box: AABB = panel.get("car_box")
		for i in 8:
			var corner: Vector3 = box.get_endpoint(i)
			# The corner must be inside the box of the atlas.
			if corner.x < car_min.x or corner.x > car_min.x + car_size.x \
					or corner.y < car_min.y or corner.y > car_min.y + car_size.y \
					or corner.z < car_min.z or corner.z > car_min.z + car_size.z:
				outside += 1
				continue
			# The corner must fall inside the region of the atlas it is painted in.
			var region := _region_of(corner, car_min, car_size)
			var uv := _atlas_uv(corner, region, car_min, car_size, rects)
			var rect: Vector4 = rects[region]
			if uv.x < rect.x - 0.5 or uv.x > rect.x + rect.z + 0.5 \
					or uv.y < rect.y - 0.5 or uv.y > rect.y + rect.w + 0.5:
				wrong_region += 1
	_expect("every corner of every painted panel is inside the box of the atlas (%d outside)"
			% outside, outside == 0)
	_expect("every corner falls inside its own region of the atlas (%d outside)" % wrong_region,
			wrong_region == 0)


## A scrape on the left must not touch the region of the right side.
func _check_right_region(painter: Object) -> void:
	var mask = painter.get("_mask")
	if mask == null:
		return
	var rects: Array = mask.rects
	var data: Image = mask.data
	var bytes := data.get_data()
	# The right side is the region 1.
	var rect: Vector4 = rects[1]
	var total := 0
	for y in range(int(rect.y), int(rect.y + rect.w)):
		for x in range(int(rect.x), int(rect.x + rect.z)):
			total += bytes[(y * 1024 + x) * 4]
	_expect("the region of the right side is untouched by a hit on the left (%d)" % total,
			total == 0)


## The region of the atlas a point of the car belongs to (the same rule as the shader).
func _region_of(point: Vector3, car_min: Vector3, car_size: Vector3) -> int:
	var centre := car_min + car_size * 0.5
	var d := point - centre
	if absf(d.y) > car_size.y * 0.35:
		return 4
	if absf(d.x) > car_size.x * 0.35:
		return 0 if d.x < 0.0 else 1
	return 2 if d.z < 0.0 else 3


## The UV of the atlas for a point of the car.
func _atlas_uv(point: Vector3, region: int, car_min: Vector3, car_size: Vector3,
		rects: Array) -> Vector2:
	var plane := Vector2.ZERO
	var origin := Vector2.ZERO
	var size := Vector2.ZERO
	match region:
		0, 1:
			plane = Vector2(point.z, point.y)
			origin = Vector2(car_min.z, car_min.y)
			size = Vector2(car_size.z, car_size.y)
		4:
			plane = Vector2(point.x, point.z)
			origin = Vector2(car_min.x, car_min.z)
			size = Vector2(car_size.x, car_size.z)
		_:
			plane = Vector2(point.x, point.y)
			origin = Vector2(car_min.x, car_min.y)
			size = Vector2(car_size.x, car_size.y)
	var local := (plane - origin) / Vector2(maxf(size.x, 0.01), maxf(size.y, 0.01))
	var rect: Vector4 = rects[region]
	return Vector2(rect.x, rect.y) + Vector2(clampf(local.x, 0.0, 1.0) * rect.z,
			clampf(local.y, 0.0, 1.0) * rect.w)


## A hit of the car at a speed, with the given normal and point.
func _hit(car: VehicleBase, speed: float, normal: Vector3, point: Vector3) -> void:
	car.linear_velocity = -normal * speed
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(car, _wall, 1900.0 * speed, point, normal)
	await Kit.wait_frames(get_tree(), 2)
	await get_tree().create_timer(0.25, true, false, true).timeout


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

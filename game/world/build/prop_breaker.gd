extends Node3D
## The street lamps break away (PropCollision.BREAKAWAY: the street lamp, the heritage and magnolia lamps of the old streets, the
## double lamp of the median of a deck). A lamp has no rigid shape: a pole of 15 cm stopped a car of 1.9 t dead, and by the damage
## rules a head-on hit at 108 km/h wrecked it (half of the random drives of tools/fuzz_drive.gd ended on a prop). A car that drives
## into a lamp knocks it down: the lamp goes from the street (its instances of the MultiMesh and its light), its pole falls as
## debris, the car keeps KEEP of its speed and loses BREAK_HP. Every car that is not frozen breaks the lamps (the player, the
## police, the rivals); a car slower than MIN_SPEED does not. A broken lamp stays broken for the game.
##
## The lamps are looked up in a spatial hash, so the check of a car costs a few cells of a grid per physics tick.

const PropLibrary := preload("res://world/loader/prop_library.gd")

## The share of its speed a car keeps when it knocks a lamp down (the rest went into the pole).
const KEEP := 0.85
## The HP a knocked lamp costs the car.
const BREAK_HP := 3.0
## Below this speed (m/s) a car does not break a lamp.
const MIN_SPEED := 2.0
## The radius of a pole (m), for the overlap with the box of a car.
const POLE_RADIUS := 0.15
## The cell of the spatial hash of the lamps (m).
const CELL := 8.0
## The other cars are watched when they are this close to the camera (m): nobody sees a lamp fall further away. The player
## car is always watched.
const WATCH_RADIUS := 250.0
## The shake of the camera of the player when it knocks a lamp down (m, s).
const SHAKE := 0.06
const SHAKE_TIME := 0.2
## The falling pole: its mass (kg), how much of the speed of the car it gets, how fast it goes up (m/s) and tips over (rad/s),
## how long it lies before it fades (s), the fade (s), the most poles at once.
const DEBRIS_MASS := 140.0
const DEBRIS_THROW := 0.6
const DEBRIS_LIFT := 1.5
const DEBRIS_SPIN := 2.5
const DEBRIS_LIFE := 6.0
const DEBRIS_FADE := 1.0
const MAX_DEBRIS := 12
## The physics layer of the debris (the layer of the parts that come off a car: the cars drive through it) and what it falls on.
const DEBRIS_LAYER := 1 << 4
const WORLD_MASK := 1

var _lamps: Array[Dictionary] = []
var _grid: Dictionary = {}
var _multimeshes: Dictionary = {}
var _light_pool: Node = null
var _library: PropLibrary = null
## The falling poles: {"body", "meshes", "age"}.
var _debris: Array[Dictionary] = []
## The box of every car (the centre and the half size in its own space), by the id of the car.
var _boxes: Dictionary = {}
## The number of lamps that were knocked down.
var broken_count := 0
## The cost of the last physics tick of the breaker (microseconds) and the most it cost so far.
var cost_usec := 0.0
var peak_usec := 0.0


func setup(lamps: Array[Dictionary], multimeshes: Dictionary, light_pool: Node, library: PropLibrary) -> void:
	_lamps = lamps
	_multimeshes = multimeshes
	_light_pool = light_pool
	_library = library
	_grid.clear()
	for i in _lamps.size():
		var key := _key((_lamps[i]["transform"] as Transform3D).origin)
		var cell: PackedInt32Array = _grid.get(key, PackedInt32Array())
		cell.append(i)
		_grid[key] = cell


## The number of lamps that break away.
func lamp_count() -> int:
	return _lamps.size()


## The lamp of an index: {"type", "transform", "height", "refs", "lights", "broken"}.
func lamp(index: int) -> Dictionary:
	return _lamps[index]


func is_broken(index: int) -> bool:
	return bool(_lamps[index].get("broken", false))


## The falling poles that are still there.
func debris_count() -> int:
	return _debris.size()


## The lamps within `radius` (in the plan) of a point.
func lamps_near(point: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for index in _near(point, radius):
		var base := (_lamps[index]["transform"] as Transform3D).origin
		if Vector2(base.x - point.x, base.z - point.z).length() <= radius:
			out.append(index)
	return out


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_age_debris(delta)
	if _lamps.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var car := node as VehicleBase
		if car == null or car.freeze or not car.is_visible_in_tree():
			continue
		# the player is always watched (the camera of a menu, a crash or a takedown can look elsewhere), the other cars near the
		# camera only
		if car != Game.player and camera != null \
				and car.global_position.distance_squared_to(camera.global_position) > WATCH_RADIUS * WATCH_RADIUS:
			continue
		_check_car(car)
	cost_usec = float(Time.get_ticks_usec() - started)
	peak_usec = maxf(peak_usec, cost_usec)


## Knocks down every lamp that the box of the car touches.
func _check_car(car: VehicleBase) -> void:
	if car.linear_velocity.length() < MIN_SPEED:
		return
	var box := _box_of(car)
	var centre: Vector3 = box[0]
	var half: Vector3 = box[1]
	var xform := car.global_transform
	var middle := xform * centre
	var reach := Vector2(half.x, half.z).length() + POLE_RADIUS
	var inverse := xform.affine_inverse()
	for index in _near(middle, reach):
		var lamp_data := _lamps[index]
		if bool(lamp_data.get("broken", false)):
			continue
		var base := (lamp_data["transform"] as Transform3D).origin
		var local := inverse * base
		if absf(local.x - centre.x) > half.x + POLE_RADIUS or absf(local.z - centre.z) > half.z + POLE_RADIUS:
			continue
		# the pole stands from its base to its top: a car on a deck over it, or on the road under a deck lamp, does not touch it
		if middle.y + half.y < base.y or middle.y - half.y > base.y + float(lamp_data["height"]):
			continue
		_break(index, car)


## The lamp goes from the street, its pole falls, the car loses a little speed and a few HP.
func _break(index: int, car: VehicleBase) -> void:
	var lamp_data := _lamps[index]
	lamp_data["broken"] = true
	broken_count += 1
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	for ref in lamp_data["refs"] as Array:
		var multimesh := _multimeshes.get(ref[0]) as MultiMesh
		if multimesh != null and int(ref[1]) < multimesh.instance_count:
			multimesh.set_instance_transform(int(ref[1]), hidden)
	if _light_pool != null and _light_pool.has_method(&"set_source_enabled"):
		for light_index in lamp_data["lights"] as Array:
			_light_pool.call(&"set_source_enabled", int(light_index), false)
	var velocity := car.linear_velocity
	_spawn_debris(lamp_data, velocity)
	car.linear_velocity = velocity * KEEP
	var point := (lamp_data["transform"] as Transform3D).origin + Vector3.UP * 0.6
	car.apply_damage(BREAK_HP, point, null)
	if car == Game.player:
		Events.camera_shake.emit(SHAKE, SHAKE_TIME)
	Events.prop_broken.emit(car, StringName(lamp_data["type"]), point, velocity.length())


## The pole of a broken lamp: the meshes of the lamp on a rigid body that the hit throws along and tips over.
func _spawn_debris(lamp_data: Dictionary, velocity: Vector3) -> void:
	var def: Dictionary = _library.get_prop(String(lamp_data["type"]), int(lamp_data.get("variant", 0))) \
			if _library != null else {}
	var height := float(lamp_data["height"])
	var body := RigidBody3D.new()
	body.name = "LampDebris"
	body.mass = DEBRIS_MASS
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = WORLD_MASK
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = POLE_RADIUS
	cylinder.height = maxf(height, 0.5)
	shape.shape = cylinder
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)
	var meshes: Array[GeometryInstance3D] = []
	var scale_vector: Vector3 = lamp_data["scale_vector"]
	for part in def.get("parts", []) as Array:
		# the glow of the head and the far dot are light, not metal: they went with the lamp
		if bool(part.get("glow", false)) or bool(part.get("atlas", false)):
			continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = part["mesh"]
		var material: Variant = part.get("material")
		if material is Material:
			mesh.material_override = material
		var part_xform: Transform3D = part["transform"]
		mesh.transform = Transform3D(part_xform.basis.scaled(scale_vector), part_xform.origin * scale_vector)
		body.add_child(mesh)
		meshes.append(mesh)
	add_child(body)
	var xform: Transform3D = lamp_data["transform"]
	body.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin + Vector3.UP * 0.05)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	body.linear_velocity = flat * DEBRIS_THROW + Vector3.UP * DEBRIS_LIFT
	if flat.length() > 0.01:
		# the top of the pole goes the way the car went
		body.angular_velocity = Vector3.UP.cross(flat.normalized()) * DEBRIS_SPIN
	_debris.append({"body": body, "meshes": meshes, "age": 0.0})
	while _debris.size() > MAX_DEBRIS:
		var oldest: Dictionary = _debris.pop_front()
		(oldest["body"] as Node).queue_free()


## The poles lie for DEBRIS_LIFE seconds, fade and go.
func _age_debris(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d := _debris[i]
		d["age"] = float(d["age"]) + delta
		var age := float(d["age"])
		if age >= DEBRIS_LIFE + DEBRIS_FADE:
			(d["body"] as Node).queue_free()
			_debris.remove_at(i)
		elif age >= DEBRIS_LIFE:
			for mesh: GeometryInstance3D in d["meshes"]:
				mesh.transparency = (age - DEBRIS_LIFE) / DEBRIS_FADE


## The box of a car in its own space: [centre, half size] of its box shape (the first box child).
func _box_of(car: VehicleBase) -> Array:
	var id := car.get_instance_id()
	if _boxes.has(id):
		return _boxes[id]
	var box: Array = [Vector3(0.0, 0.62, 0.0), Vector3(0.98, 0.43, 2.2)]
	for child in car.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			box = [shape.position, (shape.shape as BoxShape3D).size * 0.5]
			break
	_boxes[id] = box
	return box


## The lamps in the cells around a point.
func _near(point: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var span := int(ceil(radius / CELL))
	var cx := int(floor(point.x / CELL))
	var cz := int(floor(point.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if _grid.has(key):
				out.append_array(_grid[key] as PackedInt32Array)
	return out


static func _key(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL)), int(floor(point.z / CELL)))

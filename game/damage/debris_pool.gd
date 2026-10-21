extends Node3D
## The global pool of rigid-body debris (dossier §7.6): 32 bodies, 8 s of life, then a 0.5 s
## fade and the body goes back to the pool. The debris collides with the world only, never
## with the cars, so it cannot cause jitter or an unfair hit.

const POOL_SIZE := 32
const LIFETIME := 8.0
const FADE_TIME := 0.5
## Physics layer 5 (debris) and the world layer it collides with.
const DEBRIS_LAYER := 1 << 4
const WORLD_MASK := 1
## The random kick a part gets when it comes off (dossier §7.6).
const KICK := Vector3(3.0, 2.0, 3.0)
const KICK_MIN_Y := 2.0
const KICK_MAX_Y := 6.0
const SPIN := 8.0
## Where the bodies wait when they are not in the world.
const PARK := Vector3(0.0, -500.0, 0.0)
const SHAPE_BOX := &"box"
const SHAPE_CYLINDER := &"cylinder"


class Debris:
	extends RefCounted
	var body: RigidBody3D = null
	var shape: CollisionShape3D = null
	var meshes: Array[MeshInstance3D] = []
	var life: float = 0.0
	var active: bool = false


var _pool: Array[Debris] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()
## The collision shapes, cached by their size (one shape per part, not per spawn).
var _shapes: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		_pool.append(_make_body())


## The number of debris bodies that are in the world right now.
func active_count() -> int:
	var count := 0
	for d in _pool:
		if d.active:
			count += 1
	return count


## Spawns a part as debris. `spec` holds the meshes of the part, the box that carries them,
## its mass and its shape.
func spawn(spec: Dictionary, xform: Transform3D, velocity: Vector3) -> void:
	if spec.is_empty():
		return
	var meshes: Array = spec.get("meshes", []) as Array
	if meshes.is_empty():
		return
	var debris := _take()
	debris.body.global_transform = xform
	_clear_meshes(debris)
	for entry: Dictionary in meshes:
		debris.meshes.append(_add_mesh(debris, entry))
	_apply_shape(debris, spec)
	debris.body.mass = float(spec.get("mass", 10.0))
	debris.body.linear_velocity = velocity * 0.8 + Vector3(
		_rng.randf_range(-KICK.x, KICK.x),
		_rng.randf_range(KICK_MIN_Y, KICK_MAX_Y),
		_rng.randf_range(-KICK.z, KICK.z))
	debris.body.angular_velocity = Vector3(
		_rng.randf_range(-SPIN, SPIN), _rng.randf_range(-SPIN, SPIN), _rng.randf_range(-SPIN, SPIN))
	debris.body.freeze = false
	debris.body.sleeping = false
	debris.body.visible = true
	debris.active = true
	debris.life = 0.0


func _physics_process(delta: float) -> void:
	for d in _pool:
		if not d.active:
			continue
		d.life += delta
		if d.life >= LIFETIME + FADE_TIME:
			_release(d)
		elif d.life >= LIFETIME:
			# The fade: the part goes transparent over half a second.
			var k := 1.0 - (d.life - LIFETIME) / FADE_TIME
			for mesh in d.meshes:
				mesh.transparency = clampf(1.0 - k, 0.0, 1.0)


## Frees every debris body (the test and the respawn use it).
func clear() -> void:
	for d in _pool:
		if d.active:
			_release(d)


# --- the pool ------------------------------------------------------------------------------------
func _make_body() -> Debris:
	var body := RigidBody3D.new()
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = WORLD_MASK
	body.continuous_cd = false
	body.can_sleep = true
	body.contact_monitor = false
	body.gravity_scale = 1.0
	body.linear_damp = 0.1
	body.angular_damp = 0.6
	body.visible = false
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	add_child(body)
	var debris := Debris.new()
	debris.body = body
	debris.shape = shape
	return debris


## A free body, or the oldest one when the pool is full (the pool never grows).
func _take() -> Debris:
	for d in _pool:
		if not d.active:
			return d
	var oldest := _pool[_next]
	_next = (_next + 1) % _pool.size()
	return oldest


func _release(d: Debris) -> void:
	d.active = false
	d.life = 0.0
	d.body.linear_velocity = Vector3.ZERO
	d.body.angular_velocity = Vector3.ZERO
	d.body.freeze = true
	d.body.sleeping = true
	d.body.visible = false
	# The bodies wait off the map, so they never block the world.
	d.body.global_position = PARK
	_clear_meshes(d)


## Removes the meshes of a debris body.
func _clear_meshes(d: Debris) -> void:
	for mesh in d.meshes:
		mesh.queue_free()
	d.meshes.clear()


## Adds one mesh of the part, with the materials of every surface and the instance uniforms
## of the car (the paint colour of a red rival must stay red).
func _add_mesh(debris: Debris, entry: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh: Mesh = entry.get("mesh", null) as Mesh
	instance.mesh = mesh
	instance.transform = entry.get("transform", Transform3D.IDENTITY) as Transform3D
	var source := entry.get("node", null) as MeshInstance3D
	var clean: Array = entry.get("materials", []) as Array
	if source != null and mesh != null:
		for i in mesh.get_surface_count():
			var material: Material = null
			if i < clean.size():
				material = clean[i] as Material
			if material == null:
				material = source.get_active_material(i)
			if material != null:
				instance.set_surface_override_material(i, material)
	debris.body.add_child(instance)
	# The instance uniforms are set after the mesh is in the tree: Godot refuses them on a
	# node that is not in the tree yet, and the debris would lose the colour of the car.
	var params: Variant = entry.get("instance", null)
	if params is Dictionary:
		for key: StringName in params:
			instance.set_instance_shader_parameter(key, (params as Dictionary)[key])
	return instance


## The collision box of the debris, from the box of the meshes.
func _apply_shape(debris: Debris, spec: Dictionary) -> void:
	var size: Vector3 = spec.get("size", Vector3.ONE)
	var centre: Vector3 = spec.get("centre", Vector3.ZERO)
	var shape_name := StringName(spec.get("shape", SHAPE_BOX))
	if shape_name == SHAPE_CYLINDER:
		var cylinder := _shape(SHAPE_CYLINDER, size) as CylinderShape3D
		debris.shape.shape = cylinder
		# The wheel spins around X, so the cylinder lies down.
		debris.shape.rotation = Vector3(0.0, 0.0, PI * 0.5)
	else:
		debris.shape.shape = _shape(SHAPE_BOX, size) as BoxShape3D
		debris.shape.rotation = Vector3.ZERO
	debris.shape.position = centre


## One shape per size, cached: a spawn must not build a new shape.
func _shape(shape_name: StringName, size: Vector3) -> Shape3D:
	var key := "%s:%s" % [shape_name, size]
	if _shapes.has(key):
		return _shapes[key] as Shape3D
	var shape: Shape3D
	if shape_name == SHAPE_CYLINDER:
		# The cylinder lies down (the wheel spins around X): its height is the width of the
		# wheel and its radius half of its diameter.
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(maxf(size.y, size.z), 0.03) * 0.5
		cylinder.height = maxf(size.x, 0.05)
		shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape = box
	_shapes[key] = shape
	return shape

extends Node3D
## Global spark pool. Crash sparks are E5-hot streaks that fly, fall, bounce off the road and
## die inside 0.3 s. One MultiMesh (one draw call) serves every car, so the budget is fixed at
## SPARK_MAX billboards no matter how many cars crash.
##
## The pool also draws the two non-spark effects that need the same billboard machinery: the
## cold vapour puff of a nitro ignition and the thin air ribbons of a near miss. They use their
## own soft white streak texture (INSTANCE_CUSTOM.z picks it), so they never read as a hot
## orange spark.

const ADD_SHADER := preload("res://fx/fx_add.gdshader")
const PALETTE := preload("res://fx/fx_palette.gd")
const TEXTURES := preload("res://fx/fx_textures.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

const AIR := 0
const SPARK := 1
const VAPOUR := 2
## The energy of the air ribbon, as a factor of the energy of the material. It has to read on
## a night road, so it is a lot brighter than the sparks it sits next to.
const AIR_ENERGY := 0.3

var _multi: MultiMesh
var _mesh_instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _life: PackedFloat32Array
var _max_life: PackedFloat32Array
var _length: PackedFloat32Array
var _thickness: PackedFloat32Array
var _energy: PackedFloat32Array
var _gravity: PackedFloat32Array
var _ground: PackedFloat32Array
var _kind: PackedByteArray
var _next: int = 0
var _limit: int = TUNE.SPARK_MAX


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = ADD_SHADER
	_material.set_shader_parameter(&"energy", 20.0)  ## E5 tier (art DOSSIER §2.3)
	# The streak texture tapers the quad, so a spark reads as a hot line, not a plank.
	_material.set_shader_parameter(&"albedo_tex", TEXTURES.spark_streak())
	# The air ribbons (the near miss, the cold vapour) use a soft white streak.
	_material.set_shader_parameter(&"alt_tex", TEXTURES.air_streak())
	_material.set_shader_parameter(&"use_texture", true)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.use_custom_data = true
	_multi.instance_count = TUNE.SPARK_MAX
	_multi.mesh = quad

	_mesh_instance = MultiMeshInstance3D.new()
	_mesh_instance.name = "Sparks"
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.multimesh = _multi
	add_child(_mesh_instance)

	_pos.resize(TUNE.SPARK_MAX)
	_vel.resize(TUNE.SPARK_MAX)
	_life.resize(TUNE.SPARK_MAX)
	_max_life.resize(TUNE.SPARK_MAX)
	_length.resize(TUNE.SPARK_MAX)
	_thickness.resize(TUNE.SPARK_MAX)
	_energy.resize(TUNE.SPARK_MAX)
	_gravity.resize(TUNE.SPARK_MAX)
	_ground.resize(TUNE.SPARK_MAX)
	_kind.resize(TUNE.SPARK_MAX)
	for i in TUNE.SPARK_MAX:
		_life[i] = 0.0
		_hide(i)


## Scales the pool with the quality preset (0.4 low .. 1.3 ultra).
func set_quality(quality: float) -> void:
	_limit = clampi(int(float(TUNE.SPARK_MAX) * clampf(quality, 0.2, 1.3)), 24, TUNE.SPARK_MAX)


## Spawns a burst of sparks at `point`, thrown in a cone around the reflection of the car's
## velocity on the surface. scale 1.0 = normal crash; > 1 = oversized (slow-motion takedowns).
func burst(point: Vector3, normal: Vector3, count: int, speed: float, scale: float = 1.0,
		ground_y: float = 0.0, car_velocity: Vector3 = Vector3.ZERO) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var along := _reflection(car_velocity, n)
	var cone := deg_to_rad(TUNE.SPARK_CONE_DEG)
	for i in mini(count, _room()):
		var direction := _cone_vector(along, cone)
		var velocity := direction * speed * randf_range(0.55, 1.35) \
				+ car_velocity * TUNE.SPARK_CARRY
		_spawn(point, velocity,
				randf_range(TUNE.SPARK_THICKNESS_MIN, TUNE.SPARK_THICKNESS_MAX) * scale,
				randf_range(TUNE.SPARK_LENGTH_MIN, TUNE.SPARK_LENGTH_MAX) * scale,
				scale, ground_y, SPARK)


## The direction of the burst: the car's velocity reflected on the normal of the surface, so
## the sparks spray away from the surface the car hit.
func _reflection(velocity: Vector3, normal: Vector3) -> Vector3:
	var along := velocity - 2.0 * velocity.dot(normal) * normal
	if along.length() < 0.01:
		along = normal.cross(Vector3.UP)
		if along.length() < 0.01:
			along = normal.cross(Vector3.RIGHT)
	return along.normalized()


## A random direction inside a cone around an axis.
func _cone_vector(axis: Vector3, angle: float) -> Vector3:
	var a := randf() * TAU
	var radius := tan(angle * 0.5) * sqrt(randf())
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side := axis.cross(up).normalized()
	var other := axis.cross(side).normalized()
	return (axis + (side * cos(a) + other * sin(a)) * radius).normalized()


## A grinding contact throws sparks that trail BEHIND the car, not along the wall normal.
## A few sparks on every physics tick read as a continuous shower, not as a dashed line.
func scrape(point: Vector3, normal: Vector3, car_velocity: Vector3, ground_y: float = 0.0) -> void:
	for i in mini(TUNE.SPARK_SCRAPE_COUNT, _room()):
		var v := -car_velocity * TUNE.SPARK_TRAIL_FACTOR * randf_range(0.6, 1.4) \
				+ normal * randf_range(TUNE.SPARK_NORMAL_SPEED * 0.6, TUNE.SPARK_NORMAL_SPEED) \
				+ Vector3.UP * randf_range(0.0, TUNE.SPARK_UP_SPEED)
		_spawn(point, v, randf_range(0.02, 0.035), randf_range(0.1, 0.22), 0.8, ground_y, SPARK)


## The near miss: ribbons of displaced air along the passing car, cold and white.
func wind_streak(point: Vector3, direction: Vector3, relative_speed: float) -> void:
	var speed := clampf(relative_speed, 8.0, TUNE.NEAR_MISS_SPEED)
	var length := clampf(speed * TUNE.NEAR_MISS_SPEED_TIME, 2.0, TUNE.NEAR_MISS_LENGTH)
	for i in mini(TUNE.NEAR_MISS_STREAKS, _room()):
		var jitter := Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3),
				randf_range(-0.4, 0.4))
		_spawn(point + jitter, direction.normalized() * speed, TUNE.NEAR_MISS_WIDTH,
				length, AIR_ENERGY, 0.0, AIR)


## The cold vapour puff of a nitro ignition: white, slow, no fire (dossier §5.5).
func puff(point: Vector3) -> void:
	for i in mini(10, _room()):
		var v := Vector3(randf_range(-1.0, 1.0), randf_range(0.1, 0.8),
				randf_range(-0.4, 0.6)) * 2.2
		_spawn(point, v, 0.25, 0.5, AIR_ENERGY, 0.0, VAPOUR)


func _spawn(point: Vector3, velocity: Vector3, thickness: float, length: float, energy_mult: float,
		ground_y: float, kind: int) -> void:
	var i := _next
	_next = (_next + 1) % TUNE.SPARK_MAX
	_pos[i] = point
	_vel[i] = velocity
	var life := TUNE.SPARK_LIFE
	if kind == AIR:
		life = TUNE.NEAR_MISS_LIFETIME
	_life[i] = life
	_max_life[i] = life
	_length[i] = length
	_thickness[i] = thickness
	_energy[i] = energy_mult
	_gravity[i] = 1.0 if kind == SPARK else 0.0
	_ground[i] = ground_y
	_kind[i] = kind
	_multi.set_instance_color(i, _color_for(kind, 1.0))
	_write_custom(i, energy_mult, kind)


## The custom data of an instance: the energy multiplier and the flag of the second texture.
func _write_custom(i: int, energy: float, kind: int) -> void:
	var alt := 1.0 if kind != SPARK else 0.0
	_multi.set_instance_custom_data(i, Color(0.0, energy, alt, 0.0))


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	for i in TUNE.SPARK_MAX:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_hide(i)
			continue
		var v := _vel[i]
		if _gravity[i] > 0.0:
			v.y -= TUNE.SPARK_GRAVITY * delta
			v *= maxf(1.0 - TUNE.SPARK_DRAG * delta, 0.0)
		var p := _pos[i] + v * delta
		if _gravity[i] > 0.0 and p.y < _ground[i]:
			p.y = _ground[i]
			v.y = -v.y * TUNE.SPARK_BOUNCE
			v.x *= TUNE.SPARK_TANGENTIAL_LOSS
			v.z *= TUNE.SPARK_TANGENTIAL_LOSS
		_pos[i] = p
		_vel[i] = v
		_write(i, cam, fwd)


func _write(i: int, cam: Camera3D, fwd: Vector3) -> void:
	var v := _vel[i]
	var screen := v - fwd * v.dot(fwd)
	if screen.length() < 0.05:
		screen = cam.global_transform.basis.y
	screen = screen.normalized()
	var right := fwd.cross(screen).normalized()
	var k := clampf(_life[i] / maxf(_max_life[i], 0.01), 0.0, 1.0)
	# Fast sparks stretch into streaks (motion-blur read) on top of their base size.
	var length := _length[i]
	if _kind[i] == SPARK:
		length += clampf(v.length() * TUNE.SPARK_STRETCH, 0.0, TUNE.SPARK_STRETCH_MAX)
	var basis := Basis(right * _thickness[i], screen * length, -fwd)
	_multi.set_instance_transform(i, Transform3D(basis, _pos[i]))
	_multi.set_instance_color(i, _color_for(_kind[i], k))
	_write_custom(i, _energy[i] * (0.35 + 0.65 * k), _kind[i])


func _color_for(kind: int, k: float) -> Color:
	match kind:
		AIR:
			var c := PALETTE.AIR
			c.a = k * 0.5
			return c
		VAPOUR:
			var v := PALETTE.VAPOUR
			v.a = k * 0.55
			return v
		_:
			# the spark stays white-hot for most of its life, then cools to amber
			var c := PALETTE.SPARK_COOL.lerp(PALETTE.SPARK_HOT, pow(k, 0.35))
			c.a = k
			return c


func _hide(i: int) -> void:
	_life[i] = 0.0
	_multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0)))
	_multi.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.0))


## How many more sparks fit into the pool.
func _room() -> int:
	return maxi(_limit - live_count(), 0)


## Removes every live spark (the test hook: a test starts with an empty pool).
func clear() -> void:
	for i in TUNE.SPARK_MAX:
		_hide(i)


## The lowest live spark (the test hook: the sparks must not fall through the road).
func lowest_point() -> float:
	var lowest := INF
	for i in TUNE.SPARK_MAX:
		if _life[i] > 0.0:
			lowest = minf(lowest, _pos[i].y)
	return lowest


## Live spark count (budget test).
func live_count() -> int:
	var live := 0
	for i in TUNE.SPARK_MAX:
		if _life[i] > 0.0:
			live += 1
	return live

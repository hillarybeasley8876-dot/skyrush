extends Node3D
## Global debris pool: glass shards and plastic bodywork bits thrown out by a big hit
## (gameplay DOSSIER §3.3 — "sparks, glass and body parts are oversized" in a takedown).
## The shards are small irregular triangles (2-6 cm) with a fresnel glint, not crossed quads; they
## tumble, bounce and shrink away over the last 0.3 s instead of popping out.
##
## There are three glass shapes and two plastic shapes, so a burst of debris does not read as
## one shape copied a dozen times.

const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

const SHRINK_TIME := 0.3
## The number of instances of every shape.
const GLASS_PER_SHAPE := 32
const PLASTIC_PER_SHAPE := 36

var _pools: Array[MultiMesh] = []
var _pos: Array[PackedVector3Array] = []
var _vel: Array[PackedVector3Array] = []
var _spin: Array[PackedVector3Array] = []
var _angle: Array[PackedFloat32Array] = []
var _life: Array[PackedFloat32Array] = []
var _max_life: Array[PackedFloat32Array] = []
var _size: Array[PackedFloat32Array] = []
var _ground: Array[PackedFloat32Array] = []
var _next: Array[int] = []
var _limits: Array[int] = []
## The kind of every pool: 0, 1, 2 = glass, 3, 4 = plastic.
var _kinds: Array[int] = []


func _ready() -> void:
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.roughness = 0.06
	glass_mat.metallic = 0.15
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.55, 0.85, 1.0)
	glass_mat.emission_energy_multiplier = 0.4
	glass_mat.rim_enabled = true
	glass_mat.rim = 0.6
	glass_mat.rim_tint = 0.6
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var plastic_mat := StandardMaterial3D.new()
	plastic_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	plastic_mat.vertex_color_use_as_albedo = true
	plastic_mat.roughness = 0.5
	plastic_mat.metallic = 0.05
	plastic_mat.rim_enabled = true
	plastic_mat.rim = 0.25

	for i in 3:
		_add_pool(GLASS_PER_SHAPE, glass_mat, PALETTE.GLASS, _shard_mesh(20261019 + i * 7919), 0)
	for i in 2:
		_add_pool(PLASTIC_PER_SHAPE, plastic_mat, PALETTE.PLASTIC,
				_chip_mesh(424242 + i * 6151), 3 + i)


func _add_pool(count: int, material: Material, tint: Color, mesh: ArrayMesh, kind: int) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.instance_count = count
	multi.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.multimesh = multi
	add_child(mi)
	_pools.append(multi)
	_kinds.append(kind)
	_next.append(0)
	_limits.append(count)
	_pos.append(_zeros3(count))
	_vel.append(_zeros3(count))
	_spin.append(_zeros3(count))
	_angle.append(_zeros(count))
	_life.append(_zeros(count))
	_max_life.append(_zeros(count))
	_size.append(_zeros(count))
	_ground.append(_zeros(count))
	for i in count:
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0)))
		multi.set_instance_color(i, tint)


## A zeroed array of the given size.
func _zeros(count: int) -> PackedFloat32Array:
	var array := PackedFloat32Array()
	array.resize(count)
	return array


## A zeroed vector array of the given size.
func _zeros3(count: int) -> PackedVector3Array:
	var array := PackedVector3Array()
	array.resize(count)
	return array


## Scales the pools with the quality preset.
func set_quality(quality: float) -> void:
	var q := clampf(quality, 0.2, 1.3)
	for i in _limits.size():
		var count := _pools[i].instance_count
		_limits[i] = clampi(int(float(count) * q), maxi(count / 6, 4), count)


## Bursts debris at `point`: the glass shards of the pools 0-2, the plastic bits of 3-4.
func burst(point: Vector3, normal: Vector3, glass_count: int, plastic_count: int,
		scale: float = 1.0, ground_y: float = 0.0, car_velocity: Vector3 = Vector3.ZERO) -> void:
	var dir := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	for i in glass_count:
		var kind := _pick_kind(0)
		_spawn(kind, point, _shot(dir, 3.4, 1.2) + car_velocity * TUNE.DEBRIS_CARRY,
				randf_range(TUNE.DEBRIS_SIZE_MIN, TUNE.DEBRIS_SIZE_MAX) * scale, 1.7 * scale,
				ground_y)
	for i in plastic_count:
		var kind := _pick_kind(3)
		_spawn(kind, point, _shot(dir, 2.8, 0.9) + car_velocity * TUNE.DEBRIS_CARRY,
				randf_range(TUNE.DEBRIS_SIZE_MIN * 1.4, TUNE.DEBRIS_SIZE_MAX * 1.6) * scale,
				2.2 * scale, ground_y)


## A random shape of a group (0-2 = glass, 3-4 = plastic).
func _pick_kind(first: int) -> int:
	var last := 2 if first == 0 else 4
	var kind := first + (randi() % (last - first + 1))
	return kind


func _shot(dir: Vector3, speed: float, spread: float) -> Vector3:
	var v := dir * randf_range(0.4, 1.0) \
			+ Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.2), randf_range(-1.0, 1.0)) * spread
	return v.normalized() * speed * randf_range(0.5, 1.4)


func _spawn(kind: int, point: Vector3, velocity: Vector3, size: float, life: float,
		ground_y: float) -> void:
	var index := _kind_index(kind)
	if index < 0:
		return
	var count := _pools[index].instance_count
	var i := _next[index]
	# The quality limit of the pool: a burst never fills a pool that is already full.
	if _life[index][i] > 0.0 and _filled(index) >= _limits[index]:
		return
	_next[index] = (_next[index] + 1) % count
	_pos[index][i] = point
	_vel[index][i] = velocity
	_angle[index][i] = randf() * TAU
	_spin[index][i] = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0),
			randf_range(-9.0, 9.0))
	_life[index][i] = life
	_max_life[index][i] = life
	_size[index][i] = size
	_ground[index][i] = ground_y


## The index of a kind in the pool arrays.
func _kind_index(kind: int) -> int:
	for i in _kinds.size():
		if _kinds[i] == kind:
			return i
	return -1


## The number of live pieces of a pool.
func _filled(index: int) -> int:
	var live := 0
	for i in _pools[index].instance_count:
		if _life[index][i] > 0.0:
			live += 1
	return live


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	for kind in _pools.size():
		var count := _pools[kind].instance_count
		for i in count:
			if _life[kind][i] <= 0.0:
				continue
			_life[kind][i] -= delta
			if _life[kind][i] <= 0.0:
				_pools[kind].set_instance_transform(i, Transform3D(Basis.IDENTITY,
						Vector3(0.0, -1000.0, 0.0)))
				continue
			var v := _vel[kind][i]
			v.y -= TUNE.DEBRIS_GRAVITY * delta
			var p := _pos[kind][i] + v * delta
			if p.y < _ground[kind][i]:
				p.y = _ground[kind][i]
				v.y = -v.y * TUNE.DEBRIS_BOUNCE
				v.x *= 0.6
				v.z *= 0.6
			_pos[kind][i] = p
			_vel[kind][i] = v
			_angle[kind][i] += _spin[kind][i].length() * delta
			# the shard shrinks away over the last 0.3 s instead of popping out
			var k := clampf(_life[kind][i] / maxf(_max_life[kind][i], 0.01), 0.0, 1.0)
			var shrink := minf(1.0, k / (SHRINK_TIME / maxf(_max_life[kind][i], 0.01)))
			var basis := Basis.from_euler(Vector3(_angle[kind][i], _angle[kind][i] * 0.7,
					_angle[kind][i] * 0.4))
			var scale := Vector3.ONE * _size[kind][i] * shrink
			_pools[kind].set_instance_transform(i, Transform3D(basis.scaled(scale), p))


## Live debris count (budget test).
func live_count() -> int:
	var live := 0
	for kind in _pools.size():
		for i in _pools[kind].instance_count:
			if _life[kind][i] > 0.0:
				live += 1
	return live


## An irregular glass shard: a jittered triangle.
static func _shard_mesh(seed_value: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points: Array[Vector3] = []
	for i in 3:
		points.append(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5),
				rng.randf_range(-0.06, 0.06)))
	for i in 3:
		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(Vector2(0.5 + points[i].x, 0.5 + points[i].y))
		st.add_vertex(points[i])
	st.generate_normals()
	return st.commit()


## An irregular plastic chip: a jittered quad.
static func _chip_mesh(seed_value: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var corners: Array[Vector3] = []
	for i in 4:
		corners.append(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.4, 0.4),
				rng.randf_range(-0.08, 0.08)))
	for i in 2:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var c := corners[(i + 2) % 4]
		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(Vector2(0.5 + a.x, 0.5 + a.y))
		st.add_vertex(a)
		st.set_uv(Vector2(0.5 + b.x, 0.5 + b.y))
		st.add_vertex(b)
		st.set_uv(Vector2(0.5 + c.x, 0.5 + c.y))
		st.add_vertex(c)
	st.generate_normals()
	return st.commit()

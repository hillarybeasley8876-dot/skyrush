extends Node3D
## Electric arcs: jagged polylines with a hot core and a per frame flicker. Used by the 闪充
## charge flash (cyan) and by the electrical arcs of a wrecked EV (white-blue).
##
## The arcs run ON the bodywork: about 200 surface points are cached in the local space of the
## car, and every vertex of every bolt is kept within ARC_SURFACE_OFFSET of that shell. A bolt
## is never longer than ARC_MAX_LENGTH, so the arcs never span the car and never stick out
## into the air (lead F-INT3).
##
## The node is a child of the car, so the geometry is built in the local space of the car and
## follows it (and it stays on the body when the car is flipped).

const ADD_SHADER := preload("res://fx/fx_add.gdshader")
const TEXTURES := preload("res://fx/fx_textures.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _paths: Array[PackedVector3Array] = []
var _branches: Array[PackedVector3Array] = []
## The surface points of the body, in the local space of the car.
var _surface: PackedVector3Array = PackedVector3Array()
## A hash of the surface points, so the nearest point is found in constant time.
var _grid: Dictionary = {}
var _cell: float = TUNE.ARC_MAX_LENGTH
var _count: int = 6
var _color: Color = Color(0.098, 0.902, 1.0)
var _energy: float = 6.0
var _running: bool = false
var _interval: float = 0.05
var _timer: float = 0.0
var _ground: float = 0.0
## True when the bolts run from the body down to the ground (the charge flash).
var _to_ground: bool = false
## The two ends of a bolt are at most this part of ARC_MAX_LENGTH apart.
const BOLT_END_FRACTION := 0.42


func setup(color: Color, energy: float, count: int) -> void:
	_color = color
	_energy = energy
	_count = count
	_build()


## Caches the surface of the bodywork of a car, in the local space of that car.
func set_surface(vehicle: VehicleBase) -> void:
	var points := PackedVector3Array()
	if vehicle != null and is_instance_valid(vehicle):
		var visual := vehicle.get_visual_root()
		if visual != null:
			var to_car := vehicle.global_transform.affine_inverse()
			for child in visual.find_children("*", "VisualInstance3D", true, false):
				var instance := child as VisualInstance3D
				if instance == null:
					continue
				_sample_aabb(instance, to_car, points)
	set_surface_points(points)


## Uses a ready made list of surface points (the test hook and the fallback without a car).
func set_surface_points(points: PackedVector3Array) -> void:
	_surface = points
	_build_grid()


## The ground the bolts of the charge flash run down to.
func set_ground(y: float) -> void:
	_ground = y


## The arcs of the charge flash jump from the body down to the ground.
func set_to_ground(value: bool) -> void:
	_to_ground = value


func _build() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.name = "Arcs"
	_instance.mesh = _mesh
	var mat := ShaderMaterial.new()
	mat.shader = ADD_SHADER
	mat.set_shader_parameter(&"albedo_tex", TEXTURES.arc_streak())
	mat.set_shader_parameter(&"use_texture", true)
	mat.set_shader_parameter(&"tint", _color)
	mat.set_shader_parameter(&"energy", _energy)
	_instance.material_override = mat
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)


func play() -> void:
	_running = true
	_regenerate()


## Rebuilds the arcs now (the EV wreck strikes them continuously).
func regenerate() -> void:
	_regenerate()


func stop() -> void:
	_running = false
	_paths.clear()
	_branches.clear()
	_mesh.clear_surfaces()


## True while the arcs are running.
func is_running() -> bool:
	return _running


## The bolts of the last generation (the test hook).
func paths() -> Array[PackedVector3Array]:
	return _paths


## The length of a bolt (the sum of its segments).
static func path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total


func _process(delta: float) -> void:
	if not _running:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _interval
		_regenerate()
	_rebuild()


## Samples the surface of the bounding box of a mesh, in the local space of the car.
func _sample_aabb(instance: VisualInstance3D, to_car: Transform3D, out: PackedVector3Array) -> void:
	var aabb := instance.get_aabb()
	var size := aabb.size
	var steps := Vector3(
			clampi(int(size.x / 0.3), 1, 6),
			clampi(int(size.y / 0.3), 1, 6),
			clampi(int(size.z / 0.3), 1, 6))
	var xform := instance.global_transform
	for axis in 3:
		for side in 2:
			var count_a: int = steps[(axis + 1) % 3]
			var count_b: int = steps[(axis + 2) % 3]
			for i in count_a:
				for j in count_b:
					var local := aabb.position
					var u := (float(i) + 0.5) / float(count_a)
					var v := (float(j) + 0.5) / float(count_b)
					local[axis] = aabb.position[axis] + (0.0 if side == 0 else size[axis])
					local[(axis + 1) % 3] = aabb.position[(axis + 1) % 3] \
							+ size[(axis + 1) % 3] * u
					local[(axis + 2) % 3] = aabb.position[(axis + 2) % 3] \
							+ size[(axis + 2) % 3] * v
					var point: Vector3 = to_car * (xform * local)
					if out.size() < TUNE.ARC_SURFACE_POINTS * 3:
						out.append(point)


## A hash of the surface points, so the nearest point is found without a linear scan.
func _build_grid() -> void:
	_grid.clear()
	for i in _surface.size():
		var key := _cell_key(_surface[i])
		if not _grid.has(key):
			_grid[key] = []
		var bucket: Array = _grid[key]
		bucket.append(i)


func _cell_key(point: Vector3) -> Vector3i:
	return Vector3i(int(floor(point.x / _cell)), int(floor(point.y / _cell)),
			int(floor(point.z / _cell)))


## The nearest surface point of a position (the index, -1 when there is no surface).
func _nearest_index(point: Vector3) -> int:
	var key := _cell_key(point)
	var best := -1
	var best_distance := INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var k := key + Vector3i(dx, dy, dz)
				if not _grid.has(k):
					continue
				for i in _grid[k]:
					var d := _surface[i].distance_squared_to(point)
					if d < best_distance:
						best_distance = d
						best = i
	if best < 0:
		for i in _surface.size():
			var d := _surface[i].distance_squared_to(point)
			if d < best_distance:
				best_distance = d
				best = i
	return best


## Keeps a point on the body: it is never further than ARC_SURFACE_OFFSET from the shell.
func _constrain(point: Vector3) -> Vector3:
	var index := _nearest_index(point)
	if index < 0:
		return point
	var shell := _surface[index]
	var delta := point - shell
	if delta.length() <= TUNE.ARC_SURFACE_OFFSET:
		return point
	return shell + delta.normalized() * TUNE.ARC_SURFACE_OFFSET


## A random point of the shell.
func _pick_point() -> Vector3:
	if _surface.is_empty():
		return Vector3.ZERO
	return _surface[randi() % _surface.size()]


## A random point of the shell that is close to `from`. The two ends of a bolt are close
## enough that the whole bolt stays shorter than ARC_MAX_LENGTH.
func _pick_near(from: Vector3) -> Vector3:
	var near: Array[Vector3] = []
	var limit := TUNE.ARC_MAX_LENGTH * BOLT_END_FRACTION
	for point in _surface:
		if from.distance_to(point) <= limit:
			near.append(point)
	if near.is_empty():
		var index := _nearest_index(from)
		return _surface[index] if index >= 0 else from
	return near[randi() % near.size()]


## A point of the shell near the ground (the bolts of the charge flash run down to the road).
func _pick_low_point() -> Vector3:
	var low: Array[Vector3] = []
	for point in _surface:
		if point.y <= _ground + 0.7:
			low.append(point)
	if low.is_empty():
		return _pick_point()
	return low[randi() % low.size()]


func _regenerate() -> void:
	_paths.clear()
	_branches.clear()
	if _surface.size() < 4:
		return
	for i in _count:
		var path := _make_path()
		if path.size() < 2:
			continue
		_paths.append(path)
		if randf() < 0.6:
			var branch := _make_branch(path)
			if branch.size() >= 2:
				_branches.append(branch)


## One bolt: a recursive midpoint displacement between two points of the shell.
func _make_path() -> PackedVector3Array:
	var a := _pick_low_point() if _to_ground else _pick_point()
	var b := _pick_near(a)
	if _to_ground:
		b = Vector3(a.x, _ground, a.z)
	return _jagged(a, b, TUNE.ARC_DEPTH, TUNE.ARC_DISPLACEMENT)


## A short branch that leaves a bolt sideways.
func _make_branch(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 3:
		return PackedVector3Array()
	var at := randi_range(1, path.size() - 2)
	var from := path[at]
	var direction := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)).normalized()
	var to := _constrain(from + direction * TUNE.ARC_BRANCH_LENGTH)
	return _jagged(from, to, 2, TUNE.ARC_DISPLACEMENT * 0.5)


func _jagged(a: Vector3, b: Vector3, depth: int, spread: float) -> PackedVector3Array:
	if depth <= 0:
		return PackedVector3Array([a, b])
	var mid := (a + b) * 0.5 + Vector3(randf_range(-spread, spread),
			randf_range(-spread, spread), randf_range(-spread, spread))
	mid = _constrain(mid)
	var left := _jagged(a, mid, depth - 1, spread * 0.5)
	var right := _jagged(mid, b, depth - 1, spread * 0.5)
	var out := PackedVector3Array()
	out.append_array(left)
	out.append_array(right)
	return out


## Rebuilds the additive ribbon geometry: a hot core that faces the camera, flickering per frame.
func _rebuild() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var cam_local := to_local(cam.global_position) if cam != null else Vector3(0.0, 0.0, 10.0)
	for path: PackedVector3Array in _paths:
		_emit_path(path, cam_local)
	for path: PackedVector3Array in _branches:
		_emit_path(path, cam_local)
	_mesh.surface_end()


func _emit_path(path: PackedVector3Array, cam_local: Vector3) -> void:
	var flicker := randf_range(0.7, 1.3)
	for i in path.size() - 1:
		var t := float(i) / maxf(float(path.size() - 1), 1.0)
		_emit_segment(path[i], path[i + 1], TUNE.ARC_WIDTH * (0.7 + 0.6 * flicker),
				(1.0 - t * 0.5) * flicker, cam_local)


## One segment of a bolt. The ribbon faces the camera: the side of the ribbon is the direction
## of the segment times the direction to the camera.
func _emit_segment(a: Vector3, b: Vector3, width: float, fade: float, cam_local: Vector3) -> void:
	var dir := b - a
	if dir.length() < 0.0001:
		return
	dir = dir.normalized()
	var to_cam := (cam_local - a).normalized()
	var side := dir.cross(to_cam)
	if side.length() < 0.0001:
		side = dir.cross(Vector3.UP)
	side = side.normalized() * width
	_emit_quad(a - side, b - side, b + side, a + side, fade)


func _emit_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, fade: float) -> void:
	var col := Color(_color.r, _color.g, _color.b, clampf(fade, 0.0, 1.0))
	_mesh.surface_set_color(col)
	_mesh.surface_set_uv(Vector2(0.5, 0.0))
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_uv(Vector2(0.5, 1.0))
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_uv(Vector2(0.5, 1.0))
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_uv(Vector2(0.5, 0.0))
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_uv(Vector2(0.5, 1.0))
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_uv(Vector2(0.5, 0.0))
	_mesh.surface_add_vertex(d)

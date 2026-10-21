extends Node3D
## The electrical arcs of an electric car (dossier §7.4): the heavy state of the Roadster
## throws blue-white arcs over the front arches and the frunk seam.
##
## The arcs are jagged polylines (8 segments, a jitter of 6 cm) between random points of
## the front of the car. They are regenerated every 50 ms during a burst of 0.12-0.25 s, and
## a burst starts every 0.15-0.5 s. The ribbons face the camera and are HDR, so they glow.

const ARC_COLOR := Color(0.918, 0.965, 1.0)     ## #EAF6FF
const HALO_COLOR := Color(0.239, 0.482, 1.0)     ## #3D7BFF
const HALO_ALPHA := 0.5
## The core of the arc is HDR, so it is above the glow threshold of the night.
const CORE_HDR := 8.0
const HALO_HDR := 2.0
const LIGHT_COLOR := Color(0.353, 0.722, 1.0)    ## #5AB8FF
const LIGHT_ENERGY := 3.0
const LIGHT_RANGE := 4.0
## The width of the core and of the halo.
const CORE_WIDTH := 0.012
const HALO_WIDTH := 0.08
## The number of arcs and of their segments.
const ARC_COUNT := 3
const ARC_SEGMENTS := 8
## The jitter of the middle points.
const JITTER := 0.06
## The timing of the bursts.
const REGENERATE := 0.05
const BURST_MIN := 0.12
const BURST_MAX := 0.25
const GAP_MIN := 0.15
const GAP_MAX := 0.5
## The box of the car the arcs jump over (the front arches and the frunk seam).
const ARC_BOX_MIN := Vector3(-0.95, 0.35, -2.10)
const ARC_BOX_MAX := Vector3(0.95, 0.95, -1.30)

var _core: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _light: OmniLight3D = null
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _burst_left: float = 0.0
var _gap: float = 0.0
var _car: VehicleBase = null


func setup(car: VehicleBase) -> void:
	_car = car
	_rng.randomize()
	_core = _make_ribbon(ARC_COLOR * CORE_HDR, CORE_WIDTH, true)
	_halo = _make_ribbon(HALO_COLOR * HALO_HDR, HALO_WIDTH, false)
	add_child(_core)
	add_child(_halo)
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.light_energy = 0.0
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	_core.visible = false
	_halo.visible = false
	_gap = _rng.randf_range(GAP_MIN, GAP_MAX)
	# The arcs cost nothing while they are off.
	set_process(false)


func _process(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		return
	_timer -= delta
	if _burst_left > 0.0:
		_burst_left -= delta
		_light.light_energy = LIGHT_ENERGY * clampf(_burst_left / BURST_MAX, 0.0, 1.0)
		if _timer <= 0.0:
			_timer = REGENERATE
			_rebuild()
		if _burst_left <= 0.0:
			stop()
		return
	_gap -= delta
	if _gap <= 0.0:
		_gap = _rng.randf_range(GAP_MIN, GAP_MAX)
		_burst_left = _rng.randf_range(BURST_MIN, BURST_MAX)
		_timer = 0.0
		_light.light_energy = LIGHT_ENERGY
		_rebuild()


## Stops the arcs (the respawn, the repair).
func stop() -> void:
	_burst_left = 0.0
	if _core != null:
		_core.visible = false
	if _halo != null:
		_halo.visible = false
	if _light != null:
		_light.light_energy = 0.0
	set_process(false)


## The arcs of the heavy state start on their own.
func start() -> void:
	_gap = 0.0
	set_process(true)


## Builds the arcs of the burst.
func _rebuild() -> void:
	var points := _arc_points()
	_draw(_core, points, CORE_WIDTH)
	_draw(_halo, points, HALO_WIDTH)
	_core.visible = true
	_halo.visible = true


## The points of the arcs: random pairs on the front of the car.
func _arc_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var car_inv := _car.global_transform.affine_inverse()
	for a in ARC_COUNT:
		var from := _random_point(car_inv)
		var to := _random_point(car_inv)
		points.append(from)
		for i in range(1, ARC_SEGMENTS):
			var t := float(i) / float(ARC_SEGMENTS)
			var base := from.lerp(to, t)
			# The middle points are pushed sideways, so the arc is jagged.
			var side := (to - from).cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized() * _rng.randf_range(-JITTER, JITTER)
			points.append(base + side + Vector3.UP * _rng.randf_range(-JITTER, JITTER))
		points.append(to)
	return points


## A random point on the front of the car, in the space of the car.
func _random_point(car_inv: Transform3D) -> Vector3:
	var point := Vector3(
		_rng.randf_range(ARC_BOX_MIN.x, ARC_BOX_MAX.x),
		_rng.randf_range(ARC_BOX_MIN.y, ARC_BOX_MAX.y),
		_rng.randf_range(ARC_BOX_MIN.z, ARC_BOX_MAX.z))
	return car_inv * point


## The camera the arcs face.
func _camera_position() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		return camera.global_position
	return _car.global_position if _car != null else Vector3.ZERO


## Draws the polyline as a flat ribbon of the given width, facing the camera.
func _draw(target: MeshInstance3D, points: PackedVector3Array, width: float) -> void:
	if target == null:
		return
	var mesh := target.mesh as ImmediateMesh
	if mesh == null:
		mesh = ImmediateMesh.new()
		target.mesh = mesh
	var camera := _camera_position()
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := points.size()
	for i in range(1, count):
		var a := points[i - 1]
		var b := points[i]
		var direction := b - a
		if direction.length() < 0.0001:
			continue
		# The ribbon faces the camera: the side of the ribbon is the direction of the line
		# crossed with the direction of the camera.
		var to_camera := camera - (a + b) * 0.5
		var side := direction.cross(to_camera)
		if side.length() < 0.0001:
			side = direction.cross(Vector3.UP)
		if side.length() < 0.0001:
			side = direction.cross(Vector3.RIGHT)
		side = side.normalized() * width * 0.5
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(a - side)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(b - side)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(b + side)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(a - side)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(b + side)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0))
		mesh.surface_add_vertex(a + side)
	mesh.surface_end()


## The ribbon material: unshaded and additive. The colour is HDR, so the arc glows.
func _make_ribbon(colour: Color, width: float, core: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	material.albedo_color.a = 1.0 if core else HALO_ALPHA
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

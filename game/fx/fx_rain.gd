extends Node3D
## Rain (brief §5): camera-attached streak particles (≤ 6k) plus splash rings on the road near the
## camera. Driven by the environment unit's weather controller. Quality preset "rain" switches the
## whole system off on low.
##
## The streaks use their own shader: the streak axis follows (rain velocity - camera velocity) and
## converges on the vanishing point, so they rush at the camera at speed.
##
## The splashes are emitted from the points where a raycast grid found road: the point texture is
## a list of positions (one texel per hit, in metres) and the normal texture the direction of the
## surface, so the rings lie flat on a ramp.
##
## The offsets of the point texture are relative to the emitter, and the emitter stands at the
## height 0: the height of every point is the height of the road, so the rings lie ON the road
## and not under it.

const RAIN_SHADER := preload("res://fx/fx_rain.gdshader")
const SOFT_SHADER := preload("res://fx/fx_soft.gdshader")
const ADD_SHADER := preload("res://fx/fx_add.gdshader")
const TEXTURES := preload("res://fx/fx_textures.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const Dev := preload("res://fx/fx_dev.gd")

var _streaks: GPUParticles3D
var _splashes: GPUParticles3D
var _crowns: GPUParticles3D
var _rain_material: ShaderMaterial
var _intensity: float = 0.0
var _quality: float = 1.0
var _enabled: bool = true
var _probe_timer: float = 0.0
var _last_camera_position: Vector3 = Vector3.ZERO
var _camera_velocity: Vector3 = Vector3.ZERO
## The dev switches of the unit (--fx-no-splash).
var dev: Dev = null
## The points where the road was found, in world space.
var _hits: Array[Vector3] = []
var _hit_normals: Array[Vector3] = []
var _points: ImageTexture
var _normals: ImageTexture
var _point_image: Image
var _normal_image: Image


func _ready() -> void:
	# The rain follows the camera every drawn frame: no physics interpolation for it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_point_image = Image.create(TUNE.SPLASH_GRID, TUNE.SPLASH_GRID, false, Image.FORMAT_RGBF)
	_point_image.fill(Color(0.0, 0.0, 0.0))
	_normal_image = Image.create(TUNE.SPLASH_GRID, TUNE.SPLASH_GRID, false, Image.FORMAT_RGBF)
	_normal_image.fill(Color(0.0, 1.0, 0.0))
	_points = ImageTexture.create_from_image(_point_image)
	_normals = ImageTexture.create_from_image(_normal_image)
	_streaks = _make_streaks()
	add_child(_streaks)
	_splashes = _make_splashes()
	add_child(_splashes)
	_crowns = _make_crowns()
	add_child(_crowns)
	_apply()


func _make_streaks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RainStreaks"
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = TUNE.RAIN_MAX
	p.lifetime = TUNE.RAIN_LIFETIME
	p.randomness = 0.4
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 60.0, 40.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = TUNE.RAIN_BOX * 0.5
	mat.direction = Vector3(0.12, -1.0, 0.05)
	mat.spread = 2.0
	mat.initial_velocity_min = TUNE.RAIN_SPEED * 0.95
	mat.initial_velocity_max = TUNE.RAIN_SPEED * 1.05
	mat.gravity = Vector3(0.0, -6.0, 0.0)
	mat.scale_min = 0.7
	mat.scale_max = 1.5
	mat.color_ramp = _ramp([[0.0, PALETTE.RAIN], [0.35, PALETTE.RAIN], [1.0, PALETTE.RAIN]])
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain_material.set_shader_parameter(&"streak_tex", TEXTURES.rain_streak())
	quad.material = _rain_material
	p.draw_pass_1 = quad
	return p


## A flat expanding ripple on the road (a ring with thinner rings around it, no velocity).
func _make_splashes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RainSplashes"
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = TUNE.SPLASH_AMOUNT
	p.lifetime = TUNE.SPLASH_LIFETIME
	p.randomness = 0.5
	p.local_coords = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-14.0, -2.0, -14.0), Vector3(28.0, 6.0, 28.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	mat.emission_point_texture = _points
	mat.emission_normal_texture = _normals
	mat.emission_point_count = 0
	mat.direction = Vector3(0.0, 0.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = TUNE.SPLASH_SIZE_MIN
	mat.scale_max = TUNE.SPLASH_SIZE_MAX
	mat.scale_curve = _expand(TUNE.SPLASH_GROW)
	mat.color_ramp = _ramp([[0.0, PALETTE.SPLASH_RIM], [0.3, PALETTE.SPLASH_RIM],
			[1.0, PALETTE.SPLASH_RIM]])
	p.process_material = mat
	# The ring is additive: it has to catch the street lamps, and it lies flat on the road.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var qmat := ShaderMaterial.new()
	qmat.shader = ADD_SHADER
	qmat.set_shader_parameter(&"albedo_tex", TEXTURES.ripple())
	qmat.set_shader_parameter(&"use_texture", true)
	qmat.set_shader_parameter(&"tint", PALETTE.SPLASH_RIM)
	qmat.set_shader_parameter(&"energy", TUNE.SPLASH_ENERGY)
	plane.material = qmat
	p.draw_pass_1 = plane
	return p


## The tiny crown splash that jumps up from a ring.
func _make_crowns() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RainCrowns"
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = TUNE.SPLASH_CROWN_AMOUNT
	p.lifetime = TUNE.SPLASH_CROWN_LIFETIME
	p.randomness = 0.6
	p.local_coords = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-14.0, -1.0, -14.0), Vector3(28.0, 4.0, 28.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	mat.emission_point_texture = _points
	mat.emission_normal_texture = _normals
	mat.emission_point_count = 0
	# The crown jumps up along the normal of the surface.
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 30.0
	mat.initial_velocity_min = TUNE.SPLASH_CROWN_SPEED_MIN
	mat.initial_velocity_max = TUNE.SPLASH_CROWN_SPEED_MAX
	mat.gravity = Vector3(0.0, -TUNE.SPLASH_CROWN_GRAVITY, 0.0)
	mat.scale_min = TUNE.SPLASH_CROWN_SIZE_MIN
	mat.scale_max = TUNE.SPLASH_CROWN_SIZE_MAX
	mat.color_ramp = _ramp([[0.0, PALETTE.SPLASH], [1.0, PALETTE.SPLASH]])
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var qmat := ShaderMaterial.new()
	qmat.shader = SOFT_SHADER
	qmat.set_shader_parameter(&"albedo_tex", TEXTURES.rain_streak())
	qmat.set_shader_parameter(&"use_texture", false)
	qmat.set_shader_parameter(&"soft_distance", 0.15)
	qmat.set_shader_parameter(&"depth_fade", 0.0)
	qmat.set_shader_parameter(&"ambient_lift", 0.6)
	quad.material = qmat
	p.draw_pass_1 = quad
	return p


## Sets the rain strength (0..1) and the quality scale.
func set_intensity(value: float, quality: float, enabled: bool) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_quality = clampf(quality, 0.2, 1.3)
	_enabled = enabled
	_apply()


func _apply() -> void:
	if _streaks == null or _splashes == null or _crowns == null:
		return
	var on := _enabled and _intensity > 0.01
	_streaks.emitting = on
	_splashes.emitting = on and not _splash_off()
	_crowns.emitting = on and not _splash_off()
	# The streak count is hard capped (brief: ≤ 6k); amount_ratio fades the rain in.
	# The amount itself is set once, when the system is built: writing it again would
	# reallocate the system and make the rain pop.
	_streaks.amount_ratio = clampf(_intensity * _quality, 0.0, 1.0)
	_splashes.amount_ratio = clampf(_intensity * _quality, 0.0, 1.0)
	_crowns.amount_ratio = clampf(_intensity * _quality, 0.0, 1.0)


## True when the dev switches ask for the splash rings to be off.
func _splash_off() -> bool:
	return dev != null and dev.no_splash


## The ground is probed in the physics step: a raycast outside of it is not safe.
func _physics_process(delta: float) -> void:
	if not _enabled or _intensity <= 0.01 or _splash_off():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = TUNE.SPLASH_PROBE_INTERVAL
		_probe_ground(cam)


func _process(delta: float) -> void:
	if not _enabled or _intensity <= 0.01:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var position := cam.global_position
	if delta > 0.0:
		_camera_velocity = (position - _last_camera_position) / delta
	_last_camera_position = position
	# The rain volume is pushed ahead of the camera so the streaks arrive from the front.
	_streaks.global_position = position + _camera_velocity * TUNE.RAIN_LEAD \
			+ cam.global_transform.basis.y * 9.0
	_rain_material.set_shader_parameter(&"relative_velocity",
			Vector3(0.0, -TUNE.RAIN_SPEED, 0.0) - _camera_velocity)
	# The splash points are relative to the emitter, and the emitter stands at the height 0: the
	# height of every point is the height of the road, so the rings stay ON the road.
	_splashes.global_position = Vector3(position.x, 0.0, position.z)
	_crowns.global_position = _splashes.global_position
	# At speed the streaks converge on the vanishing point.
	_rain_material.set_shader_parameter(&"convergence",
			clampf(_camera_velocity.length() / 30.0, 0.0, 1.0) * 0.6)
	if _splash_off():
		return
	_update_splash_points(position)


## The camera position of the last probe of the ground.
var _last_probe_position: Vector3 = Vector3.ZERO


## Moves the splash points with the camera: the offsets are the distance from the emitter to
## the places where the road was found.
func _update_splash_points(camera_position: Vector3) -> void:
	if _hits.is_empty():
		return
	var origin := Vector3(camera_position.x, 0.0, camera_position.z)
	for i in _hits.size():
		var offset := _hits[i] - origin + Vector3.UP * TUNE.SPLASH_LIFT
		_point_image.set_pixel(i % TUNE.SPLASH_GRID, i / TUNE.SPLASH_GRID,
				Color(offset.x, offset.y, offset.z))
	_points.update(_point_image)
	_last_probe_position = camera_position


## Probes the road under the camera with a grid of rays; only the hits become splash points.
##
## Most of the points land in front of the camera, close to it: the rings that are 20 m away
## are a texture on the road, they are not read.
func _probe_ground(cam: Camera3D) -> void:
	var space := get_world_3d().direct_space_state
	var position := cam.global_position
	var forward := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	_hits.clear()
	_hit_normals.clear()
	var grid := TUNE.SPLASH_GRID
	for gz in grid:
		for gx in grid:
			var probe := _probe_point(position, forward, right, gx, gz, grid)
			var result := GROUND.probe(space, probe)
			if result["hit"]:
				_hits.append(result["point"])
				_hit_normals.append(result["normal"])
	if _hits.is_empty():
		_splashes.process_material.emission_point_count = 0
		_crowns.process_material.emission_point_count = 0
		return
	for i in _hit_normals.size():
		var n := _hit_normals[i]
		_normal_image.set_pixel(i % grid, i / grid, Color(n.x, n.y, n.z))
	_normals.update(_normal_image)
	_splashes.process_material.emission_point_count = _hits.size()
	_crowns.process_material.emission_point_count = _hits.size()
	_update_splash_points(position)


## One probe point: most of the points are a few metres in front of the camera, the rest are
## spread over the whole box around it.
func _probe_point(position: Vector3, forward: Vector3, right: Vector3, gx: int, gz: int,
		grid: int) -> Vector3:
	if randf() < TUNE.SPLASH_NEAR_SHARE:
		var ahead := randf_range(1.0, TUNE.SPLASH_NEAR_DISTANCE)
		var side := randf_range(-TUNE.SPLASH_NEAR_DISTANCE * 0.5, TUNE.SPLASH_NEAR_DISTANCE * 0.5)
		return position + forward * ahead + right * side
	var u := (float(gx) + randf_range(-0.5, 0.5)) / float(grid) - 0.5
	var v := (float(gz) + randf_range(-0.5, 0.5)) / float(grid) - 0.5
	# The grid is jittered on every probe, so the rings are never in the same place.
	u += randf_range(-TUNE.SPLASH_JITTER, TUNE.SPLASH_JITTER) / TUNE.SPLASH_BOX
	v += randf_range(-TUNE.SPLASH_JITTER, TUNE.SPLASH_JITTER) / TUNE.SPLASH_BOX
	return position + Vector3(u * TUNE.SPLASH_BOX, 0.0, v * TUNE.SPLASH_BOX)


## True while the rain is actually emitting.
func is_emitting() -> bool:
	return _streaks != null and _streaks.emitting


## The number of splash points that were found under the camera (test hook).
func splash_point_count() -> int:
	return _hits.size()


## The world position of every splash ring, read from the point texture (the test hook: the
## ring has to land on the place where the ray found the road).
func splash_ring_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var xform := _splashes.global_transform
	for i in _hits.size():
		var offset := _point_image.get_pixel(i % TUNE.SPLASH_GRID, i / TUNE.SPLASH_GRID)
		out.append(xform * Vector3(offset.r, offset.g, offset.b))
	return out


## Billboard budget of the rain system (streaks + splash rings + crowns). Only the systems that
## are actually running are counted: the rain may be off.
func billboard_count() -> int:
	if _streaks == null or not _streaks.emitting:
		return 0
	return int((_streaks.amount + _splashes.amount + _crowns.amount) * _streaks.amount_ratio)


func _ramp(points: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for pair: Array in points:
		offsets.append(float(pair[0]))
		colors.append(pair[1])
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## The growth of a ring: it starts at its size and grows by `grow` over its life.
func _expand(grow: float) -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = grow
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, grow))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

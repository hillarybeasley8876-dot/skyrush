extends Node
## The screen-space effect stack of the camera unit: the radial blur CompositorEffect and the
## speed-line streaks. Owns the camera unit's own config file (the `motion_blur` toggle
## until core adds it to `Settings`).
##
## Everything is suppressed while the takedown / focus cam owns the camera, while the game
## is paused and in the menus: the effects would otherwise smear the shot or keep flowing
## over a pause screen.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const CameraConfig := preload("res://vehicle/camera/camera_config.gd")
const CameraOverlay := preload("res://vehicle/camera/camera_overlay.gd")
const RadialBlurEffect := preload("res://vehicle/camera/radial_blur_effect.gd")

## How far ahead the motion vanishing point is placed, in metres.
const VANISHING_DIST := 100.0
## How far ahead the horizon line is placed, in metres.
const HORIZON_DIST := 1000.0
## The height of the car's centre above its origin, for the screen position.
const CAR_SCREEN_HEIGHT := 0.6
## The blur centre stays inside this box, so a vanishing point off screen cannot smear.
const BLUR_CENTRE_MIN := 0.15
const BLUR_CENTRE_MAX := 0.85
## The sharp spot around the car (a share of the screen height).
const CAR_MASK_RADIUS := 0.16
const CAR_MASK_FEATHER := 0.08
## The reference height the streak width is authored at.
const REFERENCE_HEIGHT := 1080.0

var _camera: Camera3D = null
var _overlay: CameraOverlay = null
var _config: CameraConfig = null
var _blur: RadialBlurEffect = null
var _blur_strength: float = 0.0
var _streak_colour: Color = CameraMath.STREAK_COLOUR
var _streak_alpha: float = CameraMath.STREAK_ALPHA
var _scroll_phase: float = 0.0
var _suppressed: bool = false
var _look_back: bool = false
var _player: Node3D = null


func _ready() -> void:
	Events.game_paused.connect(_on_game_paused)


func setup(camera: Camera3D, overlay: CameraOverlay) -> void:
	_camera = camera
	_overlay = overlay
	_config = CameraConfig.new()
	_config.load_from_disk()
	_setup_radial_blur()
	_set_constant_uniforms()


## The takedown / focus cam owns the camera: no streaks, no blur.
func set_suppressed(value: bool) -> void:
	_suppressed = value


## While looking back the scene recedes backwards, so the streaks are hidden.
func set_look_back(value: bool) -> void:
	_look_back = value


## Drives the stack from the gameplay state: the blur is off in the menus, the streaks only
## above 160 km/h.
func update(delta: float, speed_kmh: float, nitro: bool, player: Node3D) -> void:
	_player = player
	var paused := get_tree().paused
	var in_menu := Game.mode == &"menu"
	_update_blur(delta, speed_kmh, nitro, player, paused or in_menu)
	_update_streaks(delta, speed_kmh, nitro, player, paused or in_menu)


func motion_blur_enabled() -> bool:
	return _config != null and _config.motion_blur


## The camera shake shares the camera unit's config file.
func shake_enabled() -> bool:
	return _config == null or _config.camera_shake


## The radial blur strength the camera is driving.
func get_blur_strength() -> float:
	return _blur_strength


## The blur centre the camera is driving (the motion vanishing point).
func get_blur_centre() -> Vector2:
	return _blur_centre()


## The raw motion vanishing point in screen UV (INF when it cannot be projected).
func get_vanishing_uv(player: Node3D = null) -> Vector2:
	return _vanishing_uv(player if player != null else _player)


func set_motion_blur(enabled: bool) -> void:
	if _config != null:
		_config.set_motion_blur(enabled)


func _on_game_paused(paused: bool) -> void:
	# The camera does not tick while the game is paused, so the quad is hidden here.
	if paused and _overlay != null:
		_overlay.set_streaks_visible(false)
	_blur_strength = 0.0
	if _blur != null:
		_blur.strength = 0.0


## The uniforms that never change are set once, not every frame.
func _set_constant_uniforms() -> void:
	if _overlay == null or _overlay.streak_material == null:
		return
	var material := _overlay.streak_material
	material.set_shader_parameter(&"lanes", CameraMath.STREAK_LANES)
	material.set_shader_parameter(&"lit_ratio", CameraMath.STREAK_LIT_RATIO)
	material.set_shader_parameter(&"dash_ratio", CameraMath.STREAK_DASH_RATIO)
	material.set_shader_parameter(&"car_feather", CameraMath.STREAK_CAR_FEATHER)
	material.set_shader_parameter(&"sky_factor", CameraMath.STREAK_SKY_FACTOR)


func _setup_radial_blur() -> void:
	if _camera == null or DisplayServer.get_name() == "headless":
		return
	_blur = RadialBlurEffect.new()
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = []
	effects.append(_blur)
	compositor.compositor_effects = effects
	_camera.compositor = compositor


## The blur follows the speed ramp and never jumps (lambda 6 /s). Its centre is the motion
## vanishing point and the car is masked out, so the car itself stays sharp.
func _update_blur(delta: float, speed_kmh: float, nitro: bool, player: Node3D, quiet: bool) -> void:
	var target := 0.0
	if not quiet and not _suppressed and _config.motion_blur:
		target = CameraMath.blur_strength(speed_kmh, nitro)
	if quiet or _suppressed:
		_blur_strength = 0.0          # snap on the cut, no fade over the shot
	else:
		_blur_strength = CameraMath.damp(_blur_strength, target, CameraMath.BLUR_LAMBDA, delta)
	if _blur == null:
		return
	_blur.strength = _blur_strength
	_blur.center = _blur_centre()
	var car_uv := _car_uv(player)
	if car_uv == Vector2.INF:
		_blur.car_radius = 0.0
	else:
		_blur.car_uv = car_uv
		_blur.car_radius = CAR_MASK_RADIUS
	_blur.feather = CAR_MASK_FEATHER


## The motion vanishing point in screen UV, clamped so it can never smear the whole frame.
func _blur_centre() -> Vector2:
	if _look_back or _camera == null:
		return Vector2(0.5, 0.5)
	var focus := _vanishing_uv(_player)
	if focus == Vector2.INF:
		return Vector2(0.5, 0.5)
	return Vector2(clampf(focus.x, BLUR_CENTRE_MIN, BLUR_CENTRE_MAX),
			clampf(focus.y, BLUR_CENTRE_MIN, BLUR_CENTRE_MAX))


func _update_streaks(delta: float, speed_kmh: float, nitro: bool, player: Node3D, quiet: bool) -> void:
	if _overlay == null or _overlay.streak_material == null:
		return
	var material := _overlay.streak_material
	var intensity := 0.0
	if not quiet and not _suppressed and not _look_back and _config.speed_lines:
		intensity = CameraMath.speed_line_intensity(speed_kmh)
	_overlay.set_streaks_visible(intensity > 0.001)
	if intensity <= 0.001:
		return
	# The colour cross-fades to the ART cyan in N2.
	var target_colour := CameraMath.STREAK_COLOUR_NITRO if nitro else CameraMath.STREAK_COLOUR
	_streak_colour = _streak_colour.lerp(target_colour, 1.0 - exp(-CameraMath.STREAK_COLOUR_LAMBDA * delta))
	var target_alpha := CameraMath.STREAK_ALPHA_NITRO if nitro else CameraMath.STREAK_ALPHA
	_streak_alpha = CameraMath.damp(_streak_alpha, target_alpha, CameraMath.STREAK_COLOUR_LAMBDA, delta)
	# The streaks scroll with the game (not with the wall clock), so they freeze when it does.
	var scroll_px := speed_kmh * CameraMath.STREAK_SCROLL_PX_PER_KMH
	_scroll_phase += scroll_px * delta
	material.set_shader_parameter(&"intensity", intensity)
	material.set_shader_parameter(&"streak_color", _streak_colour)
	material.set_shader_parameter(&"alpha_scale", _streak_alpha)
	material.set_shader_parameter(&"line_width_px", CameraMath.STREAK_WIDTH_PX * _viewport_height() / REFERENCE_HEIGHT)
	material.set_shader_parameter(&"scroll_phase", _scroll_phase)
	var focus := _vanishing_uv(player)
	if focus != Vector2.INF:
		material.set_shader_parameter(&"focus", focus)
	var car_uv := _car_uv(player)
	if car_uv == Vector2.INF:
		material.set_shader_parameter(&"car_radius", 0.0)
	else:
		material.set_shader_parameter(&"car_pos", car_uv)
		material.set_shader_parameter(&"car_radius", CameraMath.STREAK_CAR_RADIUS)
	var horizon := _horizon_uv()
	if horizon != Vector2.INF:
		material.set_shader_parameter(&"horizon_y", horizon.y)


## The car's centre in world space.
func _car_point(player: Node3D) -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.INF
	return player.global_position + Vector3.UP * CAR_SCREEN_HEIGHT


## The point the road vanishes at: ahead of the car, along its velocity (the camera's
## forward is only the fallback, so a drift does not move the focus off the motion).
func _vanishing_uv(player: Node3D) -> Vector2:
	if _camera == null:
		return Vector2.INF
	var direction := Vector3.ZERO
	var body := player as RigidBody3D
	if body != null:
		direction = body.linear_velocity
	direction.y = 0.0
	if direction.length() < CameraMath.VELOCITY_MIN:
		direction = -_camera.global_transform.basis.z
		direction.y = 0.0
	if direction.length() < CameraMath.MIN_LOOK_LENGTH:
		return Vector2.INF
	var point := _camera.global_position + direction.normalized() * VANISHING_DIST
	if _camera.is_position_behind(point):
		return Vector2.INF
	return _screen_uv(point)


## The car's screen position, or INF when the car is behind the camera.
func _car_uv(player: Node3D) -> Vector2:
	if _camera == null:
		return Vector2.INF
	var point := _car_point(player)
	if point == Vector3.INF or _camera.is_position_behind(point):
		return Vector2.INF
	return _screen_uv(point)


## The horizon line: the camera's forward direction, flattened.
func _horizon_uv() -> Vector2:
	if _camera == null:
		return Vector2.INF
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < CameraMath.MIN_LOOK_LENGTH:
		return Vector2.INF
	return _screen_uv(_camera.global_position + forward.normalized() * HORIZON_DIST)


## World position to viewport UV (0..1, origin top left).
func _screen_uv(world: Vector3) -> Vector2:
	if _camera == null or world == Vector3.INF:
		return Vector2.INF
	var viewport := _camera.get_viewport()
	if viewport == null:
		return Vector2.INF
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.INF
	var pixel := _camera.unproject_position(world)
	return Vector2(pixel.x / size.x, pixel.y / size.y)


## The viewport height in pixels, for the resolution independent streak width.
func _viewport_height() -> float:
	if _camera == null:
		return REFERENCE_HEIGHT
	var viewport := _camera.get_viewport()
	if viewport == null:
		return REFERENCE_HEIGHT
	return maxf(viewport.get_visible_rect().size.y, 1.0)

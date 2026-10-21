extends Node3D
## Vehicle-led sprung chase camera (ref/gameplay/DOSSIER.md, camera sections; briefs/camera.md).
## "Camera = handling": the position converges on the car while the yaw lags at the grip rate
## (slower while drifting) and is aimed a third of the way towards the nose, so the car's
## screen position shows the turning radius. The camera looks along the velocity, never along
## the nose, and never rolls the horizon with the car. Owns the chase rig, the FOV / speed
## line / radial blur stack, the camera shake and the takedown cam (takedown_cam.gd).

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const CameraPresets := preload("res://vehicle/camera/camera_presets.gd")
const CameraShake := preload("res://vehicle/camera/camera_shake.gd")
const CameraBoost := preload("res://vehicle/camera/camera_boost.gd")
const CameraEffects := preload("res://vehicle/camera/camera_effects.gd")
const CameraRig := preload("res://vehicle/camera/camera_rig.gd")
const TakedownCam := preload("res://vehicle/camera/takedown_cam.gd")

@export var camera_path: NodePath = ^"Camera"
@export var overlay_path: NodePath = ^"Overlay"
@export var takedown_path: NodePath = ^"TakedownRig"
@export var effects_path: NodePath = ^"Effects"

var _player: VehicleBase = null
var _camera: Camera3D = null
var _overlay: CanvasLayer = null
var _takedown: TakedownCam = null
var _shake: CameraShake = null
var _boost: CameraBoost = null
var _effects: CameraEffects = null
var _rig: CameraRig = null

var _yaw: float
var _yaw_lambda: float = CameraMath.YAW_LAMBDA_GRIP
var _pos: Vector3 = Vector3.ZERO
var _feed_forward: Vector3 = Vector3.ZERO
var _fov: float = CameraMath.FOV_BASE
var _bank: float
var _preset: int = CameraPresets.Preset.NEAR
var _look_back: bool = false
var _flying: bool = false
var _started: bool = false
var _snap: bool = false


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_overlay = get_node_or_null(overlay_path) as CanvasLayer
	_takedown = get_node_or_null(takedown_path) as TakedownCam
	if _camera == null:
		push_error("camera: no Camera3D at %s" % camera_path)
		return
	_camera.fov = CameraMath.FOV_BASE
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = CameraMath.CAMERA_NEAR
	_camera.far = CameraMath.CAMERA_FAR
	_camera.current = true

	_shake = CameraShake.new()
	_boost = CameraBoost.new()
	_rig = CameraRig.new()

	_effects = get_node_or_null(effects_path) as CameraEffects
	if _effects != null:
		_effects.setup(_camera, _overlay)
		_shake.enabled = _effects.shake_enabled()
	if _takedown != null:
		_takedown.setup(_camera, _overlay)
		_takedown.finished.connect(_on_takedown_finished)
	_apply_preset()

	Events.camera_shake.connect(_on_camera_shake)
	Events.boost_started.connect(_on_boost_started)
	Events.landed.connect(_on_landed)
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.flight_changed.connect(_on_flight_changed)
	Events.player_respawned.connect(_on_player_respawned)


func _physics_process(delta: float) -> void:
	_acquire_player()
	if _player == null or _camera == null:
		return
	# The world time (the delta is scaled by the slow motion) drives the follow; the
	# unscaled step drives the cam's own timelines, so a slow motion never stretches them.
	var dt := delta
	var dt_real := CameraMath.physics_step()
	_read_input()
	_boost.update(_player.telemetry, dt_real)
	_update_yaw(dt)
	_update_position(dt)
	_update_bank(dt)
	_shake.update(dt)
	if _takedown != null:
		if _takedown.active() and _takedown.can_skip() and _face_button_pressed():
			_takedown.skip()
		_takedown.advance(dt_real)
	if _takedown == null or not _takedown.active():
		_apply_chase_transform(dt)
	_update_fov(dt)
	_update_effects(dt)


## The safety pass: the physics server sees a new wall a frame late, so the camera checks
## itself again just before the frame is drawn, and re-aims at the new spot.
func _process(_delta: float) -> void:
	if _player == null or _camera == null:
		return
	if _takedown != null and _takedown.active():
		return
	if _preset == CameraPresets.Preset.BUMPER:
		return          # the hood mount is rigid on the car, there is nothing to pull in
	var current := _camera.global_position
	var space := get_world_3d().direct_space_state
	var safe := _rig.clamp_to_clear(space, _player.global_position
			+ Vector3.UP * CameraMath.COLLISION_ANCHOR_HEIGHT, current)
	if safe != current:
		_camera.global_transform = Transform3D(_camera_basis(safe), safe)


## The camera follows Game.player and switches over as soon as the game hands it a new car.
func _acquire_player() -> void:
	var player := Game.player
	if player == _player and is_instance_valid(_player):
		return
	_player = player
	_reset_follow()


## Forgets the follow state: the camera snaps to the new car instead of flying across the map.
func _reset_follow() -> void:
	_started = false
	_feed_forward = Vector3.ZERO
	_rig.reset()
	_boost.reset()
	_snap = true


func _read_input() -> void:
	var back := Input.is_action_pressed(&"look_back")
	if back != _look_back:
		_look_back = back
		_snap = true          # the rear view cuts, it does not swing round
		_started = false
	if Input.is_action_just_pressed(&"camera_toggle") and (not _takedown or not _takedown.active()):
		_preset = CameraPresets.next_preset(_preset)
		_apply_preset()


func _face_button_pressed() -> bool:
	return Input.is_action_just_pressed(&"nitro") or Input.is_action_just_pressed(&"mini_boost") \
			or Input.is_action_just_pressed(&"hop") or Input.is_action_just_pressed(&"camera_toggle")


func _update_yaw(dt: float) -> void:
	var vel := _player.linear_velocity
	var heading := _player.get_forward()
	var head_yaw := CameraMath.yaw_of(heading)
	var vel_yaw := head_yaw
	if vel.length() > CameraMath.VELOCITY_MIN:
		vel_yaw = CameraMath.yaw_of(Vector3(vel.x, 0, vel.z))
	var target := CameraMath.yaw_target(vel_yaw, head_yaw)
	if _look_back:
		target = head_yaw + PI
	if _preset == CameraPresets.Preset.BUMPER:
		_yaw = head_yaw          # a rigidly mounted camera has no lag
		_yaw_lambda = CameraMath.YAW_LAMBDA_GRIP
		return
	# The yaw rate fades between grip and drift: assists never switch binary.
	var wanted := CameraMath.YAW_LAMBDA_GRIP
	if _is_drifting():
		wanted = CameraMath.YAW_LAMBDA_DRIFT
	if _flying:
		wanted = CameraMath.FLIGHT_YAW_LAMBDA
	_yaw_lambda = CameraMath.damp(_yaw_lambda, wanted, CameraMath.YAW_LAMBDA_BLEND, dt)
	if _snap:
		_snap = false
		_yaw = target
		return
	_yaw = CameraMath.damp_angle(_yaw, target, _yaw_lambda, dt)


func _is_drifting() -> bool:
	var tele := _player.telemetry
	if tele.drift_state == &"drift" or tele.drift_state == &"recover":
		return true
	return absf(tele.slip_angle_deg) > CameraMath.DRIFT_SLIP_DEG


func _update_position(dt: float) -> void:
	if _preset == CameraPresets.Preset.BUMPER:
		_pos = _bumper_position()
		return
	var preset := CameraPresets.get_preset(_preset)
	var speed_kmh := _player.telemetry.speed_kmh
	var dist := preset.dist + (CameraMath.distance_for_speed(speed_kmh) - CameraMath.DIST_REST)
	var height := preset.height
	if _flying:
		dist += CameraMath.FLIGHT_DIST_BONUS
		height += CameraMath.FLIGHT_HEIGHT_BONUS
	var desired := _player.global_position - CameraMath.forward_of(_yaw) * dist + Vector3.UP * height
	var lambda := CameraMath.POS_LAMBDA
	if _flying:
		lambda = CameraMath.FLIGHT_POS_LAMBDA
	# Feed forward a low-passed velocity: the camera holds the intended distance in the
	# steady state but lags when the car accelerates or stops (criterion momentum).
	var velocity := _player.linear_velocity
	if velocity.length() > CameraMath.MAX_FEED_FORWARD:
		velocity = velocity.normalized() * CameraMath.MAX_FEED_FORWARD
	_feed_forward = CameraMath.damp_vec(_feed_forward, velocity, CameraMath.FF_LAMBDA, dt)
	desired += _feed_forward / lambda
	if not _started:
		_started = true
		_pos = desired
		return
	_pos = CameraMath.damp_vec(_pos, desired, lambda, dt)


func _update_bank(dt: float) -> void:
	var target: float
	if _flying:
		target = clampf(_player.telemetry.roll_deg, -CameraMath.MAX_BANK_DEG, CameraMath.MAX_BANK_DEG)
	_bank = CameraMath.damp(_bank, target, CameraMath.BANK_LAMBDA, dt)


func _bumper_position() -> Vector3:
	if _look_back:
		return _player.global_transform * CameraPresets.BUMPER_REAR_MOUNT
	var marker := _player.get_marker(&"Camera_Hood")
	if marker != null:
		return marker.global_position
	return _player.global_transform * CameraPresets.BUMPER_FALLBACK


func _resolve_collision(dt: float, from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var high := _player.global_position + Vector3.UP * CameraMath.CLOSE_SPOT_HEIGHT \
			- CameraMath.forward_of(_yaw) * CameraMath.CLOSE_SPOT_BACK
	return _rig.resolve(space, from, to, dt, high)


func _apply_chase_transform(dt: float) -> void:
	var ideal := _pos - CameraMath.forward_of(_yaw) * _boost.punch
	var final := ideal
	if _preset != CameraPresets.Preset.BUMPER:
		final = _resolve_collision(dt, _player.global_position
				+ Vector3.UP * CameraMath.COLLISION_ANCHOR_HEIGHT, ideal)
	final += _shake.offset
	_camera.global_transform = Transform3D(_camera_basis(final), final)
	_camera.fov = _fov


## The camera aims at the look-at point (the car, up, and ahead along the velocity).
func _camera_basis(pos: Vector3) -> Basis:
	var look := _look_point() - pos
	if look.length() < CameraMath.MIN_LOOK_LENGTH:
		look = -CameraMath.forward_of(_yaw)
	var basis := Basis.looking_at(look, Vector3.UP)
	if _flying:
		basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(_bank))
	# The shake: a yaw about the world up and a pitch about the camera's right, so the
	# horizon never rolls.
	basis = Basis(Vector3.UP, deg_to_rad(_shake.rotation_deg.y)) * basis
	basis = basis * Basis(Vector3.RIGHT, deg_to_rad(_shake.rotation_deg.x))
	return basis


## The point the camera aims at: the car, LOOK_HEIGHT up, LOOK_AHEAD along the velocity.
func _look_point() -> Vector3:
	var preset := CameraPresets.get_preset(_preset)
	var dir := Vector3.ZERO
	if _preset == CameraPresets.Preset.BUMPER:
		dir = _player.get_forward()
	else:
		var vel := _player.linear_velocity
		if vel.length() > CameraMath.VELOCITY_MIN:
			dir = Vector3(vel.x, 0, vel.z).normalized()
	if _look_back:
		if dir.length() < CameraMath.MIN_LOOK_LENGTH:
			dir = _player.get_forward()
		dir = -dir
	return CameraMath.look_point(_player.global_position, dir, preset.look_ahead, preset.look_height)


func _update_fov(dt: float) -> void:
	var target := CameraMath.fov_target(_player.linear_velocity.length(), _boost.nitro, _boost.mini)
	_fov = CameraMath.damp(_fov, target, CameraMath.FOV_LAMBDA, dt)


func _update_effects(dt: float) -> void:
	if _effects == null:
		return
	# The takedown shot owns the camera: no streaks and no blur over it.
	_effects.set_suppressed(_takedown != null and _takedown.active())
	_effects.set_look_back(_look_back)
	_effects.update(dt, _player.telemetry.speed_kmh, _boost.nitro, _player)


## The hood view hides the player's own thruster haze, which sits right in front of the
## camera. `--camera_preset=far|bumper|near` starts the camera in that preset.
func _apply_preset() -> void:
	if _camera == null:
		return
	var preset_name := Game.option("camera_preset")
	if preset_name != "":
		var index := CameraPresets.NAMES.find(preset_name)
		if index >= 0:
			_preset = index
	var bit := 1 << (CameraMath.SELF_FX_LAYER - 1)
	if _preset == CameraPresets.Preset.BUMPER:
		_camera.cull_mask &= ~bit
	else:
		_camera.cull_mask |= bit


func _on_camera_shake(strength: float, duration: float) -> void:
	_shake.add(strength, duration)


func _on_boost_started(vehicle: VehicleBase, kind: StringName) -> void:
	if vehicle != _player:
		return
	if _boost.on_boost_started(kind):
		_shake.add(CameraMath.NITRO_SHAKE, CameraMath.NITRO_SHAKE_TIME)


func _on_landed(vehicle: VehicleBase, _airtime: float, impact_speed: float, _quality: StringName) -> void:
	if vehicle != _player:
		return
	_shake.add(CameraMath.landing_shake(impact_speed), CameraMath.LANDING_SHAKE_TIME)


func _on_vehicle_collided(vehicle: VehicleBase, other: Node3D, impulse: float, _point: Vector3,
		_normal: Vector3) -> void:
	if vehicle != _player:
		return
	var strength := CameraMath.hit_shake(impulse, other is VehicleBase)
	if strength > 0:
		_shake.add(strength, CameraMath.WALL_SHAKE_TIME)


func _on_flight_changed(vehicle: VehicleBase, active: bool, _lane: SkyLane) -> void:
	if vehicle != _player:
		return
	_flying = active


func _on_player_respawned() -> void:
	_acquire_player()
	_reset_follow()
	_shake.clear()


func _on_takedown_finished() -> void:
	_shake.clear()


## The render camera (for other units and tests).
func get_camera() -> Camera3D:
	return _camera


## True while the takedown / focus cam owns the camera.
func is_takedown_active() -> bool:
	return _takedown != null and _takedown.active()


## The camera's internal state, for the tests and the debug overlay.
func get_debug_state() -> Dictionary:
	return {
		"yaw_lambda": _yaw_lambda,
		"bank": _bank,
		"look_point": _look_point(),
		"blur_strength": 0.0 if _effects == null else _effects.get_blur_strength(),
		"blur_centre": Vector2(0.5, 0.5) if _effects == null else _effects.get_blur_centre(),
		"vanishing_uv": Vector2.INF if _effects == null else _effects.get_vanishing_uv(_player),
		"preset": _preset,
		"takedown_t": 0.0 if _takedown == null else _takedown.elapsed(),
		"nitro": _boost.nitro,
		"mini": _boost.mini,
		"punch": _boost.punch,
	}

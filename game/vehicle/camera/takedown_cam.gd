extends Node3D
## Burnout-style takedown cam (ref/gameplay/DOSSIER.md §3.5) and the generic focus cam
## (`Events.camera_focus`). Every time in the table is REAL time: the caller passes an
## unscaled delta to `advance(dt)`, so `Engine.time_scale` never stretches the shot.
##
##   hit-stop: the time scale drops to TAKEDOWN_HITSTOP_SCALE for TAKEDOWN_HITSTOP seconds
##             and one frame flashes white
##   cut: the side camera, TAKEDOWN_DISTANCES[0] metres from the victim, perpendicular to
##         its velocity, on the open side, TAKEDOWN_CAM_HEIGHT above the road, vFOV TAKEDOWN_FOV
##   the time scale eases from TAKEDOWN_SLOWMO to one over the ease window
##   TAKEDOWN_TOTAL: the hard cut back to the chase camera
##   skippable with any face button after TAKEDOWN_SKIP_AFTER; one slow-mo per TAKEDOWN_COOLDOWN.
##
## The side camera is placed so that it can actually see the victim: every candidate is
## checked with a sphere cast and a line-of-sight ray before it is used.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

signal finished()

enum Phase { IDLE, HITSTOP, SHOW, DONE }

## World (1) + props (3).
const WALL_MASK := 0b101

var _phase: Phase = Phase.IDLE
var _overlay: CanvasLayer = null
var _sphere := SphereShape3D.new()
var _params := PhysicsShapeQueryParameters3D.new()
var _owns_time_scale: bool = false
var _t: float
var _duration: float = CameraMath.TAKEDOWN_TOTAL
var _victim: Node3D = null
var _camera: Camera3D = null
var _base_pos: Vector3 = Vector3.ZERO
var _offset_dir: Vector3 = Vector3.ZERO      ## from the victim towards the camera
var _cooldown: float


func _ready() -> void:
	_sphere.radius = CameraMath.COLLISION_RADIUS
	_params.shape = _sphere
	_params.collision_mask = WALL_MASK
	_params.collide_with_areas = false
	Events.takedown.connect(_on_takedown)
	Events.camera_focus.connect(_on_camera_focus)


func setup(camera: Camera3D, overlay: CanvasLayer) -> void:
	_camera = camera
	_overlay = overlay


func _on_takedown(victim: VehicleBase, kind: StringName) -> void:
	play_takedown(victim, kind)


func _on_camera_focus(target: Node3D, duration: float) -> void:
	play_focus(target, duration)


func active() -> bool:
	return _phase == Phase.HITSTOP or _phase == Phase.SHOW


func on_cooldown() -> bool:
	return _cooldown > 0


## A takedown (dossier, takedown table). Traffic wrecks never get the cam (banner only).
func play_takedown(victim: Node3D, kind: StringName) -> bool:
	if victim == null or kind == &"traffic":
		return false
	return _start(victim, CameraMath.TAKEDOWN_TOTAL, true)


## `Events.camera_focus(target, duration)`: the same rig, no hit-stop, the caller's duration.
func play_focus(target: Node3D, duration: float) -> bool:
	if target == null:
		return false
	return _start(target, clampf(duration, CameraMath.TAKEDOWN_MIN_DURATION, CameraMath.TAKEDOWN_TOTAL), false)


## Advances the shot. Returns true while the cam still owns the camera. `dt` is unscaled
## ("real") seconds.
func advance(dt: float) -> bool:
	if _cooldown > 0:
		_cooldown = maxf(_cooldown - dt, 0)
	if not active():
		return false
	_t += dt
	match _phase:
		Phase.HITSTOP:
			_request_time_scale()
			if _t >= CameraMath.TAKEDOWN_CUT:
				_phase = Phase.SHOW
				_request_time_scale()
		Phase.SHOW:
			_apply_shot()
			_request_time_scale()
			if _t >= _duration:
				_finish()
	return active()


## True once the shot may be skipped (after TAKEDOWN_SKIP_AFTER).
func can_skip() -> bool:
	return active() and _t >= CameraMath.TAKEDOWN_SKIP_AFTER


func skip() -> void:
	if not active():
		return
	_finish()


func _start(victim: Node3D, duration: float, hitstop: bool) -> bool:
	if active() or on_cooldown():
		return false
	_victim = victim
	_duration = duration
	_t = 0
	_place(victim)
	_phase = Phase.HITSTOP if hitstop else Phase.SHOW
	_owns_time_scale = hitstop
	_cooldown = CameraMath.TAKEDOWN_COOLDOWN
	if hitstop:
		# Only a takedown owns the time scale: a focus shot leaves the caller's slow motion
		# alone (the damage unit asks for 0.35 for a wreck).
		_request_time_scale()
		if _overlay != null:
			_overlay.flash_frame()
	else:
		_apply_shot()
	return true


## The time scale is only ever changed through the event bus; `Game` owns the slow motion.
## Only the takedown shot uses it.
func _request_time_scale() -> void:
	if _victim == null or not _owns_time_scale:
		return
	if _phase == Phase.HITSTOP:
		Events.slowmo_request.emit(CameraMath.TAKEDOWN_HITSTOP_SCALE, CameraMath.TAKEDOWN_HITSTOP,
				_victim)
		return
	if _t < CameraMath.TAKEDOWN_EASE_START:
		Events.slowmo_request.emit(CameraMath.TAKEDOWN_SLOWMO, CameraMath.TAKEDOWN_SLOWMO_HOLD,
				_victim)
		return
	if _t < CameraMath.TAKEDOWN_EASE_END:
		var k := (_t - CameraMath.TAKEDOWN_EASE_START) / \
				(CameraMath.TAKEDOWN_EASE_END - CameraMath.TAKEDOWN_EASE_START)
		Events.slowmo_request.emit(lerpf(CameraMath.TAKEDOWN_SLOWMO, 1.0, CameraMath.smooth01(k)),
				CameraMath.TAKEDOWN_SLOWMO_HOLD, _victim)
		return
	Events.slowmo_request.emit(1, 0, _victim)


## Places the side camera: the first candidate that can see the victim wins.
func _place(victim: Node3D) -> void:
	var centre := victim.global_position + Vector3.UP * CameraMath.TAKEDOWN_VICTIM_CENTRE
	var perp := _perpendicular(victim)
	var open_side := _open_side(centre, perp)
	var sides: Array[Vector3] = [open_side, -open_side]
	for distance in CameraMath.TAKEDOWN_DISTANCES:
		for height in CameraMath.TAKEDOWN_HEIGHTS:
			for side in sides:
				var pos := centre + side * distance \
						+ Vector3.UP * (height - CameraMath.TAKEDOWN_VICTIM_CENTRE)
				if _is_clear(centre, pos) and _has_line_of_sight(pos, victim):
					_base_pos = pos
					_offset_dir = side
					return
	# Nothing works: a high shot above and behind the victim.
	var back := -_forward_of(victim)
	_base_pos = victim.global_position + back * CameraMath.TAKEDOWN_FALLBACK_BACK \
			+ Vector3.UP * CameraMath.TAKEDOWN_FALLBACK_HEIGHT
	_offset_dir = -back


## Perpendicular to the victim's velocity (or to the line from the player to the victim).
func _perpendicular(victim: Node3D) -> Vector3:
	var dir := _velocity_of(victim)
	if dir.length() < 1:
		var player := Game.player
		if player != null and is_instance_valid(player):
			dir = victim.global_position - player.global_position
	dir.y = 0
	if dir.length() < CameraMath.MIN_LOOK_LENGTH:
		dir = _forward_of(victim)
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	return side if side.length() > CameraMath.MIN_LOOK_LENGTH else Vector3.RIGHT


## The side with more open space, measured from the victim's centre.
func _open_side(centre: Vector3, perp: Vector3) -> Vector3:
	var forward_free := _free_distance(centre, perp)
	var backward_free := _free_distance(centre, -perp)
	return perp if forward_free >= backward_free else -perp


## A horizontal direction in front of the victim.
func _forward_of(node: Node3D) -> Vector3:
	var body := node as RigidBody3D
	if body != null:
		var forward := -body.global_transform.basis.z
		forward.y = 0
		if forward.length() > CameraMath.MIN_LOOK_LENGTH:
			return forward.normalized()
	return Vector3.FORWARD


func _velocity_of(node: Node3D) -> Vector3:
	var body := node as RigidBody3D
	if body != null:
		return body.linear_velocity
	return Vector3.ZERO


## True when a sphere cast from `from` to `to` is clear (the cast also covers the dolly path).
func _is_clear(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	_params.transform = Transform3D(Basis.IDENTITY, from)
	_params.motion = to - from
	var result := space.cast_motion(_params)
	if result.is_empty():
		return true
	return float(result[0]) >= 1


## True when the camera can see the victim.
func _has_line_of_sight(cam_pos: Vector3, victim: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var target := victim.global_position + Vector3.UP * CameraMath.TAKEDOWN_LOOK_HEIGHT
	var params := PhysicsRayQueryParameters3D.create(cam_pos, target, WALL_MASK)
	params.collide_with_areas = false
	return space.intersect_ray(params).is_empty()


## Distance to the first wall along `dir`.
func _free_distance(from: Vector3, dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from,
			from + dir * CameraMath.TAKEDOWN_FREE_DIST, WALL_MASK)
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return CameraMath.TAKEDOWN_FREE_DIST
	return from.distance_to(hit["position"] as Vector3)


func _apply_shot() -> void:
	if _camera == null or _victim == null or not is_instance_valid(_victim):
		return
	var dolly := clampf((_t - CameraMath.TAKEDOWN_CUT) /
			maxf(CameraMath.TAKEDOWN_DOLLY_END - CameraMath.TAKEDOWN_CUT, 0.001), 0, 1)
	_camera.global_position = _base_pos - _offset_dir * CameraMath.TAKEDOWN_DOLLY * dolly
	var look := _victim.global_position + Vector3.UP * CameraMath.TAKEDOWN_LOOK_HEIGHT
	if _camera.global_position.distance_to(look) > CameraMath.TAKEDOWN_MIN_LOOK_DIST:
		_camera.look_at(look, Vector3.UP)
	_camera.fov = CameraMath.TAKEDOWN_FOV


func _finish() -> void:
	_phase = Phase.DONE
	if _owns_time_scale:
		Events.slowmo_request.emit(1, 0, _victim)
		_owns_time_scale = false
	finished.emit()


## The unscaled seconds since the shot started.
func elapsed() -> float:
	return _t

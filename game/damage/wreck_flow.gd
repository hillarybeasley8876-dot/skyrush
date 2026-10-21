extends Node3D
## The wreck flow of dossier §7.8:
##   * an AI car stays wrecked for 6 s, then sinks and fades out (it stops being an obstacle),
##   * the player gets the crash cam, the slow motion and the banner, and respawns on the
##     nearest lane 30 m behind the wreck at 70 % of the pre-crash speed with 60 HP and a
##     2 s ghost (no collisions with the cars, half transparent).
##
## The timings run on the scene tree's clock, not on the wall clock, so a movie run at a
## fixed frame rate respawns the player at the same moment every time.

const Rules := preload("res://damage/damage_rules.gd")

## How long a wrecked AI car stays before it sinks away.
const AI_LIFETIME := 6.0
const AI_FADE := 1.5
const AI_SINK := 0.4
## The crash cam of the player.
const CAM_TIME := 2.2
const SLOWMO_SCALE := 0.35
## The respawn.
const RESPAWN_BACK := 30.0
const RESPAWN_SPEED := 0.7
const RESPAWN_MIN_SPEED := 16.67    ## 60 km/h
const RESPAWN_HP := 60.0
## The ghost: 2 s of no collisions with the cars, half transparent.
const GHOST_TIME := 2.0
const GHOST_HZ := 6.0
const GHOST_ALPHA := 0.5
const GHOST_ALPHA_JITTER := 0.2
## The layer of the cars (physics layer 2) that the ghost ignores.
const VEHICLE_LAYER := 1 << 1


## The respawn of one car, waiting for the crash cam to end.
class Respawn:
	extends RefCounted
	var car: VehicleBase = null
	var speed: float = 0.0
	var heading: Vector3 = Vector3.FORWARD

	func _init(p_car: VehicleBase = null, p_speed: float = 0.0,
			p_heading: Vector3 = Vector3.FORWARD) -> void:
		car = p_car
		speed = p_speed
		heading = p_heading


## The ghost of one car: the time it has been running and the transparency of its meshes.
class Ghost:
	extends RefCounted
	var elapsed: float = 0.0
	var saved: Dictionary = {}
	var exceptions: Array = []


var _pending: Respawn = null
## The ghosts that are running, by the id of the car.
var _ghosts: Dictionary = {}


## The player is wrecked: the crash cam, the slow motion, the banner and the respawn.
## `speed` is the speed of the car before the hit (m/s), `heading` its horizontal heading.
func player_wreck(car: VehicleBase, speed: float, heading: Vector3) -> void:
	Events.camera_focus.emit(car, CAM_TIME)
	Events.slowmo_request.emit(SLOWMO_SCALE, CAM_TIME, car)
	Events.toast.emit("撞车 WRECKED", &"danger")
	_pending = Respawn.new(car, speed, heading)
	# The respawn happens on the scene tree's clock, so a fixed frame rate run is the same
	# every time.
	var timer := get_tree().create_timer(CAM_TIME, true, false, true)
	timer.timeout.connect(_apply_pending_respawn)


## An AI car is wrecked: it stays 6 s, then sinks and fades. The car is bound by its id:
## a car that leaves the world before the timer must not break the call.
func ai_wreck(car: VehicleBase) -> void:
	var timer := get_tree().create_timer(AI_LIFETIME, true, false, true)
	timer.timeout.connect(_sink_away.bind(car.get_instance_id()))


func _process(delta: float) -> void:
	_tick_ghosts(delta)


# --- the respawn ---------------------------------------------------------------------------------
func _apply_pending_respawn() -> void:
	if _pending == null:
		return
	var car := _pending.car
	var speed := _pending.speed
	var heading := _pending.heading
	_pending = null
	if car == null or not is_instance_valid(car):
		return
	_respawn(car, speed, heading)


## The respawn: the car is repaired, put back on the road behind the wreck and sent off
## along the road at 70 % of its pre-crash speed.
func _respawn(car: VehicleBase, speed: float, heading: Vector3) -> void:
	var direction := heading
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = -car.global_transform.basis.z
		direction.y = 0.0
	if direction.length() < 0.01:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var behind := car.global_position - direction * RESPAWN_BACK
	var xform := Transform3D(Basis.IDENTITY, behind + Vector3.UP)
	if Game.world != null:
		xform = Game.world.nearest_road_transform(behind)
	# The lane can face against the direction of the crash: the car must drive away from
	# the wreck, so the road transform is flipped when it points the wrong way.
	var road_forward := -xform.basis.z
	road_forward.y = 0.0
	if road_forward.length() > 0.01:
		road_forward = road_forward.normalized()
		if road_forward.dot(direction) < 0.0:
			xform.basis = xform.basis.rotated(Vector3.UP, PI)
	car.reset_to(xform)
	var drive := -xform.basis.z
	drive.y = 0.0
	if drive.length() < 0.01:
		drive = direction
	drive = drive.normalized()
	car.linear_velocity = drive * maxf(speed * RESPAWN_SPEED, RESPAWN_MIN_SPEED)
	# The car must be whole again: `repair` clears the wrecked flag, the damage state is
	# reset by the damage unit through Events.player_respawned.
	car.repair()
	car.health = RESPAWN_HP
	car.telemetry.health_norm = RESPAWN_HP / maxf(car.max_health, 1.0)
	_start_ghost(car)
	Events.player_respawned.emit()


# --- the ghost -----------------------------------------------------------------------------------
## The 2 s ghost: the car passes through the other cars and is half transparent.
## Jolt reports a contact when EITHER body's mask holds the other's layer, so the mask alone
## is not enough: the ghost needs a collision exception for every car.
func _start_ghost(car: VehicleBase) -> void:
	car.collision_mask = car.collision_mask & ~VEHICLE_LAYER
	var ghost := Ghost.new()
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var other := node as Node3D
		if other == null or other == car:
			continue
		car.add_collision_exception_with(other)
		ghost.exceptions.append(other)
	_save_transparency(car, ghost)
	_ghosts[car.get_instance_id()] = ghost
	# A car that joins the world during the ghost must pass through it as well.
	var refresh := get_tree().create_timer(0.25, true, false, true)
	refresh.timeout.connect(_refresh_exceptions.bind(car))


## The ghost of the car fades in and out at 6 Hz, driven by the real time.
func _tick_ghosts(delta: float) -> void:
	if _ghosts.is_empty():
		return
	for id: int in _ghosts.keys():
		var ghost := _ghosts[id] as Ghost
		if ghost == null:
			continue
		ghost.elapsed += delta
		var car := _car_of(id)
		if car == null:
			_ghosts.erase(id)
			continue
		if ghost.elapsed >= GHOST_TIME:
			_end_ghost(car, ghost)
			_ghosts.erase(id)
			continue
		var alpha := GHOST_ALPHA + GHOST_ALPHA_JITTER * sin(ghost.elapsed * GHOST_HZ * TAU)
		_set_transparency(car, clampf(alpha, 0.0, 1.0))


## Adds the collision exception for the cars that joined the world during the ghost.
func _refresh_exceptions(car: VehicleBase) -> void:
	if car == null or not is_instance_valid(car):
		return
	var ghost := _ghosts.get(car.get_instance_id(), null) as Ghost
	if ghost == null:
		return
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var other := node as Node3D
		if other == null or other == car or ghost.exceptions.has(other):
			continue
		car.add_collision_exception_with(other)
		ghost.exceptions.append(other)


func _end_ghost(car: VehicleBase, ghost: Ghost) -> void:
	car.collision_mask = car.collision_mask | VEHICLE_LAYER
	for other in ghost.exceptions:
		if other != null and is_instance_valid(other):
			car.remove_collision_exception_with(other)
	_restore_transparency(car, ghost)


## The car of a ghost, when it is still in the world.
func _car_of(id: int) -> VehicleBase:
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var car := node as VehicleBase
		if car != null and car.get_instance_id() == id:
			return car
	return null


## Saves the transparency of the meshes of the car, so it can be restored.
func _save_transparency(car: VehicleBase, ghost: Ghost) -> void:
	for child in _meshes(car):
		ghost.saved[child.get_instance_id()] = (child as GeometryInstance3D).transparency


## The transparency of the meshes of the car (0 = opaque, 1 = invisible).
func _set_transparency(car: VehicleBase, value: float) -> void:
	for child in _meshes(car):
		(child as GeometryInstance3D).transparency = value


func _restore_transparency(car: VehicleBase, ghost: Ghost) -> void:
	for child in _meshes(car):
		var id: int = child.get_instance_id()
		if ghost.saved.has(id):
			(child as GeometryInstance3D).transparency = float(ghost.saved[id])
		else:
			(child as GeometryInstance3D).transparency = 0.0


func _meshes(car: VehicleBase) -> Array:
	var visual := car.get_visual_root()
	if visual == null:
		return []
	return visual.find_children("*", "MeshInstance3D", true, false)


# --- the AI wreck --------------------------------------------------------------------------------
## The wrecked AI car stops being an obstacle, sinks a little and fades out.
func _sink_away(id: int) -> void:
	var car := _car_of(id)
	if car == null:
		return
	# It must not be an invisible obstacle any more.
	car.freeze = true
	car.collision_layer = 0
	car.collision_mask = 0
	var visual := car.get_visual_root()
	var target := car.global_position - Vector3.UP * AI_SINK
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(car, "global_position", target, AI_FADE)
	if visual != null:
		_fade_out(visual, 0.0)
	tween.chain().tween_callback(_hide.bind(id))


## Fades the meshes of a visual from the value they have to 1.0 (invisible).
func _fade_out(visual: Node3D, from: float) -> void:
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as GeometryInstance3D
		var tween := create_tween()
		tween.tween_property(mesh, "transparency", 1.0, AI_FADE).from(from)


func _hide(id: int) -> void:
	var car := _car_of(id)
	if car != null:
		car.visible = false

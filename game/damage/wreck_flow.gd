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
## The longest a ghost waits, after its 2 s, for the car to be clear of the other cars.
const GHOST_HOLD_MAX := 3.0


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


## The wreck of one car: the serial of the life it belongs to and the tweens that sink it.
##
## A car that comes out of its pool gets a new serial: the timer and the tweens of the old
## wreck must not touch the new life of the car.
class Sink:
	extends RefCounted
	var serial: int = 0
	var tweens: Array[Tween] = []


var _pending: Respawn = null
## The ghosts that are running, by the id of the car.
var _ghosts: Dictionary = {}
## The wrecks that are running, by the id of the car.
var _sinks: Dictionary = {}


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
	if car == null or not is_instance_valid(car):
		return
	var id := car.get_instance_id()
	var sink := _sink_of(car)
	sink.serial += 1
	var serial := sink.serial
	var timer := get_tree().create_timer(AI_LIFETIME, true, false, true)
	timer.timeout.connect(_sink_away.bind(id, serial))


## The wreck of a car, with its serial. A car that was wrecked before keeps its record, so
## the serial of the new wreck is always higher than the one of the old one.
func _sink_of(car: VehicleBase) -> Sink:
	var id := car.get_instance_id()
	var sink := _sinks.get(id, null) as Sink
	if sink == null:
		sink = Sink.new()
		_sinks[id] = sink
		car.tree_exiting.connect(_on_car_gone.bind(id))
	return sink


## A car left the world: its wreck is forgotten and its tweens are stopped (they would
## write on meshes that are gone).
func _on_car_gone(id: int) -> void:
	var sink := _sinks.get(id, null) as Sink
	if sink != null:
		for tween in sink.tweens:
			if tween != null and tween.is_valid():
				tween.kill()
		sink.tweens.clear()
	_sinks.erase(id)


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
		# The world takes a lane that runs the way the car drove (in the direction of its traffic) and moves the car along it
		# to a place where the road ahead is clear.
		xform = Game.world.respawn_transform(behind, direction)
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
	# A car that is put back during its ghost (a second wreck within the 2 s) keeps the ghost it has, from the start again.
	# A new ghost saved the half transparent car of the running one as the car to come back to: the car stayed see-through
	# for the rest of the game.
	var ghost := _ghosts.get(car.get_instance_id(), null) as Ghost
	if ghost == null:
		ghost = Ghost.new()
		_save_transparency(car, ghost)
		_ghosts[car.get_instance_id()] = ghost
	ghost.elapsed = 0.0
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var other := node as Node3D
		if other == null or other == car or ghost.exceptions.has(other):
			continue
		car.add_collision_exception_with(other)
		ghost.exceptions.append(other)
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
		# The collision with the cars comes back when the car is clear of them: two boxes inside each other are thrown apart
		# by the solver (a player that a police car had driven into was kicked up and spun at the end of its ghost).
		if ghost.elapsed >= GHOST_TIME and (ghost.elapsed >= GHOST_TIME + GHOST_HOLD_MAX or not _inside_a_car(car)):
			_end_ghost(car, ghost)
			_ghosts.erase(id)
			continue
		var alpha := GHOST_ALPHA + GHOST_ALPHA_JITTER * sin(ghost.elapsed * GHOST_HZ * TAU)
		_set_transparency(car, clampf(alpha, 0.0, 1.0))


## True when the collision shapes of the car overlap another car (a shape query does not see the collision exceptions).
func _inside_a_car(car: VehicleBase) -> bool:
	var space := car.get_world_3d().direct_space_state
	if space == null:
		return false
	for child in car.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collision_mask = VEHICLE_LAYER
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [car.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false


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
##
## The car is bound by its id and by the serial of its wreck: a car that comes out of its
## pool while its old wreck is sinking must not sink again.
func _sink_away(id: int, serial: int) -> void:
	var sink := _sinks.get(id, null) as Sink
	if sink == null or sink.serial != serial:
		return
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
	sink.tweens.append(tween)
	if visual != null:
		sink.tweens.append_array(_fade_out(visual, 0.0))
	tween.chain().tween_callback(_hide.bind(id, serial))


## Fades the meshes of a visual from the value they have to 1.0 (invisible). The tweens are
## returned, so a car that comes out of its pool can stop them.
func _fade_out(visual: Node3D, from: float) -> Array[Tween]:
	var tweens: Array[Tween] = []
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as GeometryInstance3D
		var tween := create_tween()
		tween.tween_property(mesh, "transparency", 1.0, AI_FADE).from(from)
		tweens.append(tween)
	return tweens


## The car of the wreck is hidden when the fade is over. The serial keeps the hide of an
## old wreck from hiding a car that is back on the road.
func _hide(id: int, serial: int) -> void:
	var sink := _sinks.get(id, null) as Sink
	if sink == null or sink.serial != serial:
		return
	var car := _car_of(id)
	if car != null:
		car.visible = false


## The car comes out of its pool: the wreck of its old life is void. The timer that was
## waiting for the sink and the tweens that were fading the car out must not touch the new
## life of the car.
func cancel_sink(car: VehicleBase) -> void:
	if car == null or not is_instance_valid(car):
		return
	var sink := _sinks.get(car.get_instance_id(), null) as Sink
	if sink == null:
		return
	sink.serial += 1
	for tween in sink.tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	sink.tweens.clear()


## The car is whole again: its meshes are opaque and it is on the screen.
func restore_visual(car: VehicleBase) -> void:
	if car == null or not is_instance_valid(car):
		return
	car.visible = true
	_set_transparency(car, 0.0)

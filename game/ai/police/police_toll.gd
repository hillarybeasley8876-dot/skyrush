class_name PoliceToll
extends RefCounted
## The toll plazas the police close at heat 5 (ref/gameplay/DOSSIER.md §3.4).
##
## A plaza on the route of the player is closed: the cars of a block stand across every lane
## of it. The plazas of the world are read every few seconds, not every frame: the list of the
## points of interest of the world is not free.

## The kind of a point of interest of the world.
const KIND := &"toll"
## The distance of the plaza from the player (m).
const RANGE := 600.0
## Two plazas closer than this are the same plaza (m).
const SAME_PLAZA := 30.0
## The seconds between two readings of the points of interest of the world.
const REFRESH := 5.0

## The world of the game.
var world: WorldBase = null
## The plazas of the world.
var plazas: Array[Vector3] = []
## The plazas that are closed already.
var closed: Array[Vector3] = []
## The time until the plazas are read again.
var _timer: float = 0.0


## The world changed: the plazas are read again.
func set_world(world_node: WorldBase) -> void:
	world = world_node
	plazas.clear()
	closed.clear()
	_timer = 0.0


## The plaza ahead of the player that is not closed yet.
##
## Returns {"found": bool, "position": Vector3}.
func plaza_ahead(player: VehicleBase, delta: float) -> Dictionary:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_read_plazas()
	if world == null or player == null:
		return {"found": false, "position": Vector3.ZERO}
	var forward := player.get_forward()
	for pos in plazas:
		# The plaza has to be AHEAD of the player.
		if (pos - player.global_position).dot(forward) <= 0.0:
			continue
		if pos.distance_to(player.global_position) > RANGE:
			continue
		if is_closed(pos):
			continue
		return {"found": true, "position": pos}
	return {"found": false, "position": Vector3.ZERO}


## True when the plaza is already closed.
func is_closed(pos: Vector3) -> bool:
	for closed_pos in closed:
		if closed_pos.distance_to(pos) < SAME_PLAZA:
			return true
	return false


## Marks the plaza as closed.
func close(pos: Vector3) -> void:
	closed.append(pos)


## Reads the plazas of the world.
func _read_plazas() -> void:
	if world == null:
		return
	plazas.clear()
	for poi in world.get_points_of_interest():
		if StringName(poi.get("kind", &"")) != KIND:
			continue
		plazas.append(poi.get("position", Vector3.ZERO))

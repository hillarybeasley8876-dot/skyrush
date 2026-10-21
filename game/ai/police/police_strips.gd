class_name PoliceStrips
extends RefCounted
## The spike strips on the road (ref/gameplay/DOSSIER.md §6.3).
##
## The units drop the strips ahead of the player, the drone drops one from the air, and the
## strips the player left behind are cleaned up.

## The distance of the strip the units drop (m ahead of the player).
const STRIP_AHEAD := 80.0
## The time between two strips the units drop (s).
const STRIP_INTERVAL := 12.0
## The maximum number of strips on the road.
const STRIP_MAX := 4
## A strip further than this behind the player is removed (m).
const STRIP_CLEANUP := 300.0

## The strips on the road (the list of the dispatcher).
var list: Array[PoliceSpikeStrip] = []
## The pool the strips come from.
var pool: PolicePool = null
## The node the strips are added to.
var host: Node3D = null
## The time until the next strip a unit drops.
var timer: float = STRIP_INTERVAL


## The tick of the strips: the units drop one now and then.
func update(delta: float, player: VehicleBase, lane: int, lane_s: float,
		spot: Dictionary) -> void:
	timer -= delta
	if timer > 0.0:
		return
	timer = STRIP_INTERVAL
	cleanup(player)
	if list.size() >= STRIP_MAX:
		return
	if spot.is_empty():
		return
	add(spot["position"], spot["across"], false)


## Drops a strip on the route `distance` metres ahead of the player (the drone drops one).
func drop(player: VehicleBase, spot: Dictionary, falling: bool) -> bool:
	cleanup(player)
	if list.size() >= STRIP_MAX:
		return false
	if spot.is_empty():
		return false
	return add(spot["position"], spot["across"], falling) != null


## Adds a strip to the road. A strip that falls out of a drone starts in the air.
func add(position: Vector3, across: Vector3, falling: bool) -> PoliceSpikeStrip:
	if host == null:
		return null
	var strip := _take_strip()
	if strip == null:
		return null
	strip.global_position = position
	strip.aim(across)
	if falling:
		strip.drop_from_height()
	list.append(strip)
	return strip


## Removes the strips the player left behind.
func cleanup(player: VehicleBase) -> void:
	for i in range(list.size() - 1, -1, -1):
		var strip := list[i] as PoliceSpikeStrip
		if strip == null:
			list.remove_at(i)
			continue
		if player.global_position.distance_to(strip.global_position) > STRIP_CLEANUP:
			list.remove_at(i)
			_release(strip)


## The number of strips on the road.
func count() -> int:
	return list.size()


## Takes every strip off the road (the tests).
func clear() -> void:
	for i in range(list.size() - 1, -1, -1):
		_release(list[i])
	list.clear()


## Takes a strip out of the pool.
func _take_strip() -> PoliceSpikeStrip:
	if pool != null:
		return pool.take_strip()
	var strip := PoliceSpikeStrip.new()
	host.add_child(strip)
	return strip


## Puts a strip back into the pool.
func _release(strip: PoliceSpikeStrip) -> void:
	if pool != null:
		pool.release_strip(strip)
	else:
		strip.queue_free()

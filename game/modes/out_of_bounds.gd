class_name OutOfBounds
extends RefCounted
## The recovery of a lost player.
##
## The world has water (the Huangpu), a kill floor and edges: a car that drives into the river or
## falls under the map sits there for good, because the water and the floor are solid colliders.
## This watches the player and, after a few seconds of being lost, puts it back on the nearest
## lane and tells it with a toast.
##
## The rules:
##   - the player is lost when it is more than LOST_DISTANCE metres from the nearest lane (the
##     world weighs the height of a lane, so a deck 10 m above does not win over the street the
##     player is on, and the tunnel 28 m below is a road like any other);
##   - it is put back after LOST_SECONDS of being continuously lost; the timer restarts when the
##     player is found again;
##   - the timer does not count while the player flies in a sky lane, while it has been in the
##     air for less than AIRBORNE_GRACE seconds (a long jump over the river is fine) or while it
##     waits on the grid of a race (the player is frozen).

## The distance from the nearest lane above which the player counts as lost.
const LOST_DISTANCE := 15.0
## The seconds of being lost before the player is put back on the road.
const LOST_SECONDS := 3.0
## The airtime a jump may last before the player counts as lost.
const AIRBORNE_GRACE := 6.0
## How often the distance to the nearest lane is measured (the scan is not free).
const CHECK_INTERVAL := 0.25
## How far above the lane the player is put back.
const PUT_BACK_LIFT := 0.5
## The message of the recovery.
const MESSAGE := "已回到路面  BACK ON THE ROAD"

## The seconds the player has been lost (0 when it was found again).
var lost_time: float = 0.0
## True while the player is lost.
var is_lost: bool = false

var _timer: float = 0.0
var _road: Transform3D = Transform3D.IDENTITY


## Watches the player. Returns true on the tick that put the player back on the road.
func update(delta: float, player: VehicleBase, world: WorldBase) -> bool:
	if player == null or world == null or not _world_ready(world):
		_forget()
		return false
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_measure(player, world)
	if not is_lost or _exempt(player):
		return false
	lost_time += delta
	if lost_time < LOST_SECONDS:
		return false
	_put_back(player, world)
	return true


## Measures the distance to the nearest lane (four times a second at most).
func _measure(player: VehicleBase, world: WorldBase) -> void:
	_road = world.nearest_road_transform(player.global_position)
	if player.global_position.distance_to(_road.origin) > LOST_DISTANCE:
		if not is_lost:
			lost_time = 0.0
		is_lost = true
	else:
		is_lost = false
		lost_time = 0.0


## True when the player must not be put back: it flies, it is in a jump or it waits on the grid.
func _exempt(player: VehicleBase) -> bool:
	if player.freeze:
		return true
	var telemetry := player.telemetry
	if telemetry == null:
		return false
	if telemetry.flying:
		return true
	return telemetry.airborne and telemetry.airtime < AIRBORNE_GRACE


## Puts the player back on the nearest lane, facing along it, and tells it.
func _put_back(player: VehicleBase, world: WorldBase) -> void:
	# The lane is measured once more: the player may have fallen a long way since the last
	# measurement, and the lane under the water is not the deck it jumped from.
	_road = world.nearest_road_transform(player.global_position)
	var xform := _road
	xform.origin.y += PUT_BACK_LIFT
	player.reset_to(xform)
	is_lost = false
	lost_time = 0.0
	Events.toast.emit(MESSAGE, &"info")


## True when the world can answer the API (the real city builds over several seconds).
func _world_ready(world: WorldBase) -> bool:
	if not Game.world_built():
		return false
	if world.has_method(&"is_ready") and not bool(world.call(&"is_ready")):
		return false
	return true


## The player is not watched (no player, or no world that is built).
func _forget() -> void:
	is_lost = false
	lost_time = 0.0

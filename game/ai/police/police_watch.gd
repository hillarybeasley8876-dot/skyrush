class_name PoliceWatch
extends RefCounted
## What the dispatcher watches (ref/gameplay/DOSSIER.md §3.4).
##
## The watch owns the things the dispatcher has to know about the world and the player:
## where the player is on the lane graph, the line of sight of the units, the offences the
## police spots itself, the velocities of the bodies and the point the units that hold back
## drive to.

## The distance the player may be from the lane he is on (m).
const LANE_TOLERANCE := 6.0
## How far the lane of the player is searched around his last place (m).
const LANE_SEARCH_RADIUS := 80.0
## The seconds between two measurements of the hold-back point.
const HOLD_REFRESH := 0.5

## The lane of the player on the graph.
var lane: int = 0
## The distance of the player along his lane (m).
var lane_offset: float = 0.0
## The lane graph of the world.
var graph: LaneGraph = null
## The lane grid of the world: the fast "which lane is near this point" search.
var grid: LaneGrid = null
## The rules of the pursuit.
var pursuit: PolicePursuit = null
## The four offences of §3.4 and the grace.
var offences: PoliceOffences = null
## The events of the bus.
var events: PoliceEvents = null
## The velocity cache of the contacts.
var contact: PoliceContact = null

## The time until the line of sight is checked again.
var _sight_timer: float = 0.0
## The point the units that hold back drive to.
var _hold_point: Vector3 = Vector3.ZERO
## The time until the hold-back point is measured again.
var _hold_timer: float = 0.0


## The world changed: the graph and the grid of the new world.
func setup(lane_graph: LaneGraph, lane_grid: LaneGrid) -> void:
	graph = lane_graph
	grid = lane_grid
	lane = 0
	lane_offset = 0.0
	_hold_point = Vector3.ZERO
	_hold_timer = 0.0


## Remembers where the player is on the lane graph, so the spawns can be placed on the lanes.
func track(player: VehicleBase) -> void:
	if graph == null or player == null:
		return
	var near := graph.closest_offset_near(lane, player.global_position, lane_offset,
			LANE_SEARCH_RADIUS)
	if graph.position_at(lane, near).distance_to(player.global_position) > LANE_TOLERANCE:
		lane = _closest_lane(player.global_position)
		near = graph.closest_offset(lane, player.global_position)
	lane_offset = near


## The lane of the player: the one whose centre line is the closest to him.
##
## The grid knows the lanes by their sample points, and the sample of the lane next to it can
## lie closer to the player than the sample of his own lane. The neighbours of the lane of the
## grid are checked, so the units are placed on the lane the player really drives on.
func _closest_lane(position: Vector3) -> int:
	var best := grid.nearest_lane(position, PoliceFleet.LANE_SEARCH_RADIUS)
	if best < 0:
		# The player is not on a lane (he is on a pavement or in a plaza): the lane of the
		# road next to him is used, so the units are still placed on his route.
		best = grid.nearest_lane(position, PoliceFleet.LANE_SEARCH_RADIUS * 6.0)
	if best < 0:
		return 0
	var best_distance := _lane_distance(best, position)
	for candidate: int in [graph.left[best], graph.right[best]]:
		if candidate < 0:
			continue
		var distance := _lane_distance(candidate, position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## The distance of a point to the centre line of a lane (m).
func _lane_distance(lane: int, position: Vector3) -> float:
	var offset := graph.closest_offset(lane, position)
	return graph.position_at(lane, offset).distance_to(position)


## The line of sight: every 0.2 s a ray from the roof of every unit to the roof of the player.
func update_sight(delta: float, space: PhysicsDirectSpaceState3D, player: VehicleBase,
		units: Array[PoliceCar], drones: Array[PoliceDrone]) -> void:
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = PoliceSight.INTERVAL
	pursuit.update_sight(space, player, units, drones)


## The offences the police spots itself: the player is caught speeding in front of a patrol.
##
## The offence is edge triggered: it is reported once, and only while no pursuit is running (a
## running pursuit is not started again by another offence).
func check_offences(delta: float, player: VehicleBase) -> void:
	offences.tick(delta)
	if not pursuit.is_over():
		return
	if not pursuit.seen_now:
		return
	if player.get_speed_kmh() > PoliceOffences.SPEEDING_KMH:
		events.report_offence(&"speeding")


## Remembers the velocity of every body, so a contact can tell who hit whom.
func cache_contacts(player: VehicleBase, units: Array[PoliceCar]) -> void:
	contact.cache(player)
	for unit in units:
		contact.cache(unit)


## The point behind the player the units that hold back drive to.
##
## The point is measured every half second: the walk of the lane graph is not free and the point
## does not move much in between.
func hold_back_point(delta: float) -> Vector3:
	_hold_timer -= delta
	if _hold_timer > 0.0 and _hold_point != Vector3.ZERO:
		return _hold_point
	_hold_timer = HOLD_REFRESH
	var walk := PoliceRoute.walk(graph, lane, lane_offset, PoliceCar.HOLD_BACK_DISTANCE, true)
	_hold_point = walk["position"]
	return _hold_point

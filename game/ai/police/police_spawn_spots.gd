class_name PoliceSpawnSpots
extends RefCounted
## The places the police units appear (ref/gameplay/DOSSIER.md §6.3).
##
## A unit never appears in the view of the player: the spot is out of the frustum of the
## camera, out of the range of the eye and behind a building. The places are the police
## stations of the world, the oncoming lanes, the lanes ahead of the player and the lanes
## behind him.

## The share of the spawns that appear behind the player.
const BEHIND_SHARE := 0.3
## The distance at which a police station may spawn a unit.
const STATION_MIN := 120.0
const STATION_MAX := 420.0
## The head-on unit: the distance ahead of the player (m).
const HEAD_ON_MIN := 350.0
const HEAD_ON_MAX := 450.0
## How far the oncoming lane may be from the route of the player (m).
const HEAD_ON_LANE_RADIUS := 15.0
## The tolerance of the distance of the head-on spot (m).
const HEAD_ON_TOLERANCE := 30.0
## A lane is oncoming when its direction is this far against the player (cosine).
const ONCOMING_DOT := -0.7
## A unit does not spawn inside a roadblock (m).
const BLOCK_CLEARANCE := 20.0
## The number of places that are tried before the spawn is given up.
const SPOT_TRIES := 6

## The shared AI context (the lane graph of the world).
var ctx: DriveContext = DriveContext.new()
## The world of the game.
var world: WorldBase = null
## The lane grid of the world: the fast "which lane is near this point" search.
var grid: LaneGrid = LaneGrid.new()
## The shared random source.
var rng := RandomNumberGenerator.new()
## The roadblocks of the dispatcher: a unit does not spawn inside a block.
var blockade: PoliceBlockade = null
## The node the units are added to (the viewport of the camera belongs to it).
var host: Node3D = null


## The place a new unit appears: out of sight, 150-320 m from the player.
func spawn_spot(role: PoliceFleet.Role, player: VehicleBase, lane: int,
		lane_s: float) -> Dictionary:
	if role == PoliceFleet.Role.HEAD_ON:
		var head_on := head_on_spot(player, lane, lane_s)
		if not head_on.is_empty():
			return head_on
	var station := station_spot(player)
	if not station.is_empty():
		return station
	var oncoming := oncoming_spot(player, lane, lane_s)
	if not oncoming.is_empty():
		return oncoming
	for i in SPOT_TRIES:
		var on_lane := lane_spot(player, lane, lane_s)
		if not on_lane.is_empty():
			return on_lane
	return {}


## A police station of the world: the unit comes out of the station, on the road next to it.
func station_spot(player: VehicleBase) -> Dictionary:
	if world == null:
		return {}
	for poi in world.get_points_of_interest():
		if StringName(poi.get("kind", &"")) != &"police_station":
			continue
		var pos: Vector3 = poi.get("position", Vector3.ZERO)
		var distance := pos.distance_to(player.global_position)
		if distance < STATION_MIN or distance > STATION_MAX:
			continue
		if visible_to_player(pos):
			continue
		# The unit starts on the road next to the station, not on the station itself.
		var road := world.nearest_road_transform(pos)
		var lane := 0
		var offset := 0.0
		if ctx.graph != null and ctx.graph.lane_count() > 0:
			lane = grid.nearest_lane(road.origin, PoliceFleet.LANE_SEARCH_RADIUS)
			if lane < 0:
				lane = 0
			offset = ctx.graph.closest_offset(lane, road.origin)
		return {"transform": road, "lane": lane, "s": offset}
	return {}


## A spot on an oncoming lane: the unit comes towards the player and does not have to turn.
##
## The lane has to be on the level of the player: a unit that spawns on the street under the
## deck the player drives on can never reach him.
func oncoming_spot(player: VehicleBase, _lane: int, _lane_s: float) -> Dictionary:
	var graph := ctx.graph
	if graph == null or graph.lane_count() == 0:
		return {}
	var forward := player.get_forward()
	for i in graph.lane_count():
		var length := graph.lane_length(i)
		if length <= 1.0:
			continue
		var middle := length * 0.5
		if graph.tangent_at(i, middle).dot(forward) > ONCOMING_DOT:
			continue
		var pos := graph.position_at(i, middle)
		# The lane of the spot has to be on the level of the player.
		if absf(pos.y - player.global_position.y) > PolicePursuit.LEVEL:
			continue
		# The spot has to be AHEAD of the player: the unit comes towards him.
		if (pos - player.global_position).dot(forward) <= 0.0:
			continue
		if pos.distance_to(player.global_position) < PoliceSpawner.SPAWN_MIN \
				or pos.distance_to(player.global_position) > PoliceSpawner.SPAWN_MAX:
			continue
		if visible_to_player(pos):
			continue
		return {"transform": graph.transform_at(i, middle, 0.0), "lane": i, "s": middle}
	return {}


## A spot on the lanes of the world: behind or ahead of the player.
func lane_spot(player: VehicleBase, lane: int, lane_s: float) -> Dictionary:
	var graph := ctx.graph
	if graph == null or graph.lane_count() == 0:
		return {}
	var roll := rng.randf()
	var behind := roll < BEHIND_SHARE
	var distance := rng.randf_range(PoliceSpawner.SPAWN_MIN, PoliceSpawner.SPAWN_MAX)
	var target_lane := lane
	var s := lane_s + distance
	if behind:
		s = lane_s - distance
		if s < 0.0:
			var previous := previous_lane(lane)
			if previous >= 0:
				target_lane = previous
				s = graph.lane_length(previous) + s
			else:
				s = lane_s + distance
	var guard := 0
	while s >= graph.lane_length(target_lane) and guard < PoliceSpawner.SPOT_GUARD:
		s -= graph.lane_length(target_lane)
		var next := PoliceRoute.successor(graph, target_lane)
		if next < 0:
			return {}
		target_lane = next
		guard += 1
	if s < 0.0:
		return {}
	var pos := graph.position_at(target_lane, s)
	if visible_to_player(pos):
		return {}
	return {"transform": graph.transform_at(target_lane, s, 0.0), "lane": target_lane, "s": s}


## The spot of the head-on unit: an oncoming lane 350-450 m ahead of the player.
##
## The spot is found on the ROUTE of the player: the point 350-450 m ahead on his own lane and
## then the lane that runs against him next to that point.
func head_on_spot(player: VehicleBase, lane: int, lane_s: float) -> Dictionary:
	var graph := ctx.graph
	if graph == null or graph.lane_count() == 0:
		return {}
	var forward := player.get_forward()
	var limit := head_on_limit(player)
	if limit < HEAD_ON_MIN:
		# A roadblock stands on the whole route ahead: there is no room for the head-on unit.
		return {}
	var route := PoliceRoute.route_points(graph, lane, lane_s, HEAD_ON_MIN, limit)
	for point in route:
		var oncoming := oncoming_lane_at(point, forward)
		if oncoming < 0:
			continue
		var s := graph.closest_offset(oncoming, point)
		var pos := graph.position_at(oncoming, s)
		var distance := pos.distance_to(player.global_position)
		if distance < HEAD_ON_MIN - HEAD_ON_TOLERANCE or distance > HEAD_ON_MAX + HEAD_ON_TOLERANCE:
			continue
		if visible_to_player(pos):
			continue
		return {"transform": graph.transform_at(oncoming, s, 0.0), "lane": oncoming, "s": s,
			"position": pos}
	# A one way road has no lane against the player: the unit turns around and comes at him.
	var walk := PoliceRoute.walk(graph, lane, lane_s, HEAD_ON_MIN)
	if not bool(walk["found"]):
		return {}
	var target_lane := int(walk["lane"])
	var offset := float(walk["s"])
	var xform := graph.transform_at(target_lane, offset, 0.0)
	xform.basis = Basis(Vector3.UP, PI) * xform.basis
	var spot_pos := xform.origin
	var spot_distance := spot_pos.distance_to(player.global_position)
	if spot_distance < HEAD_ON_MIN - HEAD_ON_TOLERANCE \
			or spot_distance > HEAD_ON_MAX + HEAD_ON_TOLERANCE:
		return {}
	if visible_to_player(spot_pos):
		return {}
	return {"transform": xform, "lane": target_lane, "s": offset, "position": spot_pos}


## True when a roadblock stands at the point: a unit does not spawn inside a block.
func blocked(position: Vector3) -> bool:
	if blockade == null:
		return false
	return blockade.occupied(position, BLOCK_CLEARANCE)


## The farthest the head-on unit may be (m).
##
## A roadblock on the route is a wall: the unit would drive into it and stand there. So the
## unit starts in front of the block and comes at the player from there.
func head_on_limit(player: VehicleBase) -> float:
	var limit := HEAD_ON_MAX
	if blockade == null:
		return limit
	for block in blockade.blocks:
		var ahead := (block.global_position - player.global_position).dot(player.get_forward())
		if ahead <= 0.0 or ahead > HEAD_ON_MAX + BLOCK_CLEARANCE:
			continue
		limit = minf(limit, ahead - BLOCK_CLEARANCE)
	return limit


## The lane that runs against the player next to `point` (-1 when there is none).
##
## The lane has to be on the level of the point: the lane on the deck above (or on the street
## below) is not the lane the head-on unit comes along.
func oncoming_lane_at(point: Vector3, forward: Vector3) -> int:
	var graph := ctx.graph
	if graph == null:
		return -1
	for candidate in grid.lanes_near(point, HEAD_ON_LANE_RADIUS):
		var s := graph.closest_offset(candidate, point)
		var closest := graph.position_at(candidate, s)
		if closest.distance_to(point) > HEAD_ON_LANE_RADIUS:
			continue
		if absf(closest.y - point.y) > PolicePursuit.LEVEL:
			continue
		if graph.tangent_at(candidate, s).dot(forward) > ONCOMING_DOT:
			continue
		return candidate
	return -1


## The lane that continues into `lane` (the road behind the player).
func previous_lane(lane: int) -> int:
	return PoliceRoute.previous_lane(ctx.graph, lane)


## True when the player can see the point (a spawn must not be in his view).
func visible_to_player(pos: Vector3) -> bool:
	if host == null:
		return false
	var camera := host.get_viewport().get_camera_3d()
	return PoliceSight.visible_to_player(camera, pos)

class_name TrafficLevel
extends RefCounted
## The level rule of the traffic and the lookups that go with it.
##
## The map is not flat: a street at y = 0 runs under the elevated roads (y = 10 to 31) and under
## the bridges, so two things can lie on the same x/z and be ten metres apart in height. A check
## that measures a 3D distance alone sees the deck as a neighbour of the street. The constant
## lives here, in ONE place of the folder, so every file of the unit asks the question the same
## way.
##
## The two tighter constants of the unit (`TrafficPlayerEvents.LEVEL_GAP` and
## `TrafficLaneChange.REACT_LEVEL`) measure a car, not a place on the road: a car is 1.5 m high.

const LEVEL := 4.0  ## m: the height difference under which two things are on the same level


## True when the two heights are on the same level.
static func same_level(y_a: float, y_b: float) -> bool:
	return absf(y_a - y_b) <= LEVEL


## The lane that lies the closest to `pos` and runs on the level of `pos` (-1 when there is
## none).
##
## `LaneGrid.nearest_lane` cannot filter by height: it would answer the deck that is ten metres
## above the street. The grid holds the samples of the lanes with the height of the lane, so
## the samples on the level of the point are the ones that count and the closest of them gives
## the lane. Nothing is allocated: the search walks the cells of the grid around the point.
static func nearest_lane_at_level(grid: LaneGrid, pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for cell in grid.cells_around(pos, radius):
		for entry in grid.samples_in(cell) as Array:
			var point: Vector3 = entry[2]
			if not same_level(point.y, pos.y):
				continue
			var d := point.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = int(entry[0])
	return best


## The road the player is driving on ("" when the player is on no road).
##
## The lane of the player is only kept while the player is on its level: a player that left the
## deck by a ramp and drives on the street under it is only a few metres away from the deck lane
## in the plan, but ten metres below it. The traffic of the deck must not fill the street (and
## the other way round).
static func player_road(graph: LaneGraph, grid: LaneGrid, lane: int, s: float, position: Vector3,
		radius: float) -> String:
	if lane < 0 or lane >= graph.lanes.size():
		return ""
	var point := graph.position_at(lane, s)
	if point.distance_to(position) > radius or not same_level(point.y, position.y):
		lane = nearest_lane_at_level(grid, position, radius)
		if lane < 0:
			return ""
	var lane_path: LanePath = graph.lanes[lane]
	return "" if lane_path == null else String(lane_path.road_id)

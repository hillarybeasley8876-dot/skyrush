class_name PoliceRoute
extends RefCounted
## The lane graph walks of the police (the route of the player, the spot of a block, the place a
## unit holds back).
##
## The module is the ONE place that walks the lane graph, so the spawner, the blockade and the
## squad all measure their distances the same way.
##
## A walk follows the STRAIGHTEST successor of a lane, not the first one in the list: the city
## is a grid, so the first successor of a lane is often a turn, and a roadblock that is
## "350 m ahead" would end up round a block.

## The step of a walk (m).
const STEP := 10.0
## The guard against a loop that never ends.
const GUARD := 60
## The distance from the end of a lane the tangent is measured at (m).
const TANGENT_OFFSET := 0.5


## The lane that continues into `lane` (the road behind the player), or -1 when there is none.
##
## The city is a grid, so many lanes lead into the same lane: the predecessor is the one whose
## end lies closest to the start of `lane` (the road the player really comes from).
static func previous_lane(graph: LaneGraph, lane: int) -> int:
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return -1
	var start := graph.position_at(lane, 0.0)
	var best := -1
	var best_distance := INF
	for i in graph.lane_count():
		if not graph.next_lanes[i].has(lane):
			continue
		var end := graph.position_at(i, graph.lane_length(i))
		var distance := end.distance_to(start)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## The lane a walk continues into: the successor whose start tangent is the closest to the
## tangent the current lane ends with.
##
## That is the straight road on. The first successor in the list is a turn in a grid city, and
## a walk that always turns leaves the route of the player.
static func successor(graph: LaneGraph, lane: int) -> int:
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return -1
	var options := graph.next_lanes[lane]
	if options.is_empty():
		return -1
	if options.size() == 1:
		return options[0]
	var end_tangent := _tangent_at(graph, lane, graph.lane_length(lane) - TANGENT_OFFSET)
	if end_tangent == Vector3.ZERO:
		return options[0]
	var best := options[0]
	var best_dot := -2.0
	for option in options:
		var tangent := _tangent_at(graph, option, TANGENT_OFFSET)
		if tangent == Vector3.ZERO:
			continue
		var dot := tangent.dot(end_tangent)
		if dot > best_dot:
			best_dot = dot
			best = option
	return best


## The tangent of a lane at a place (the zero vector when there is none).
static func _tangent_at(graph: LaneGraph, lane: int, s: float) -> Vector3:
	var length := graph.lane_length(lane)
	var tangent := graph.tangent_at(lane, clampf(s, 0.0, length))
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3.ZERO
	return tangent.normalized()


## Walks the graph from (lane, s) `distance` metres.
##
## Returns {"lane": int, "s": float, "position": Vector3, "found": bool}; "found" is false when
## the walk runs out of lanes. `backwards` walks against the direction of the lanes.
static func walk(graph: LaneGraph, lane: int, s: float, distance: float,
		backwards: bool = false) -> Dictionary:
	var out := {"lane": lane, "s": s, "position": Vector3.ZERO, "found": false}
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return out
	var target_lane := lane
	var offset := s
	var walked := 0.0
	var guard := 0
	var dead_end := false
	while walked < distance and guard < GUARD:
		guard += 1
		if backwards:
			offset -= STEP
			walked += STEP
			if offset < 0.0:
				var previous := previous_lane(graph, target_lane)
				if previous < 0:
					dead_end = true
					break
				target_lane = previous
				offset += graph.lane_length(previous)
			continue
		offset += STEP
		walked += STEP
		while offset >= graph.lane_length(target_lane) and guard < GUARD:
			offset -= graph.lane_length(target_lane)
			var next := successor(graph, target_lane)
			if next < 0:
				dead_end = true
				break
			target_lane = next
		if dead_end:
			break
		if offset > graph.lane_length(target_lane):
			dead_end = true
			break
	out["lane"] = target_lane
	out["s"] = offset
	out["position"] = graph.position_at(target_lane, offset)
	out["found"] = not dead_end and walked >= distance
	return out


## The points of the route between two distances ahead of (lane, s) (m).
static func route_points(graph: LaneGraph, lane: int, s: float, from: float,
		to: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return out
	var target_lane := lane
	var offset := s
	var walked := 0.0
	var guard := 0
	while walked <= to and guard < GUARD:
		guard += 1
		if walked >= from:
			out.append(graph.position_at(target_lane, offset))
		offset += STEP
		walked += STEP
		while offset >= graph.lane_length(target_lane) and guard < GUARD:
			offset -= graph.lane_length(target_lane)
			var next := successor(graph, target_lane)
			if next < 0:
				return out
			target_lane = next
	return out

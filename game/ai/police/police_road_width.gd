class_name PoliceRoadWidth
extends RefCounted
## The width of the road at a place (the carriageway the police block has to cover).
##
## The world knows the width of its roads exactly; the police measure it on the lanes that run
## beside a lane: the carriageway reaches half a lane past the outermost of them. The traffic
## unit only calls a lane a neighbour when it is one lane width away, so the lanes of the other
## side of the road are found here.

## How far the lanes that run beside the road are looked for (m).
const SEARCH_RADIUS := 20.0
## The shoulder the block covers on each side of the carriageway (m).
const SHOULDER := 1.0
## The narrowest road the police measure (m).
const MIN_WIDTH := 6.0


## The width of the road at a lane: the whole carriageway plus a metre of shoulder on each side.
static func width_at(graph: LaneGraph, grid: LaneGrid, lane: int, s: float = 0.0) -> float:
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return MIN_WIDTH
	var lane_path := graph.lanes[lane]
	var width := lane_path.lane_width
	var point := graph.position_at(lane, s)
	# The direction of the lane at that place: the tangent of the curve is not always there
	# (at the end of a lane it is the zero vector).
	var length := graph.lane_length(lane)
	var forward := graph.position_at(lane, clampf(s + 1.0, 0.0, length)) \
			- graph.position_at(lane, clampf(s - 1.0, 0.0, length))
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var road_id := graph.lanes[lane].road_id
	for other in lanes_beside(grid, point):
		if other == lane:
			continue
		if road_id != &"" and graph.lanes[other].road_id != road_id:
			# A lane of another road (a plaza or a side street) is not part of the road.
			continue
		var offset := graph.closest_offset(other, point)
		# The distance across the road: the part of the way to the other lane that is not
		# along the road.
		var delta := graph.position_at(other, offset) - point
		var along := delta.dot(forward)
		var lateral := sqrt(maxf(delta.length_squared() - along * along, 0.0))
		# The carriageway reaches the outer edge of the other lane.
		width = maxf(width, lateral + lane_path.lane_width * 0.5
				+ graph.lanes[other].lane_width * 0.5)
	return maxf(width + 2.0 * SHOULDER, MIN_WIDTH)


## The lanes that run beside a point (the grid knows the lanes near a point).
static func lanes_beside(grid: LaneGrid, point: Vector3) -> Array[int]:
	var out: Array[int] = []
	if grid == null:
		return out
	for index: int in grid.lanes_near(point, SEARCH_RADIUS):
		out.append(index)
	return out


## The lane of the graph that is nearest to a point.
static func lane_at(graph: LaneGraph, point: Vector3) -> int:
	if graph == null or graph.lane_count() == 0:
		return 0
	var best := 0
	var best_distance := INF
	for i in graph.lane_count():
		var s := graph.closest_offset(i, point)
		var distance := graph.position_at(i, s).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

class_name TrafficTestRoad
extends RefCounted
## A straight road with parallel lanes, for the tests of the traffic.
##
## The lanes run along the X axis, one lane width apart. The lane 0 is the slowest one (z = 0),
## the lane 1 the middle one and the lane 2 the one on the other side (z = 2 x the width).

const LENGTH := 400.0     ## m: the length of the lanes
const SPACING := 3.5      ## m: the distance between the centres of two lanes
const LIMIT_KMH := 80.0   ## the speed limit of the lanes


## A lane graph with `count` parallel lanes.
static func build(count: int = 3, length: float = LENGTH, spacing: float = SPACING,
		limit_kmh: float = LIMIT_KMH) -> LaneGraph:
	var lanes: Array[LanePath] = []
	for i in count:
		var path := LanePath.new()
		path.road_id = &"test_road"
		path.speed_limit_kmh = limit_kmh
		path.lane_width = spacing
		path.curve = _straight(Vector3(0.0, 0.0, float(i) * spacing), length)
		lanes.append(path)
	var graph := LaneGraph.new()
	graph.build(lanes)
	return graph


## A straight lane of `length` metres, starting at `offset`.
static func _straight(offset: Vector3, length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(offset)
	curve.add_point(offset + Vector3(length, 0.0, 0.0))
	return curve

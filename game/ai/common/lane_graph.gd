class_name LaneGraph
extends RefCounted
## Lane adjacency and geometry for every AI driver (traffic, police, rivals).
##
## Built once from a world's `Array[LanePath]`. The world provides the lane curves and the
## authored `next_lanes`; everything else is derived here so all AI units ask the same questions
## of the same roads:
##
##  * the lane to the left and to the right (and the distance between their centres, measured
##    where the car actually is - not averaged over the whole lane);
##  * the continuations at the end of a lane, each with the point where the car enters the next
##    lane and a connector curve that turns the car through the junction box instead of letting
##    it jump to the start of the next lane;
##  * the fast sampling of a lane (see LaneSampler).
##
## The work itself is split over three files: this one holds the data and the queries, LaneLinks
## works out the continuations and the junction connectors, LaneNeighbours finds the lanes that
## run side by side. The two helpers are preloaded here, they have no class_name of their own:
## they belong to the graph and to nothing else.
##
## Coordinates: the lane curve points along the driving direction, the tangent is the direction of
## travel, `right` = tangent.cross(Vector3.UP) (Godot: -Z forward, +X right).

const LaneLinks := preload("res://ai/common/lane_links.gd")
const LaneNeighbours := preload("res://ai/common/lane_neighbours.gd")
const LaneSampler := preload("res://ai/common/lane_sampler.gd")

const NEIGHBOUR_MAX_DISTANCE := 6.0   ## m: two lanes further apart are not neighbours
const NEIGHBOUR_MIN_OVERLAP := 0.35   ## tangent dot product: same direction, not the opposite
const NEIGHBOUR_MAX_LEVEL := 1.0      ## m: a neighbour is on the same level (no deck above)
const NEIGHBOUR_CELL := 6.0           ## m: the cell size of the neighbour search
const NEIGHBOUR_SAMPLES := 5          ## how many places along a lane are compared
const LINK_MAX_DISTANCE := 20.0       ## m: how far the entry of the next lane may be
const LINK_MAX_LEVEL := 1.0           ## m: the next lane must be on the same level
const LINK_MAX_ANGLE := 1.75          ## rad (100 deg): how sharp a turn at a junction may be
const CONNECTOR_MIN_LENGTH := 0.5      ## m: below this the two lanes meet and need no connector
const STRAIGHT_ANGLE := 0.52            ## rad (30 deg): the heading change of a straight link
const LOOP_MIN_LENGTH := 50.0          ## m: a lane shorter than this is never a loop
const LOOP_MAX_GAP := 8.0              ## m: how close the ends of a loop lane have to be
const SAMPLE_STEP := 20.0              ## m: the arc step of the internal lane samples
const DUPLICATE_WINDOW := 4             ## how many lanes ahead a twin is looked for
const DUPLICATE_TOLERANCE := 0.6        ## m: how close two lanes have to be to be twins

var lanes: Array[LanePath] = []
var lengths: PackedFloat32Array = PackedFloat32Array()
## Index of the lane to the left (-1 = none) and its centre-to-centre distance.
var left: PackedInt32Array = PackedInt32Array()
var left_gap: PackedFloat32Array = PackedFloat32Array()
## Index of the lane to the right (-1 = none) and its centre-to-centre distance.
var right: PackedInt32Array = PackedInt32Array()
var right_gap: PackedFloat32Array = PackedFloat32Array()
## The lanes this lane can continue into at its end.
var next_lanes: Array[PackedInt32Array] = []
## The distance along the next lane where the car enters it (parallel to `next_lanes`).
var next_entry: Array[PackedFloat32Array] = []
## The length of the connector curve of a link (parallel to `next_lanes`), 0 when the lanes meet.
var next_connector: Array[PackedFloat32Array] = []
## 1 when the lane curve returns to its start (a loop, e.g. the sandbox circuit).
var is_loop: PackedByteArray = PackedByteArray()
## The continuation of a lane that goes straight on (the best "straight" link), -1 when there is
## none. The turns are in `turn_next`.
var straight_next: PackedInt32Array = PackedInt32Array()
## The continuations of a lane that turn.
var turn_next: Array[PackedInt32Array] = []
## The number of lanes that are built twice.
var duplicates: int = 0
## The links that were dropped because they do not fit (the end of the lane and the start of the
## next one are too far apart, on another level or in the wrong direction).
var dropped_links: int = 0
## The lane this one duplicates (-1 when it is not a duplicate). The world builds a few roads
## twice, and two cars on the twin lanes would drive through each other.
var duplicate_of: PackedInt32Array = PackedInt32Array()

## One sampler per lane: the baked points of the lane and the fast sampling of them.
var _samplers: Array[LaneSampler] = []
## The connector curve of a link, keyed by the pair of the lanes.
var _connectors: Dictionary = {}


## Builds the graph from the world's lane paths. Safe to call again after a world change.
func build(lane_list: Array[LanePath]) -> void:
	lanes = lane_list
	var n := lanes.size()
	lengths.resize(n)
	left.resize(n)
	right.resize(n)
	left_gap.resize(n)
	right_gap.resize(n)
	is_loop.resize(n)
	next_lanes.clear()
	next_entry.clear()
	next_connector.clear()
	straight_next.clear()
	turn_next.clear()
	_samplers.clear()
	_connectors.clear()
	dropped_links = 0
	for i in n:
		var lane := lanes[i]
		lengths[i] = lane.curve.get_baked_length() if lane.curve != null else 0.0
		_sample_lane(i)
		left[i] = -1
		right[i] = -1
		left_gap[i] = 0.0
		right_gap[i] = 0.0
		is_loop[i] = 1 if _detect_loop(i) else 0
		next_lanes.append(PackedInt32Array())
		next_entry.append(PackedFloat32Array())
		next_connector.append(PackedFloat32Array())
	_find_duplicates()
	var neighbours := LaneNeighbours.new()
	neighbours.build(self)
	var links := LaneLinks.new()
	links.build(self)


## True when the lane is the second copy of a road the world built twice.
func is_duplicate(index: int) -> bool:
	return index >= 0 and index < duplicate_of.size() and duplicate_of[index] >= 0


## Finds the lanes that are built twice: the same road, the same start and the same end.
func _find_duplicates() -> void:
	duplicate_of.resize(lanes.size())
	duplicate_of.fill(-1)
	for i in lanes.size():
		for k in range(1, DUPLICATE_WINDOW):
			var j := i + k
			if j >= lanes.size():
				break
			if position_at(i, 0.0).distance_to(position_at(j, 0.0)) > DUPLICATE_TOLERANCE:
				continue
			if position_at(i, lengths[i]).distance_to(position_at(j, lengths[j])) \
					> DUPLICATE_TOLERANCE:
				continue
			duplicate_of[j] = i
			duplicates += 1


func lane_count() -> int:
	return lanes.size()


func lane_length(index: int) -> float:
	return lengths[index] if index >= 0 and index < lengths.size() else 0.0


## World position of the lane centre at `s` metres along the lane.
func position_at(index: int, s: float) -> Vector3:
	if index < 0 or index >= _samplers.size():
		return Vector3.ZERO
	return _samplers[index].position_at(s)


## Direction of travel at `s` (unit vector, flattened to the ground).
func tangent_at(index: int, s: float) -> Vector3:
	if index < 0 or index >= _samplers.size():
		return Vector3.FORWARD
	return _samplers[index].tangent_at(s)


## Right-hand side of the lane at `s` (unit vector, flattened to the ground).
func right_at(index: int, s: float) -> Vector3:
	if index < 0 or index >= _samplers.size():
		return Vector3.RIGHT
	return _samplers[index].right_at(s)


## The rise of the lane per metre it drives (0 on a flat road, -0.05 on a 5 % downhill).
##
## The tangent of a lane is flattened (a car drives on the ground), so the grade of the road has
## to be asked for on its own: a car on a ramp has to climb with it, or it drives into the road.
func slope_at(index: int, s: float) -> float:
	if index < 0 or index >= _samplers.size():
		return 0.0
	return _samplers[index].slope_at(s)


## The right-hand side of a direction (unit vector, flattened to the ground).
static func right_of(tangent: Vector3) -> Vector3:
	return LaneSampler.right_of(tangent)


## The transform of a car that drives along the lane: the centre line plus `lateral` metres to
## the right, with -Z pointing along the lane.
func transform_at(index: int, s: float, lateral: float) -> Transform3D:
	if index < 0 or index >= _samplers.size():
		return Transform3D.IDENTITY
	return _samplers[index].transform_at(s, lateral)


## The arc length of the lane point closest to `pos`.
func closest_offset(index: int, pos: Vector3) -> float:
	if index < 0 or index >= _samplers.size():
		return 0.0
	return _samplers[index].closest_offset(pos)


## The arc length of the lane point closest to `pos`, searched around `hint` (metres along the
## lane). Falls back to the full search when the hint is stale.
func closest_offset_near(index: int, pos: Vector3, hint: float, radius: float) -> float:
	if index < 0 or index >= _samplers.size():
		return 0.0
	return _samplers[index].closest_offset_near(pos, hint, radius)


## Signed distance of `pos` from the lane centre (positive = right of the driving direction).
func lateral_offset(index: int, s: float, pos: Vector3) -> float:
	return (pos - position_at(index, s)).dot(right_at(index, s))


## The distance between the centre of the lane `from` and the centre of the lane `to` at the
## place where they are side by side, measured at `s` on `from`. This is the gap a car has to
## cross in a lane change, and it is measured where the car is, not averaged over the lane.
func neighbour_gap(from: int, to: int, s: float) -> float:
	if from < 0 or to < 0 or from >= _samplers.size() or to >= _samplers.size():
		return INF
	var point := position_at(from, s)
	var hint := clampf(s / maxf(lengths[from], 1.0), 0.0, 1.0) * lengths[to]
	var entry := closest_offset_near(to, point, hint, 60.0)
	return point.distance_to(position_at(to, entry))


## The arc length on the lane `to` of the point that lies beside the point at `s` on the lane
## `from`. This is where the car is when it changes lanes, so every lane-change query uses it.
func aligned_offset(from: int, to: int, s: float) -> float:
	if from < 0 or to < 0 or from >= _samplers.size() or to >= _samplers.size():
		return 0.0
	var point := position_at(from, s)
	var hint := clampf(s / maxf(lengths[from], 1.0), 0.0, 1.0) * lengths[to]
	return closest_offset_near(to, point, hint, 30.0)


## True when the road of the lane ends there: the car has to stop at the end of the lane.
func is_dead_end(index: int) -> bool:
	if index < 0 or index >= next_lanes.size():
		return true
	return next_lanes[index].is_empty() and is_loop[index] == 0


## The connector curve of a link: the car drives it from the end of its lane to the entry of the
## next one, so it turns through the junction box instead of jumping.
func connector_of(from: int, to: int) -> Curve3D:
	return _connectors.get(link_key(from, to)) as Curve3D


## The key of a link in the connector table. An integer key is a lot faster than a string one,
## and the traffic asks for a connector every time a car reaches the end of its lane.
static func link_key(from: int, to: int) -> int:
	return (from << 32) | to


## The distance along the next lane where the car enters it (0 when the link is unknown).
func entry_offset(from: int, to: int) -> float:
	var index := next_lanes[from].find(to)
	if index < 0:
		return 0.0
	return next_entry[from][index]


## The length of the connector curve of a link (0 when the two lanes meet).
func connector_length(from: int, to: int) -> float:
	if from < 0 or from >= next_connector.size():
		return 0.0
	var index := next_lanes[from].find(to)
	if index < 0:
		return 0.0
	return next_connector[from][index]


## Keeps the baked points of a lane and the coarse samples the neighbour search works on.
func _sample_lane(index: int) -> void:
	var sampler := LaneSampler.new()
	var lane := lanes[index]
	if lane.curve != null and lengths[index] > 0.0:
		sampler.setup(lane.curve, lengths[index])
	_samplers.append(sampler)


## A lane is a loop when its start and end meet. A short lane is never a loop: a six metre
## stub that links to itself is a dead end, and a car that circles on the spot looks broken.
func _detect_loop(index: int) -> bool:
	if lengths[index] < LOOP_MIN_LENGTH:
		return false
	return position_at(index, 0.0).distance_to(position_at(index, lengths[index])) < LOOP_MAX_GAP

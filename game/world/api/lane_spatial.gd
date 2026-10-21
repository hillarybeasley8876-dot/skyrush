extends RefCounted
## A fine spatial grid over the lane centre lines. The furniture filter and the route builder
## need the distance from a point to the nearest lane; scanning every lane cost 15 s, so the
## lane segments are indexed in 12 m cells and the distance is computed from the segments.
##
## The grid answers "how far is this point from every lane around it" in a few microseconds,
## which is what the furniture filter needs to move a prop out of the carriageway.

const CELL := 6.0
## The length of one segment of a lane.
const SEGMENT := 8.0

var _cells: Dictionary = {}  # the cell key -> PackedInt32Array of segment indices
var _seg_lane: PackedInt32Array = PackedInt32Array()
var _seg_a: PackedVector3Array = PackedVector3Array()
var _seg_b: PackedVector3Array = PackedVector3Array()
var _seg_offset: PackedFloat32Array = PackedFloat32Array()
## The lanes of the grid (the exact distance to a curve is needed when a prop stands near it).
var _lanes: Array[LanePath] = []
var _lane_total := 0


func build(lanes: Array[LanePath]) -> void:
	_cells.clear()
	_lanes = lanes
	_seg_lane = PackedInt32Array()
	_seg_a = PackedVector3Array()
	_seg_b = PackedVector3Array()
	_seg_offset = PackedFloat32Array()
	_lane_total = lanes.size()
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		if length < 0.01:
			continue
		var steps := maxi(int(length / SEGMENT), 1)
		var step_length := length / float(steps)
		var previous := lane.curve.sample_baked(0.0, true)
		for s in range(1, steps + 1):
			var offset := step_length * float(s)
			var point := lane.curve.sample_baked(offset, true)
			_add_segment(i, previous, point, offset - step_length)
			previous = point


## The lanes the grid was built from.
func lanes() -> Array[LanePath]:
	return _lanes
## The exact distance from a point to the curve of a lane. The grid approximates a curve with
## straight segments of 8 m, so a tight curve (a junction) can hide a lane from the fast query:
## the callers check the lanes that are near the point with this exact distance.
func closest_distance(lane_index: int, point: Vector3) -> float:
	var closest := closest_point(lane_index, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length()


## The point of the curve of a lane that is closest to the point.
func closest_point(lane_index: int, point: Vector3) -> Vector3:
	if lane_index < 0 or lane_index >= _lanes.size():
		return point
	var lane := _lanes[lane_index]
	if lane == null or lane.curve == null:
		return point
	return lane.curve.sample_baked(lane.curve.get_closest_offset(point), true)
## The lanes around the point with their distance to it: the fast query (no dictionary per
## lane, so the furniture filter can ask 60,000 times without a pause).
## {"lanes": PackedInt32Array, "distances": PackedFloat32Array, "heights": PackedFloat32Array}
func query_near(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_height: Dictionary = {}
	var span := maxi(int(floor(radius / CELL)), 1)
	var cx := int(floor(point.x / CELL))
	var cz := int(floor(point.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := _key(cx + dx, cz + dz)
			if not _cells.has(key):
				continue
			for index in _cells[key] as PackedInt32Array:
				var a := _seg_a[index]
				var b := _seg_b[index]
				var t := _segment_parameter(a, b, point)
				var closest := a.lerp(b, t)
				var distance := Vector2(closest.x - point.x, closest.z - point.z).length()
				# The grid stores the lanes as straight segments: the middle of a sharp curve is
				# farther from its chord than the curve is from the point, so a lane is kept when
				# its chord is one segment farther than the radius. The callers measure the lanes
				# they get on the curve.
				if distance > radius + SEGMENT:
					continue
				var lane_index := _seg_lane[index]
				if best.has(lane_index) and float(best[lane_index]) <= distance:
					continue
				best[lane_index] = distance
				best_height[lane_index] = closest.y
	var lanes := PackedInt32Array()
	var distances := PackedFloat32Array()
	var heights := PackedFloat32Array()
	for lane_index in best.keys():
		lanes.append(int(lane_index))
		distances.append(float(best[lane_index]))
		heights.append(float(best_height[lane_index]))
	return {"lanes": lanes, "distances": distances, "heights": heights}


## The closest point of one lane: the point, the offset along it and its direction. The curve
## is measured exactly (the segments of the grid are a straight approximation).
func detail(lane_index: int, point: Vector3) -> Dictionary:
	if lane_index < 0 or lane_index >= _lanes.size():
		return {"distance": INF, "point": point, "offset": 0.0, "tangent": Vector3.FORWARD}
	var lane := _lanes[lane_index]
	if lane == null or lane.curve == null:
		return {"distance": INF, "point": point, "offset": 0.0, "tangent": Vector3.FORWARD}
	var offset := lane.curve.get_closest_offset(point)
	var closest := lane.curve.sample_baked(offset, true)
	var length := lane.curve.get_baked_length()
	var ahead := lane.curve.sample_baked(minf(offset + 4.0, length), true)
	var tangent := ahead - closest
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD
	return {
		"distance": Vector2(closest.x - point.x, closest.z - point.z).length(),
		"point": closest,
		"offset": offset,
		"tangent": tangent.normalized(),
	}


func _add_segment(lane_index: int, a: Vector3, b: Vector3, offset: float) -> void:
	var index := _seg_lane.size()
	_seg_lane.append(lane_index)
	_seg_a.append(a)
	_seg_b.append(b)
	_seg_offset.append(offset)
	var cx0 := int(floor(minf(a.x, b.x) / CELL))
	var cx1 := int(floor(maxf(a.x, b.x) / CELL))
	var cz0 := int(floor(minf(a.z, b.z) / CELL))
	var cz1 := int(floor(maxf(a.z, b.z) / CELL))
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			var key := _key(cx, cz)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			var list: PackedInt32Array = _cells[key]
			list.append(index)
			_cells[key] = list


## The lanes around the point: {lane index: {"distance", "point", "offset", "tangent"}}.
func query(point: Vector3, radius: float) -> Dictionary:
	var out: Dictionary = {}
	var span := maxi(int(floor(radius / CELL)), 1)
	var cx := int(floor(point.x / CELL))
	var cz := int(floor(point.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := _key(cx + dx, cz + dz)
			if not _cells.has(key):
				continue
			for index in _cells[key] as PackedInt32Array:
				var a := _seg_a[index]
				var b := _seg_b[index]
				var t := _segment_parameter(a, b, point)
				var closest := a.lerp(b, t)
				var distance := Vector2(closest.x - point.x, closest.z - point.z).length()
				if distance > radius:
					continue
				var lane_index := _seg_lane[index]
				if out.has(lane_index) and float(out[lane_index]["distance"]) <= distance:
					continue
				var tangent := b - a
				tangent.y = 0.0
				if tangent.length_squared() > 0.0001:
					tangent = tangent.normalized()
				out[lane_index] = {
					"distance": distance,
					"point": closest,
					"offset": _seg_offset[index] + t * a.distance_to(b),
					"tangent": tangent,
				}
	return out


## The key of a cell (an integer, so the lookup does not build a string).
static func _key(cx: int, cz: int) -> int:
	return (cx + 32768) * 65536 + (cz + 32768)


## The parameter (0..1) of the closest point of the segment.
static func _segment_parameter(a: Vector3, b: Vector3, point: Vector3) -> float:
	var d := b - a
	var length_squared := d.x * d.x + d.z * d.z
	if length_squared < 0.0001:
		return 0.0
	var t := ((point.x - a.x) * d.x + (point.z - a.z) * d.z) / length_squared
	return clampf(t, 0.0, 1.0)

extends RefCounted
## Finds the lanes that run side by side (the lane to the left and to the right of a lane).
##
## The helper is preloaded by LaneGraph, it has no class_name of its own.
##
## A neighbour has to be on the same level - a deck above is not a neighbour, a car that changes
## "lane" there would drop through the deck - and it has to run alongside at a distance of about
## one lane width. The distance is measured at five places along the lane, because two roads that
## cross in the middle of the map are neighbours for a moment only.
##
## The search walks a grid of coarse sample points (one every SAMPLE_STEP metres), so the work
## is proportional to the length of the roads and not to the number of lanes.

## How many places along a lane are compared.
const SAMPLES := 5

var _graph: LaneGraph = null
var _points: Array[PackedVector3Array] = []
var _tangents: Array[PackedVector3Array] = []


## Fills the `left`, `right`, `left_gap` and `right_gap` arrays of the graph.
func build(graph: LaneGraph) -> void:
	_graph = graph
	_sample_all()
	_chain_all()


func _sample_all() -> void:
	var step := LaneGraph.SAMPLE_STEP
	for i in _graph.lane_count():
		var coarse := PackedVector3Array()
		var count := maxi(int(_graph.lane_length(i) / step) + 1, 2)
		for k in count:
			coarse.append(_graph.position_at(i, _graph.lane_length(i) * float(k) / float(count - 1)))
		var coarse_tangents := PackedVector3Array()
		for k in coarse.size():
			var a := coarse[maxi(k - 1, 0)]
			var b := coarse[mini(k + 1, coarse.size() - 1)]
			var t := b - a
			t.y = 0.0
			coarse_tangents.append(t.normalized() if t.length_squared() > 0.0001 else Vector3.FORWARD)
		_points.append(coarse)
		_tangents.append(coarse_tangents)


## Pairs every lane with the lanes beside it.
func _chain_all() -> void:
	var grid: Dictionary = {}
	for i in _points.size():
		for k in _points[i].size():
			var key := _cell_key(_points[i][k])
			if not grid.has(key):
				grid[key] = [] as Array
			(grid[key] as Array).append(Vector2i(i, k))
	for i in _points.size():
		var candidates: Dictionary = {}
		for k in _points[i].size():
			for entry in _near_cells(grid, _points[i][k]):
				var j: int = entry.x
				if j != i:
					candidates[j] = true
		_chain_one(i, candidates)


## Picks the lane to the left and the lane to the right of this one.
func _chain_one(index: int, candidates: Dictionary) -> void:
	var best_left := -1
	var best_right := -1
	var gap_left := INF
	var gap_right := INF
	for j: int in candidates:
		if not _runs_alongside(index, j):
			continue
		var offset := _mean_offset(index, j)
		var distance := absf(offset)
		if distance > LaneGraph.NEIGHBOUR_MAX_DISTANCE:
			continue
		if offset < 0.0:
			if best_left < 0 or distance < gap_left:
				best_left = j
				gap_left = distance
		else:
			if best_right < 0 or distance < gap_right:
				best_right = j
				gap_right = distance
	_graph.left[index] = best_left
	_graph.right[index] = best_right
	_graph.left_gap[index] = gap_left if best_left >= 0 else 0.0
	_graph.right_gap[index] = gap_right if best_right >= 0 else 0.0


## True when the two lanes run in the same direction next to each other, on the same level.
func _runs_alongside(a: int, b: int) -> bool:
	if _tangents[a].is_empty() or _tangents[b].is_empty():
		return false
	var mid := _tangents[a].size() / 2
	var other := int(float(mid) * float(_tangents[b].size()) / float(maxi(_tangents[a].size(), 1)))
	other = clampi(other, 0, _tangents[b].size() - 1)
	if _tangents[a][mid].dot(_tangents[b][other]) < LaneGraph.NEIGHBOUR_MIN_OVERLAP:
		return false
	return _level_difference(a, b) <= LaneGraph.NEIGHBOUR_MAX_LEVEL


## The biggest height difference between the two lanes, measured where they run alongside.
func _level_difference(a: int, b: int) -> float:
	var worst := 0.0
	for k in SAMPLES:
		var f := float(k + 1) / float(SAMPLES + 1)
		var s := _graph.lane_length(a) * f
		var point := _graph.position_at(a, s)
		var entry := _graph.closest_offset_near(b, point, _graph.lane_length(b) * f, 40.0)
		worst = maxf(worst, absf(_graph.position_at(b, entry).y - point.y))
	return worst


## The signed distance from lane `a` to lane `b`, measured between the points at the same arc
## length. Positive means `b` is to the right of `a`.
func _mean_offset(a: int, b: int) -> float:
	var pa := _points[a]
	var pb := _points[b]
	var n := mini(pa.size(), pb.size())
	if n < 2:
		return 0.0
	var total := 0.0
	for k in n:
		var index_b := int(float(k) * float(pb.size() - 1) / float(n - 1))
		var right_v := _tangents[a][k].cross(Vector3.UP)
		total += (pb[index_b] - pa[k]).dot(right_v)
	return total / float(n)


func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / LaneGraph.NEIGHBOUR_CELL)),
			int(floor(p.z / LaneGraph.NEIGHBOUR_CELL)))


## The sample points in the 3x3 cell block around `p`.
func _near_cells(grid: Dictionary, p: Vector3) -> Array:
	var out: Array = []
	var key := _cell_key(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := key + Vector2i(dx, dz)
			if grid.has(k):
				out.append_array(grid[k] as Array)
	return out

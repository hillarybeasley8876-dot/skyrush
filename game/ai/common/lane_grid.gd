class_name LaneGrid
extends RefCounted
## A static grid of the lane samples of a world.
##
## Built once per world, it answers "which lanes are near this point" without walking every lane
## of the city: the traffic needs that every tick (the player may be off its lane) and the ring
## measurement needs it every two seconds.

const CELL := 50.0        ## m: the size of a cell
const SAMPLE_STEP := 12.0  ## m: the step of the samples that go into the grid

var _cells: Dictionary = {}  ## Vector2i -> Array of [lane: int, s: float, point: Vector3]

## The distance between two samples of the grid.
const sample_step := SAMPLE_STEP


## Fills the grid with the samples of every lane of the graph.
func build(graph: LaneGraph) -> void:
	_cells.clear()
	for i in graph.lane_count():
		var length := graph.lane_length(i)
		if length <= 0.0:
			continue
		var s := 0.0
		while s <= length:
			_add(i, s, graph.position_at(i, s))
			s += SAMPLE_STEP


## The lanes that have a sample within `radius` of `pos`.
func lanes_near(pos: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var seen: Dictionary = {}
	var reach := int(ceil(radius / CELL))
	var key := _key(pos)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := key + Vector2i(dx, dz)
			if not _cells.has(cell):
				continue
			for entry in _cells[cell] as Array:
				var lane: int = entry[0]
				if seen.has(lane):
					continue
				seen[lane] = true
				out.append(lane)
	return out


## The lane with the closest centre to `pos`, or -1 when nothing is within `radius`.
func nearest_lane(pos: Vector3, radius: float) -> int:
	var reach := int(ceil(radius / CELL))
	var key := _key(pos)
	var best := -1
	var best_d := radius * radius
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := key + Vector2i(dx, dz)
			if not _cells.has(cell):
				continue
			for entry in _cells[cell] as Array:
				var sample: Vector3 = entry[2]
				var d := sample.distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = entry[0]
	return best


## The cells of the grid around a point, as a flat list the caller can walk in slices.
func cells_around(pos: Vector3, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach := int(ceil(radius / CELL))
	var key := _key(pos)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := key + Vector2i(dx, dz)
			if _cells.has(cell):
				out.append(cell)
	return out


## The samples in one cell: [lane: int, s: float, point: Vector3].
func samples_in(cell: Vector2i) -> Array:
	return _cells.get(cell, []) as Array


## The number of cells the grid holds (the size of the city).
func cell_count() -> int:
	return _cells.size()


func _add(lane: int, s: float, point: Vector3) -> void:
	var key := _key(point)
	if not _cells.has(key):
		_cells[key] = [] as Array
	(_cells[key] as Array).append([lane, s, point] as Array)


func _key(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL)), int(floor(point.z / CELL)))

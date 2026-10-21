extends RefCounted
## A spatial index over the lane curves: the nearest lane is found in the cells around a point
## instead of scanning every lane (666 lanes × two curve queries per call was 0.7-1.2 ms).

const CELL := 64.0
const SAMPLE := 20.0

var _cells: Dictionary = {}  # "x_z" -> Array[int] of lane indices


func build(lanes: Array[LanePath]) -> void:
	_cells.clear()
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var steps := maxi(int(length / SAMPLE), 1)
		for s in steps + 1:
			var point := lane.curve.sample_baked(length * float(s) / float(steps), true)
			_insert(point, i)


## The lanes that pass within `radius` of the point (plus the lanes of the neighbouring cells).
func candidates(point: Vector3, radius: float = CELL * 1.5) -> Array[int]:
	var out: Array[int] = []
	var span := maxi(int(ceil(radius / CELL)), 1)
	var cx := int(floor(point.x / CELL))
	var cz := int(floor(point.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := "%d_%d" % [cx + dx, cz + dz]
			if not _cells.has(key):
				continue
			for index in _cells[key] as Array:
				if not out.has(index):
					out.append(index)
	return out


func _insert(point: Vector3, index: int) -> void:
	var key := "%d_%d" % [int(floor(point.x / CELL)), int(floor(point.z / CELL))]
	if not _cells.has(key):
		_cells[key] = []
	var list: Array = _cells[key]
	if not list.has(index):
		list.append(index)

extends RefCounted
## The Douglas-Peucker simplification of the road polylines (in metres) and their bounding box.
## Kept in its own file so the minimap panel stays small.

## The tolerance of the simplification, in metres.
const TOLERANCE := 3.0


## Simplify a polyline: the points that are closer than TOLERANCE to the line between their
## neighbours are dropped.
static func simplify(points: PackedVector2Array, tolerance: float = TOLERANCE) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	_simplify_range(points, 0, points.size() - 1, tolerance, out)
	out.append(points[points.size() - 1])
	return out


static func _simplify_range(points: PackedVector2Array, first: int, last: int, tolerance: float,
		out: PackedVector2Array) -> void:
	if last <= first + 1:
		return
	var a := points[first]
	var b := points[last]
	var max_dist := 0.0
	var index := first
	for i in range(first + 1, last):
		var d := perp_distance(points[i], a, b)
		if d > max_dist:
			max_dist = d
			index = i
	if max_dist > tolerance:
		_simplify_range(points, first, index, tolerance, out)
		out.append(points[index])
		_simplify_range(points, index, last, tolerance, out)


## The distance of p from the segment a..b.
static func perp_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The bounding box of a polyline.
static func bounds_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var r := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		r = r.expand(points[i])
	return r

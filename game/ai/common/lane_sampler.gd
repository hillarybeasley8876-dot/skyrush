extends RefCounted
## The baked points of one lane and the fast sampling of them.
##
## PERFORMANCE: this does NOT use `Curve3D.sample_baked()`. That function scans the baked points
## linearly, which costs ~15 us per call on a long lane - with 60 cars and five calls per tick
## that is the whole frame budget. The sampler keeps the baked points itself and searches them
## with a binary search instead.
##
## The sampler is loaded by LaneGraph (preload), it has no class_name of its own: it is a helper
## of the graph and of nothing else.

const CLOSEST_SAMPLES := 256  ## how many points the full closest-point search looks at

var points: PackedVector3Array = PackedVector3Array()
var offsets: PackedFloat32Array = PackedFloat32Array()
var tangents: PackedVector3Array = PackedVector3Array()
var length: float = 0.0


## Bakes the curve and computes the tangents.
func setup(curve: Curve3D, total_length: float) -> void:
	length = total_length
	if curve == null or total_length <= 0.0:
		return
	points = curve.get_baked_points()
	offsets = _offsets_of(points, total_length)
	if points.size() >= 2:
		for k in points.size():
			var a := points[maxi(k - 1, 0)]
			var b := points[mini(k + 1, points.size() - 1)]
			var t := b - a
			t.y = 0.0
			tangents.append(t.normalized() if t.length_squared() > 0.0001 else Vector3.FORWARD)


## World position of the lane centre at `s` metres along the lane.
func position_at(s: float) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO
	var i := segment(s)
	if i >= points.size() - 1:
		return points[points.size() - 1]
	var f := _fraction(i, s)
	return points[i].lerp(points[i + 1], f)


## Direction of travel at `s` (unit vector, flattened to the ground).
func tangent_at(s: float) -> Vector3:
	if tangents.is_empty():
		return Vector3.FORWARD
	var i := segment(s)
	if i >= tangents.size() - 1:
		return tangents[tangents.size() - 1]
	return tangents[i].lerp(tangents[i + 1], 0.5).normalized()


## Right-hand side of the lane at `s` (unit vector, flattened to the ground).
func right_at(s: float) -> Vector3:
	var r := tangent_at(s).cross(Vector3.UP)
	r.y = 0.0
	if r.length_squared() < 0.0001:
		return Vector3.RIGHT
	return r.normalized()


## The rise of the lane per metre it drives (0 on a flat road, -0.05 on a 5 % downhill).
##
## The tangents of the lanes are flattened (a car drives on the ground), so the grade of the road
## has to be asked for separately: a car on a ramp has to climb with it, or it drives into the
## road or off the deck.
func slope_at(s: float) -> float:
	if points.size() < 2:
		return 0.0
	var i := segment(s)
	if i >= points.size() - 1:
		i = points.size() - 2
	var flat := Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
	if flat < 0.0001:
		return 0.0
	return (points[i + 1].y - points[i].y) / flat


## The transform of a car that drives along the lane: the centre line plus `lateral` metres to
## the right, with -Z pointing along the lane.
func transform_at(s: float, lateral: float) -> Transform3D:
	if points.size() < 2:
		return Transform3D.IDENTITY
	var i := segment(s)
	var f := _fraction(i, s)
	var centre := points[i].lerp(points[i + 1], f)
	var tangent := tangents[i].lerp(tangents[i + 1], 0.5)
	tangent.y = 0.0
	tangent = tangent.normalized() if tangent.length_squared() > 0.0001 else Vector3.FORWARD
	var right := tangent.cross(Vector3.UP)
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	return Transform3D(Basis(right, Vector3.UP, -tangent), centre + right * lateral)


## The arc length of the lane point closest to `pos`.
func closest_offset(pos: Vector3) -> float:
	if points.is_empty():
		return 0.0
	var step := maxi(1, points.size() / CLOSEST_SAMPLES)
	var best := 0
	var best_d := INF
	for i in range(0, points.size(), step):
		var d := points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	var offset := 0.0
	var best_segment_d := INF
	for i in range(maxi(best - step, 0), mini(best + step, points.size() - 1)):
		var found := _project(pos, i)
		if found[1] < best_segment_d:
			best_segment_d = found[1]
			offset = found[0]
	return offset


## The arc length of the lane point closest to `pos`, searched around `hint` (metres along the
## lane). Falls back to the full search when the hint is stale.
func closest_offset_near(pos: Vector3, hint: float, radius: float) -> float:
	if points.is_empty():
		return 0.0
	var lo := segment(maxf(hint - radius, 0.0))
	var hi := segment(minf(hint + radius, length))
	var best := lo
	var best_d := INF
	var best_f := 0.0
	for i in range(lo, mini(hi + 1, points.size() - 1)):
		var found := _project(pos, i)
		if found[1] < best_d:
			best_d = found[1]
			best = i
			best_f = found[2]
	if best_d > radius * radius:
		return closest_offset(pos)
	return offsets[best] + (offsets[best + 1] - offsets[best]) * best_f


## The distance along the lane of the point of the segment `i` that is closest to `pos`.
##
## The result is [the arc length, the squared distance, the fraction of the segment]. The arc
## length is interpolated: the baked points of a lane are four metres apart, and a car that
## gets the distance of a baked point instead of the real one jumps four metres.
func _project(pos: Vector3, i: int) -> Array:
	var a := points[i]
	var b := points[i + 1]
	var seg := b - a
	var length2 := seg.length_squared()
	var f := 0.0
	if length2 > 0.0001:
		f = clampf((pos - a).dot(seg) / length2, 0.0, 1.0)
	var point := a.lerp(b, f)
	return [offsets[i] + (offsets[i + 1] - offsets[i]) * f, point.distance_squared_to(pos), f]


## The index of the baked point before `s` (the segment the sample falls into).
func segment(s: float) -> int:
	if offsets.size() < 2:
		return 0
	var lo := 0
	var hi := offsets.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if offsets[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return mini(lo, offsets.size() - 2)


## How far `s` is into the segment that starts at `i` (0..1).
func _fraction(i: int, s: float) -> float:
	var span := offsets[i + 1] - offsets[i]
	if span <= 0.0:
		return 0.0
	return (clampf(s, 0.0, length) - offsets[i]) / span


## The arc length of every baked point, rescaled so the polyline ends at the real curve length.
func _offsets_of(baked: PackedVector3Array, total_length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var acc := 0.0
	for k in baked.size():
		out.append(acc)
		if k < baked.size() - 1:
			acc += baked[k].distance_to(baked[k + 1])
	if acc > 0.0 and total_length > 0.0:
		var scale := total_length / acc
		for k in out.size():
			out[k] *= scale
	return out


## The right-hand side of a direction (unit vector, flattened to the ground).
static func right_of(tangent: Vector3) -> Vector3:
	var r := tangent.cross(Vector3.UP)
	r.y = 0.0
	if r.length_squared() < 0.0001:
		return Vector3.RIGHT
	return r.normalized()

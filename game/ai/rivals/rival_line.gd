class_name RivalLine
extends RefCounted
## The racing line of a route, prepared for the rival AI: a sampled point table, a curvature
## table, a speed profile and a straight table, so a rival can look ahead every tick without
## scanning the whole curve (a city route is 100 km long).
##
## The tables are built once when the race starts. Everything a rival needs per tick is a
## table lookup.

const STEP := 2.0          ## m between two sampled points
const CURVATURE_SPAN := 6   ## samples (12 m) the curvature is measured over
const SMOOTH_SPAN := 10     ## samples (20 m) the curvature is smoothed over
const LEAD_IN := 60.0       ## m of straight before the start of an open line
const CLOSE_EPS := 12.0     ## m: a curve whose ends are this close counts as closed
const KAPPA_MIN := 0.0002   ## 1/m: the curvature below which a corner counts as straight
const STRAIGHT_KAPPA := 0.004 ## 1/m: the curvature above which a corner stops the straight
const MAX_CURVATURE_LOOKAHEAD := 30.0 ## m: the window of the max curvature table

var curve: Curve3D = null
var length: float = 0.0
var closed: bool = false
## The offset of the start of the table (the lead-in of an open line).
var table_start: float = 0.0

var _points: PackedVector3Array = PackedVector3Array()
var _curvature: PackedFloat32Array = PackedFloat32Array()
var _straights: PackedFloat32Array = PackedFloat32Array()
var _max_curvature: PackedFloat32Array = PackedFloat32Array()
var _profiles: Dictionary = {}


func _init(source: Curve3D) -> void:
	curve = source
	if curve == null:
		return
	length = curve.get_baked_length()
	if length < 1.0:
		return
	var first := curve.sample_baked(0.0, true)
	var last := curve.sample_baked(length - 0.01, true)
	closed = first.distance_to(last) < CLOSE_EPS
	_build_tables()


## Fills the point, the curvature and the straight tables.
func _build_tables() -> void:
	table_start = 0.0 if closed else -LEAD_IN
	var count := maxi(int((length - table_start) / STEP), 2)
	_points.resize(count + 1)
	for i in count + 1:
		var offset := table_start + length * float(i) / float(count)
		if offset < 0.0:
			# The lead-in: a straight continuation of the tangent at the start.
			var head := curve.sample_baked(0.0, true)
			var ahead := curve.sample_baked(2.0, true)
			var dir := (ahead - head).normalized()
			_points[i] = head + dir * offset
		else:
			_points[i] = curve.sample_baked(offset, true)
	_curvature.resize(count + 1)
	for i in count + 1:
		_curvature[i] = _curvature_at_index(i, count)
	_smooth_curvature(count)
	_build_straights(count)
	_build_max_curvature(count)


## The Menger curvature of three points (1/m). 0 on a straight.
##
## The three points are CURVATURE_SPAN samples apart (12 m): a lane curve is a spline through
## control points, and a short baseline would read the kinks of the spline as 10 m corners.
func _curvature_at_index(index: int, count: int) -> float:
	var a := _points[_wrap(index - CURVATURE_SPAN, count)]
	var b := _points[index]
	var c := _points[_wrap(index + CURVATURE_SPAN, count)]
	var ab := b - a
	var bc := c - b
	var ac := c - a
	var la := ab.length()
	var lb := bc.length()
	var lc := ac.length()
	if la < 0.01 or lb < 0.01 or lc < 0.01:
		return 0.0
	var area := ab.cross(ac).length() * 0.5
	return 4.0 * area / (la * lb * lc)


## Smooths the curvature over +-SMOOTH_SPAN samples: a lane spline has single points where
## the direction jumps, and a car must not slow down to 10 km/h for a 5 m kink.
func _smooth_curvature(count: int) -> void:
	var raw := _curvature.duplicate()
	for i in count + 1:
		var sum := 0.0
		for k in range(-SMOOTH_SPAN, SMOOTH_SPAN + 1):
			sum += raw[_wrap(i + k, count)]
		_curvature[i] = sum / float(2 * SMOOTH_SPAN + 1)


## The distance of the straight ahead for every point of the table.
func _build_straights(count: int) -> void:
	_straights.resize(count + 1)
	for i in count + 1:
		var distance := 0.0
		var k := 0
		while k < count:
			k += 1
			if _curvature[_wrap(i + k, count)] > STRAIGHT_KAPPA:
				break
			distance += STEP
		_straights[i] = distance


## The highest curvature of the next `distance` metres, for every point of the table.
##
## The rival starts its drift when the corner is this close, so the table saves a scan of the
## line on every tick.
func _build_max_curvature(count: int) -> void:
	var span := int(MAX_CURVATURE_LOOKAHEAD / STEP)
	_max_curvature.resize(count + 1)
	for i in count + 1:
		var best := 0.0
		for k in range(0, span + 1):
			best = maxf(best, _curvature[_wrap(i + k, count)])
		_max_curvature[i] = best


## The highest curvature of the next `distance` metres (1/m).
func max_curvature_ahead(offset: float, distance: float) -> float:
	if _max_curvature.is_empty():
		return 0.0
	var span := int(distance / STEP)
	var index := _index_at(offset)
	var count := _max_curvature.size() - 1
	var best := 0.0
	for k in range(0, span + 1):
		best = maxf(best, _max_curvature[_wrap(index + k, count)])
	return best


## Wraps an index into the table (the table has one extra point that repeats the first).
func _wrap(index: int, count: int) -> int:
	return ((index % count) + count) % count


## The index of the table point at `offset` (the offset wraps on a closed line).
func _index_at(offset: float) -> int:
	var o := offset
	if closed:
		o = fposmod(o, length)
	else:
		o = clampf(o, table_start, length)
	var f := (o - table_start) / STEP
	return clampi(int(f), 0, _points.size() - 1)


## The point on the line at `offset` metres (the offset wraps on a closed line).
func point_at(offset: float) -> Vector3:
	if _points.is_empty():
		return Vector3.ZERO
	var o := offset
	if closed:
		o = fposmod(o, length)
	else:
		o = clampf(o, table_start, length)
	var f := (o - table_start) / STEP
	var i := int(f)
	if i >= _points.size() - 1:
		return _points[_points.size() - 1]
	return _points[i].lerp(_points[i + 1], f - float(i))


## The unit tangent (XZ) at `offset` metres.
func tangent_at(offset: float) -> Vector3:
	var a := point_at(offset - 1.0)
	var b := point_at(offset + 1.0)
	var dir := b - a
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


## The unit right vector (XZ) at `offset`: right = forward x up.
func right_at(offset: float) -> Vector3:
	return tangent_at(offset).cross(Vector3.UP).normalized()


## The curvature (1/m) at `offset`.
func curvature_at(offset: float) -> float:
	if _curvature.is_empty():
		return 0.0
	var o := offset
	if closed:
		o = fposmod(o, length)
	else:
		o = clampf(o, table_start, length)
	var f := (o - table_start) / STEP
	var i := int(f)
	if i >= _curvature.size() - 1:
		return _curvature[_curvature.size() - 1]
	return lerpf(_curvature[i], _curvature[i + 1], f - float(i))


## The speed a corner at `offset` can be taken at: v = sqrt(A / kappa) (dossier 6.2).
func corner_speed(offset: float, a_lat: float) -> float:
	var kappa := maxf(curvature_at(offset), KAPPA_MIN)
	return sqrt(maxf(a_lat, 1.0) / kappa)


## The speed profile of the route for a grip budget: the highest speed the car may hold at
## every point of the line so that it can still make every corner ahead.
##
## It is a backward pass (`v[i] = min(v_corner[i], sqrt(v[i+1]^2 + 2 * a_brake * STEP))`), so
## the lookup is O(1) instead of a scan over the braking distance.
func profile(a_lat: float, a_brake: float) -> PackedFloat32Array:
	var key := "%0.2f|%0.2f" % [a_lat, a_brake]
	if _profiles.has(key):
		return _profiles[key] as PackedFloat32Array
	var count := _curvature.size() - 1
	var v := PackedFloat32Array()
	v.resize(count + 1)
	for i in count + 1:
		v[i] = sqrt(maxf(a_lat, 1.0) / maxf(_curvature[i], KAPPA_MIN))
	var passes := 3 if closed else 1
	for p in passes:
		for i in range(count, -1, -1):
			var next := v[_wrap(i + 1, count)]
			v[i] = minf(v[i], sqrt(next * next + 2.0 * a_brake * STEP))
	_profiles[key] = v
	return v


## The speed the car may hold at `offset` (the profile already looks at the corners ahead).
func speed_limit(offset: float, a_lat: float, a_brake: float) -> float:
	if _curvature.is_empty():
		return INF
	return profile(a_lat, a_brake)[_index_at(offset)]


## The distance of the straight ahead (how far the curvature stays under the threshold).
func straight_ahead(offset: float) -> float:
	if _straights.is_empty():
		return 0.0
	return _straights[_index_at(offset)]


## The offset of the point of the line closest to `pos`, searched in a window around
## `from_offset` (the local search keeps the per-tick cost constant on a 100 km route).
func project(from_offset: float, pos: Vector3, window: float) -> float:
	if _points.is_empty():
		return 0.0
	var count := _points.size() - 1
	var first := int(floor((from_offset - window - table_start) / STEP))
	var last := int(ceil((from_offset + window - table_start) / STEP))
	var best := from_offset
	var best_distance := INF
	for i in range(first, last + 1):
		var index := _wrap(i, count)
		var a := _points[index]
		var b := _points[index + 1]
		var seg := b - a
		var len_sq := seg.length_squared()
		var t := 0.0
		if len_sq > 0.0001:
			t = clampf((pos - a).dot(seg) / len_sq, 0.0, 1.0)
		var distance := pos.distance_squared_to(a + seg * t)
		if distance < best_distance:
			best_distance = distance
			best = table_start + (float(i) + t) * STEP
	return best

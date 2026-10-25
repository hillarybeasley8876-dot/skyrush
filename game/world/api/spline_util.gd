extends RefCounted
## Shared polyline maths: Catmull-Rom sampling (city.json "spline": "catmull" | "linear"),
## resampling to a fixed spacing, tangents and lateral offsets.

const DEFAULT_SPACING := 4.0


## Samples a Catmull-Rom spline through the control points (uniform, centripetal-free).
static func catmull_rom(points: PackedVector3Array, per_segment: int = 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	if points.size() < 2:
		return points
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		for s in per_segment:
			var t := float(s) / float(per_segment)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(points[points.size() - 1])
	return out


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Samples the centre-line of a road as the schema asks: catmull or linear.
static func sample_centerline(points: PackedVector3Array, spline: String) -> PackedVector3Array:
	if points.size() < 2:
		return points
	if spline == "linear":
		return _linear(points)
	return catmull_rom(points)


static func _linear(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(int(a.distance_to(b) / DEFAULT_SPACING), 1)
		for s in steps:
			out.append(a.lerp(b, float(s) / float(steps)))
	out.append(points[points.size() - 1])
	return out


## Resamples a polyline so that consecutive points are about `spacing` metres apart.
static func resample(points: PackedVector3Array, spacing: float = DEFAULT_SPACING) -> PackedVector3Array:
	var out := PackedVector3Array()
	if points.size() < 2:
		return points
	out.append(points[0])
	var carry := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir := (b - a) / seg
		var travelled := carry
		while travelled + spacing <= seg:
			travelled += spacing
			out.append(a + dir * travelled)
		carry = travelled - seg
	var last := points[points.size() - 1]
	if out[out.size() - 1].distance_to(last) > 0.01:
		out.append(last)
	return out


## Unit tangents (XZ only) for a polyline; degenerate segments inherit a neighbour's tangent.
static func tangents(points: PackedVector3Array) -> Array[Vector3]:
	var raw: Array[Vector3] = []
	for i in points.size():
		var dir := Vector3.ZERO
		if i < points.size() - 1:
			dir = points[i + 1] - points[i]
		elif i > 0:
			dir = points[i] - points[i - 1]
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = Vector3.ZERO
		raw.append(dir)
	for i in points.size():
		if raw[i] != Vector3.ZERO:
			continue
		var found := Vector3.ZERO
		for j in range(i + 1, points.size()):
			if raw[j] != Vector3.ZERO:
				found = raw[j]
				break
		if found == Vector3.ZERO:
			for j in range(i - 1, -1, -1):
				if raw[j] != Vector3.ZERO:
					found = raw[j]
					break
		raw[i] = found
	var out: Array[Vector3] = []
	for dir in raw:
		if dir == Vector3.ZERO:
			out.append(Vector3.FORWARD)
		else:
			out.append(dir.normalized())
	return out


## Left-hand normal (in XZ) of a tangent.
static func left_normal(tangent: Vector3) -> Vector3:
	return Vector3(-tangent.z, 0.0, tangent.x)


## Offsets a polyline sideways (positive = left of the driving direction).
static func offset_polyline(points: PackedVector3Array, offset: float) -> PackedVector3Array:
	var tans := tangents(points)
	var out := PackedVector3Array()
	for i in points.size():
		out.append(points[i] + left_normal(tans[i]) * offset)
	return out


## The centre line of a road of the city description.
static func road_line(road: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	var raw: Variant = road.get("points", [])
	if not raw is Array:
		return points
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			points.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return resample(sample_centerline(points, str(road.get("spline", "catmull"))), 4.0)


## Builds a Curve3D through the points (baked, so sample_baked works).
## The bake interval of the lanes of the city is 4 m: 508 km of lanes at 2 m would double the
## build time of the world for nothing.
static func make_curve(points: PackedVector3Array, bake_interval: float = 2.0,
		smooth: bool = false) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = bake_interval
	# The up vector of a curve is only needed by a track; Godot computes it with a rotation
	# around an axis that is not normalized on a sharp turn, and the engine complains.
	curve.set_up_vector_enabled(false)
	var count := points.size()
	for i in count:
		if not smooth or count < 3:
			curve.add_point(points[i])
			continue
		# A smooth curve passes the points with the tangents of a Catmull-Rom spline (its
		# Bezier handles are a sixth of the chord around the point): the heading turns
		# gradually instead of at every point.
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, count - 1)]
		var handle := (after - before) / 6.0
		if i == 0 or i == count - 1:
			handle *= 2.0
		curve.add_point(points[i], -handle if i > 0 else Vector3.ZERO,
				handle if i < count - 1 else Vector3.ZERO)
	return curve


## The point at `distance` metres along a polyline.
static func point_at(points: PackedVector3Array, distance: float) -> Vector3:
	var travelled := 0.0
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if seg < 0.0001:
			continue
		if travelled + seg >= distance:
			return points[i].lerp(points[i + 1], (distance - travelled) / seg)
		travelled += seg
	return points[points.size() - 1]


## The index of the polyline segment that contains `distance`.
static func index_at(points: PackedVector3Array, distance: float) -> int:
	var travelled := 0.0
	for i in points.size() - 1:
		travelled += points[i].distance_to(points[i + 1])
		if travelled >= distance:
			return i
	return maxi(points.size() - 2, 0)


## The unit tangent (XZ) at `distance` metres along a polyline.
static func tangent_at(points: PackedVector3Array, distance: float) -> Vector3:
	var index := index_at(points, distance)
	var tangent := Vector3.FORWARD
	if index < points.size() - 1:
		tangent = points[index + 1] - points[index]
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD
	return tangent.normalized()


static func total_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total

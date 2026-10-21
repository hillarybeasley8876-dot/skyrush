extends RefCounted
## The water of the city: the polygons of the rivers and of the harbour, and the points on the
## surface of the water. The quality test casts rays into the water to find out that the
## ground of the world does not lie over the river.

const CityData := preload("res://world/loader/city_data.gd")

## The polygons of the water bodies.
var polygons: Array[PackedVector2Array] = []


## Reads the water bodies of the city description.
func setup(data: CityData) -> void:
	polygons.clear()
	for body in data.water():
		var polygon := to_polygon(body.get("polygon", []))
		if polygon.size() < 3 and body.has("centerline"):
			polygon = strip(to_polygon(body.get("centerline", [])), float(body.get("width", 70.0)))
		if polygon.size() >= 3:
			polygons.append(polygon)


## True when the point is inside one of the water bodies.
func is_water(point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


## True when the point is close to one of the water bodies.
func near_water(point: Vector2, distance: float) -> bool:
	for polygon in polygons:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if distance_to_segment(point, a, b) <= distance:
				return true
	return false


## Points on the surface of the water (taken from the water meshes).
func water_points(world: WorldBase) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node in world.find_children("Water_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# The centroids of the triangles: they are inside the water, not on its edge.
			for v in range(0, vertices.size() - 2, 3):
				out.append((vertices[v] + vertices[v + 1] + vertices[v + 2]) / 3.0)
	return out


## A strip of the given width around a centre line (the creeks).
static func strip(line: PackedVector2Array, width: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line.size() < 2:
		return out
	var half := width * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in line.size():
		var dir := Vector2.RIGHT
		if i < line.size() - 1:
			dir = (line[i + 1] - line[i]).normalized()
		elif i > 0:
			dir = (line[i] - line[i - 1]).normalized()
		var n := Vector2(-dir.y, dir.x) * half
		left.append(line[i] + n)
		right.append(line[i] - n)
	out.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		out.append(right[i])
	return out


## The points of a water body as a polygon.
static func to_polygon(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


## The distance from a point to a segment.
static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)

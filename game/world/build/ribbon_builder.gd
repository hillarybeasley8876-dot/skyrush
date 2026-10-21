extends RefCounted
## Quad-strip meshing helpers used by the road, block and water builders.
## Offsets are lateral, measured from the centre line: `left` is to the left of the travel
## direction, `right` to the right (both in metres, always positive).

const Spline := preload("res://world/api/spline_util.gd")


## A flat ribbon following a polyline: spans +left .. -right laterally.
## The ribbon gets UVs: u = metres along the ribbon / uv_length, v = 0..1 across the width
## (the soffit shader needs that to place its LED strips on the deck edges).
static func strip(points: PackedVector3Array, left: float, right: float, dy: float = 0.0,
		flip: bool = false, uv_length: float = 10.0) -> ArrayMesh:
	var tans := Spline.tangents(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var travelled := 0.0
	for i in points.size() - 1:
		var n := Spline.left_normal(tans[i])
		var a := points[i] + n * left + Vector3.UP * dy
		var b := points[i] - n * right + Vector3.UP * dy
		var c := points[i + 1] - n * right + Vector3.UP * dy
		var d := points[i + 1] + n * left + Vector3.UP * dy
		var u0 := travelled / uv_length
		var u1 := (travelled + points[i].distance_to(points[i + 1])) / uv_length
		var va := Vector2(u0, 0.0)
		var vb := Vector2(u0, 1.0)
		var vc := Vector2(u1, 1.0)
		var vd := Vector2(u1, 0.0)
		if flip:
			_face_uv(st, a, va, d, vd, c, vc, b, vb)
		else:
			_face_uv(st, a, va, b, vb, c, vc, d, vd)
		travelled += points[i].distance_to(points[i + 1])
	return _finish(st)


static func _face_uv(st: SurfaceTool, a: Vector3, ua: Vector2, b: Vector3, ub: Vector2,
		c: Vector3, uc: Vector2, d: Vector3, ud: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_uv(ud)
	st.add_vertex(d)


## A vertical wall along one side of a polyline. Heights are relative to the polyline's own
## height, so a wall on an elevated deck follows the deck.
static func wall(points: PackedVector3Array, offset: float, is_left: bool,
		y_bottom: float, y_top: float) -> ArrayMesh:
	var tans := Spline.tangents(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var n := Spline.left_normal(tans[i]) * (1.0 if is_left else -1.0)
		var a := points[i] + n * offset
		var b := points[i + 1] + n * offset
		var ab := Vector3(a.x, a.y + y_bottom, a.z)
		var bb := Vector3(b.x, b.y + y_bottom, b.z)
		var at := Vector3(a.x, a.y + y_top, a.z)
		var bt := Vector3(b.x, b.y + y_top, b.z)
		if is_left:
			_face(st, ab, bb, bt, at)
		else:
			_face(st, at, bt, bb, ab)
	return _finish(st)


## A ribbon with a flat top and a flat bottom (a deck slab).
static func slab(points: PackedVector3Array, left: float, right: float, thickness: float) -> ArrayMesh:
	var tans := Spline.tangents(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var n := Spline.left_normal(tans[i])
		var a := points[i] + n * left
		var b := points[i] - n * right
		var c := points[i + 1] - n * right
		var d := points[i + 1] + n * left
		_face(st, a, b, c, d)
		var a2 := a - Vector3.UP * thickness
		var b2 := b - Vector3.UP * thickness
		var c2 := c - Vector3.UP * thickness
		var d2 := d - Vector3.UP * thickness
		_face(st, d2, c2, b2, a2)
		_face(st, a, d, d2, a2)
		_face(st, c, b, b2, c2)
	return _finish(st)


## A closed extruded prism from a 2D polygon (used for blocks and islands).
static func prism(poly: PackedVector2Array, y_bottom: float, y_top: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(poly)
	for i in indices:
		var p := poly[i]
		st.add_vertex(Vector3(p.x, y_top, p.y))
	for i in indices:
		var p2 := poly[i]
		st.add_vertex(Vector3(p2.x, y_bottom, p2.y))
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		_face(st, Vector3(a.x, y_bottom, a.y), Vector3(b.x, y_bottom, b.y),
			Vector3(b.x, y_top, b.y), Vector3(a.x, y_top, a.y))
	return _finish(st)


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()
## Collision faces for a ribbon: two triangles per segment.
static func strip_faces(points: PackedVector3Array, left: float, right: float,
		dy: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var tans := Spline.tangents(points)
	for i in points.size() - 1:
		var n := Spline.left_normal(tans[i])
		var a := points[i] + n * left + Vector3.UP * dy
		var b := points[i] - n * right + Vector3.UP * dy
		var c := points[i + 1] - n * right + Vector3.UP * dy
		var d := points[i + 1] + n * left + Vector3.UP * dy
		out.append(a)
		out.append(b)
		out.append(c)
		out.append(a)
		out.append(c)
		out.append(d)
	return out

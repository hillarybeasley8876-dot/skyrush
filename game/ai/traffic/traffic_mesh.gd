class_name TrafficMesh
extends RefCounted
## Procedural car bodies for the AI traffic.
##
## The npc_cars unit owns the real models (`res://assets/cars/npc/*.glb`); until those land, and as a
## fallback for models that never get one, the traffic builds its cars from these primitives.
## Every surface is UV mapped in metres so the shared car-paint shader keeps a constant texel
## density, and no surface is left untextured.

## Builds a box that tapers from `bottom` (x, z half extents) to `top`, `height` tall, with its
## base at `y_offset`. `top_shift` moves the top rectangle sideways, which is how the raked
## windscreen and the tapered cabin of a car are made. UVs are in metres.
static func tapered_box(bottom: Vector2, top: Vector2, height: float, y_offset: float = 0.0,
		top_shift: Vector2 = Vector2.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b: Array[Vector3] = [
		Vector3(-bottom.x, y_offset, -bottom.y), Vector3(bottom.x, y_offset, -bottom.y),
		Vector3(bottom.x, y_offset, bottom.y), Vector3(-bottom.x, y_offset, bottom.y),
	]
	var t: Array[Vector3] = [
		Vector3(-top.x + top_shift.x, y_offset + height, -top.y + top_shift.y),
		Vector3(top.x + top_shift.x, y_offset + height, -top.y + top_shift.y),
		Vector3(top.x + top_shift.x, y_offset + height, top.y + top_shift.y),
		Vector3(-top.x + top_shift.x, y_offset + height, top.y + top_shift.y),
	]
	for i in 4:
		var j := (i + 1) % 4
		var w := (b[j] - b[i]).length()
		var slope := ((t[i] - b[i]) + (t[j] - b[j])) * 0.5
		_face(st, b[i], b[j], t[j], t[i], Vector2(0.0, 0.0), Vector2(w, 0.0),
				Vector2(w, height), Vector2(0.0, height), slope.cross(b[j] - b[i]))
	_face(st, t[0], t[1], t[2], t[3], Vector2(-top.x, -top.y), Vector2(top.x, -top.y),
			Vector2(top.x, top.y), Vector2(-top.x, top.y), Vector3.UP)
	_face(st, b[0], b[3], b[2], b[1], Vector2(-bottom.x, -bottom.y), Vector2(-bottom.x, bottom.y),
			Vector2(bottom.x, bottom.y), Vector2(bottom.x, -bottom.y), Vector3.DOWN)
	return st.commit()


## A flat quad in the XY plane, facing -Z, with UVs in metres. `size` is the full width/height.
static func quad(size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	_face(st, Vector3(-h.x, -h.y, 0.0), Vector3(h.x, -h.y, 0.0), Vector3(h.x, h.y, 0.0),
			Vector3(-h.x, h.y, 0.0), Vector2(0.0, 0.0), Vector2(size.x, 0.0),
			Vector2(size.x, size.y), Vector2(0.0, size.y), Vector3.BACK)
	return st.commit()


## A wheel: a rubber tyre (axis along X) with a hub cap.
static func wheel(radius: float, width: float) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var tyre := CylinderMesh.new()
	tyre.top_radius = radius
	tyre.bottom_radius = radius
	tyre.height = width
	tyre.radial_segments = 14
	tyre.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = tyre
	mi.rotation.z = PI * 0.5
	root.add_child(mi)
	return root


## Emits one quad: four corners, four UVs, one normal. Godot's front face is clockwise seen from
## the front, so the corner order below matches the outward normal.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, normal: Vector3) -> void:
	var n := normal
	if n.length_squared() < 0.0001:
		n = (a - b).cross(c - b)
	st.set_normal(n.normalized())
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.add_vertex(c)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_uv(uvc)
	st.add_vertex(c)
	st.set_uv(uvd)
	st.add_vertex(d)

extends RefCounted
## The ground of the city: one merged mesh of land cells with the water areas cut out of it, and
## the same triangles as the collision (the old single box was an invisible floor over the river).
## The cells that touch a water body are cut with a fine grid, so the ground meets the bank.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")

## The size of the coarse cells and of the fine cells near the water.
const CELL := 100.0
const FINE_CELL := 5.0
## A cell this far from the water is land without any test.
const WATER_MARGIN := 60.0
## The world tiling of the ground material (metres per texture repeat).
const GROUND_UV := 1.0 / 12.0
const GROUND_Y := -0.02


## Builds the ground mesh and its collision under `parent`.
func build(parent: Node3D, window: Rect2, water_polys: Array[PackedVector2Array]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := window.position.x
	var z0 := window.position.y
	var cols := int(ceil(window.size.x / CELL))
	var rows := int(ceil(window.size.y / CELL))
	for cx in cols:
		for cz in rows:
			var x := x0 + float(cx) * CELL
			var z := z0 + float(cz) * CELL
			var corners := [
				Vector2(x, z), Vector2(x + CELL, z),
				Vector2(x + CELL, z + CELL), Vector2(x, z + CELL),
			]
			if _far_from_water(corners, water_polys):
				_quad(st, corners[0], corners[1], corners[2], corners[3])
				continue
			_add_fine(st, corners, water_polys)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = _ground_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_add_collision(parent, mesh)


## The ground material: the wet asphalt shader of the road, dark and tiled so the ground is not
## a flat pale plane (ART.md §11: the albedo of a hard surface is at most #2A2A2E; the shader
## adds the world-space macro variation and the wet roughness).
static func _ground_material() -> Material:
	var source := load("res://shaders/materials/SH_wet_asphalt.tres") as ShaderMaterial
	if source == null:
		return ProcMeshes.material("ground")
	var mat := source.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"tile_m", 6.0)
	mat.set_shader_parameter(&"macro_m", 37.0)
	mat.set_shader_parameter(&"macro_strength", 0.5)
	mat.set_shader_parameter(&"tint", Color(0.80, 0.84, 0.92))
	# The lots are #1F1F22: dark enough to carry the lamps, light enough to keep the grain of
	# the asphalt and the puddles (ART.md §2: never pure #000, keep the detail in the darks).
	mat.set_shader_parameter(&"albedo_mul", 0.35)
	return mat


## The same triangles as the collision, so the car drives on exactly what is drawn.
func _add_collision(parent: Node3D, mesh: ArrayMesh) -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(_faces(mesh))
	shape.shape = concave
	body.add_child(shape)
	parent.add_child(body)


## The vertices of the mesh as collision faces (three per triangle).
static func _faces(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh.get_surface_count() == 0:
		return out
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(0, vertices.size() - 2, 3):
		out.append(vertices[i])
		out.append(vertices[i + 1])
		out.append(vertices[i + 2])
	return out


## Cuts a cell that touches the water into fine cells: the land cells are kept, the water cells are dropped, and a cell that the
## edge of the water crosses is clipped to the edge. The crossed cells used to be dropped: the ground stopped up to 7 m short of
## the bank, and nothing was under that strip (the water starts at the bank): a car that came off the road there fell to the kill
## floor (the shore ring only looks like water).
func _add_fine(st: SurfaceTool, corners: Array, water_polys: Array[PackedVector2Array]) -> void:
	var steps := int(CELL / FINE_CELL)
	var origin: Vector2 = corners[0]
	for i in steps:
		for j in steps:
			var a := origin + Vector2(float(i) * FINE_CELL, float(j) * FINE_CELL)
			var b := a + Vector2(FINE_CELL, 0.0)
			var c := a + Vector2(FINE_CELL, FINE_CELL)
			var d := a + Vector2(0.0, FINE_CELL)
			if _cut_by_water(a, b, c, d, water_polys):
				_add_clipped(st, PackedVector2Array([a, b, c, d]), water_polys)
				continue
			if _in_water((a + c) * 0.5, water_polys):
				continue
			_quad(st, a, b, c, d)


## The land part of a cell that the edge of the water crosses: the cell less every water body, in triangles.
func _add_clipped(st: SurfaceTool, cell: PackedVector2Array, water_polys: Array[PackedVector2Array]) -> void:
	var pieces: Array[PackedVector2Array] = [cell]
	var outer_clockwise := Geometry2D.is_polygon_clockwise(cell)
	for poly in water_polys:
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			for part in Geometry2D.clip_polygons(piece, poly):
				# a hole (a water body inside the cell) turns the other way: the outline is kept, the hole is not cut
				if Geometry2D.is_polygon_clockwise(part) == outer_clockwise:
					next.append(part)
		pieces = next
	for piece in pieces:
		var indices := Geometry2D.triangulate_polygon(piece)
		for t in range(0, indices.size() - 2, 3):
			var p0 := piece[indices[t]]
			var p1 := piece[indices[t + 1]]
			var p2 := piece[indices[t + 2]]
			# the face points up when the corners turn the way of a quad of the ground (a, b, c)
			if (p1 - p0).cross(p2 - p0) < 0.0:
				var swap := p1
				p1 = p2
				p2 = swap
			_vertex(st, p0)
			_vertex(st, p1)
			_vertex(st, p2)


## True when the edge of a water body crosses the cell.
func _cut_by_water(a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		water_polys: Array[PackedVector2Array]) -> bool:
	for poly in water_polys:
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			if Geometry2D.segment_intersects_segment(p, q, a, b) != null:
				return true
			if Geometry2D.segment_intersects_segment(p, q, b, c) != null:
				return true
			if Geometry2D.segment_intersects_segment(p, q, c, d) != null:
				return true
			if Geometry2D.segment_intersects_segment(p, q, d, a) != null:
				return true
	return false


## True when the cell is further than the margin from every water body.
func _far_from_water(corners: Array, water_polys: Array[PackedVector2Array]) -> bool:
	for poly in water_polys:
		for corner in corners:
			var point: Vector2 = corner
			if _distance_to_polygon(point, poly) <= WATER_MARGIN:
				return false
	return true


## True when the point is inside a water body.
func _in_water(point: Vector2, water_polys: Array[PackedVector2Array]) -> bool:
	for poly in water_polys:
		if Geometry2D.is_point_in_polygon(point, poly):
			return true
	return false


## The distance from a point to the edge of a polygon (0 inside).
static func _distance_to_polygon(point: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, _distance_to_segment(point, a, b))
	return best


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## One quad of the ground, with the world UVs.
static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	_vertex(st, a)
	_vertex(st, b)
	_vertex(st, c)
	_vertex(st, a)
	_vertex(st, c)
	_vertex(st, d)


static func _vertex(st: SurfaceTool, point: Vector2) -> void:
	st.set_uv(point * GROUND_UV)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(point.x, GROUND_Y, point.y))

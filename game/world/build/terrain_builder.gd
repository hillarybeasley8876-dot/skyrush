extends RefCounted
## The water of the city (the Huangpu and the Suzhou Creek), the bank walls and the kill floor.
## The ground (with the water cut out of it) is built by the ground builder.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Ribbon := preload("res://world/build/ribbon_builder.gd")

const WATER_Y := -3.0
const KILL_Y := -60.0
const BANK_TOP := 0.6
## The shore ring fills the gap between the cut ground and the water.
const SHORE_WIDTH := 8.0


var _water_polys: Array[PackedVector2Array] = []


## Parses the city.json water specs into polygons: {"poly", "y", "bank", "creek", "id"}.
func parse_water(specs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in specs:
		if not spec is Dictionary:
			continue
		var d := spec as Dictionary
		var y := float(d.get("y", WATER_Y))
		if d.has("polygon"):
			var pts := _to_vector2_array(d.get("polygon", []))
			if pts.size() >= 3:
				out.append({"poly": pts, "y": y, "bank": str(d.get("bank", "wall")),
					"creek": false, "id": str(d.get("id", "water"))})
				_water_polys.append(pts)
		elif d.has("centerline"):
			var line := _to_vector2_array(d.get("centerline", []))
			var width := float(d.get("width", 70.0))
			if line.size() >= 2:
				var pts := _strip(line, width)
				out.append({"poly": pts, "y": y, "bank": str(d.get("bank", "slope")),
					"creek": true, "line": line, "width": width, "id": str(d.get("id", "creek"))})
				_water_polys.append(pts)
	return out


## The water polygons (the ground builder cuts them out of the land).
func water_polygons() -> Array[PackedVector2Array]:
	return _water_polys


func build_water(parent: Node3D, bodies: Array[Dictionary]) -> void:
	for body in bodies:
		if bool(body.get("creek", false)):
			_build_creek(parent, body)
			continue
		_build_polygon(parent, body)


## A closed water body: the surface, the collision and the bank walls.
func _build_polygon(parent: Node3D, body: Dictionary) -> void:
	var poly: PackedVector2Array = body["poly"]
	var y: float = body["y"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in Geometry2D.triangulate_polygon(poly):
		var p := poly[i]
		st.add_vertex(Vector3(p.x, y, p.y))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Water_" + str(body.get("id", "water"))
	mi.mesh = mesh
	mi.material_override = ProcMeshes.material("water")
	parent.add_child(mi)
	var body_node := StaticBody3D.new()
	body_node.name = "WaterBody_" + str(body.get("id", "water"))
	body_node.collision_layer = 1
	var cshape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(_triangles(poly, y))
	cshape.shape = concave
	body_node.add_child(cshape)
	parent.add_child(body_node)
	_build_shore(parent, poly, y, str(body.get("id", "water")))
	if str(body.get("bank", "wall")) != "slope":
		_build_banks(parent, poly, y, str(body.get("id", "water")))


## A creek is a strip along its centre line: a quad ribbon instead of a triangulated polygon.
func _build_creek(parent: Node3D, body: Dictionary) -> void:
	var line2: PackedVector2Array = body["line"]
	var width := float(body.get("width", 70.0))
	var y := float(body.get("y", WATER_Y))
	var points := PackedVector3Array()
	for p in line2:
		points.append(Vector3(p.x, y, p.y))
	var half := width * 0.5
	var mi := MeshInstance3D.new()
	mi.name = "Water_" + str(body.get("id", "creek"))
	mi.mesh = Ribbon.strip(points, half, half)
	mi.material_override = ProcMeshes.material("water")
	parent.add_child(mi)
	var body_node := StaticBody3D.new()
	body_node.name = "WaterBody_" + str(body.get("id", "creek"))
	body_node.collision_layer = 1
	var cshape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(Ribbon.strip_faces(points, half, half))
	cshape.shape = concave
	body_node.add_child(cshape)
	parent.add_child(body_node)
	if str(body.get("bank", "slope")) != "slope":
		for side in [true, false]:
			var wall := MeshInstance3D.new()
			wall.name = "BankWalls_" + str(body.get("id", "creek")) + ("_l" if side else "_r")
			wall.mesh = Ribbon.wall(points, half, side, 0.0, BANK_TOP - y)
			wall.material_override = load("res://shaders/materials/SH_concrete_pier.tres")
			parent.add_child(wall)


## The shore ring: the water reaches under the cut ground, so no hole shows at the bank.
func _build_shore(parent: Node3D, poly: PackedVector2Array, y: float, id: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sign := _signed_area(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var edge := b - a
		if edge.length_squared() < 0.0001:
			continue
		var normal := Vector2(edge.y, -edge.x).normalized() * sign
		var a2 := a + normal * SHORE_WIDTH
		var b2 := b + normal * SHORE_WIDTH
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y, a.y))
		st.add_vertex(Vector3(b.x, y, b.y))
		st.add_vertex(Vector3(b2.x, y, b2.y))
		st.add_vertex(Vector3(a.x, y, a.y))
		st.add_vertex(Vector3(b2.x, y, b2.y))
		st.add_vertex(Vector3(a2.x, y, a2.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Shore_" + id
	mi.mesh = st.commit()
	mi.material_override = ProcMeshes.material("water")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The vertical bank walls (the flood wall of the Bund).
func _build_banks(parent: Node3D, poly: PackedVector2Array, y: float, id: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		_quad(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
			Vector3(b.x, BANK_TOP, b.y), Vector3(a.x, BANK_TOP, a.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "BankWalls_" + id
	mi.mesh = st.commit()
	mi.material_override = load("res://shaders/materials/SH_concrete_pier.tres")
	parent.add_child(mi)


## The ground of the city goes on for EDGE_RING metres past the window, and the walls stand at the end of it. Before, the
## ground ended at the window and a car that drove off the end of a road at the edge fell 60 m to the kill floor (9 drives of 60
## in the fuzz drive), was wrecked there, and the police cars that followed it fell as well.
const EDGE_RING := 100.0
## The walls at the edge: thick (a car at 250 km/h moves 0.6 m a tick), from under the kill floor to far above the highest
## viaduct and sky lane, and slippery (the car slides along them, it does not stick).
const EDGE_WALL_THICKNESS := 10.0
const EDGE_WALL_BOTTOM := -80.0
const EDGE_WALL_TOP := 400.0
const EDGE_WALL_FRICTION := 0.05


## The invisible walls around `area` (the ground of the city and its ring): four boxes outside the border, whose inner faces are
## on the border.
func build_edge_walls(parent: Node3D, area: Rect2) -> void:
	var body := StaticBody3D.new()
	body.name = "EdgeWalls"
	body.collision_layer = 1
	body.collision_mask = 0
	var material := PhysicsMaterial.new()
	material.friction = EDGE_WALL_FRICTION
	material.bounce = 0.0
	body.physics_material_override = material
	var height := EDGE_WALL_TOP - EDGE_WALL_BOTTOM
	var middle := (EDGE_WALL_TOP + EDGE_WALL_BOTTOM) * 0.5
	var long_x := area.size.x + 2.0 * EDGE_WALL_THICKNESS
	var long_z := area.size.y + 2.0 * EDGE_WALL_THICKNESS
	var centre := area.get_center()
	var half := EDGE_WALL_THICKNESS * 0.5
	# west, east, north, south: {size, centre}
	var walls: Array[Array] = [
		[Vector3(EDGE_WALL_THICKNESS, height, long_z), Vector3(area.position.x - half, middle, centre.y)],
		[Vector3(EDGE_WALL_THICKNESS, height, long_z), Vector3(area.end.x + half, middle, centre.y)],
		[Vector3(long_x, height, EDGE_WALL_THICKNESS), Vector3(centre.x, middle, area.position.y - half)],
		[Vector3(long_x, height, EDGE_WALL_THICKNESS), Vector3(centre.x, middle, area.end.y + half)],
	]
	for wall in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[0]
		shape.shape = box
		shape.position = wall[1]
		body.add_child(shape)
	parent.add_child(body)


func build_kill_floor(parent: Node3D, window: Rect2) -> void:
	var mesh := ProcMeshes.box(Vector3(window.size.x + 400.0, 4.0, window.size.y + 400.0))
	var mi := MeshInstance3D.new()
	mi.name = "KillFloor"
	mi.mesh = mesh
	mi.position = Vector3(window.position.x + window.size.x * 0.5, KILL_Y,
		window.position.y + window.size.y * 0.5)
	mi.material_override = ProcMeshes.material("concrete")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "KillFloorBody"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(window.size.x + 400.0, 4.0, window.size.y + 400.0)
	shape.shape = box
	shape.position = mi.position
	body.add_child(shape)
	parent.add_child(body)


# --- helpers ---------------------------------------------------------------------------------------

## The signed area of a polygon (positive when it is counter-clockwise).
static func _signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return signf(area)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _triangles(poly: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in Geometry2D.triangulate_polygon(poly):
		var p := poly[i]
		out.append(Vector3(p.x, y, p.y))
	return out


static func _to_vector2_array(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


## Builds a closed strip polygon of the given width around a centre line.
static func _strip(line: PackedVector2Array, width: float) -> PackedVector2Array:
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
	var out := PackedVector2Array()
	out.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		out.append(right[i])
	return out

extends RefCounted
## The water of the city (the Huangpu and the Suzhou Creek), the bank walls and the kill floor.
## The ground (with the water cut out of it) is built by the ground builder.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Ribbon := preload("res://world/build/ribbon_builder.gd")
const Spline := preload("res://world/api/spline_util.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")

const WATER_Y := -3.0
const KILL_Y := -60.0
## The top of the bank walls over the road level. The walls were drawn 0.6 m high and had no collision at all: a car that left the
## road at a bank drove through the drawn wall, fell 3.6 m onto the water (a solid floor) and drove on the river, or fell through
## the holes of the floor of the creek at its bends to the kill floor (tools/fuzz_drive.gd). A wall of 0.6 m is climbed by a car
## at speed (the parapets of the decks went to 1.0 m for that), so the flood wall is 1.0 m.
const BANK_TOP := 1.0
## The bank wall is built of pieces of this length (m), so a piece can be left out where a road crosses the bank.
const BANK_PIECE := 4.0
## The thickness of the collision of a bank wall (m): a box on the water side of the bank line, thick enough that a car at 250 km/h
## (0.6 m a tick) does not pass through it in one tick.
const BANK_THICKNESS := 1.0
## A piece of the wall is left out when a lane crosses the bank (more than 30 degrees to it) within this distance (m) of the piece
## (the lanes of a bridge of the creek, and the road beside them), or runs along the bank closer than BANK_ALONG_CLEAR (a wall in
## the lane).
const BANK_CROSS_CLEAR := 6.0
const BANK_CROSS_COS := 0.866
const BANK_ALONG_CLEAR := 2.6
## The lanes that cut the wall are at the height of the road: a lane on a deck higher than this over the road level, or in a
## tunnel under the water, passes the bank without touching the wall.
const BANK_LANE_ABOVE := 4.0
## The shore ring fills the gap between the cut ground and the water.
const SHORE_WIDTH := 8.0


var _water_polys: Array[PackedVector2Array] = []
## The bank lines of the water: {"points": PackedVector2Array, "closed": bool, "water": Array[Vector2] (the side of the water of
## every segment), "id": String}. The walls are built after the lanes (build_banks): a road that crosses the bank needs a gap.
var _bank_lines: Array[Dictionary] = []
## The number of wall pieces that were built and left out (the tests read them).
var bank_pieces := 0
var bank_gaps := 0


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
	body_node.add_to_group(&"water")
	parent.add_child(body_node)
	_build_shore(parent, poly, y, str(body.get("id", "water")))
	if str(body.get("bank", "wall")) != "slope":
		_add_polygon_bank(poly, str(body.get("id", "water")))


## A creek is a strip along its centre line. Its floor and its surface are the outline that is cut out of the ground (the strip
## polygon): a ribbon of quads, one per segment, left a wedge of 8 m without a floor on the outside of every bend and covered the
## ground on the inside (the ground and the floor were 15 m apart at a bend of 26 degrees), and a car fell through the wedges to
## the kill floor. The ribbon is only the fallback when the outline cannot be cut into triangles.
func _build_creek(parent: Node3D, body: Dictionary) -> void:
	var line2: PackedVector2Array = body["line"]
	var width := float(body.get("width", 70.0))
	var y := float(body.get("y", WATER_Y))
	var points := PackedVector3Array()
	for p in line2:
		points.append(Vector3(p.x, y, p.y))
	var half := width * 0.5
	var poly: PackedVector2Array = body["poly"]
	var faces := _triangles(poly, y)
	var mi := MeshInstance3D.new()
	mi.name = "Water_" + str(body.get("id", "creek"))
	if faces.is_empty():
		push_warning("terrain: the outline of %s has no triangles, the creek is a ribbon" % str(body.get("id", "creek")))
		mi.mesh = Ribbon.strip(points, half, half)
		faces = Ribbon.strip_faces(points, half, half)
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in faces:
			st.add_vertex(v)
		st.generate_normals()
		mi.mesh = st.commit()
	mi.material_override = ProcMeshes.material("water")
	parent.add_child(mi)
	var body_node := StaticBody3D.new()
	body_node.name = "WaterBody_" + str(body.get("id", "creek"))
	body_node.collision_layer = 1
	var cshape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	cshape.shape = concave
	body_node.add_child(cshape)
	body_node.add_to_group(&"water")
	parent.add_child(body_node)
	if str(body.get("bank", "slope")) != "slope":
		var ground := PackedVector3Array()
		for p in line2:
			ground.append(Vector3(p.x, 0.0, p.y))
		for side in [1.0, -1.0]:
			var edge := Spline.offset_polyline(ground, side * half)
			var line := PackedVector2Array()
			for p in edge:
				line.append(Vector2(p.x, p.z))
			# the water is on the side of the centre line: right of the left bank, left of the right bank
			_add_bank_line(line, false, -side, str(body.get("id", "creek")) + ("_l" if side > 0.0 else "_r"))


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


# --- the bank walls ------------------------------------------------------------------------------

## The bank of a closed water body is its outline (the water is inside it).
func _add_polygon_bank(poly: PackedVector2Array, id: String) -> void:
	# an outline with a positive area has the water on the left of its edges
	_add_bank_line(poly, true, _signed_area(poly), id)


## A bank line and the side of its water: `water_left` 1 = left of the direction of the line, -1 = right of it.
func _add_bank_line(points: PackedVector2Array, closed: bool, water_left: float, id: String) -> void:
	var water: Array[Vector2] = []
	var count := points.size() if closed else points.size() - 1
	for i in count:
		var dir := points[(i + 1) % points.size()] - points[i]
		if dir.length_squared() < 0.0001:
			water.append(Vector2.ZERO)
			continue
		dir = dir.normalized()
		# the left of a direction in the plan (x, z), as Spline.left_normal
		water.append(Vector2(-dir.y, dir.x) * water_left)
	_bank_lines.append({"points": points, "closed": closed, "water": water, "id": id})


## The bank walls: one mesh and one body of boxes per bank line, built of BANK_PIECE pieces, inside `area` (the ground of the
## city: the outline of the river goes on past it, where there is no ground and no car). A piece is left out where a lane crosses
## the bank at the height of the road, or runs along it closer than a car (lane_grid may be null: no gaps).
func build_banks(parent: Node3D, lane_grid: LaneSpatial, area: Rect2) -> void:
	bank_pieces = 0
	bank_gaps = 0
	var material := load("res://shaders/materials/SH_concrete_pier.tres") as Material
	for bank in _bank_lines:
		var points: PackedVector2Array = bank["points"]
		var water: Array[Vector2] = bank["water"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var body := StaticBody3D.new()
		body.name = "BankWallBody_" + String(bank["id"])
		body.collision_layer = 1
		body.collision_mask = 0
		var shapes: Array[BoxShape3D] = []
		var faces := 0
		for i in water.size():
			var to_water := water[i]
			if to_water == Vector2.ZERO:
				continue
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var count := maxi(int(ceil(a.distance_to(b) / BANK_PIECE)), 1)
			var run_start := -1
			for k in count + 1:
				var keep := false
				if k < count:
					var p0 := a.lerp(b, float(k) / float(count))
					var p1 := a.lerp(b, float(k + 1) / float(count))
					# past the ground of the city there is no wall (and no gap: there is no road either)
					var inside := area.has_point((p0 + p1) * 0.5)
					keep = inside and not _bank_cut(p0, p1, to_water, lane_grid)
					if keep:
						bank_pieces += 1
						shapes.append(_bank_box(body, p0, p1, to_water))
					elif inside:
						bank_gaps += 1
				if keep and run_start < 0:
					run_start = k
				elif not keep and run_start >= 0:
					# the end of a run of kept pieces: one face of wall for all of them
					_bank_faces(st, a.lerp(b, float(run_start) / float(count)), a.lerp(b, float(k) / float(count)), to_water)
					faces += 1
					run_start = -1
		body.set_meta(&"shapes", shapes)
		parent.add_child(body)
		if faces == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "BankWalls_" + String(bank["id"])
		mi.mesh = st.commit()
		mi.material_override = material
		parent.add_child(mi)


## True when a lane crosses the bank between p0 and p1 at the height of the road (or runs along it closer than a car), or when
## the other side of the bank is water as well (the outline of the river across the mouth of the creek).
func _bank_cut(p0: Vector2, p1: Vector2, to_water: Vector2, lane_grid: LaneSpatial) -> bool:
	var mid := (p0 + p1) * 0.5
	var land := mid - to_water * 1.5
	for poly in _water_polys:
		if Geometry2D.is_point_in_polygon(land, poly):
			return true
	if lane_grid == null:
		return false
	var along_bank := (p1 - p0).normalized()
	var half := p0.distance_to(p1) * 0.5
	var centre := Vector3(mid.x, 0.0, mid.y)
	var near := lane_grid.query_near(centre, BANK_CROSS_CLEAR + half)
	for lane_index in near["lanes"] as PackedInt32Array:
		var detail := lane_grid.detail(lane_index, centre)
		var point: Vector3 = detail["point"]
		if point.y < WATER_Y - 1.0 or point.y > BANK_TOP + BANK_LANE_ABOVE:
			continue
		var distance := float(detail["distance"])
		var tangent: Vector3 = detail["tangent"]
		var along := absf(Vector2(tangent.x, tangent.z).dot(along_bank))
		if along < BANK_CROSS_COS and distance < BANK_CROSS_CLEAR + half:
			return true
		if distance < BANK_ALONG_CLEAR + half:
			return true
	return false


## The box of one piece of wall: on the water side of the bank line, from the water to BANK_TOP.
func _bank_box(body: StaticBody3D, p0: Vector2, p1: Vector2, to_water: Vector2) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(p0.distance_to(p1) + 0.1, BANK_TOP - WATER_Y, BANK_THICKNESS)
	var shape := CollisionShape3D.new()
	shape.shape = box
	var mid := (p0 + p1) * 0.5 + to_water * (BANK_THICKNESS * 0.5)
	var along := (p1 - p0).normalized()
	var x := Vector3(along.x, 0.0, along.y)
	var z := Vector3(to_water.x, 0.0, to_water.y)
	shape.transform = Transform3D(Basis(x, Vector3.UP, z).orthonormalized(),
		Vector3(mid.x, (BANK_TOP + WATER_Y) * 0.5, mid.y))
	body.add_child(shape)
	return box


## The drawn wall of a run of pieces: the face to the land, the top and the face to the water.
func _bank_faces(st: SurfaceTool, p0: Vector2, p1: Vector2, to_water: Vector2) -> void:
	var land := Vector3(-to_water.x, 0.0, -to_water.y)
	var out := Vector3(to_water.x, 0.0, to_water.y) * BANK_THICKNESS
	var a := Vector3(p0.x, WATER_Y, p0.y)
	var b := Vector3(p1.x, WATER_Y, p1.y)
	var at := Vector3(p0.x, BANK_TOP, p0.y)
	var bt := Vector3(p1.x, BANK_TOP, p1.y)
	_quad_facing(st, a, b, bt, at, land)
	_quad_facing(st, at, bt, bt + out, at + out, Vector3.UP)
	_quad_facing(st, a + out, b + out, bt + out, at + out, -land)


## A quad that faces `normal`. Godot draws the side from which the corners turn clockwise, so the order is turned when it
## faces the other way.
static func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = d
		d = swap
	st.set_normal(normal)
	_quad(st, a, b, c, d)


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


## The triangles of a polygon at the height y, every one facing up (the corners turn like a quad of the ground: the water of
## the creek is drawn from these triangles, and a triangle that faced down was not drawn from above).
static func _triangles(poly: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var indices := Geometry2D.triangulate_polygon(poly)
	for t in range(0, indices.size() - 2, 3):
		var a := poly[indices[t]]
		var b := poly[indices[t + 1]]
		var c := poly[indices[t + 2]]
		if (b - a).cross(c - a) < 0.0:
			var swap := b
			b = c
			c = swap
		out.append(Vector3(a.x, y, a.y))
		out.append(Vector3(b.x, y, b.y))
		out.append(Vector3(c.x, y, c.y))
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

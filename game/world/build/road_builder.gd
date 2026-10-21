extends RefCounted
## Fallback road geometry built from city.json. Only used while the roads unit has not shipped
## res://assets/city/roads/roads_*.glb; the real tiles replace it as soon as they exist.
## Surfaces use the shared wet-asphalt shader, decks get a soffit wash and piers, medians and
## sidewalks are concrete.

const Spline := preload("res://world/api/spline_util.gd")
const Ribbon := preload("res://world/build/ribbon_builder.gd")
const ProcMeshes := preload("res://world/loader/proc_meshes.gd")

const DECK_THICKNESS := 0.9
const MEDIAN_BARRIER_H := 0.95
const ISLAND_H := 0.16
const SIDEWALK_H := 0.16


func build(parent: Node3D, roads: Array) -> void:
	for road in roads:
		if road is Dictionary:
			_build_road(parent, road as Dictionary)


func _build_road(parent: Node3D, road: Dictionary) -> void:
	var pts := _points(road)
	if pts.size() < 2:
		return
	var kind := str(road.get("kind", "surface"))
	var spline := str(road.get("spline", "catmull"))
	var line := Spline.resample(Spline.sample_centerline(pts, spline), 4.0)
	var w := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	var shoulder := float(road.get("shoulder", 0.5))
	var sidewalk := float(road.get("sidewalk", 0.0))
	var fwd := int(road.get("lanes_fwd", 2))
	var back := int(road.get("lanes_back", 2))
	var elevated := kind == "elevated" or kind == "bridge"
	var left_extent := median * 0.5 + float(back) * w + shoulder + sidewalk
	var right_extent := median * 0.5 + float(fwd) * w + shoulder + sidewalk
	var id := str(road.get("id", "road"))

	var root := Node3D.new()
	root.name = "Road_" + id
	parent.add_child(root)

	_surface(root, line, left_extent, right_extent)
	_collision(root, line, left_extent, right_extent)
	_markings(root, line, median, fwd, back, w)
	if elevated:
		_deck(root, line, left_extent, right_extent)
		_piers(root, line, left_extent, right_extent, float(road.get("pier_spacing", 30.0)))
	else:
		_sidewalks(root, line, left_extent, right_extent, sidewalk)
	_median(root, line, median, elevated)


func _surface(root: Node3D, line: PackedVector3Array, left: float, right: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = Ribbon.strip(line, left, right)
	mi.material_override = load("res://shaders/materials/SH_wet_asphalt.tres")
	root.add_child(mi)


func _collision(root: Node3D, line: PackedVector3Array, left: float, right: float) -> void:
	var body := StaticBody3D.new()
	body.name = "RoadBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(Ribbon.strip_faces(line, left, right))
	shape.shape = concave
	body.add_child(shape)
	root.add_child(body)


func _deck(root: Node3D, line: PackedVector3Array, left: float, right: float) -> void:
	var walls := MeshInstance3D.new()
	walls.name = "DeckWalls"
	walls.mesh = Ribbon.slab(line, left, right, DECK_THICKNESS)
	walls.material_override = ProcMeshes.material("concrete")
	root.add_child(walls)
	var soffit := MeshInstance3D.new()
	soffit.name = "Soffit"
	soffit.mesh = Ribbon.strip(line, left, right, -DECK_THICKNESS - 0.03, true)
	soffit.material_override = load("res://shaders/materials/SH_soffit_blue.tres")
	root.add_child(soffit)


func _piers(root: Node3D, line: PackedVector3Array, left: float, right: float,
		spacing: float) -> void:
	var mat := ProcMeshes.material("concrete")
	var mesh := ProcMeshes.box(Vector3(1.8, 1.0, 1.8))
	var tans := Spline.tangents(line)
	var travelled := spacing * 0.5
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		while travelled <= seg:
			var n := Spline.left_normal(tans[i])
			var p := a.lerp(b, travelled / seg)
			var top := p.y - DECK_THICKNESS
			if top > 1.0:
				var mi := MeshInstance3D.new()
				mi.name = "Pier"
				mi.mesh = mesh
				mi.material_override = mat
				mi.position = Vector3(p.x, top * 0.5, p.z)
				mi.scale.y = top
				root.add_child(mi)
			travelled += spacing
		travelled -= seg


func _sidewalks(root: Node3D, line: PackedVector3Array, left: float, right: float,
		width: float) -> void:
	if width <= 0.01:
		return
	var mat := ProcMeshes.material("concrete")
	for side in [-1.0, 1.0]:
		var extent := left if side > 0.0 else right
		var a := extent - width
		var b := extent
		if side < 0.0:
			a = -extent + width
			b = -extent
		var mi := MeshInstance3D.new()
		mi.name = "Sidewalk"
		mi.mesh = Ribbon.strip(line, b, -a, SIDEWALK_H)
		mi.material_override = mat
		root.add_child(mi)


## Lane markings: dashed white lines between the lanes, a solid edge line, and a double yellow
## centre line when the road has no physical median.
func _markings(root: Node3D, line: PackedVector3Array, median: float, fwd: int, back: int,
		lane_width: float) -> void:
	var length := Spline.total_length(line)
	var white := _marking_material("res://shaders/materials/SH_road_marking_white.tres")
	var yellow := _marking_material("res://shaders/materials/SH_road_marking_yellow.tres")
	if median <= 0.05:
		for side in [-1.0, 1.0]:
			_dashes(root, line, side * 0.22, 0.15, length, yellow, 0.0, 1.0)
	for k in fwd:
		var offset := median * 0.5 + float(k) * lane_width
		_dashes(root, line, -offset, 0.15, length, white, 0.02, 0.0)
	for k in back:
		var offset2 := median * 0.5 + float(k) * lane_width
		_dashes(root, line, offset2, 0.15, length, white, 0.02, 0.0)


## A dashed line at a lateral offset: `dash` metres of paint, `gap` metres of nothing.
## The shared marking material with the retro-reflection toned down, so the lines do not turn
## into a solid white band when the road is seen at a grazing angle.
func _marking_material(path: String) -> Material:
	var mat := load(path) as ShaderMaterial
	if mat == null:
		return ProcMeshes.material("concrete")
	var copy := mat.duplicate() as ShaderMaterial
	copy.set_shader_parameter(&"retro_strength", 0.10)
	return copy


func _dashes(root: Node3D, line: PackedVector3Array, offset: float, width: float,
		length: float, material: Material, dy: float, solid: float) -> void:
	var dash := 9.0
	var gap := 6.0
	if solid > 0.5:
		dash = length
		gap = 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := 0.0
	while d < length:
		var run := minf(dash, length - d)
		_dash_quad(st, line, d, d + run, offset, width, dy)
		d += dash + gap
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Marking"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _dash_quad(st: SurfaceTool, line: PackedVector3Array, from_d: float, to_d: float,
		offset: float, width: float, dy: float) -> void:
	var a := Spline.point_at(line, from_d)
	var b := Spline.point_at(line, to_d)
	var ta := Spline.tangent_at(line, from_d)
	var tb := Spline.tangent_at(line, to_d)
	var na := Spline.left_normal(ta) * offset
	var nb := Spline.left_normal(tb) * offset
	var half := width * 0.5
	var p0 := a + na - Spline.left_normal(ta) * half + Vector3.UP * dy
	var p1 := a + na + Spline.left_normal(ta) * half + Vector3.UP * dy
	var p2 := b + nb + Spline.left_normal(tb) * half + Vector3.UP * dy
	var p3 := b + nb - Spline.left_normal(tb) * half + Vector3.UP * dy
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)


func _median(root: Node3D, line: PackedVector3Array, median: float, elevated: bool) -> void:
	if median <= 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Median"
	if elevated:
		mi.mesh = Ribbon.strip(line, median * 0.5, median * 0.5, 0.0)
		var wall := MeshInstance3D.new()
		wall.name = "MedianWall"
		wall.mesh = Ribbon.wall(line, median * 0.5, true, 0.0, MEDIAN_BARRIER_H)
		wall.material_override = ProcMeshes.material("concrete")
		root.add_child(wall)
	else:
		mi.mesh = Ribbon.strip(line, median * 0.5, median * 0.5, ISLAND_H)
	mi.material_override = ProcMeshes.material("concrete")
	root.add_child(mi)


static func _points(road: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var raw: Variant = road.get("points", [])
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out

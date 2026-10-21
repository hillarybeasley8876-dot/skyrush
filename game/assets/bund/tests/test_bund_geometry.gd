extends Node
## Geometry test for the Bund assets (bund unit).
##
##   tools/godot.sh test res://assets/bund/tests/test_bund_geometry.gd
##
## Checks the landmarks the lead judges (the HSBC dome and its portico, the Customs
## House clock tower, the bronze bull of the Financial Plaza) and the orientation of the
## glass: a pane that faces into the building is culled and the opening shows the grey
## core of the mass behind it (review r3, MF2).

const BUILDINGS_GLB := "res://assets/bund/bund_buildings.glb"
const PROMENADE_GLB := "res://assets/bund/bund_promenade.glb"
const BULL_MIN_Y := 2.45
const BULL_MIN_TRIS := 3000
const PORTICO_COLUMNS := 6

var _fails := 0


func _ready() -> void:
	_check_landmarks()
	_check_bull()
	_check_glass_facing()
	if _fails == 0:
		print("PASS bund geometry")
	else:
		print("FAIL %d checks" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)


func _ok(msg: String) -> void:
	print("PASS ", msg)


func _check_landmarks() -> void:
	var packed: PackedScene = load(BUILDINGS_GLB)
	if packed == null:
		_fail("cannot load " + BUILDINGS_GLB)
		return
	var root: Node = packed.instantiate()
	# the revolved parts have to be present and closed
	for name in ["Bund_12_HSBC_dome", "Bund_2_ShanghaiClub_dome", "Bund_7_GreatNorthern_dome"]:
		var mesh := _find_mesh(root, name)
		if mesh == null:
			_fail("missing " + name)
			continue
		if mesh.mesh.get_faces().size() < 100:
			_fail("%s is empty" % name)
		else:
			_ok("%s is present (%d triangles)" % [name, mesh.mesh.get_faces().size() / 3])
	# the clock dials of the Customs House
	var dials := _find_mesh(root, "Bund_13_CustomsHouse_clock")
	if dials == null:
		_fail("missing Bund_13_CustomsHouse_clock")
	else:
		_ok("the Customs House carries %d clock triangles" % (dials.mesh.get_faces().size() / 3))
	# the HSBC portico: six columns, symmetric about the centre of the facade
	var bays: Array = _sidecar_portico("Bund_12_HSBC")
	if bays.size() != PORTICO_COLUMNS:
		_fail("the HSBC portico has %d columns, the dossier has 6" % bays.size())
	else:
		var symmetric := true
		for y in bays:
			var mirrored := false
			for other in bays:
				if absf(absf(float(y)) - absf(float(other))) < 0.05 \
						and signf(float(y)) != signf(float(other)):
					mirrored = true
			if not mirrored:
				symmetric = false
		if symmetric:
			_ok("the HSBC portico has 6 symmetric columns")
		else:
			_fail("the portico columns are not symmetric: %s" % str(bays))
	# the wash cards: one per building, and the crown shells
	var wash := 0
	var crown := 0
	for child in _all_nodes(root):
		var n := String(child.name)
		if n.ends_with("_wash"):
			wash += 1
		elif n.ends_with("_washcrown"):
			crown += 1
	if wash < 25:
		_fail("only %d facade wash cards" % wash)
	else:
		_ok("%d facade wash cards" % wash)
	if crown < 5:
		_fail("only %d crown wash shells" % crown)
	else:
		_ok("%d crown wash shells" % crown)
	root.free()


func _check_bull() -> void:
	"""The bronze bull of the Financial Plaza stands on the promenade deck."""
	var packed: PackedScene = load(PROMENADE_GLB)
	if packed == null:
		_fail("cannot load " + PROMENADE_GLB)
		return
	var root: Node = packed.instantiate()
	var bull := _find_mesh(root, "Bund_Promenade_bronze")
	if bull == null:
		_fail("the bull is missing from the promenade")
		root.free()
		return
	var box: AABB = bull.get_aabb()
	var tris := bull.mesh.get_faces().size() / 3
	if box.position.y < BULL_MIN_Y:
		_fail("the bull's base is at y %.2f, it has to stand on the deck (%.2f)"
				% [box.position.y, BULL_MIN_Y])
	else:
		_ok("the bull stands on the deck (y %.2f)" % box.position.y)
	if tris < BULL_MIN_TRIS:
		_fail("the bull has only %d triangles" % tris)
	else:
		_ok("the bull has %d triangles" % tris)
	if box.size.x < 3.0 or box.size.z < 1.0:
		_fail("the bull is only %.1f x %.1f m" % [box.size.x, box.size.z])
	else:
		_ok("the bull is %.1f x %.1f m" % [box.size.x, box.size.z])
	root.free()


func _check_glass_facing() -> void:
	"""Every pane of glass has to look out of its wall.

	The building's local frame: +X is the facade normal (towards the river), +Y runs
	along the row and +Z is up. A pane on the front has to look +X, one on the rear -X
	and one on a flank +Y or -Y."""
	var packed: PackedScene = load(BUILDINGS_GLB)
	if packed == null:
		_fail("cannot load " + BUILDINGS_GLB)
		return
	var root: Node = packed.instantiate()
	var inward := 0
	var checked := 0
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var node: Node3D = child
		# the rear wall is the westernmost geometry; the frontage is the width of the row
		var rear := 0.0
		var frontage := 0.0
		for sub in node.get_children():
			if sub is MeshInstance3D and (sub as MeshInstance3D).mesh != null:
				var box: AABB = (sub as MeshInstance3D).get_aabb()
				rear = minf(rear, box.position.x)
				frontage = maxf(frontage, box.size.z)
		for sub in node.get_children():
			if not (sub is MeshInstance3D):
				continue
			var mesh: MeshInstance3D = sub
			if mesh.mesh == null:
				continue
			for i in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(i)
				if mat == null or not String(mat.resource_name).contains("Window"):
					continue
				var arrays: Array = mesh.mesh.surface_get_arrays(i)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for t in range(0, index.size(), 3):
					var a: Vector3 = verts[index[t]]
					var n: Vector3 = norms[index[t]]
					if absf(n.y) > 0.5:
						continue
					var centre := a
					var want := Vector2.ZERO
					if centre.x > -1.0:
						want = Vector2(1.0, 0.0)
					elif centre.x < rear + 1.2:
						want = Vector2(-1.0, 0.0)
					elif absf(centre.z) > frontage * 0.5 - 1.5:
						want = Vector2(0.0, 1.0 if centre.z > 0.0 else -1.0)
					if want == Vector2.ZERO:
						continue
					checked += 1
					if n.x * want.x + n.z * want.y < 0.5:
						inward += 1
	if checked == 0:
		_fail("no glass panes were checked")
	elif inward > 0:
		_fail("%d of %d glass panes face into the building" % [inward, checked])
	else:
		_ok("all %d glass panes look out of the building" % checked)
	root.free()


func _sidecar_portico(building: String) -> Array:
	"""The column positions of a portico, from the light sidecar."""
	var file := FileAccess.open("res://assets/bund/bund_lights.json", FileAccess.READ)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var portico: Dictionary = data.get("portico", {})
	return portico.get(building, [])


func _count_columns(root: Node, building: String) -> int:
	"""The columns of the portico: the free-standing shafts in front of the facade.

	They are the only geometry of the building in front of x = 2.5 m, so their centres
	are clustered along the row: six clusters for the six columns of the HSBC."""
	var node := _find_node(root, building)
	if node == null:
		return 0
	var ys: Array[float] = []
	for sub in node.get_children():
		if not (sub is MeshInstance3D):
			continue
		var mesh: MeshInstance3D = sub
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			if mat == null or not String(mat.resource_name).contains("Stone"):
				continue
			for v in mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = v
				if p.x > 2.5 and p.y > 2.0 and p.y < 14.0:
					ys.append(p.z)
	ys.sort()
	var centres: Array[float] = []
	var last := -1000.0
	for y in ys:
		if y - last > 1.0:
			centres.append(y)
			last = y
	# the six columns stand single-double-double-single: the row is symmetric about
	# the centre of the facade
	var symmetric := true
	for c in centres:
		var found := false
		for other in centres:
			if absf(absf(c) - absf(other)) < 0.6 and signf(c) != signf(other):
				found = true
		if not found:
			symmetric = false
	return centres.size() if symmetric else 0


func _all_nodes(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_nodes(child))
	return out


func _find_node(node: Node, name: String) -> Node:
	for child in node.get_children():
		if String(child.name) == name:
			return child
		var sub := _find_node(child, name)
		if sub != null:
			return sub
	return null


func _find_mesh(node: Node, name: String) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).name == name:
			return child
		var sub := _find_mesh(child, name)
		if sub != null:
			return sub
	return null

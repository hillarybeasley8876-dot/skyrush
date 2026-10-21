extends Node
## Unit test for the Bund assets (bund unit).
##
##   tools/godot.sh test res://assets/bund/tests/test_bund.gd
##
## Checks the exported glb files: the 25 building nodes at the dossier's positions and
## heights, the colliders, the promenade on the correct (east) side of the road, the light
## sidecar, the materials (every mesh has one, the normal maps, the vertex colours, the
## additive wash) and the generated maps.
##
## The geometry of the landmarks and the orientation of the glass are checked by
## test_bund_geometry.gd.

const BUILDINGS_GLB := "res://assets/bund/bund_buildings.glb"
const PROMENADE_GLB := "res://assets/bund/bund_promenade.glb"
const LIGHTS_JSON := "res://assets/bund/bund_lights.json"
const TEXTURE_DIR := "res://assets/bund/textures"
const HEIGHT_TOLERANCE := 3.0
const TRIS_BUDGET := 1200000
const MIN_MAP_PX := 1024

# (node name, game z of the facade centre, height in m) - ref/shanghai dossier 5.3
const EXPECTED := [
	["Bund_1_Asia", -32.0, 31.0],
	["Bund_2_ShanghaiClub", -59.0, 30.0],
	["Bund_3_Union", -91.0, 30.0],
	["Bund_5_Nisshin", -120.0, 28.0],
	["Bund_6_CommBankChina", -140.0, 20.0],
	["Bund_7_GreatNorthern", -181.0, 22.0],
	["Bund_9_ChinaMerchants", -207.0, 20.0],
	["Bund_12_HSBC", -268.0, 50.0],
	["Bund_13_CustomsHouse", -328.0, 79.2],
	["Bund_14_BankComm", -366.0, 36.0],
	["Bund_15_RussoChinese", -418.0, 20.0],
	["Bund_16_BankTaiwan", -447.0, 22.0],
	["Bund_17_NorthChinaDaily", -465.0, 40.0],
	["Bund_18_Bund18", -488.0, 26.0],
	["Bund_19_PalaceHotel", -518.0, 30.0],
	["Bund_20_SassoonHouse", -569.0, 77.0],
	["Bund_23_BankOfChina", -600.0, 77.0],
	["Bund_24_YokohamaSpecie", -628.0, 30.0],
	["Bund_26_Yangtze", -655.0, 30.0],
	["Bund_27_Jardine", -683.0, 32.0],
	["Bund_28_GlenLine", -720.0, 27.5],
	["Bund_29_Indochine", -744.0, 18.0],
	["Bund_33_BritishConsulate", -808.0, 12.0],
	["Bund_32_Peninsula", -837.0, 60.0],
	["Bund_0_BroadwayMansions", -1051.0, 77.0],
]

var _fails := 0
var _missing_mat := 0
var _bad_name := 0
var _no_normal := 0
var _with_albedo := 0
var _no_vcol := 0
var _wash := 0
var _tris := 0


func _ready() -> void:
	_check_buildings()
	_check_promenade()
	_check_lights()
	_check_materials()
	_check_textures()
	if _fails == 0:
		print("PASS bund assets")
	else:
		print("FAIL %d checks" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)


func _ok(msg: String) -> void:
	print("PASS ", msg)


func _check_buildings() -> void:
	var packed: PackedScene = load(BUILDINGS_GLB)
	if packed == null:
		_fail("cannot load " + BUILDINGS_GLB)
		return
	var root: Node = packed.instantiate()
	var found := {}
	var colliders := 0
	for child in root.get_children():
		found[child.name] = child
		colliders += _count_colliders(child)
	for entry in EXPECTED:
		var node_name: String = entry[0]
		var want_z: float = entry[1]
		var want_h: float = entry[2]
		if not found.has(node_name):
			_fail("missing building node " + node_name)
			continue
		var node: Node3D = found[node_name]
		if absf(node.position.z - want_z) > 1.0:
			_fail("%s at z=%.1f, expected %.1f" % [node_name, node.position.z, want_z])
			continue
		var top := -1000.0
		for sub in node.get_children():
			if sub is MeshInstance3D:
				var mesh: MeshInstance3D = sub
				if mesh.mesh == null:
					continue
				var box: AABB = mesh.get_aabb()
				top = maxf(top, box.position.y + box.size.y)
		if absf(top - want_h) > HEIGHT_TOLERANCE:
			_fail("%s height %.1f, expected %.1f (+/-%.0f)" % [node_name, top, want_h, HEIGHT_TOLERANCE])
			continue
		_ok("%s at z=%.0f h=%.0f" % [node_name, node.position.z, top])
	if colliders < 25:
		_fail("only %d -convcolonly colliders" % colliders)
	else:
		_ok("%d building colliders" % colliders)
	root.free()


func _check_promenade() -> void:
	var packed: PackedScene = load(PROMENADE_GLB)
	if packed == null:
		_fail("cannot load " + PROMENADE_GLB)
		return
	var root: Node = packed.instantiate()
	var tris := 0
	var flood_z := Vector2.ZERO
	var meshes := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child
			meshes += 1
			if mesh.mesh == null:
				continue
			tris += mesh.mesh.get_faces().size() / 3
			if child.name == "Bund_Promenade_flood":
				var box := mesh.get_aabb()
				flood_z = Vector2(box.position.z, box.position.z + box.size.z)
	if meshes < 6:
		_fail("the promenade has only %d meshes" % meshes)
	else:
		_ok("promenade: %d meshes, %d tris" % [meshes, tris])
	# the flood wall must be EAST of the road: 49 m east of the centreline (dossier 5.2)
	# at z = -330 the centreline is at x -121.6, so the river face has to be at -73 +/- 1.5
	var face := _wall_x_at(root, -330.0)
	if absf(face + 73.0) > 1.5:
		_fail("the river face is at x %.1f at z -330, expected -73 +/- 1.5" % face)
	else:
		_ok("the river face is at x %.1f at z -330 (49 m east of the road)" % face)
	for check in [[-500.0, -94.0], [-350.0, -76.0], [-450.0, -87.0]]:
		var got := _wall_x_at(root, float(check[0]))
		if absf(got - float(check[1])) > 3.0:
			_fail("the river face is at x %.1f at z %.0f, expected %.0f" % [got, check[0], check[1]])
		else:
			_ok("the river face is at x %.1f at z %.0f" % [got, check[0]])
	if flood_z.x > -25.0 or flood_z.y < -960.0:
		_fail("the promenade covers z %.0f..%.0f, expected -25..-960" % [flood_z.x, flood_z.y])
	else:
		_ok("the promenade covers z %.0f..%.0f" % [flood_z.x, flood_z.y])
	root.free()


func _check_lights() -> void:
	var file := FileAccess.open(LIGHTS_JSON, FileAccess.READ)
	if file == null:
		_fail("cannot read " + LIGHTS_JSON)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		_fail("malformed " + LIGHTS_JSON)
		return
	var lights: Array = data.get("lights", [])
	if lights.size() < 100:
		_fail("only %d lights in the sidecar" % lights.size())
	else:
		_ok("%d lights in the sidecar" % lights.size())
	var uplights := 0
	var crowns := 0
	var buildings := {}
	for rec: Dictionary in lights:
		var pos: Array = rec["position"]
		var dir: Array = rec["direction"]
		if pos.size() != 3 or dir.size() != 3:
			_fail("malformed light record " + String(rec.get("name", "?")))
			continue
		var angle := float(rec.get("angle", 0.0))
		if angle <= 0.0 or angle > 60.0:
			_fail("light %s has a %d deg cone (art dossier 3.4: 40 deg)" % [rec["name"], angle])
		var energy := float(rec.get("energy", 0.0))
		if energy <= 0.0 or energy > 60.0:
			_fail("light %s has energy %.1f (art dossier 3.4: 25)" % [rec["name"], energy])
		var name := String(rec["name"])
		if name.begins_with("Uplight_"):
			uplights += 1
			var d := Vector3(dir[0], dir[1], dir[2])
			if d.length() < 0.5:
				_fail("light " + name + " has no direction")
			if d.y < 0.8:
				_fail("uplight " + name + " is not aimed up (dy=%.2f)" % d.y)
		elif name.begins_with("Crown_"):
			crowns += 1
			var b := String(rec.get("building", ""))
			buildings[b] = int(buildings.get(b, 0)) + 1
	if uplights < 100:
		_fail("only %d uplights" % uplights)
	else:
		_ok("%d uplights, all aimed up" % uplights)
	if crowns < 40:
		_fail("only %d crown floods" % crowns)
	else:
		_ok("%d crown floods" % crowns)
	var without := 0
	for b in buildings:
		if int(buildings[b]) < 2:
			without += 1
	if without > 0:
		_fail("%d buildings have fewer than 2 crown floods" % without)
	else:
		_ok("every lit building has at least 2 crown floods")
	var deck: Array = data.get("deck_lamps", [])
	if deck.size() < 20:
		_fail("only %d deck lanterns in the sidecar" % deck.size())
	else:
		_ok("%d deck lanterns in the sidecar" % deck.size())
	var road: Array = data.get("road", [])
	var river: Array = data.get("river", [])
	if road.size() < 5 or river.size() < 50:
		_fail("the sidecar has no road / river line (%d / %d points)" % [road.size(), river.size()])
	else:
		_ok("the sidecar carries the road (%d) and the river (%d) lines" % [road.size(), river.size()])


func _check_materials() -> void:
	var total_tris := 0
	for path in [BUILDINGS_GLB, PROMENADE_GLB]:
		_reset_counters()
		var packed: PackedScene = load(path)
		if packed == null:
			_fail("cannot load " + path)
			continue
		var root: Node = packed.instantiate()
		for child in root.get_children():
			if not _valid_name(child.name):
				_bad_name += 1
		_scan_meshes(root)
		total_tris += _tris
		if _missing_mat > 0:
			_fail("%d meshes without a Bund_ material in %s" % [_missing_mat, path.get_file()])
		else:
			_ok("every mesh in %s has a Bund_ material" % path.get_file())
		if _bad_name > 0:
			_fail("%d node names outside [A-Za-z0-9_-] in %s" % [_bad_name, path.get_file()])
		else:
			_ok("node names are ASCII in %s" % path.get_file())
		if _no_normal > 0:
			_fail("%d textured materials without a normal map in %s" % [_no_normal, path.get_file()])
		else:
			_ok("%d textured materials carry a normal map" % _with_albedo)
		if _no_vcol > 0:
			_fail("%d vertex-coloured materials do not multiply the albedo in %s" % [_no_vcol, path.get_file()])
		else:
			_ok("the vertex colours reach the albedo in %s" % path.get_file())
		if path == BUILDINGS_GLB:
			if _wash <= 0:
				_fail("the wash cards are not the additive shader in %s" % path.get_file())
			else:
				_ok("%d wash surfaces use the additive shader" % _wash)
		root.free()
	if total_tris > TRIS_BUDGET:
		_fail("%d triangles, the budget is %d" % [total_tris, TRIS_BUDGET])
	else:
		_ok("%d triangles (budget %d)" % [total_tris, TRIS_BUDGET])


func _check_textures() -> void:
	"""The generated maps: read them from the bytes, not with Image.load_from_file.

	Image.load_from_file on a res:// path prints an engine warning for every map, so the
	review's "the log has 0 WARNING lines" could not be met."""
	var dir := DirAccess.open(TEXTURE_DIR)
	if dir == null:
		_fail("cannot open " + TEXTURE_DIR)
		return
	var small := 0
	var maps := 0
	for file in dir.get_files():
		if not (file.ends_with("_diff.jpg") or file.ends_with("_nor_gl.jpg")
				or file.ends_with("_rough.jpg")):
			continue
		maps += 1
		var bytes := FileAccess.get_file_as_bytes(TEXTURE_DIR + "/" + file)
		if bytes.is_empty():
			_fail("cannot read " + file)
			continue
		var img := Image.new()
		var err := img.load_jpg_from_buffer(bytes)
		if err != OK:
			_fail("cannot decode " + file)
			continue
		if img.get_width() < MIN_MAP_PX or img.get_height() < MIN_MAP_PX:
			small += 1
			_fail("%s is %dx%d, the maps are %d px or bigger"
					% [file, img.get_width(), img.get_height(), MIN_MAP_PX])
	if small == 0:
		_ok("%d maps, none under %d px" % [maps, MIN_MAP_PX])


func _valid_name(name: String) -> bool:
	for i in name.length():
		var c := name.unicode_at(i)
		if not (c == 45 or c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)):
			return false
	return true


func _reset_counters() -> void:
	_missing_mat = 0
	_bad_name = 0
	_no_normal = 0
	_with_albedo = 0
	_no_vcol = 0
	_wash = 0
	_tris = 0


func _scan_meshes(node: Node) -> void:
	"""Count the meshes without a Bund_ material, the bad node names, the missing normal
	maps, the materials that ignore the vertex colours and the wash surfaces."""
	for child in node.get_children():
		if not _valid_name(child.name):
			_bad_name += 1
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child
			if mesh.mesh != null:
				_tris += mesh.mesh.get_faces().size() / 3
				for i in mesh.mesh.get_surface_count():
					var mat: Material = mesh.mesh.surface_get_material(i)
					if mat == null or not mat.resource_name.begins_with("Bund_"):
						_missing_mat += 1
						continue
					if mat is ShaderMaterial:
						_wash += 1
						continue
					if mat is BaseMaterial3D:
						var std := mat as BaseMaterial3D
						if std.albedo_texture != null:
							_with_albedo += 1
							if std.normal_texture == null:
								_no_normal += 1
						var arrays: Array = mesh.mesh.surface_get_arrays(i)
						var colours: Variant = arrays[Mesh.ARRAY_COLOR]
						if colours != null and (colours as Array).size() > 0 \
								and not std.vertex_color_use_as_albedo:
							_no_vcol += 1
		_scan_meshes(child)


func _wall_x_at(root: Node, z: float) -> float:
	"""The x of the flood wall's river face at a given game Z."""
	var best := 1e9
	for child in root.get_children():
		if child.name != "Bund_Promenade_flood" or not (child is MeshInstance3D):
			continue
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			for v in mesh.mesh.surface_get_arrays(i)[mesh.mesh.ARRAY_VERTEX]:
				var p: Vector3 = v
				if absf(p.z - z) < 2.0:
					best = minf(best, p.x)
	return best


func _count_colliders(node: Node) -> int:
	var n := 0
	if node is CollisionShape3D or node is StaticBody3D or node is CollisionObject3D:
		n += 1
	for child in node.get_children():
		n += _count_colliders(child)
	return n

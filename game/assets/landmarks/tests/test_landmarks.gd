extends Node
## Landmarks unit test: every glb loads, the manifest matches the dossier, the
## preview scene places the assets at their anchors, the contract nodes
## (collision suffixes, light empties, sign meshes) are present and no
## non-LED material is left without an albedo and a normal map.
##
##   tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd

const MANIFEST := "res://assets/landmarks/landmarks_manifest.json"
const PREVIEW := "res://assets/landmarks/preview_skyline.tscn"
const COLLIDER_TRIS_MAX := 20000
const EXPECTED_LIGHTS := 39
const WRAPPER_REQUIRED := ["jin_mao", "swfc", "shanghai_tower", "lujiazui_backdrop",
	"lupu_bridge_far"]
const PREVIEW_NAMES := {
	"oriental_pearl": "OrientalPearl",
	"pearl_ring": "PearlRing",
	"jin_mao": "JinMao",
	"swfc": "SWFC",
	"shanghai_tower": "ShanghaiTower",
	"lujiazui_backdrop": "LujiazuiBackdrop",
	"dragon_pillar": "DragonPillar",
	"nanpu_bridge": "NanpuBridge",
	"lupu_bridge_far": "LupuBridge",
	"waibaidu_bridge": "WaibaiduBridge",
}
const EXPECTED := {
	"oriental_pearl": 468.0,
	"jin_mao": 420.5,
	"swfc": 492.0,
	"shanghai_tower": 632.0,
	"nanpu_bridge": 150.0,
	"lupu_bridge_far": 108.0,
	"waibaidu_bridge": 9.144,
	"pearl_ring": 8.7,
	"lujiazui_backdrop": 256.0,
	"dragon_pillar": 29.4,
}


func _ready() -> void:
	var ok := true
	ok = _check_manifest() and ok
	ok = _check_assets() and ok
	ok = _check_preview() and ok
	get_tree().quit(0 if ok else 1)


func _check_manifest() -> bool:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		print("FAIL manifest missing")
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("assets"):
		print("FAIL manifest is not a dictionary with assets")
		return false
	var assets: Array = (data as Dictionary)["assets"]
	var ok := assets.size() == EXPECTED.size()
	print(("PASS" if ok else "FAIL") + " manifest lists %d assets" % assets.size())
	for a in assets:
		var entry: Dictionary = a
		if not entry.has("name") or not entry.has("anchor") or not entry.has("rotation_y"):
			print("FAIL manifest entry without name/anchor/rotation_y")
			ok = false
		# the towers must go through their wrapper scene: the raw glb only
		# carries the flat fallback facade
		var asset_name := String(entry["name"])
		if asset_name in WRAPPER_REQUIRED:
			var wrapper := String(entry.get("wrapper", ""))
			var good := wrapper != "" and ResourceLoader.exists(wrapper)
			print(("PASS" if good else "FAIL") + " %s uses its wrapper scene" % asset_name)
			ok = ok and good
	return ok


func _check_assets() -> bool:
	var ok := true
	for asset_name in EXPECTED.keys():
		var path := "res://assets/landmarks/%s.glb" % asset_name
		var scene := load(path) as PackedScene
		if scene == null:
			print("FAIL %s does not load" % asset_name)
			ok = false
			continue
		var inst := scene.instantiate()
		add_child(inst)
		var h := _height(inst)
		var want: float = EXPECTED[asset_name]
		var good := absf(h - want) < maxf(want * 0.06, 3.0)
		print(("PASS" if good else "FAIL") + " %s height %.1f m (dossier %.1f)" % [asset_name, h, want])
		ok = ok and good
		if asset_name == "pearl_ring":
			var ring_ok := _find(inst, "PearlRing_ColDeck") != null
			print(("PASS" if ring_ok else "FAIL") + " pearl_ring has the -colonly deck collider")
			ok = ok and ring_ok
			var clear := _min_y(inst, "PearlRing_Deck")
			var clear_ok := clear >= 5.5
			print(("PASS" if clear_ok else "FAIL") + " pearl_ring girder soffit at %.2f m (>= 5.5)" % clear)
			ok = ok and clear_ok
		if asset_name == "waibaidu_bridge":
			var wb_ok := _find(inst, "Waibaidu_ColDeck") != null
			print(("PASS" if wb_ok else "FAIL") + " waibaidu_bridge has the -colonly deck collider")
			ok = ok and wb_ok
		if asset_name == "nanpu_bridge":
			var sign_ok := _find(inst, "LED_Nanpu_Sign_W") != null
			print(("PASS" if sign_ok else "FAIL") + " nanpu_bridge has the red name sign")
			ok = ok and sign_ok
			var cable_ok := _cables_clear_of_road(inst)
			print(("PASS" if cable_ok else "FAIL") + " nanpu_bridge cables stay off the carriageway")
			ok = ok and cable_ok
		if asset_name == "dragon_pillar":
			var lights := 0
			for c in inst.get_children():
				if c.name.begins_with("Flood_Base_"):
					lights += 1
			var lights_ok := lights == 4
			print(("PASS" if lights_ok else "FAIL") + " dragon_pillar has 4 uplight empties")
			ok = ok and lights_ok
		var tex_ok := _materials_textured(inst)
		print(("PASS" if tex_ok else "FAIL") + " %s has no untextured surface" % asset_name)
		ok = ok and tex_ok
		var col_ok := _check_colliders(inst, asset_name)
		ok = ok and col_ok
		inst.queue_free()
	return ok


func _check_colliders(inst: Node, asset_name: String) -> bool:
	"""Every solid landmark has at least one collider, and no collider is huge.

	Godot's glTF importer turns a `-colonly` / `-convcolonly` node into a
	StaticBody3D with a CollisionShape3D, so the colliders are counted there."""
	var count := 0
	var ok := true
	for body in _bodies(inst):
		count += 1
		var faces := _shape_faces(body)
		if faces > COLLIDER_TRIS_MAX:
			print("  FAIL collider %s has %d faces (> %d)" % [body.name, faces, COLLIDER_TRIS_MAX])
			ok = false
	if asset_name == "lupu_bridge_far":
		print("PASS lupu_bridge_far is backdrop only (no collider needed)")
		return ok
	var good := count >= 1
	print(("PASS" if good else "FAIL") + " %s has %d collider mesh(es)" % [asset_name, count])
	return ok and good


func _bodies(node: Node) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child in node.get_children():
		if child is StaticBody3D:
			out.append(child)
		out.append_array(_bodies(child))
	return out


func _shape_faces(body: StaticBody3D) -> int:
	var faces := 0
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		var shape := cs.shape
		if shape is ConcavePolygonShape3D:
			faces += (shape as ConcavePolygonShape3D).get_faces().size() / 3
		elif shape is ConvexPolygonShape3D:
			faces += (shape as ConvexPolygonShape3D).points.size()
	return faces


func _check_preview() -> bool:
	var scene := load(PREVIEW) as PackedScene
	if scene == null:
		print("FAIL preview scene does not load")
		return false
	var inst := scene.instantiate()
	add_child(inst)
	var ok := true
	for asset_name in PREVIEW_NAMES.keys():
		var n: String = PREVIEW_NAMES[asset_name]
		var node := inst.get_node_or_null(n)
		if node == null:
			print("FAIL preview scene is missing " + n)
			ok = false
			continue
		var entry := _manifest_entry(asset_name)
		if entry.is_empty():
			print("FAIL manifest has no entry for " + asset_name)
			ok = false
			continue
		var anchor: Array = entry["anchor"]
		var node3d0 := node as Node3D
		var pos: Vector3 = node3d0.position if node3d0 != null else Vector3.ZERO
		var good := Vector2(pos.x, pos.z).distance_to(Vector2(anchor[0], anchor[2])) < 0.5
		print(("PASS" if good else "FAIL") + " preview places %s at (%.1f, %.1f)" % [n, pos.x, pos.z])
		ok = ok and good
		# the preview basis must match the manifest rotation_y
		var want := float(entry["rotation_y"])
		var got := 0.0
		if node3d0 != null:
			got = atan2(node3d0.basis.z.x, node3d0.basis.x.x)
		var same := absf(angle_difference(want, got)) < 0.01
		print(("PASS" if same else "FAIL") + " preview rotates %s by %.4f (manifest %.4f)" % [n, got, want])
		ok = ok and same
	ok = _check_lights(inst) and ok
	inst.queue_free()
	return ok


func _manifest_entry(asset_name: String) -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	for a in (data as Dictionary)["assets"]:
		if String((a as Dictionary)["name"]) == asset_name:
			return a
	return {}


func _check_lights(inst: Node) -> bool:
	"""The rig must spawn the expected lights, and no light may sit inside a
	small mesh of its own asset."""
	var rig := inst.get_node_or_null("Lights")
	var lights: Array[Node] = []
	if rig != null:
		for c in rig.get_children():
			if c is Light3D:
				lights.append(c)
	var ok := lights.size() == EXPECTED_LIGHTS
	print(("PASS" if ok else "FAIL") + " light rig spawned %d lights (expected %d)" % [lights.size(), EXPECTED_LIGHTS])
	for l in lights:
		var light := l as Light3D
		var asset_name := _asset_of_light(light.name)
		if asset_name == "":
			continue
		var host := inst.get_node_or_null(PREVIEW_NAMES[asset_name])
		if host == null:
			continue
		for mi in _meshes(host):
			if mi.mesh == null or mi.name.ends_with("-colonly") or mi.name.ends_with("-convcolonly"):
				continue
			var aabb := mi.mesh.get_aabb()
			if aabb.size.length() > 120.0:
				continue          # a big hull: the AABB test would be meaningless
			var p := light.global_position
			if aabb.has_point(p):
				print("  FAIL light %s sits inside the AABB of %s" % [light.name, mi.name])
				ok = false
	return ok


func _asset_of_light(light_name: String) -> String:
	for asset_name in PREVIEW_NAMES.keys():
		if light_name.begins_with("Light_%s_" % asset_name):
			return asset_name
	return ""


func _height(node: Node) -> float:
	var top := -1.0e9
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null:
				top = maxf(top, mi.global_position.y + mi.mesh.get_aabb().end.y)
		elif c is Node3D:
			top = maxf(top, _height(c))
	return top if top > -1.0e8 else 0.0


func _min_y(node: Node, mesh_name: String) -> float:
	var low := 1.0e9
	for mi in _meshes(node):
		if mi.mesh != null and mi.name == mesh_name:
			low = minf(low, mi.global_position.y + mi.mesh.get_aabb().position.y)
	return low if low < 1.0e8 else -1.0


func _materials_textured(node: Node) -> bool:
	var ok := true
	for mi in _meshes(node):
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(i)
			if mat == null:
				continue
			var mat_name := String(mat.resource_name)
			if mat_name.begins_with("LED_") or mat_name.ends_with("Collider"):
				continue
			var std := mat as StandardMaterial3D
			if std == null:
				continue
			if std.albedo_texture == null or std.normal_texture == null:
				print("  FAIL untextured material: " + mat_name)
				ok = false
	return ok


func _cables_clear_of_road(node: Node) -> bool:
	"""No cable vertex may sit inside the 11.2 m carriageway below the deck."""
	var ok := true
	for mi in _meshes(node):
		if mi.name != "LED_Nanpu_Cables" or mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v in verts:
				if absf(v.x) < 12.0 and v.y < 50.0:
					ok = false
	return ok


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out


func _find(node: Node, n: String) -> Node:
	if node.name == n:
		return node
	for c in node.get_children():
		var r := _find(c, n)
		if r != null:
			return r
	return null

extends Node
## Landmarks NIGHT test (the r3 review's missing asserts).
##
##   tools/godot.sh test res://assets/landmarks/tests/test_landmarks_night.gd
##
## Checks the things the r3 review asked for and the main test does not cover:
##   * every spawned SpotLight3D carries the manifest's angle in DEGREES
##     (the old rig used deg_to_rad, so every beam was 0.44 deg wide);
##   * the pillar's four Flood_Base empties meet the column between 8 and 25 m;
##   * every roof above 100 m carries a red aviation beacon mesh;
##   * every LED_* material in every wrapper has disable_fog set;
##   * the pillar's steel carries a real metallicRoughness texture.
##
## The preview scene is used as the rig host, so the light check runs against
## the same rig the world unit spawns.

const MANIFEST := "res://assets/landmarks/landmarks_manifest.json"
const PREVIEW := "res://assets/landmarks/preview_skyline.tscn"
const PILLAR_ORIGIN := Vector3(-1299.0, 0.0, 687.0)
const COLUMN_R := 2.5
# asset -> the number of aviation beacons it must carry
const BEACONS := {
	"oriental_pearl": 1,
	"jin_mao": 1,
	"swfc": 1,
	"shanghai_tower": 1,
	"lujiazui_backdrop": 12,
	"nanpu_bridge": 2,
}
const WRAPPERS := ["oriental_pearl", "nanpu_bridge", "jin_mao", "swfc",
	"shanghai_tower", "lujiazui_backdrop", "lupu_bridge_far", "dragon_pillar",
	"pearl_ring", "waibaidu_bridge"]


func _ready() -> void:
	var ok := true
	ok = await _check_spot_angles() and ok
	ok = await _check_pillar_aim() and ok
	ok = _check_beacons() and ok
	ok = await _check_unfogged() and ok
	ok = _check_pillar_orm() and ok
	ok = await _check_beacons_blink() and ok
	get_tree().quit(0 if ok else 1)


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _check_spot_angles() -> bool:
	"""Every spot must carry the manifest's angle in degrees (5-45)."""
	var data := _manifest()
	var specs: Array = data.get("lights", [])
	var by_prefix: Dictionary = {}
	for s in specs:
		var entry: Dictionary = s
		by_prefix["%s/%s" % [entry.get("asset", ""), entry.get("empty", "")]] = entry
	var scene := load(PREVIEW) as PackedScene
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var ok := true
	var rig := inst.get_node_or_null("Lights")
	if rig == null:
		print("FAIL no light rig in the preview")
		return false
	for c in rig.get_children():
		if not (c is SpotLight3D):
			continue
		var light := c as SpotLight3D
		var asset := _asset_of(light.name)
		var empty := _empty_of(light.name)
		var want := -1.0
		for s in specs:
			var entry: Dictionary = s
			if String(entry.get("asset", "")) != asset:
				continue
			if empty.begins_with(String(entry.get("empty", ""))):
				want = float(entry.get("angle", -1.0))
				break
		if want < 0.0:
			print("FAIL no manifest spec for ", light.name, " (", asset, "/", empty, ")")
			ok = false
			continue
		var good := absf(light.spot_angle - want) < 0.01 and want >= 5.0 and want <= 45.0
		print(("PASS" if good else "FAIL") + " %s spot_angle %.2f deg (manifest %.2f)"
			% [light.name, light.spot_angle, want])
		ok = ok and good
	inst.queue_free()
	return ok


func _check_pillar_aim() -> bool:
	"""The four pillar uplights must graze the column between 8 and 25 m."""
	var scene := load(PREVIEW) as PackedScene
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var ok := true
	var rig := inst.get_node_or_null("Lights")
	if rig == null:
		return false
	for c in rig.get_children():
		if not (c is SpotLight3D):
			continue
		var light := c as SpotLight3D
		if not light.name.contains("Flood_Base_") or not light.name.contains("pillar"):
			continue
		var p := light.global_position
		var dir := -light.global_transform.basis.z
		var radial := Vector3(p.x - PILLAR_ORIGIN.x, 0.0, p.z - PILLAR_ORIGIN.z)
		var inward := -radial.normalized()
		var horiz := Vector3(inward.x, 0.0, inward.z)
		var dh := dir.dot(horiz)
		if dh < 0.01:
			print("FAIL ", light.name, " does not point at the column")
			ok = false
			continue
		# where does the beam axis cross the column's surface?
		var t := (radial.length() - COLUMN_R) / dh
		var y := p.y + dir.y * t
		var good := y >= 8.0 and y <= 25.0
		print(("PASS" if good else "FAIL") + " %s axis meets the column at y=%.1f m (8..25)"
			% [light.name, y])
		ok = ok and good
	inst.queue_free()
	return ok


func _check_beacons() -> bool:
	"""Every roof above 100 m carries a red aviation beacon (ART.md 11)."""
	var ok := true
	for asset in BEACONS.keys():
		var path := "res://assets/landmarks/%s.glb" % asset
		var scene := load(path) as PackedScene
		if scene == null:
			print("FAIL ", asset, " does not load")
			ok = false
			continue
		var inst := scene.instantiate()
		add_child(inst)
		var count := 0
		var red := true
		for mi in _meshes(inst):
			if not mi.name.begins_with("LED_Aviation"):
				continue
			count += 1
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var c: Color = (mat as StandardMaterial3D).emission
					if c.r < 0.5 or c.g > 0.4:
						red = false
		var want := int(BEACONS[asset])
		var good := count == want and red
		print(("PASS" if good else "FAIL") + " %s carries %d red aviation beacon(s) (expected %d)"
			% [asset, count, want])
		ok = ok and good
		inst.queue_free()
	return ok


func _check_unfogged() -> bool:
	"""Every LED_* material of every wrapper must have disable_fog set."""
	var ok := true
	for asset in WRAPPERS:
		var path := "res://assets/landmarks/%s.tscn" % asset
		var scene := load(path) as PackedScene
		if scene == null:
			print("FAIL no wrapper for ", asset)
			ok = false
			continue
		var inst := scene.instantiate()
		add_child(inst)
		await get_tree().process_frame
		var total := 0
		var unfogged := 0
		for mi in _meshes(inst):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D and mat.resource_name.begins_with("LED_"):
					total += 1
					if (mat as StandardMaterial3D).disable_fog:
						unfogged += 1
		var good := total > 0 and unfogged == total
		print(("PASS" if good else "FAIL") + " %s wrapper: %d/%d LED materials unfogged"
			% [asset, unfogged, total])
		ok = ok and good
		inst.queue_free()
	return ok


func _check_pillar_orm() -> bool:
	"""The pillar's steel must carry a real metallicRoughness texture."""
	var scene := load("res://assets/landmarks/dragon_pillar.glb") as PackedScene
	if scene == null:
		print("FAIL the pillar does not load")
		return false
	var inst := scene.instantiate()
	add_child(inst)
	var ok := false
	for mi in _meshes(inst):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and mat.resource_name == "LM_PILLAR_Steel":
				var std := mat as StandardMaterial3D
				var good := std.metallic_texture != null and std.normal_texture != null \
					and std.albedo_texture != null
				print(("PASS" if good else "FAIL")
					+ " LM_PILLAR_Steel has albedo + normal + metallicRoughness textures")
				ok = good
	inst.queue_free()
	return ok


const ASSETS := ["oriental_pearl", "pearl_ring", "jin_mao", "swfc", "shanghai_tower",
	"lujiazui_backdrop", "dragon_pillar", "nanpu_bridge", "lupu_bridge_far",
	"waibaidu_bridge"]


func _check_beacons_blink() -> bool:
	"""The beacons must blink: 0.25 s on, 1 Hz, with a per-tower phase.

    The headless test tree runs on a virtual clock, so the check is the state
    against the formula: every material must be in the state the 1 Hz / 0.25 s
    pattern gives for its own phase, and the phases must differ (some towers
    lit, some dark)."""
	var scene := load(PREVIEW) as PackedScene
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var mats: Array[StandardMaterial3D] = []
	var seen: Dictionary = {}
	for mi in _meshes(inst):
		if mi.mesh == null or not mi.name.begins_with("LED_Aviation"):
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and mat.resource_name.begins_with("LED_Aviation"):
				var std := mat as StandardMaterial3D
				if not seen.has(std.get_rid()):
					seen[std.get_rid()] = true
					mats.append(std)
	if mats.is_empty():
		print("FAIL no aviation materials found")
		return false
	var now := float(Time.get_ticks_msec()) * 0.001
	var consistent := 0
	var on_count := 0
	for m in mats:
		var t := fposmod(now + _phase_of(m.resource_name), 1.0)
		var want := 1.0 if t < 0.25 else 0.0
		if is_equal_approx(m.emission_energy_multiplier, want):
			consistent += 1
		if want > 0.5:
			on_count += 1
	var ok := consistent == mats.size() and on_count > 0 and on_count < mats.size()
	print(("PASS" if ok else "FAIL")
		+ " %d/%d aviation beacons follow the 1 Hz pattern, %d lit / %d dark"
		% [consistent, mats.size(), on_count, mats.size() - on_count])
	inst.queue_free()
	return ok


## The same phase hash as materials/aviation_blink.gd.
func _phase_of(mat_name: String) -> float:
	var h: int = 0
	for i in mat_name.length():
		h = (h * 31 + mat_name.unicode_at(i)) & 0xffff
	return float(h) / 65535.0


func _asset_of(light_name: String) -> String:
	# Light_<asset>_<empty...>  (the asset names contain underscores)
	var rest := light_name.trim_prefix("Light_")
	for a in ASSETS:
		if rest.begins_with(a + "_"):
			return a
	return ""


func _empty_of(light_name: String) -> String:
	var rest := light_name.trim_prefix("Light_")
	var asset := _asset_of(light_name)
	if asset == "":
		return ""
	rest = rest.trim_prefix(asset + "_")
	# the empty name is the rest without its trailing number
	var cut := rest.rfind("_")
	if cut < 0:
		return rest
	var tail := rest.substr(cut + 1)
	if tail.is_valid_int():
		return rest.substr(0, cut + 1)
	return rest


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out

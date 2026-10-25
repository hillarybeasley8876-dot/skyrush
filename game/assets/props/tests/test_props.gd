extends Node
## Contract test for the props unit (unit: props).
##
##   tools/godot.sh test res://assets/props/tests/test_props.gd
##
## Checks the node-name contract the world and gameplay units rely on
## (CONTRACTS.md §2, briefs/props.md): named markers, breakable supports, the
## barrier arms, the charging trigger volume, the shared shader materials, the
## surface budget and the texel density of every surface.
##
## The shared constants and the checks live in `prop_contract.gd`,
## `prop_layout.gd` and `prop_sites.gd`, so this file stays readable.

const PropContract = preload("res://assets/props/tests/prop_contract.gd")
const PropLayout = preload("res://assets/props/tests/prop_layout.gd")
const PropSites = preload("res://assets/props/tests/prop_sites.gd")

const STREET := "res://assets/props/street/"
const SITES := "res://assets/props/sites/"

## The exact contract names: only these nodes stay separate in a prop.
const DYNAMIC_EXACT := ["Lens_R", "Lens_A", "Lens_G", "Spikes", "Canopy",
		"BayNumbers"]
const DYNAMIC_PREFIX := ["Barrier_", "LaneSignal_", "Support_", "Chevron_"]
const SITE_FILES := ["toll_plaza", "toll_plaza_road", "gas_station", "charge_station", "sky_lane_pad",
		"sky_lane_gate", "sky_lane_gantry", "guide_gantry_19", "guide_gantry_27",
		"guide_gantry_34"]
## The surface budget of PR-INT1: a street prop is one node per material
## family, a site may carry a few more.
const STREET_SURFACE_LIMIT := 3
const SITE_SURFACE_LIMIT := 8
## The guide sign hangs with 5.5 m of clearance (the Big Hop flies at 7.8 m).
const SIGN_CLEARANCE := 5.49
const SIGN_HEIGHT := 1.2
## The traffic light lenses ship dark.
const LENS_COUNT := 3

var _failures: int = 0


func _ready() -> void:
	_check_street_files()
	_check_traffic_light_lenses()
	_check_breakable_supports()
	_check_sites()
	_check_sky_lane()
	_check_materials()
	_check_family_materials()
	_check_surface_budget()
	_check_texel_density()
	print(("FAIL" if _failures > 0 else "PASS") + " props contract (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(what: String, ok: bool) -> void:
	if ok:
		print("PASS  ", what)
	else:
		print("FAIL  ", what)
		_failures += 1


func _names(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		out.append(String(child.name))
		out.append_array(_names(child))
	return out


func _load(dir: String, file: String) -> Node:
	var path := dir + file
	if not ResourceLoader.exists(path):
		_expect("%s exists" % file, false)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_expect("%s loads" % file, false)
		return null
	var node := packed.instantiate()
	add_child(node)
	return node


func _has(names: Array[String], wanted: String) -> bool:
	return names.has(wanted)


func _has_prefix(names: Array[String], prefix: String, count: int) -> bool:
	var found := 0
	for n in names:
		if n.begins_with(prefix):
			found += 1
	return found >= count


func _check_street_files() -> void:
	var expected := ["lamp_deck_double", "lamp_street", "lamp_magnolia", "lamp_heritage",
			"lamp_shikumen", "traffic_light_mast", "road_name_sign", "guide_gantry_19",
			"guide_gantry_27", "guide_gantry_34", "guide_sign", "vms_board", "bus_stop",
			"plane_tree_1", "plane_tree_2", "plane_tree_3", "planter_pot_bougainvillea",
			"planter_pot_privet", "noise_wall", "metro_entrance", "bin", "bollard",
			"hydrant", "bike_share", "e_scooter", "ac_unit", "cone", "crash_barrier",
			"crowd_barrier", "roadblock_barrier", "spike_strip", "billboard_pole",
			"scaffold", "neon_blade_frame", "hologram_projector", "police_sign_board"]
	var missing := 0
	for name in expected:
		if not ResourceLoader.exists(STREET + name + ".glb"):
			missing += 1
	_expect("every street prop glb is present (%d files)" % expected.size(), missing == 0)
	for name in ["toll_plaza", "gas_station", "charge_station", "sky_lane_pad",
			"sky_lane_gate", "sky_lane_gantry"]:
		_expect("site %s.glb is present" % name,
				ResourceLoader.exists(SITES + name + ".glb"))


func _check_traffic_light_lenses() -> void:
	var node := _load(STREET, "traffic_light_mast.glb")
	if node == null:
		return
	var names := _names(node)
	for lens in ["Lens_R", "Lens_A", "Lens_G"]:
		_expect("the traffic light has %s" % lens, _has(names, lens))
	_expect("the traffic light has a Light marker", _has(names, "Light"))
	# PR-INT2: the lenses ship dark, the world unit switches them on
	var dark := 0
	for mi in node.find_children("Lens_*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat != null and mat.emission.r + mat.emission.g + mat.emission.b < 0.05:
			dark += 1
	_expect("the three lenses ship dark (%d)" % dark, dark == LENS_COUNT)


func _check_breakable_supports() -> void:
	var board := _load(STREET, "billboard_pole.glb")
	if board != null:
		var names := _names(board)
		_expect("the billboard has Support_1 and Support_2",
				_has(names, "Support_1") and _has(names, "Support_2"))
	var spike := _load(STREET, "spike_strip.glb")
	if spike != null:
		_expect("the spike strip has a Spikes node", _has(_names(spike), "Spikes"))


func _check_sites() -> void:
	var toll := _load(SITES, "toll_plaza.glb")
	if toll != null:
		for check in PropSites.toll_checks(toll):
			_expect(String(check[0]), bool(check[1]))
	var gas := _load(SITES, "gas_station.glb")
	if gas != null:
		for check in PropSites.gas_checks(gas):
			_expect(String(check[0]), bool(check[1]))
	var charge := _load(SITES, "charge_station.glb")
	if charge != null:
		for check in PropSites.charge_checks(charge):
			_expect(String(check[0]), bool(check[1]))


func _check_sky_lane() -> void:
	var pad := _load(SITES, "sky_lane_pad.glb")
	if pad != null:
		_expect("the launch pad has chevron slots", _has_prefix(_names(pad), "Chevron_", 6))
	var gate := _load(SITES, "sky_lane_gate.glb")
	if gate != null:
		var found := false
		for mi in gate.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi as MeshInstance3D
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.mesh.surface_get_material(i)
				if mat != null and mat.resource_name.begins_with("SH_hologram"):
					found = true
		_expect("the ring gate uses the SH_hologram material", found)
	var gantry := _load(SITES, "sky_lane_gantry.glb")
	if gantry != null:
		_expect("the sky-lane gantry has a light marker", _has(_names(gantry), "Light"))
	var guide := _load(STREET, "guide_gantry_27.glb")
	if guide != null:
		_expect("the guide gantry has per-lane sign mounts",
				_has_prefix(_names(guide), "SignMount_", 3))
		# dossier §2.6: the sign bottom must clear 5.5 m (the Big Hop flies at 7.8 m)
		var mount := guide.find_child("SignMount_1", true, false) as Node3D
		if mount != null:
			_expect("the guide sign hangs with 5.5 m of clearance (%.2f m)"
					% (mount.position.y - SIGN_HEIGHT),
					mount.position.y - SIGN_HEIGHT >= SIGN_CLEARANCE)
		else:
			_expect("the guide gantry has a SignMount_1 marker", false)


func _check_materials() -> void:
	# no visible surface may fall back to the default grey material
	var bad := 0
	var untinted := 0
	for dir in [STREET, SITES]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".glb"):
				continue
			var node := _load(dir, file)
			if node == null:
				continue
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := mi as MeshInstance3D
				for i in mesh.mesh.get_surface_count():
					var mat := mesh.mesh.surface_get_material(i)
					if mat == null:
						bad += 1
						continue
					# the family materials must use the vertex colour as albedo
					var std := mat as StandardMaterial3D
					if std != null and PropContract.FAMILY_MATERIALS.has(std.resource_name):
						if not std.vertex_color_use_as_albedo:
							untinted += 1
			node.queue_free()
	_expect("every prop surface has a material", bad == 0)
	_expect("every family material uses the vertex colour as albedo (%d bad)" % untinted,
			untinted == 0)


## The review of round 3: Godot has to read the roughness of the family maps
## from the GREEN channel (the glTF layout), a painted surface has to be a
## dielectric, and the foliage has to be an alpha mask with the culling off.
func _check_family_materials() -> void:
	for family in PropContract.FAMILY_MATERIALS:
		var mat := PropContract.family_material(family)
		if mat == null:
			_expect("the %s material exists" % family, false)
			continue
		var ok := mat.roughness_texture != null
		ok = ok and mat.roughness_texture_channel == PropContract.ROUGHNESS_CHANNEL
		_expect("%s reads its roughness from the green channel (%d)" % [family,
				mat.roughness_texture_channel], ok)
		if mat.roughness_texture == null:
			continue
		var stats := PropContract.channel_stats(mat.roughness_texture, 1)
		_expect("%s keeps a roughness breakup in green (sigma %.3f)" % [family, stats.y],
				stats.y > 0.01)
	# a painted surface is a dielectric, a bare metal one is not
	var paint := PropContract.family_material("paint")
	_expect("the paint family is a dielectric (metallic %.2f)"
			% (paint.metallic if paint != null else -1.0),
			paint != null and paint.metallic < 0.05)
	var metal := PropContract.family_material("metal")
	_expect("the metal family is a metal (metallic %.2f)"
			% (metal.metallic if metal != null else -1.0),
			metal != null and metal.metallic > 0.5)
	# the foliage is an alpha mask with the culling off (art dossier §4.9)
	var foliage := PropContract.family_material("foliage")
	if foliage != null:
		_expect("the foliage is an alpha scissor (mode %d)" % foliage.transparency,
				foliage.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
		_expect("the foliage keeps the culling off (mode %d)" % foliage.cull_mode,
				foliage.cull_mode == BaseMaterial3D.CULL_DISABLED)
	else:
		_expect("the foliage material exists", false)


## PR-INT1: one static node per prop, and only the contract nodes stay separate.
func _is_dynamic(node_name: String) -> bool:
	if DYNAMIC_EXACT.has(node_name):
		return true
	for prefix in DYNAMIC_PREFIX:
		if node_name.begins_with(prefix):
			return true
	return false


func _surface_count(node: Node) -> Dictionary:
	var out := {"static": 0, "dynamic": 0, "nodes": 0, "materials": [] as Array[String]}
	var seen := {}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null:
			continue
		out["nodes"] = int(out["nodes"]) + 1
		var count := mesh.mesh.get_surface_count()
		if _is_dynamic(String(mesh.name)):
			out["dynamic"] = int(out["dynamic"]) + count
		else:
			out["static"] = int(out["static"]) + count
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(i)
			if mat != null and not seen.has(mat.resource_name):
				seen[mat.resource_name] = true
				(out["materials"] as Array[String]).append(mat.resource_name)
	return out


func _check_surface_budget() -> void:
	var rows: Array[String] = []
	for dir in [STREET, SITES]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".glb"):
				continue
			var node := _load(dir, file)
			if node == null:
				continue
			var stats := _surface_count(node)
			var limit := STREET_SURFACE_LIMIT
			if SITE_FILES.has(file.get_basename()):
				limit = SITE_SURFACE_LIMIT
			var ok := int(stats["static"]) <= limit
			_expect("%s: %d static surfaces (limit %d, %d dynamic, %d nodes)" %
					[file.get_basename(), int(stats["static"]), limit,
					 int(stats["dynamic"]), int(stats["nodes"])], ok)
			rows.append("%s|%d|%d|%d|%d|%s" % [file.get_basename(), int(stats["static"]),
					int(stats["dynamic"]), int(stats["nodes"]),
					(stats["materials"] as Array[String]).size(),
					",".join(stats["materials"] as Array[String])])
			node.queue_free()
	var out := FileAccess.open("user://props_surfaces.txt", FileAccess.WRITE)
	if out != null:
		out.store_string("\n".join(rows))
		out.close()


## PR-INT2 / review r2 item 1: every family surface must sample its texture
## at 512 px/m (the share of the area below 300 px/m must stay under 5 %).
func _check_texel_density() -> void:
	for dir in [STREET, SITES]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".glb"):
				continue
			var node := _load(dir, file)
			if node == null:
				continue
			var share := PropContract.bad_share(node)
			_expect("%s: %.1f%% of the surface below 300 px/m" %
					[file.get_basename(), 100.0 * share], share <= PropContract.MAX_BAD_SHARE)
			node.queue_free()

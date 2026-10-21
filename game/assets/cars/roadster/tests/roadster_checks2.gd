extends "res://assets/cars/roadster/tests/roadster_checks.gd"
## The geometry checks of the hero Roadster (part 2): the surfaces, the lamps,
## the clearances, the wing and the tyres.

## every surface of the car has a material
func check_surfaces(by_name: Dictionary) -> void:
	var bare: Array[String] = []
	var count := 0
	for n in by_name.keys():
		var mi := mesh(by_name, str(n))
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			count += 1
			if mi.get_active_material(s) == null:
				bare.append("%s[%d]" % [str(n), s])
	check(bare.is_empty(), "all %d surfaces have a material%s"
		% [count, "" if bare.is_empty() else " (bare: %s)" % ", ".join(bare)])


## the head lamps are the emissive jewels, not an empty triangle
func check_lamps(by_name: Dictionary) -> void:
	var bad: Array[String] = []
	for n in ["Lamp_FL", "Lamp_FR"]:
		var mi := mesh(by_name, n)
		if mi == null:
			bad.append("%s missing" % n)
			continue
		if mi.mesh.get_surface_count() == 0 or mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() < 36:
			bad.append("%s has %d verts" % [n, mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()])
			continue
		var mat := mi.get_active_material(0)
		if mat == null or not (mat as BaseMaterial3D).emission_enabled:
			bad.append("%s is not emissive" % n)
	check(bad.is_empty(), "Lamp_FL/Lamp_FR are emissive jewels%s"
		% ["" if bad.is_empty() else " (%s)" % ", ".join(bad)])


## the plate stands clear of its frame, and the brake light of the bar
func check_clearances(by_name: Dictionary) -> void:
	# Godot is Y up: the car's length runs on Z, so the depth of the tail
	# parts is measured on Z (the frame's front face against the plate).
	var plate := mesh(by_name, "Plate_Rear")
	var frame := mesh(by_name, "Plate_Frame")
	if plate == null or frame == null:
		check(false, "the plate and its frame are 1 mm apart")
	else:
		var gap := absf(world_aabb(frame).end.z - world_aabb(plate).end.z)
		check(gap >= 0.001, "the plate is %.1f mm clear of its frame" % (gap * 1000.0))
	var bar := mesh(by_name, "LightBar_Rear")
	var brake := mesh(by_name, "Brake_Light")
	if bar == null or brake == null:
		check(false, "the brake light is 1 mm clear of the light bar")
	else:
		var gap := absf(world_aabb(brake).end.z - world_aabb(bar).end.z)
		check(gap >= 0.0008, "the brake light is %.1f mm clear of the bar" % (gap * 1000.0))


## the wing's parts: stowed they sit on the wing, deployed they are in place
func check_wing(by_name: Dictionary) -> void:
	var wing := by_name.get("Wing") as Node3D
	if wing == null:
		check(false, "the wing's parts follow the wing")
		return
	# the pose angles live in the node's extras (the glTF extras)
	var extras: Dictionary = wing.get_meta("extras", {})
	var poses: Variant = extras.get("poses", null)
	var poses_ok := poses is Dictionary
	if poses_ok:
		poses_ok = (poses as Dictionary).has("high_downforce") and (poses as Dictionary).has("air_brake")
	check(poses_ok, "the wing carries the poses property")
	var origin := wing.global_position
	var loose: Array[String] = []
	for p in ["Wing_Slat", "Wing_EndPlate_L", "Wing_EndPlate_R", "Wing_Strut_L", "Wing_Strut_R"]:
		var node: Node = by_name.get(p)
		if node == null:
			loose.append("%s missing" % p)
			continue
		if not is_descendant(node, wing):
			loose.append("%s is not a child of the wing" % p)
			continue
		var c := (node as Node3D).global_position
		var d := Vector2(c.y - origin.y, c.z - origin.z).length()
		if d > 0.6:
			loose.append("%s is %.2f m from the wing" % [p, d])
	check(loose.is_empty(), "every wing part is stowed on the wing%s"
		% ["" if loose.is_empty() else " (%s)" % ", ".join(loose)])
	# the deploy contract: the wing is pitched by -15 deg about its local X and
	# the parts are scaled from 0.001 to 1.0. The positions are COMPUTED here
	# instead of read back from the scene, so the check does not depend on the
	# order in which Godot composes the global transforms.
	var ang := -deg_to_rad(WING_PITCH_DEG)
	var basis := Basis(Vector3.RIGHT, ang)
	var wrong: Array[String] = []
	for p in ["Wing_EndPlate_L", "Wing_EndPlate_R"]:
		var mi := mesh(by_name, p)
		if mi == null:
			wrong.append("%s missing" % p)
			continue
		# the part's own local transform (the pivot) and its mesh data
		var pivot := mi.transform.origin
		var rot := mi.transform.basis.orthonormalized()
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var w: Vector3 = origin + basis * (pivot + rot * v)
			lo = lo.min(w)
			hi = hi.max(w)
		var cx := (lo.x + hi.x) * 0.5
		if absf(cx) < 0.74 or absf(cx) > 0.80:
			wrong.append("%s at x %.3f" % [p, cx])
		# Godot is Y up: the car's length runs on Z and its height on Y
		if lo.y < 0.78 or hi.y > 1.15:
			wrong.append("%s at y %.3f..%.3f" % [p, lo.y, hi.y])
		if lo.z < 1.70 or hi.z > 2.40:
			wrong.append("%s at z %.3f..%.3f" % [p, lo.z, hi.z])
	check(wrong.is_empty(), "the deployed end plates are in place%s"
		% ["" if wrong.is_empty() else " (%s)" % ", ".join(wrong)])


## both tyres are wound the same way, so the lettering reads on both sides
func check_tyre_winding(by_name: Dictionary) -> void:
	var left := _sidewall_sign(mesh(by_name, "Tyre_FL"))
	var right := _sidewall_sign(mesh(by_name, "Tyre_FR"))
	if left == 0 or right == 0:
		check(false, "the tyres carry the same lettering winding")
		return
	check(left == right, "the tyres carry the same lettering winding (%+d / %+d)" % [left, right])


func _sidewall_sign(mi: MeshInstance3D) -> int:
	"""+1 or -1: the direction the outboard sidewall runs in the u axis.

	The direction is measured the way a viewer OUTSIDE the wheel sees it, so
	both tyres have to give the same sign.
	"""
	if mi == null:
		return 0
	var outboard := signf(mi.global_position.x)
	var basis := mi.global_transform.basis
	var total := 0.0
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for i in range(0, mi.mesh.surface_get_array_len(s), 3):
			if i + 2 >= uvs.size():
				break
			# only the outboard sidewall (v 0.77..1.0 of the profile)
			if (uvs[i].y + uvs[i + 1].y + uvs[i + 2].y) / 3.0 < 0.77:
				continue
			var v0 := basis * verts[i]
			var v1 := basis * verts[i + 1]
			var v2 := basis * verts[i + 2]
			var e1 := v1 - v0
			var e2 := v2 - v1
			var du := (uvs[i + 1].x - uvs[i].x) * e1 + (uvs[i + 2].x - uvs[i + 1].x) * e2
			var dv := (uvs[i + 1].y - uvs[i].y) * e1 + (uvs[i + 2].y - uvs[i + 1].y) * e2
			if du.length() < 1e-9 or dv.length() < 1e-9:
				continue
			total += du.cross(dv).dot(Vector3(outboard, 0.0, 0.0))
	return 0 if absf(total) < 1e-12 else (1 if total > 0.0 else -1)

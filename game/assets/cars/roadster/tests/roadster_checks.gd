extends RefCounted
## The checks of the hero Roadster, split out of test_roadster.gd.
##
## The test loads the glb, instantiates the car and hands the root node to
## these checks. Every check prints one PASS/FAIL line.

const GLB := "res://assets/cars/roadster/roadster.glb"

## the contract node names (CONTRACTS.md §6)
const NODES := [
	"Body", "Glass", "Interior", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR",
	"Caliper_FL", "Caliper_FR", "Caliper_RL", "Caliper_RR", "Wing", "Door_L", "Door_R",
	"Bumper_F", "Bumper_R", "Hood", "Diffuser", "LightBar_Rear", "Brake_Light",
	"Lamp_Front", "Lamp_FL", "Lamp_FR", "HeadlampPanel_L", "HeadlampPanel_R",
	"Skirt_L", "Skirt_R", "Plate_Rear",
	"Nozzle_R1", "Nozzle_R2", "Nozzle_R3", "Nozzle_R4",
	"Nozzle_P1", "Nozzle_P2", "Nozzle_P3", "Nozzle_P4", "Nozzle_P5", "Nozzle_P6",
	"NozzleMesh_R1", "NozzleMesh_R2", "NozzleMesh_R3", "NozzleMesh_R4",
	"NozzleMesh_P1", "NozzleMesh_P2", "NozzleMesh_P3", "NozzleMesh_P4",
	"NozzleMesh_P5", "NozzleMesh_P6",
	"Fan_R1", "Fan_R2", "Fan_R3", "Fan_R4",
	"Wing_Slat", "Wing_EndPlate_L", "Wing_EndPlate_R", "Wing_Strut_L", "Wing_Strut_R",
	"Fan_Intake", "Light_Front", "Light_Rear", "Camera_Hood", "Seat_Driver",
]

## the body and the wheels: the car's own shape
const BODY := ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR",
	"Tyre_FL", "Tyre_FR", "Tyre_RL", "Tyre_RR"]

## the body, the wheels and the two parts that stick out
const HULL := BODY + ["Diffuser", "Splitter"]

## the detachable panels and the dark surface behind each of them
const PANELS := {
	"Door_L": "Door_Inner_L", "Door_R": "Door_Inner_R",
	"Hood": "Hood_Inner", "Bumper_F": "Bumper_F_Inner", "Bumper_R": "Bumper_R_Inner",
	"Skirt_L": "Skirt_Inner_L", "Skirt_R": "Skirt_Inner_R",
	"HeadlampPanel_L": "HeadlampPanel_Inner_L", "HeadlampPanel_R": "HeadlampPanel_Inner_R",
}

const WING_PARTS := ["Wing_Slat", "Wing_EndPlate_L", "Wing_EndPlate_R",
	"Wing_Strut_L", "Wing_Strut_R"]

## the deploy contract: the wing is pitched by -pitch_deg and the parts are
## scaled from 0.001 (stowed) to 1.0 (deployed)
const WING_PITCH_DEG := 15.0

var failures := 0


func check(ok: bool, label: String) -> bool:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
	return ok


func mesh(by_name: Dictionary, n: String) -> MeshInstance3D:
	if by_name.has(n) and by_name[n] is MeshInstance3D:
		return by_name[n] as MeshInstance3D
	return null


func world_aabb(mi: MeshInstance3D) -> AABB:
	var aabb := AABB()
	var first := true
	for m in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(m)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := mi.global_transform * v
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func collect(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		out[child.name] = child
		collect(child, out)


func collect_materials(node: Node, out: Array[String]) -> void:
	if node is MeshInstance3D:
		for m in (node as MeshInstance3D).mesh.get_surface_count():
			var mat := (node as MeshInstance3D).get_active_material(m)
			if mat != null and not out.has(mat.resource_name):
				out.append(mat.resource_name)
	for child in node.get_children():
		collect_materials(child, out)


func is_descendant(node: Node, ancestor: Node) -> bool:
	var n := node
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false


## the contract node names
func check_names(by_name: Dictionary) -> void:
	var missing: Array[String] = []
	for n in NODES:
		if not by_name.has(n):
			missing.append(n)
	check(missing.is_empty(), "all %d contract node names present%s"
		% [NODES.size(), "" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)])


## the contract materials, and no material imported twice
func check_materials(by_name: Dictionary, root: Node) -> void:
	var mats: Array[String] = []
	collect_materials(root, mats)
	var want := ["SH_car_paint", "SH_glass_gold", "M_BlackTrim", "M_BrakeLight", "M_Plate"]
	var lack: Array[String] = []
	for w in want:
		if not mats.has(w):
			lack.append(w)
	check(lack.is_empty(), "contract materials present%s"
		% ["" if lack.is_empty() else " (missing: %s)" % ", ".join(lack)])
	var dupes: Array[String] = []
	for m in mats:
		if m.contains("."):
			dupes.append(m)
	check(dupes.is_empty(), "no duplicated material names%s"
		% ["" if dupes.is_empty() else " (duplicates: %s)" % ", ".join(dupes)])
	var paint_ok := false
	var body := mesh(by_name, "Body")
	if body != null:
		var mat := body.get_active_material(0)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_enabled:
			paint_ok = true
	check(paint_ok, "body paint has a normal map (panel gaps)")


## the bounding box against the body and the wheel hull
func check_dimensions(by_name: Dictionary) -> void:
	var hull := hull_aabb(by_name, BODY)
	var size := hull.size
	var ok := absf(size.x - 1.98) < 0.06 and absf(size.y - 1.147) < 0.05 \
		and absf(size.z - 4.38) < 0.08
	check(ok, "bounding box %.3f x %.3f x %.3f m (target 1.98 x 1.15 x 4.38)"
		% [size.x, size.y, size.z])


func hull_aabb(by_name: Dictionary, parts: Array = HULL) -> AABB:
	var out := AABB()
	var first := true
	for n in parts:
		var mi := mesh(by_name, n)
		if mi == null:
			continue
		var b := world_aabb(mi)
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## every mesh of the car sits inside the hull
func check_inside(by_name: Dictionary) -> void:
	var hull := hull_aabb(by_name)
	var outside: Array[String] = []
	var lowest := 1e9
	for n in by_name.keys():
		var mi := mesh(by_name, str(n))
		if mi == null:
			continue
		var b := world_aabb(mi)
		lowest = min(lowest, b.position.y)
		if b.position.x < hull.position.x - 0.01 or b.end.x > hull.end.x + 0.01 \
				or b.position.y < hull.position.y - 0.01 or b.end.y > hull.end.y + 0.01 \
				or b.position.z < hull.position.z - 0.01 or b.end.z > hull.end.z + 0.01:
			outside.append(str(n))
	check(outside.is_empty(), "every mesh inside the body+wheel AABB (lowest y = %.4f)%s"
		% [lowest, "" if outside.is_empty() else " (outside: %s)" % ", ".join(outside)])


## the dark surface behind a panel is inside the panel
func check_panels(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	for panel in PANELS.keys():
		var pm := mesh(by_name, panel)
		var im := mesh(by_name, PANELS[panel])
		if pm == null or im == null:
			wrong.append("%s/%s missing" % [panel, PANELS[panel]])
			continue
		var pb := world_aabb(pm)
		var ib := world_aabb(im)
		var pc := (pb.position + pb.end) * 0.5
		var ic := (ib.position + ib.end) * 0.5
		var ok := false
		if panel == "Hood":
			ok = ic.y < pc.y
		elif panel.begins_with("Skirt"):
			ok = absf(ic.x) < absf(pc.x)
		else:
			ok = absf(ic.x) < absf(pc.x) or ic.y < pc.y - 0.001
		if not ok:
			wrong.append("%s (panel centre %s, inner centre %s)" % [panel, pc, ic])
	check(wrong.is_empty(), "every panel's inner surface lies inside the panel%s"
		% ["" if wrong.is_empty() else " (wrong: %s)" % ", ".join(wrong)])
	var dm := mesh(by_name, "Diffuser")
	if dm == null:
		check(false, "diffuser symmetry")
	else:
		var db := world_aabb(dm)
		var asym := absf(db.position.x + db.end.x)
		check(asym < 0.002, "diffuser is symmetric (|x_min + x_max| = %.4f m)" % asym)


## the wheel hubs on the axle height
func check_wheels(by_name: Dictionary) -> void:
	var ground_ok := true
	for n in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		if not by_name.has(n):
			ground_ok = false
			continue
		var w := by_name[n] as Node3D
		if absf(w.global_position.y - 0.3425) > 0.03 and absf(w.global_position.y - 0.367) > 0.03:
			ground_ok = false
	check(ground_ok, "wheel hubs on the axle height (front 0.343 / rear 0.367)")


## the _L parts on the left, the _R parts on the right
func check_layout(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	for n in by_name.keys():
		var s := str(n)
		if not (s.ends_with("_L") or s.ends_with("_R")):
			continue
		if s in ["Bumper_R", "Bumper_F", "Diffuser", "Wing", "Hood"]:
			continue
		var node := by_name[n] as Node3D
		if node == null:
			continue
		var mi := mesh(by_name, s)
		if mi == null:
			continue
		var b := world_aabb(mi)
		if b.size == Vector3.ZERO:
			continue
		var cx := (b.position.x + b.end.x) * 0.5
		if s.ends_with("_L") and cx > -0.001:
			wrong.append("%s (x=%.3f)" % [s, cx])
		if s.ends_with("_R") and cx < 0.001:
			wrong.append("%s (x=%.3f)" % [s, cx])
	check(wrong.is_empty(), "left parts on the left, right parts on the right%s"
		% ["" if wrong.is_empty() else " (wrong: %s)" % ", ".join(wrong)])


## the body's surface UVs stay inside 0..1 (the panel-gap map is drawn there)
func check_uvs(by_name: Dictionary) -> void:
	var body := mesh(by_name, "Body")
	if body == null:
		check(false, "body UVs")
		return
	var lo := Vector2(2.0, 2.0)
	var hi := Vector2(-2.0, -2.0)
	for s in body.mesh.get_surface_count():
		var arr := body.mesh.surface_get_arrays(s)
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for uv in uvs:
			lo = lo.min(uv)
			hi = hi.max(uv)
	var ok := lo.x >= -0.001 and lo.y >= -0.001 and hi.x <= 1.001 and hi.y <= 1.001
	check(ok, "body surface UVs within 0..1 (u %.3f..%.3f, v %.3f..%.3f)"
		% [lo.x, hi.x, lo.y, hi.y])


## every imported normal map really varies, and the plate maps 1:1
func check_textures(by_name: Dictionary) -> void:
	var flat: Array[String] = []
	var checked := 0
	for n in by_name.keys():
		var mi := mesh(by_name, str(n))
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_enabled:
				var tex := (mat as BaseMaterial3D).normal_texture
				if tex == null:
					continue
				checked += 1
				var img := tex.get_image()
				if img == null:
					continue
				if _spread(img) < 5 and not _has_relief(img):
					flat.append("%s %s" % [str(n), tex.resource_path.get_file()])
	check(flat.is_empty(), "%d normal textures carry relief (spread > 5/255)%s"
		% [checked, "" if flat.is_empty() else " (flat: %s)" % ", ".join(flat)])
	var plate_ok := false
	var plate := mesh(by_name, "Plate_Rear")
	if plate != null:
		var mat := plate.get_active_material(0)
		if mat is BaseMaterial3D:
			var tex := (mat as BaseMaterial3D).albedo_texture
			if tex != null:
				plate_ok = is_equal_approx(mat.uv1_scale.x, 1.0) and is_equal_approx(mat.uv1_scale.y, 1.0)
	check(plate_ok, "plate texture transform scale is 1")


func _spread(img: Image) -> int:
	"""The spread of the R and G channels over a sparse sample of the image."""
	var w := img.get_width()
	var h := img.get_height()
	var lo_r := 255
	var hi_r := 0
	var lo_g := 255
	var hi_g := 0
	for i in range(0, 1024):
		var x := (i * 37) % w
		var y := (i * 53) % h
		var c := img.get_pixel(x, y)
		lo_r = min(lo_r, c.r * 255.0)
		hi_r = max(hi_r, c.r * 255.0)
		lo_g = min(lo_g, c.g * 255.0)
		hi_g = max(hi_g, c.g * 255.0)
	return int(max(hi_r - lo_r, hi_g - lo_g))


func _has_relief(img: Image) -> bool:
	"""True when the image's R or G channel spreads over more than 5/255."""
	var data := img.get_data()
	var lo_r := 255
	var hi_r := 0
	var lo_g := 255
	var hi_g := 0
	var i := 0
	while i < data.size():
		var r := data[i]
		var g := data[i + 1]
		lo_r = min(lo_r, r)
		hi_r = max(hi_r, r)
		lo_g = min(lo_g, g)
		hi_g = max(hi_g, g)
		i += 4
	return hi_r - lo_r > 5 or hi_g - lo_g > 5

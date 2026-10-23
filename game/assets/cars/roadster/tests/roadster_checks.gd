extends RefCounted
## The checks of the hero Roadster, split out of test_roadster.gd.
##
## The car is the Khronos "Car Concept" (CC BY 4.0, see CREDITS.md) converted by blender/car/concept:
## white pearl with gloss black panels, no texture, 65k triangles. The test loads the glb,
## instantiates the car and hands the root node to these checks. Every check prints one
## PASS/FAIL line.

const GLB := "res://assets/cars/roadster/roadster.glb"

## the contract node names (CONTRACTS.md 6) and the parts the damage unit knows
const NODES := [
	"Body", "Glass", "Interior", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR",
	"Caliper_FL", "Caliper_FR", "Caliper_RL", "Caliper_RR", "Wing", "Door_L", "Door_R",
	"Mirror_L", "Mirror_R", "Bumper_F", "Bumper_R", "Hood", "Skirt_L", "Skirt_R",
	"LightBar_Rear", "Brake_Light", "Lamp_FL", "Lamp_FR", "Plate_Rear",
	"Nozzle_R1", "Nozzle_R2", "Nozzle_R3", "Nozzle_R4",
	"Nozzle_P1", "Nozzle_P2", "Nozzle_P3", "Nozzle_P4", "Nozzle_P5", "Nozzle_P6",
	"Fan_Intake", "Light_Front", "Light_Rear", "Camera_Hood", "Seat_Driver",
]
const WHEELS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

## the materials the car must carry, and the ones that would break the black and white scheme
const WANTED_MATERIALS := ["SH_car_paint", "SH_car_paint_black", "SH_glass_smoke", "M_BrakeLight",
	"M_Headlamp", "M_Plate"]
const BANNED_MATERIALS := ["SH_glass_gold", "M_GoldWheel", "M_NozzleGold", "M_RedAccent"]
## the lights may carry a colour (red brake light, white lamps); nothing else may
const LIT_MATERIALS := ["M_BrakeLight", "M_Headlamp", "M_Screen"]
const MAX_SATURATION := 0.15
const MATERIAL_BUDGET := 20
const TRIANGLE_BUDGET := 80000

const TYRE_RADIUS := 0.384
const WHEELBASE := 2.80
const FRONT_TRACK := 1.952
const REAR_TRACK := 1.964
const BODY_SIZE := Vector3(2.236, 1.06, 4.363)

var failures := 0
## The self test of the checks runs them on a car they must reject, without printing a FAIL line.
var quiet := false


func check(ok: bool, label: String) -> bool:
	if not quiet:
		print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
	return ok


func mesh(by_name: Dictionary, n: String) -> MeshInstance3D:
	if by_name.has(n) and by_name[n] is MeshInstance3D:
		return by_name[n] as MeshInstance3D
	return null


## The AABB of a mesh node in the car frame (the nodes of the glb are not scaled or rotated).
func world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()


func collect(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		out[child.name] = child
		collect(child, out)


func collect_materials(node: Node, out: Array[Material]) -> void:
	if node is MeshInstance3D:
		for m in (node as MeshInstance3D).mesh.get_surface_count():
			var mat := (node as MeshInstance3D).get_active_material(m)
			if mat != null and not out.has(mat):
				out.append(mat)
	for child in node.get_children():
		collect_materials(child, out)


func triangles(mi: MeshInstance3D) -> int:
	var count := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (index.size() if index.size() > 0 else verts.size()) / 3
	return count


## the contract node names
func check_names(by_name: Dictionary) -> void:
	var missing: Array[String] = []
	for n in NODES:
		if not by_name.has(n):
			missing.append(n)
	check(missing.is_empty(), "all %d contract node names present%s"
		% [NODES.size(), "" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)])
	var wrong: Array[String] = []
	for n in ["Body", "Glass", "Interior", "Hood", "Door_L", "Door_R", "Mirror_L", "Mirror_R", "Bumper_F",
			"Bumper_R", "Skirt_L", "Skirt_R", "Wing", "Brake_Light", "LightBar_Rear"] + WHEELS:
		if by_name.has(n) and not (by_name[n] is MeshInstance3D):
			wrong.append(n)
	check(wrong.is_empty(), "the parts the damage unit moves are meshes%s"
		% ["" if wrong.is_empty() else " (not meshes: %s)" % ", ".join(wrong)])


## the materials: the two paints, the smoke glass, the lights, and nothing of the old gold
func check_materials(root: Node) -> void:
	var mats: Array[Material] = []
	collect_materials(root, mats)
	var names: Array[String] = []
	for m in mats:
		names.append(m.resource_name)
	var lack: Array[String] = []
	for w in WANTED_MATERIALS:
		if not names.has(w):
			lack.append(w)
	check(lack.is_empty(), "contract materials present%s"
		% ["" if lack.is_empty() else " (missing: %s)" % ", ".join(lack)])
	var banned: Array[String] = []
	for n in names:
		if BANNED_MATERIALS.has(n):
			banned.append(n)
	check(banned.is_empty(), "no gold or red accent material%s"
		% ["" if banned.is_empty() else " (found: %s)" % ", ".join(banned)])
	var dupes: Array[String] = []
	for n in names:
		if n.contains("."):
			dupes.append(n)
	check(dupes.is_empty(), "no duplicated material names%s"
		% ["" if dupes.is_empty() else " (duplicates: %s)" % ", ".join(dupes)])
	check(names.size() <= MATERIAL_BUDGET, "%d materials (budget %d)" % [names.size(), MATERIAL_BUDGET])


## black and white: every surface is neutral, only the lights carry a colour, nothing is textured
func check_palette(root: Node) -> void:
	var mats: Array[Material] = []
	collect_materials(root, mats)
	var coloured: Array[String] = []
	var textured: Array[String] = []
	for m in mats:
		var base := m as BaseMaterial3D
		if base == null:
			continue
		if base.albedo_texture != null or base.normal_texture != null or base.emission_texture != null:
			textured.append(m.resource_name)
		if LIT_MATERIALS.has(m.resource_name):
			continue
		var c := base.albedo_color
		var high := maxf(c.r, maxf(c.g, c.b))
		var low := minf(c.r, minf(c.g, c.b))
		var saturation := (high - low) / high if high > 0.001 else 0.0
		if saturation > MAX_SATURATION:
			coloured.append("%s (%.2f)" % [m.resource_name, saturation])
	check(coloured.is_empty(), "every surface is black, white or grey%s"
		% ["" if coloured.is_empty() else " (coloured: %s)" % ", ".join(coloured)])
	check(textured.is_empty(), "the car has no texture, so Godot extracts nothing next to the glb%s"
		% ["" if textured.is_empty() else " (textured: %s)" % ", ".join(textured)])


## the size of the body and the triangle budget
func check_dimensions(by_name: Dictionary, root: Node) -> void:
	var body := mesh(by_name, "Body")
	if body == null:
		check(false, "body size")
		return
	var size := world_aabb(body).size
	var ok := absf(size.x - BODY_SIZE.x) < 0.08 and absf(size.y - BODY_SIZE.y) < 0.08 \
		and absf(size.z - BODY_SIZE.z) < 0.1
	check(ok, "body %.3f x %.3f x %.3f m (target %.2f x %.2f x %.2f)"
		% [size.x, size.y, size.z, BODY_SIZE.x, BODY_SIZE.y, BODY_SIZE.z])
	var total := 0
	for n in by_name.keys():
		var mi := mesh(by_name, str(n))
		if mi != null:
			total += triangles(mi)
	check(total <= TRIANGLE_BUDGET and total > 20000, "%d triangles (budget %d)" % [total, TRIANGLE_BUDGET])


## the wheels: the layout the spec is generated from
func check_wheels(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	for n in WHEELS:
		var w := mesh(by_name, n)
		if w == null:
			wrong.append(n + " missing")
			continue
		if absf(w.position.y - TYRE_RADIUS) > 0.004:
			wrong.append("%s hub at y %.3f" % [n, w.position.y])
		if not w.transform.basis.is_equal_approx(Basis.IDENTITY):
			wrong.append("%s is rotated" % n)
		var box := w.mesh.get_aabb()
		if absf(box.size.y - 2.0 * TYRE_RADIUS) > 0.012 or absf(box.size.z - 2.0 * TYRE_RADIUS) > 0.012:
			wrong.append("%s is %.3f x %.3f" % [n, box.size.y, box.size.z])
		if box.size.x < 0.2 or box.size.x > 0.4:
			wrong.append("%s is %.3f wide" % [n, box.size.x])
		var middle := box.get_center()
		if middle.length() > 0.02:
			wrong.append("%s is not centred on its hub (%s)" % [n, str(middle)])
	check(wrong.is_empty(), "the wheels sit on their hubs, spin about X and are one tyre round%s"
		% ["" if wrong.is_empty() else " (%s)" % ", ".join(wrong)])
	var fl := by_name.get("Wheel_FL") as Node3D
	var fr := by_name.get("Wheel_FR") as Node3D
	var rl := by_name.get("Wheel_RL") as Node3D
	var rr := by_name.get("Wheel_RR") as Node3D
	if fl == null or fr == null or rl == null or rr == null:
		check(false, "wheel layout")
		return
	var base := rl.position.z - fl.position.z
	var front := fr.position.x - fl.position.x
	var rear := rr.position.x - rl.position.x
	var ok := absf(base - WHEELBASE) < 0.02 and absf(front - FRONT_TRACK) < 0.01 \
		and absf(rear - REAR_TRACK) < 0.01 and absf(fl.position.x + fr.position.x) < 0.002 \
		and absf(rl.position.x + rr.position.x) < 0.002 and absf(fl.position.z + rl.position.z) < 0.01
	check(ok, "wheelbase %.3f, track %.3f / %.3f, the middle of the wheelbase is the origin"
		% [base, front, rear])
	for pair in [["Caliper_FL", fl], ["Caliper_FR", fr], ["Caliper_RL", rl], ["Caliper_RR", rr]]:
		var caliper := by_name.get(pair[0]) as Node3D
		if caliper == null or not caliper.position.is_equal_approx((pair[1] as Node3D).position):
			ok = false
	check(ok, "the calipers sit on the hubs of their wheels")


## the _L parts on the left (-X), the _R parts on the right
func check_layout(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	for n in by_name.keys():
		var s := str(n)
		if not (s.ends_with("_L") or s.ends_with("_R") or s.ends_with("_FL") or s.ends_with("_FR")
				or s.ends_with("_RL") or s.ends_with("_RR")):
			continue
		if s in ["Bumper_R", "Bumper_F"] or s.begins_with("Nozzle") or s.begins_with("Light_"):
			continue
		var mi := mesh(by_name, s)
		if mi == null:
			continue
		var left := s.ends_with("L")
		var cx := world_aabb(mi).get_center().x
		if left and cx > -0.001:
			wrong.append("%s (x=%.3f)" % [s, cx])
		if not left and cx < 0.001:
			wrong.append("%s (x=%.3f)" % [s, cx])
	check(wrong.is_empty(), "left parts on the left, right parts on the right%s"
		% ["" if wrong.is_empty() else " (wrong: %s)" % ", ".join(wrong)])

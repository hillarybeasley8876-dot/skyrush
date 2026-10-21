extends Node
## npc_cars node and geometry contract test (unit: npc_cars).
##
## Every fleet model must expose the node names the game relies on
## (CONTRACTS.md §6 + the unit brief), sit on the ground, carry its lamps on
## the right end, keep its number plate readable, and stay inside the
## triangle budget of the brief.
##
##     tools/godot.sh test res://assets/cars/npc/tests/test_npc_nodes.gd

const GROUND_NODES := ["Body", "Glass", "Bumper_F", "Bumper_R", "Lamp_F", "Lamp_R",
	"Light_Front", "Light_Rear"]
const WHEEL_NODES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
const EXTRA_NODES := {
	"sedan_ev": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior"],
	"suv_ev": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior"],
	"hatch_ev": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior"],
	"taxi": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior",
		"RoofSign"],
	"robotaxi": ["Door_FL", "Door_FR", "Interior", "LiDAR"],
	"police_patrol": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior",
		"LightBar", "LightBar_Red", "LightBar_Blue", "Siren"],
	"police_interceptor": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR",
		"Interior", "LightBar_Red", "LightBar_Blue", "Siren", "Splitter"],
	"police_suv": ["Hood", "Door_FL", "Door_FR", "Door_RL", "Door_RR", "Interior",
		"LightBar_Red", "LightBar_Blue", "Siren", "RamBar"],
	"van": ["Interior", "Door_FL", "Door_FR", "Livery"],
	"truck": ["Interior", "Door_FL", "Door_FR"],
	"bus": ["Interior", "SignRoute", "SignRouteSide", "Door_FR", "Door_RR", "Roof"],
	"police_drone": ["Spot", "Strobe_Red", "Strobe_Blue", "Rotor_FL", "Rotor_FR",
		"Rotor_RL", "Rotor_RR"],
}

const BUDGET := {
	"sedan_ev": 25000, "suv_ev": 25000, "hatch_ev": 25000, "taxi": 25000,
	"robotaxi": 25000, "police_patrol": 30000, "police_interceptor": 30000,
	"police_suv": 30000, "van": 30000, "truck": 30000, "bus": 30000,
	"police_drone": 8000,
}
# The shared body generator (lib/car_body.py) puts the underbody and the
# rocker cladding in their own material slot and the wheels carry a tyre and
# an alloy rim, so a car has more surfaces than the flat r3 fleet.
const MAX_SURFACES := {
	"sedan_ev": 36, "suv_ev": 36, "hatch_ev": 36, "taxi": 44, "robotaxi": 36,
	"police_patrol": 40, "police_interceptor": 42, "police_suv": 42,
	"van": 26, "truck": 26, "bus": 28, "police_drone": 20,
}
# nothing may go under the road (r3 item 7)
const MIN_Y := -0.005


func _ready() -> void:
	var ok := true
	for model_name in EXTRA_NODES:
		ok = _check_model(model_name) and ok
	get_tree().quit(0 if ok else 1)


func _check_model(model_name: String) -> bool:
	var ok := true
	var path := "res://assets/cars/npc/%s.glb" % model_name
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL %s does not load" % model_name)
		return false
	var root := packed.instantiate()
	add_child(root)
	var names := _collect(root)
	var required: Array[String] = []
	if model_name != "police_drone":
		required.append_array(GROUND_NODES)
		required.append_array(WHEEL_NODES)
	required.append_array(EXTRA_NODES[model_name])
	var missing: Array[String] = []
	for node_name in required:
		if not names.has(node_name):
			missing.append(node_name)
	if missing.is_empty():
		print("PASS %s has all %d contract nodes" % [model_name, required.size()])
	else:
		print("FAIL %s missing %s" % [model_name, ", ".join(missing)])
		ok = false
	if not names.has(model_name):
		print("FAIL %s root node is not named after the file" % model_name)
		ok = false
	var dupes := _duplicates(root)
	if not dupes.is_empty():
		print("FAIL %s duplicate node names: %s" % [model_name, ", ".join(dupes)])
		ok = false
	ok = _check_lamp_ends(root, model_name) and ok
	ok = _check_on_ground(root, model_name) and ok
	if model_name != "police_drone":
		ok = _check_plate_in_front(root, model_name) and ok
		ok = _check_front_plate_readable(root, model_name) and ok
	ok = _check_door_tops(root, model_name) and ok
	if model_name == "bus":
		ok = _check_bus(root) and ok
	if model_name.begins_with("police_") and model_name != "police_drone":
		ok = _check_police_livery(root, model_name) and ok
	var surfaces := _surface_count(root)
	var max_surfaces: int = MAX_SURFACES[model_name]
	if surfaces > max_surfaces:
		print("FAIL %s has %d surfaces (max %d)" % [model_name, surfaces, max_surfaces])
		ok = false
	else:
		print("PASS %s surfaces=%d tris=%d" % [model_name, surfaces, _triangles(root)])
	var tris := _triangles(root)
	var budget: int = BUDGET[model_name]
	if tris > budget:
		print("FAIL %s has %d tris (budget %d)" % [model_name, tris, budget])
		ok = false
	root.queue_free()
	return ok


func _check_lamp_ends(root: Node, model_name: String) -> bool:
	"""Godot -Z is forward, so the front lamp sits at negative z."""
	if model_name == "police_drone":
		return true
	var ok := true
	var lamp_f := _aabb_centre(root, "Lamp_F")
	var lamp_r := _aabb_centre(root, "Lamp_R")
	if lamp_f.is_empty() or lamp_r.is_empty():
		print("FAIL %s is missing a lamp" % model_name)
		return false
	if (lamp_f[1] as Vector3).z >= 0.0:
		print("FAIL %s Lamp_F is at z=%.2f (the front is -Z)"
				% [model_name, (lamp_f[1] as Vector3).z])
		ok = false
	if (lamp_r[1] as Vector3).z <= 0.0:
		print("FAIL %s Lamp_R is at z=%.2f (the rear is +Z)"
				% [model_name, (lamp_r[1] as Vector3).z])
		ok = false
	if ok:
		print("PASS %s lamps are on the right ends" % model_name)
	return ok


func _check_on_ground(root: Node, model_name: String) -> bool:
	"""No mesh may reach under the road (r3 item 7).

	The drone flies, so it is not on the road.
	"""
	var ok := true
	if model_name == "police_drone":
		return true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var low := (mi.global_transform * mi.get_aabb()).position.y
		if low < MIN_Y:
			print("FAIL %s %s reaches y=%.3f (the floor is %.3f)"
					% [model_name, mi.name, low, MIN_Y])
			ok = false
	if ok:
		print("PASS %s everything is on the ground" % model_name)
	return ok


func _check_plate_in_front(root: Node, model_name: String) -> bool:
	"""The number plate must be the front-most surface of the nose and tail."""
	var ok := true
	for front in [true, false]:
		var plate := _aabb(root, "Plate")
		if plate.is_empty():
			print("FAIL %s is missing the plate" % model_name)
			return false
		var pbox: AABB = plate[1]
		var y0 := pbox.position.y - 0.02
		var y1 := pbox.end.y + 0.02
		var plate_z := _frontmost(root, "Plate", y0, y1, front)
		if is_inf(plate_z):
			print("FAIL %s the plate has no vertices" % model_name)
			ok = false
			continue
		for child in root.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null or String(mi.name) == "Plate":
				continue
			var other := _frontmost_one(mi, y0, y1, front)
			if is_inf(other):
				continue
			if front and other < plate_z - 0.001:
				print("FAIL %s %s is in front of the plate" % [model_name, mi.name])
				ok = false
			if not front and other > plate_z + 0.001:
				print("FAIL %s %s is behind the plate" % [model_name, mi.name])
				ok = false
	if ok:
		print("PASS %s the plates are the front-most surfaces" % model_name)
	return ok


func _check_front_plate_readable(root: Node, model_name: String) -> bool:
	"""On the front plate the u must grow towards the viewer's right (r3 item 6).

	The viewer of a -Z face sees +X on their left, so u has to fall when x
	rises: the characters must not be mirrored.
	"""
	var ok := true
	for child in root.find_children("Plate", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if verts.is_empty() or uvs.is_empty():
				continue
			# the outer skin of the plate: the biggest u at the smallest x
			# must be bigger than the biggest u at the largest x
			var min_x := 99.0
			var max_x := -99.0
			for k in range(verts.size()):
				if verts[k].z > 0.0:
					continue      # the rear plate reads the other way round
				min_x = minf(min_x, verts[k].x)
				max_x = maxf(max_x, verts[k].x)
			if min_x > 90.0 or max_x < -90.0:
				continue
			var left_u := -1.0
			var right_u := -1.0
			for k in range(verts.size()):
				if verts[k].z > 0.0:
					continue
				if absf(verts[k].x - min_x) < 0.005:
					left_u = maxf(left_u, uvs[k].x)
				if absf(verts[k].x - max_x) < 0.005:
					right_u = maxf(right_u, uvs[k].x)
			if left_u < 0.0 or right_u < 0.0:
				continue
			if left_u <= right_u:
				print("FAIL %s the front plate is mirrored (u %.3f at -X, %.3f at +X)"
						% [model_name, left_u, right_u])
				ok = false
	if ok:
		print("PASS %s the front plate is not mirrored" % model_name)
	return ok


func _check_bus(root: Node) -> bool:
	"""The bus: the bumpers sit low and the route sign uses its whole image."""
	var ok := true
	for node_name in ["Bumper_F", "Bumper_R"]:
		var box := _aabb(root, node_name)
		if box.is_empty():
			print("FAIL bus is missing %s" % node_name)
			ok = false
			continue
		var top: float = (box[1] as AABB).end.y
		if top > 0.9:
			print("FAIL bus %s reaches %.2f m (the bumpers belong at the bottom)"
					% [node_name, top])
			ok = false
	var sign := _aabb(root, "SignRoute")
	if sign.is_empty():
		print("FAIL bus is missing SignRoute")
		ok = false
	if ok:
		print("PASS bus the bumpers are low and the route sign is there")
	return ok


func _check_door_tops(root: Node, model_name: String) -> bool:
	"""The left and the right doors must have the same belt line."""
	var ok := true
	for tag in ["F", "R"]:
		var left := _aabb(root, "Door_%sL" % tag)
		var right := _aabb(root, "Door_%sR" % tag)
		if left.is_empty() or right.is_empty():
			continue
		var dl: float = (left[1] as AABB).end.y
		var dr: float = (right[1] as AABB).end.y
		if absf(dl - dr) > 0.005:
			print("FAIL %s Door_%sL (%.3f) and Door_%sR (%.3f) differ"
					% [model_name, tag, dl, tag, dr])
			ok = false
	if ok:
		print("PASS %s the doors are level" % model_name)
	return ok


func _check_police_livery(root: Node, model_name: String) -> bool:
	"""Every police car carries the livery paint on its second UV set."""
	var ok := true
	for child in root.find_children("Body", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var named := false
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat != null and String(mat.resource_name) == "SH_car_paint_police":
				named = true
			var arrays := mi.mesh.surface_get_arrays(i)
			if arrays[Mesh.ARRAY_TEX_UV2] == null \
					or (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).is_empty():
				print("FAIL %s the body has no livery UV set" % model_name)
				ok = false
		if not named:
			print("FAIL %s the body does not use SH_car_paint_police" % model_name)
			ok = false
	if ok:
		print("PASS %s carries the police livery" % model_name)
	return ok


func _frontmost(root: Node, node_name: String, y0: float, y1: float,
		front: bool) -> float:
	for child in root.find_children(node_name, "MeshInstance3D", true, false):
		return _frontmost_one(child as MeshInstance3D, y0, y1, front)
	return INF


func _frontmost_one(mi: MeshInstance3D, y0: float, y1: float, front: bool) -> float:
	"""The most extreme z of the mesh vertices inside a height band."""
	var best := INF if front else -INF
	for i in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y < y0 or v.y > y1:
				continue
			if front:
				best = min(best, v.z)
			else:
				best = max(best, v.z)
	return best


func _aabb_centre(node: Node, node_name: String) -> Array:
	"""[found, centre] of a named mesh, or an empty array."""
	for child in node.find_children(node_name, "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		return [true, mi.get_aabb().get_center()]
	return []


func _aabb(node: Node, node_name: String) -> Array:
	"""[found, aabb] of a named mesh, or an empty array."""
	for child in node.find_children(node_name, "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		return [true, mi.get_aabb()]
	return []


func _surface_count(node: Node) -> int:
	var total := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh != null:
			total += mi.mesh.get_surface_count()
	return total


func _triangles(node: Node) -> int:
	var total := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			var idx: Array = arrays[Mesh.ARRAY_INDEX]
			var count: int = idx.size()
			if count == 0:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				count = verts.size()
			total += count / 3
	return total


func _collect(node: Node) -> Array:
	var out: Array = []
	if node.name != "":
		out.append(String(node.name))
	for child in node.get_children():
		out.append_array(_collect(child))
	return out


func _duplicates(node: Node) -> Array:
	"""Every node name in the tree must be unique (Godot renames '.' to '_')."""
	var seen := {}
	var out: Array = []
	for name in _collect(node):
		var key := String(name)
		if seen.has(key):
			if not out.has(key):
				out.append(key)
		seen[key] = true
	return out

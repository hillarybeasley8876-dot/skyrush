extends Node
## npc_cars node and geometry contract test.
##
## The fleet is made of realistic CC BY 4.0 / CC0 models (Daniel Zhabotinsky's Kiri '10, Ace '11, Urban '10 and Light Commercial
## Truck '07, Comrade1280's minivan, denniswoo1993's SHC MC, Grab3D's city bus; CREDITS.md), converted by
## blender/npc_cars/web/convert_real.py (the drone is the procedural model of the old generator). Every model must expose the
## node names the game relies on (CONTRACTS.md 6, the traffic lamps, the police light bar, the damage parts), stand on the
## ground, carry its lamps on the right end, have its wheels where the physics expects them, match the dimensions of the fleet
## table, and stay inside the triangle budget.
##
##     python tools/gd.py test res://assets/cars/npc/tests/test_npc_nodes.gd

const CARS := ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "robotaxi", "van", "truck", "bus",
	"police_patrol", "police_interceptor", "police_suv"]
const GROUND_NODES := ["Body", "Glass", "Lamp_F", "Lamp_R", "Light_Front", "Light_Rear", "Mirror_L", "Mirror_R"]
const WHEEL_NODES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
const POLICE_NODES := ["LightBar_Red", "LightBar_Blue", "Siren"]
## The parts that the damage unit tears off (damage/part_catalog.gd looks for these exact names): every car has the two bumpers, the
## cars with a bonnet have the Hood.
const PART_NODES := ["Bumper_F", "Bumper_R"]
const HOOD_CARS := ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "police_patrol", "police_interceptor", "police_suv"]
const DRONE_NODES := ["Spot", "Strobe_Red", "Strobe_Blue", "Rotor_FL", "Rotor_FR", "Rotor_RL", "Rotor_RR"]
## The triangles of a car: CONTRACTS.md 2 allows an NPC car 25 k and a police car 30 k, briefs/npc_cars.md a bus or a truck
## 30 k (the cars are 7-24 k).
const CAR_BUDGET := 25000
const POLICE_BUDGET := 30000
const BIG_BUDGET := 30000
const BIG_CARS := ["bus", "truck"]
## The surfaces of a car. A surface is a draw call, and the traffic runs up to 90 cars: the body (its paint, one black and a
## chrome or silver trim), the glass, the lenses, the mirrors, the three tear-off parts and the wheels (a tyre and a rim each)
## make 20-25; a police car adds the navy band and the yellow stripe of its livery and the two halves of its light bar.
const CAR_SURFACES := 26
const POLICE_SURFACES := 30
const DRONE_BUDGET := 8000
const DRONE_SURFACES := 20
## How far the Body may differ from the fleet table of the traffic (m): the mirrors are not part of the Body.
const TABLE_TOLERANCE := 0.12
## nothing may go under the road
const MIN_Y := -0.005
## The wheel centre is the wheel radius above the road (m), within this tolerance.
const WHEEL_TOLERANCE := 0.06


func _ready() -> void:
	var ok := true
	for model_name in CARS:
		ok = _check_car(model_name) and ok
	ok = _check_drone() and ok
	get_tree().quit(0 if ok else 1)


func _load(model_name: String) -> Node:
	var packed := load("res://assets/cars/npc/%s.glb" % model_name) as PackedScene
	if packed == null:
		print("FAIL %s does not load" % model_name)
		return null
	var root := packed.instantiate()
	add_child(root)
	return root


func _check_car(model_name: String) -> bool:
	var root := _load(model_name)
	if root == null:
		return false
	var ok := true
	var names := _collect(root)
	var required: Array[String] = []
	required.append_array(GROUND_NODES)
	required.append_array(WHEEL_NODES)
	required.append_array(PART_NODES)
	if HOOD_CARS.has(model_name):
		required.append("Hood")
	if model_name.begins_with("police_"):
		required.append_array(POLICE_NODES)
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
	ok = _check_wheels(root, model_name) and ok
	ok = _check_fleet_table(root, model_name) and ok
	ok = _check_mirrors(root, model_name) and ok
	ok = _check_parts(root, model_name) and ok
	var surfaces := _surface_count(root)
	var tris := _triangles(root)
	var police := model_name.begins_with("police_")
	var max_surfaces := POLICE_SURFACES if police else CAR_SURFACES
	var budget := POLICE_BUDGET if police else (BIG_BUDGET if BIG_CARS.has(model_name) else CAR_BUDGET)
	if surfaces > max_surfaces or tris > budget:
		print("FAIL %s has %d surfaces (max %d) and %d triangles (budget %d)"
				% [model_name, surfaces, max_surfaces, tris, budget])
		ok = false
	else:
		print("PASS %s surfaces=%d tris=%d" % [model_name, surfaces, tris])
	root.queue_free()
	return ok


func _check_drone() -> bool:
	var root := _load("police_drone")
	if root == null:
		return false
	var ok := true
	var names := _collect(root)
	for node_name in DRONE_NODES:
		if not names.has(node_name):
			print("FAIL police_drone missing %s" % node_name)
			ok = false
	var surfaces := _surface_count(root)
	var tris := _triangles(root)
	if surfaces > DRONE_SURFACES or tris > DRONE_BUDGET:
		print("FAIL police_drone has %d surfaces and %d triangles" % [surfaces, tris])
		ok = false
	if ok:
		print("PASS police_drone has its nodes (surfaces=%d tris=%d)" % [surfaces, tris])
	root.queue_free()
	return ok


## Godot -Z is forward, so the front lamp sits at negative z.
func _check_lamp_ends(root: Node, model_name: String) -> bool:
	var lamp_f := _aabb(root, "Lamp_F")
	var lamp_r := _aabb(root, "Lamp_R")
	if lamp_f.is_empty() or lamp_r.is_empty():
		print("FAIL %s is missing a lamp" % model_name)
		return false
	var ok := true
	var front: Vector3 = ((lamp_f[0] as Transform3D) * (lamp_f[1] as AABB)).get_center()
	var rear: Vector3 = ((lamp_r[0] as Transform3D) * (lamp_r[1] as AABB)).get_center()
	if front.z >= 0.0:
		print("FAIL %s Lamp_F is at z=%.2f (the front is -Z)" % [model_name, front.z])
		ok = false
	if rear.z <= 0.0:
		print("FAIL %s Lamp_R is at z=%.2f (the rear is +Z)" % [model_name, rear.z])
		ok = false
	if ok:
		print("PASS %s lamps are on the right ends" % model_name)
	return ok


## No mesh may reach under the road.
func _check_on_ground(root: Node, model_name: String) -> bool:
	var ok := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var low := (mi.global_transform * mi.get_aabb()).position.y
		if low < MIN_Y:
			print("FAIL %s %s reaches y=%.3f (the floor is %.3f)" % [model_name, mi.name, low, MIN_Y])
			ok = false
	if ok:
		print("PASS %s everything is on the ground" % model_name)
	return ok


## The wheel nodes are the contract of the car physics: the origin is the centre of the wheel (the radius over the road), the
## left wheels are at -X, the front wheels at -Z, and the wheels of an axle are mirror images.
func _check_wheels(root: Node, model_name: String) -> bool:
	var ok := true
	var centres := {}
	for wheel_name in WHEEL_NODES:
		var wheel := root.find_child(wheel_name, true, false) as Node3D
		if wheel == null:
			continue
		var mesh := wheel as MeshInstance3D
		var radius := mesh.get_aabb().size.y * 0.5 if mesh != null else 0.0
		centres[wheel_name] = wheel.global_position
		if absf(wheel.global_position.y - radius) > WHEEL_TOLERANCE:
			print("FAIL %s %s is at y=%.3f, its radius is %.3f" % [model_name, wheel_name, wheel.global_position.y, radius])
			ok = false
		if mesh != null and absf(mesh.get_aabb().get_center().x) > 0.02:
			print("FAIL %s %s is not centred on its origin (x %.3f)" % [model_name, wheel_name, mesh.get_aabb().get_center().x])
			ok = false
	if centres.size() == 4:
		var fl: Vector3 = centres["Wheel_FL"]
		var fr: Vector3 = centres["Wheel_FR"]
		var rl: Vector3 = centres["Wheel_RL"]
		var rr: Vector3 = centres["Wheel_RR"]
		if not (fl.x < 0.0 and rl.x < 0.0 and fr.x > 0.0 and rr.x > 0.0):
			print("FAIL %s the left wheels have to be at -X" % model_name)
			ok = false
		if not (fl.z < rl.z and fr.z < rr.z):
			print("FAIL %s the front wheels have to be at -Z" % model_name)
			ok = false
		if absf(fl.x + fr.x) > 0.02 or absf(rl.x + rr.x) > 0.02 or absf(fl.z - fr.z) > 0.02 or absf(rl.z - rr.z) > 0.02:
			print("FAIL %s the wheels of an axle are not mirror images" % model_name)
			ok = false
	if ok:
		print("PASS %s the wheels are where the physics expects them" % model_name)
	return ok


## The Body (without the mirrors) is the size that the fleet table of the traffic says: the box collider and the gaps are made from
## either of them.
func _check_fleet_table(root: Node, model_name: String) -> bool:
	var entry := {}
	for id: StringName in TrafficFleet.MODELS:
		var data: Dictionary = TrafficFleet.MODELS[id]
		if String(data["glb"]) == model_name:
			entry = data
	if entry.is_empty():
		return true       # the police cars are not in the table of the traffic
	var body := _aabb(root, "Body")
	if body.is_empty():
		return false
	var box: AABB = body[1]
	var ok := true
	for pair in [["length", box.size.z], ["width", box.size.x], ["height", box.end.y]]:
		var want := float(entry[String(pair[0])])
		if absf(want - float(pair[1])) > TABLE_TOLERANCE:
			print("FAIL %s Body %s %.2f but the traffic table says %.2f" % [model_name, pair[0], pair[1], want])
			ok = false
	if ok:
		print("PASS %s matches the fleet table of the traffic" % model_name)
	return ok


## The mirrors stand outside the Body: the box collider is measured from the Body.
func _check_mirrors(root: Node, model_name: String) -> bool:
	var body := _aabb(root, "Body")
	var left := _aabb(root, "Mirror_L")
	var right := _aabb(root, "Mirror_R")
	if body.is_empty() or left.is_empty() or right.is_empty():
		return false
	var box: AABB = body[1]
	var ok := true
	if (left[1] as AABB).position.x > box.position.x or (right[1] as AABB).end.x < box.end.x:
		print("FAIL %s the mirrors do not reach out of the Body" % model_name)
		ok = false
	if ok:
		print("PASS %s the mirrors are outside the Body" % model_name)
	return ok


## The tear-off parts sit on the origin of the car (the damage unit reads the side of a part from its mesh, the hanging bumper turns
## about the corner of its AABB), the bumpers are at the ends of the car and the Hood is in front of the middle.
func _check_parts(root: Node, model_name: String) -> bool:
	var ok := true
	for part_name: String in PART_NODES + ["Hood"]:
		var mi := root.find_child(part_name, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue            # a missing part is reported by the node check
		if mi.position.length() > 0.01:
			print("FAIL %s %s is not on the origin of the car: %s" % [model_name, part_name, mi.position])
			ok = false
		var centre: Vector3 = (mi.global_transform * mi.get_aabb()).get_center()
		var wanted := 0.0
		match part_name:
			"Bumper_F":
				wanted = -1.0
			"Bumper_R":
				wanted = 1.0
			"Hood":
				wanted = -1.0
		if centre.z * wanted < 0.4 and part_name != "Hood" or part_name == "Hood" and centre.z * wanted < 0.2:
			print("FAIL %s %s is at z=%.2f (it belongs at %s)" % [model_name, part_name, centre.z, "the front" if wanted < 0.0 else "the rear"])
			ok = false
		if mi.mesh.get_surface_count() == 0:
			print("FAIL %s %s is empty" % [model_name, part_name])
			ok = false
	if ok:
		print("PASS %s the tear-off parts are on the origin and at their ends" % model_name)
	return ok


## [transform, aabb] of a named mesh, or an empty array.
func _aabb(node: Node, node_name: String) -> Array:
	for child in node.find_children(node_name, "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		return [mi.global_transform, mi.get_aabb()]
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


## Every node name in the tree must be unique (Godot renames '.' to '_').
func _duplicates(node: Node) -> Array:
	var seen := {}
	var out: Array = []
	for name in _collect(node):
		var key := String(name)
		if seen.has(key):
			if not out.has(key):
				out.append(key)
		seen[key] = true
	return out

extends RefCounted
## The detachable parts of a car (dossier §7.6): it finds the named parts of the car, decides
## which one the hit takes off and spawns it as debris.
##
## Only the exact names of CONTRACTS §6 (and of the npc cars) are parts: the child meshes of
## a part ("Wing_EndPlate_L") and the interior meshes ("DoorCard_L") are not.

const Parts := preload("res://damage/part_catalog.gd")
const CarDamage := preload("res://damage/car_damage.gd")
const Contact := preload("res://damage/contact.gd")
const DentMaterials := preload("res://damage/dent_materials.gd")

## The debris pool the parts fly into.
var debris: Node = null
## The part nodes of the cars, cached (a hit must not walk the whole visual).
var _nodes: Dictionary = {}


## Looks for the parts of the car that the hit may tear off and detaches the ones that go.
## `own_velocity` is the velocity of the car before the hit: the debris flies with the car
## as it was, not with the speed it had after the impact.
func check(car: VehicleBase, state: CarDamage, contact: Contact, v_n: float,
		impact: float, own_velocity: Vector3 = Vector3.ZERO) -> void:
	for entry in part_nodes(car):
		var node_name: StringName = entry["name"]
		if state.is_detached(node_name):
			continue
		var part := Parts.part_for(node_name)
		if part.is_empty():
			continue
		# The parts that only come off with a violent wreck are handled by `detach_wheel`,
		# so a wreck does not take every wheel of the car off.
		if StringName(part.get("mode", Parts.MODE_DETACH)) == Parts.MODE_WRECK:
			continue
		if not same_side(car, entry, contact):
			continue
		var zone: int = contact.zone
		var cumulative := state.zone_total(zone_key(zone))
		if not Parts.should_detach(part, zone, v_n, cumulative, car.is_wrecked, impact):
			continue
		if StringName(part.get("mode", Parts.MODE_DETACH)) == Parts.MODE_SPRING:
			_spring_open(car, state, entry)
			continue
		detach(car, state, entry, part, own_velocity)


## The mesh nodes of the car that the part catalogue knows.
func part_nodes(car: VehicleBase) -> Array:
	var id := car.get_instance_id()
	if _nodes.has(id):
		return _nodes[id] as Array
	var found: Array = []
	var visual := car.get_visual_root()
	if visual != null:
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node == null:
				continue
			var name := StringName(mesh_node.name.get_slice(".", 0))
			if Parts.part_for(name).is_empty():
				continue
			found.append({"name": name, "node": mesh_node})
	_nodes[id] = found
	return found


## A side part only comes off when the side it is on was hit. The side is read from the
## centre of the mesh, not from the origin of the node (the npc doors sit on the car origin).
func same_side(car: VehicleBase, entry: Dictionary, contact: Contact) -> bool:
	var zone: int = contact.zone
	if zone != Parts.Zone.SIDE:
		return true
	var node := entry["node"] as MeshInstance3D
	if node == null:
		return true
	var local := car.global_transform.affine_inverse() * _mesh_centre(node)
	var hit_x := contact.local_point.x
	if absf(local.x) < 0.01 or absf(hit_x) < 0.01:
		return true
	return signf(local.x) == signf(hit_x)


## The name of the zone the damage of a hit is counted under.
static func zone_key(zone: int) -> StringName:
	match zone:
		Parts.Zone.FRONT:
			return CarDamage.ZONE_FRONT
		Parts.Zone.REAR:
			return CarDamage.ZONE_REAR
		Parts.Zone.SIDE:
			return CarDamage.ZONE_SIDE
		Parts.Zone.TOP:
			return CarDamage.ZONE_TOP
	return &"any"


## The door springs open on its hinge, it does not come off. It opens OUTWARDS, and only
## once: the sign is the one that takes the door away from the car.
func _spring_open(car: VehicleBase, state: CarDamage, entry: Dictionary) -> void:
	var node := entry["node"] as MeshInstance3D
	if node == null:
		return
	var name: StringName = entry["name"]
	if state.is_sprung(name):
		return
	state.mark_sprung(name)
	state.remember_rest(name, node.transform)
	var angle := deg_to_rad(Parts.DOOR_SPRING_ANGLE)
	node.transform = node.transform * Transform3D(Basis(Vector3.UP, _outward_sign(car, node) * angle),
			Vector3.ZERO)


## The sign of the rotation that opens the door outwards: the one that takes the centre of
## the door away from the middle of the car.
func _outward_sign(car: VehicleBase, node: MeshInstance3D) -> float:
	var local_centre := Vector3.ZERO
	if node.mesh != null:
		local_centre = node.mesh.get_aabb().get_center()
	var car_inv := car.global_transform.affine_inverse()
	var angle := deg_to_rad(Parts.DOOR_SPRING_ANGLE)
	var best := 1.0
	var best_x := -1.0
	for s: float in [1.0, -1.0]:
		var moved := node.transform * Transform3D(Basis(Vector3.UP, s * angle), Vector3.ZERO)
		var point := car_inv * (node.global_transform * (moved * local_centre))
		if absf(point.x) > best_x:
			best_x = absf(point.x)
			best = s
	return best


## The centre of the mesh of a node, in the world.
func _mesh_centre(node: MeshInstance3D) -> Vector3:
	if node.mesh == null:
		return node.global_position
	return node.global_transform * node.mesh.get_aabb().get_center()


## The part comes off: it disappears from the car at once and flies away as debris.
func detach(car: VehicleBase, state: CarDamage, entry: Dictionary, part: Dictionary,
		own_velocity: Vector3 = Vector3.ZERO) -> void:
	var node := entry["node"] as MeshInstance3D
	if node == null or debris == null:
		return
	var name: StringName = entry["name"]
	var group := _part_group(car, node, name)
	state.mark_detached(name, node)
	for mesh_node in group:
		(mesh_node as MeshInstance3D).visible = false
	# The debris is built after the hit: the spawn of a rigid body with its meshes costs
	# more than the whole budget of a hit (dossier §7.7).
	_spawn_debris.call_deferred(part, group, node, own_velocity)


## The part flies away as debris (a frame after the hit, so the hit stays cheap).
func _spawn_debris(part: Dictionary, group: Array, node: MeshInstance3D,
		own_velocity: Vector3) -> void:
	if debris == null or node == null or not is_instance_valid(node):
		return
	debris.spawn(_debris_spec(part, group, node), node.global_transform, own_velocity)


## The meshes that come off with the part: the node, its children and its "_Inner" sibling.
func _part_group(car: VehicleBase, node: MeshInstance3D, name: StringName) -> Array:
	var group: Array = [node]
	for child in node.find_children("*", "MeshInstance3D", true, false):
		group.append(child as MeshInstance3D)
	var inner := node.get_parent().find_child(String(name) + "_Inner", true, false)
	if inner is MeshInstance3D:
		group.append(inner as MeshInstance3D)
	return group


## The debris of a part: its meshes, their materials and the box that carries them.
func _debris_spec(part: Dictionary, group: Array, root: MeshInstance3D) -> Dictionary:
	var root_inv := root.global_transform.affine_inverse()
	var meshes: Array = []
	var box := AABB()
	var first := true
	for mesh_node: MeshInstance3D in group:
		if mesh_node.mesh == null:
			continue
		var local := root_inv * mesh_node.global_transform
		var mesh_box := local * mesh_node.mesh.get_aabb()
		if first:
			box = mesh_box
			first = false
		else:
			box = box.merge(mesh_box)
		meshes.append({
			"mesh": mesh_node.mesh,
			"node": mesh_node,
			"transform": local,
			"instance": _instance_uniforms(mesh_node),
			"materials": _clean_materials(mesh_node),
		})
	var size := Vector3(
		maxf(box.size.x, 0.03), maxf(box.size.y, 0.03), maxf(box.size.z, 0.03))
	return {
		"meshes": meshes,
		"size": size,
		"centre": box.get_center(),
		"mass": float(part.get("mass", 10.0)),
		"shape": StringName(part.get("shape", Parts.BOX)),
	}


## The instance uniforms of a mesh (the paint colour of a car is one of them): the debris
## wears the colour of the car it came from.
func _instance_uniforms(node: MeshInstance3D) -> Dictionary:
	var out: Dictionary = {}
	for name in Parts.INSTANCE_UNIFORMS:
		var value: Variant = node.get_instance_shader_parameter(name)
		if value != null:
			out[name] = value
	return out


## The materials a mesh had before the damage unit replaced them: a flying part must not
## carry the dent field of the car it came from.
func _clean_materials(node: MeshInstance3D) -> Array:
	var out: Array = []
	if node.mesh == null:
		return out
	for i in node.mesh.get_surface_count():
		out.append(DentMaterials.clean_of(node.get_active_material(i)))
	return out


## The wheel that comes off a violent wreck: the one nearest the hit, and only that one.
func detach_wheel(car: VehicleBase, state: CarDamage) -> void:
	var part := Parts.part_for(&"Wheel_FL")
	if part.is_empty() or debris == null:
		return
	if state.wreck_impact < Parts.WHEEL_IMPACT:
		return
	var best: Dictionary = {}
	var best_distance := INF
	for entry in part_nodes(car):
		var name: StringName = entry["name"]
		if not String(name).begins_with("Wheel") or state.is_detached(name):
			continue
		var node := entry["node"] as MeshInstance3D
		if node == null:
			continue
		var distance := node.global_position.distance_to(state.wreck_point)
		if distance < best_distance:
			best_distance = distance
			best = entry
	if best.is_empty():
		return
	var node := best["node"] as MeshInstance3D
	var name: StringName = best["name"]
	state.mark_detached(name, node)
	node.visible = false
	# The wheel flies away after the hit, like every other debris (dossier §7.7).
	_spawn_wheel.call_deferred(part, node, state.pre_crash_velocity)
	_tilt_on_hub(car, node)


## The wheel flies away as debris (a frame after the wreck, so the hit stays cheap).
func _spawn_wheel(part: Dictionary, node: MeshInstance3D, velocity: Vector3) -> void:
	if debris == null or node == null or not is_instance_valid(node):
		return
	debris.spawn(_wheel_spec(part, node), node.global_transform, velocity)


## The debris of a wheel: a cylinder that lies down, its height is the width of the wheel
## and its radius half of its diameter.
func _wheel_spec(part: Dictionary, node: MeshInstance3D) -> Dictionary:
	var spec := _debris_spec(part, [node], node)
	var box := AABB()
	if node.mesh != null:
		box = node.mesh.get_aabb()
	var radius := maxf(box.size.y, box.size.z) * 0.5
	spec["size"] = Vector3(maxf(box.size.x, 0.05), radius, radius)
	return spec


## The car leans on the bare hub: the visual drops on the corner that lost its wheel.
func _tilt_on_hub(car: VehicleBase, wheel: MeshInstance3D) -> void:
	var visual := car.get_visual_root()
	if visual == null or wheel.mesh == null:
		return
	var local := car.global_transform.affine_inverse() * wheel.global_position
	var side := signf(local.x)
	if absf(side) < 0.01:
		return
	var box := wheel.mesh.get_aabb()
	var drop := maxf(box.size.y, box.size.z) * 0.5
	var track := maxf(absf(local.x), 0.5)
	var angle := asin(clampf(drop / track, -1.0, 1.0))
	var pivot := Vector3(-side * track, 0.0, 0.0)
	var rotation := Basis(Vector3.BACK, side * angle)
	visual.transform = Transform3D(rotation * visual.transform.basis,
			rotation * (visual.transform.origin - pivot) + pivot)

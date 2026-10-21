extends RefCounted
## Reads the geometry of a car glb: the collision box of the body and the wheel centres and
## radii. The NPC CarSpec presets are generated from this (gen_specs.gd) and the test compares
## the presets against it (test_specs.gd), so the car mesh and the physics never drift apart.
##
## The glb contract (CONTRACTS.md 6): the car body is a "Body" node, the wheels are
## "Wheel_FL/FR/RL/RR" and their node origin is the wheel centre.

const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

## The names of the four wheels, in the car order.
const WHEEL_NAMES: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]


## The AABB of a node in its own local space: its own mesh plus the meshes of its children.
static func node_aabb(node: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			out = mesh.get_aabb()
			first = false
	for child in node.get_children():
		if child is MeshInstance3D:
			var child_mesh: Mesh = (child as MeshInstance3D).mesh
			if child_mesh == null:
				continue
			var box: AABB = child_mesh.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	if first:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	return out


## The radius of a wheel: half the height of its AABB (the glb wheels have their axis on X).
static func wheel_radius(node: Node3D) -> float:
	return maxf(node_aabb(node).size.y * 0.5, 0.1)


## The wheel centre of a car, in the car local space.
static func wheel_centre(model: Node3D, index: int) -> Vector3:
	var node: Node3D = model.find_child(WHEEL_NAMES[index], true, false) as Node3D
	if node == null:
		return Vector3.ZERO
	return node.position


## The suspension mount of a wheel: the wheel centre plus the rest length minus the static sag.
static func wheel_mount(model: Node3D, index: int) -> Vector3:
	return wheel_centre(model, index) + Vector3(0.0, SuspensionTuning.REST_LEN - SuspensionTuning.STATIC_SAG, 0.0)


## The collision box of the car body: the size and the height of the centre of the "Body" AABB.
## Returns an empty dictionary when the model has no body.
static func body_box(model: Node3D) -> Dictionary:
	var body: Node3D = model.find_child("Body", true, false) as Node3D
	if body == null:
		return {}
	var aabb: AABB = node_aabb(body)
	return {
		"size": aabb.size,
		"centre_y": aabb.position.y + aabb.size.y * 0.5,
	}

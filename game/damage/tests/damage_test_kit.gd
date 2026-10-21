extends RefCounted
## The helpers of the damage tests: a stub car with a painted body, a collision box and the
## named parts of CONTRACTS.md 6, so the unit can be driven without the vehicle unit.

const PAINT_PATH := "res://shaders/materials/SH_car_paint.tres"
const BODY_SIZE := Vector3(1.95, 0.80, 4.38)


## A stub car. `parts` are the node names of the detachable panels it carries.
static func make_car(team: int, max_health: float, mass: float,
		parts: PackedStringArray = PackedStringArray()) -> VehicleBase:
	var car := VehicleBase.new()
	car.team = team as VehicleBase.Team
	car.max_health = max_health
	car.mass = mass
	car.collision_layer = 2
	car.collision_mask = 7
	car.contact_monitor = true
	car.max_contacts_reported = 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, 0.62, 0.0)
	car.add_child(shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	car.add_child(visual)
	_add_mesh(visual, "Body", BODY_SIZE, true)
	for part: String in parts:
		_add_mesh(visual, part, Vector3(0.4, 0.2, 0.3), false)
	return car


## A painted mesh with the shared car paint, so the dent painter can find it.
static func _add_mesh(parent: Node3D, mesh_name: String, size: Vector3, painted: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	var box := BoxMesh.new()
	box.size = size
	# A subdivided box: a panel of one quad cannot hold a dent.
	box.subdivide_width = 8
	box.subdivide_depth = 8
	box.subdivide_height = 2
	mesh.mesh = box
	if painted and ResourceLoader.exists(PAINT_PATH):
		mesh.material_override = load(PAINT_PATH).duplicate() as Material
	parent.add_child(mesh)


## A floor so the cars do not fall forever.
static func make_floor(parent: Node) -> StaticBody3D:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	floor.add_child(shape)
	parent.add_child(floor)
	return floor


## The damage director of the unit, ready to use.
static func make_director(parent: Node) -> Node:
	var scene := load("res://damage/damage_director.tscn") as PackedScene
	var director := scene.instantiate()
	parent.add_child(director)
	return director


## Waits for a number of physics frames.
static func wait_frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.physics_frame

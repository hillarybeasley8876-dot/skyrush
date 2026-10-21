extends RefCounted
## The stage of the fx demo (game/fx/demo/fx_demo.gd): the wet asphalt road, the guard rail
## and the street lamps. It is a script of its own, so the demo script stays a readable
## timeline of the beats.
##
## The sandbox ground is a grid plane half a metre above its own collider, so the demo builds
## its own road on top of it: the visible strip and the collider are both at ROAD_TOP, which is
## where the wheels of the car are. The skid marks therefore lie on the surface the camera sees.

const WET_ASPHALT := preload("res://shaders/materials/SH_wet_asphalt.tres")
const BARRIER_MATERIAL := preload("res://shaders/materials/SH_concrete_barrier.tres")

## The road strip of the demo: the car drives north (-Z) along it, through the charge lane.
const ROAD_CENTRE := Vector3(-420.0, 0.0, -1000.0)
const ROAD_WIDTH := 44.0
const ROAD_LENGTH := 2200.0
## The visible road sits on the top of the sandbox grid plane.
const ROAD_TOP := 0.56
## The thickness of the road slab.
const ROAD_THICKNESS := 0.6
## The lamps stand this far from the middle of the road, every LAMP_STEP metres.
const LAMP_OUT := 9.0
const LAMP_STEP := 30.0
const LAMP_COUNT := 12
const LAMP_HEIGHT := 5.0
## The energy and the range of a lamp: the night road needs a light, or the smoke, the spray
## and the skid marks have nothing to be seen against.
const LAMP_ENERGY := 6.0
const LAMP_RANGE := 26.0


## Builds the stage under `parent` and returns the guard rail (the scrape beat moves it).
func build(parent: Node3D) -> StaticBody3D:
	_build_road(parent)
	var barrier := _build_barrier(parent)
	_build_lamps(parent)
	return barrier


## The road: a collider and the visible strip.
func _build_road(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "RoadBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ROAD_WIDTH, ROAD_THICKNESS, ROAD_LENGTH)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(ROAD_CENTRE.x, ROAD_TOP - ROAD_THICKNESS * 0.5, ROAD_CENTRE.z)
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_WIDTH, ROAD_LENGTH)
	plane.material = WET_ASPHALT
	mesh.mesh = plane
	mesh.position = Vector3(ROAD_CENTRE.x, ROAD_TOP + 0.005, ROAD_CENTRE.z)
	mesh.name = "RoadMesh"
	parent.add_child(mesh)


## A concrete guard rail along the left side of the road: the scrape beat grinds the car
## along it (it moves the rail next to the car when the beat fires).
func _build_barrier(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Barrier"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.1, 120.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(ROAD_CENTRE.x - 1.6, ROAD_TOP + 0.55, ROAD_CENTRE.z - 40.0)
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	box_mesh.material = BARRIER_MATERIAL
	mesh.mesh = box_mesh
	body.add_child(mesh)
	return body


## The street lamps, on both sides of the road.
func _build_lamps(parent: Node3D) -> void:
	for i in LAMP_COUNT:
		var z := -80.0 - float(i) * LAMP_STEP
		for side: float in [-1.0, 1.0]:
			var pole := MeshInstance3D.new()
			var pole_mesh := BoxMesh.new()
			pole_mesh.size = Vector3(0.16, LAMP_HEIGHT, 0.16)
			var pole_mat := StandardMaterial3D.new()
			pole_mat.albedo_color = Color(0.13, 0.14, 0.16)
			pole_mat.roughness = 0.6
			pole_mesh.material = pole_mat
			pole.mesh = pole_mesh
			pole.position = Vector3(ROAD_CENTRE.x + side * LAMP_OUT, ROAD_TOP + LAMP_HEIGHT * 0.5, z)
			parent.add_child(pole)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.86, 0.62)
			lamp.light_energy = LAMP_ENERGY
			lamp.omni_range = LAMP_RANGE
			lamp.shadow_enabled = false
			lamp.position = Vector3(ROAD_CENTRE.x + side * (LAMP_OUT - 0.6),
					ROAD_TOP + LAMP_HEIGHT - 0.1, z)
			parent.add_child(lamp)

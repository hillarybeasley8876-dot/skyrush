extends SceneTree
## Generates the NPC CarSpec presets from the car glbs (the vehicle unit owns the presets).
##
## The wheel geometry comes from the glb: the Wheel_* node origin is the wheel centre and the
## tyre AABB gives the radius. The mount (the top of the suspension travel) is the wheel centre
## plus REST_LEN - STATIC_SAG. The body box comes from the Body AABB.
##
## Run: tools/godot.sh test res://vehicle/specs/gen_specs.gd
## (the file name of a preset is the car id, the glb is the model of that id)

const CarMesh := preload("res://vehicle/specs/car_mesh.gd")

## The cars: id -> [glb name, display name, hp, mass, top km/h, accel, brake, mu_f, mu_r].
const CARS: Dictionary = {
	"sedan": ["sedan_ev", "Traffic Sedan", 40.0, 1500.0, 180.0, 9.0, 14.0, 1.35, 1.32],
	"hatch_ev": ["hatch_ev", "Compact Hatch", 40.0, 1350.0, 170.0, 9.5, 14.0, 1.35, 1.32],
	"suv": ["suv_ev", "Compact SUV", 60.0, 2000.0, 190.0, 9.5, 15.0, 1.38, 1.35],
	"taxi": ["taxi", "Shanghai Taxi", 40.0, 1600.0, 175.0, 8.5, 14.0, 1.35, 1.30],
	"van": ["van", "Delivery Van", 60.0, 2400.0, 165.0, 7.5, 14.0, 1.32, 1.30],
	"truck": ["truck", "Box Truck", 150.0, 9000.0, 110.0, 3.5, 11.0, 1.25, 1.25],
	"bus": ["bus", "City Bus", 300.0, 12000.0, 120.0, 4.0, 10.0, 1.20, 1.20],
	"robotaxi": ["robotaxi", "Robotaxi", 60.0, 2100.0, 175.0, 8.0, 15.0, 1.36, 1.34],
	"patrol": ["police_patrol", "Patrol EV", 60.0, 1800.0, 230.0, 13.0, 16.0, 1.45, 1.42],
	"interceptor": ["police_interceptor", "Interceptor", 70.0, 1900.0, 290.0, 16.0, 17.0, 1.48, 1.45],
	"heavy_suv": ["police_suv", "Heavy SUV", 140.0, 2600.0, 210.0, 10.0, 18.0, 1.50, 1.45],
}


func _initialize() -> void:
	for id: String in CARS:
		var data: Array = CARS[id]
		var path: String = "res://assets/cars/npc/%s.glb" % data[0]
		if not ResourceLoader.exists(path):
			printerr("gen_specs: %s is missing" % path)
			continue
		var spec: CarSpec = _make_spec(id, path, data)
		if spec == null:
			continue
		var out: String = "res://vehicle/specs/%s.tres" % id
		var err: int = ResourceSaver.save(spec, out)
		if err != OK:
			printerr("gen_specs: cannot write %s (%d)" % [out, err])
			continue
		print("gen_specs: wrote %s" % out)
	quit(0)


## Builds the spec of one car from its glb.
func _make_spec(id: String, path: String, data: Array) -> CarSpec:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return null
	var spec := CarSpec.new()
	spec.id = StringName(id)
	spec.display_name = String(data[1])
	spec.mass = float(data[3])
	spec.max_health = float(data[2])
	spec.top_speed = float(data[4]) / 3.6
	spec.accel = float(data[5])
	spec.brake_accel = float(data[6])
	spec.mu_front = float(data[7])
	spec.mu_rear = float(data[8])
	spec.visual_scene_path = path
	# The suspension: the spring keeps the static sag at every mass, so a heavy car does not
	# sit on its bump stops (dossier 4.4).
	var suspension: Dictionary = CarSpec.suspension_for(spec.mass)
	spec.spring_k = float(suspension["spring_k"])
	spec.damp_bump = float(suspension["damp_bump"])
	spec.damp_rebound = float(suspension["damp_rebound"])
	spec.arb_front = float(suspension["arb_front"])
	spec.arb_rear = float(suspension["arb_rear"])
	spec.bumpstop_k = float(suspension["bumpstop_k"])
	spec.susp_max = float(suspension["susp_max"])
	spec.rest_len = float(suspension["rest_len"])
	spec.travel = float(suspension["travel"])
	# The wheels: the node origin is the wheel centre, the AABB gives the tyre radius.
	var mounts: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 4:
		var node: Node3D = model.find_child(CarMesh.WHEEL_NAMES[i], true, false) as Node3D
		if node == null:
			printerr("gen_specs: %s has no %s" % [id, CarMesh.WHEEL_NAMES[i]])
			model.free()
			return null
		mounts.append(CarMesh.wheel_mount(model, i))
		radii.append(CarMesh.wheel_radius(node))
	spec.wheel_mounts = mounts
	spec.wheel_radii = radii
	# The body box from the Body AABB.
	var box: Dictionary = CarMesh.body_box(model)
	if box.is_empty():
		printerr("gen_specs: %s has no Body" % id)
		model.free()
		return null
	var size: Vector3 = box["size"]
	spec.body_size = size
	spec.body_center_y = float(box["centre_y"])
	# The centre of mass sits a little above the wheel centres, the inertia comes from the box.
	var com_y: float = clampf(radii[0] * 1.2, 0.30, 0.60)
	spec.center_of_mass = Vector3(0.0, com_y, 0.0)
	var mass: float = spec.mass
	var h: float = size.y
	var w: float = size.x
	var d: float = size.z
	spec.inertia = Vector3(
		mass / 12.0 * (h * h + d * d),
		mass / 12.0 * (w * w + d * d) * 0.88,
		mass / 12.0 * (w * w + h * h))
	model.free()
	return spec

extends Node
## Every NPC preset has to match its glb: the wheel mounts are the wheel centres of the mesh and
## the body box is the Body AABB (the visual moves the glb wheels to the spec positions, so a
## mismatch would draw the wheels outside their arches).
## Run: tools/godot.sh test res://vehicle/tests/test_specs.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const CarMesh := preload("res://vehicle/specs/car_mesh.gd")

## The NPC cars and their preset files.
const CARS: Array[String] = ["sedan", "hatch_ev", "suv", "taxi", "van", "truck", "bus",
		"robotaxi", "patrol", "interceptor", "heavy_suv"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	for id: String in CARS:
		var spec: CarSpec = load("res://vehicle/specs/%s.tres" % id) as CarSpec
		if spec == null:
			t.check("%s has a preset" % id, false, "= missing")
			continue
		t.check("%s has a preset" % id, true, "= %s" % spec.display_name)
		# The glb has to exist, so the car is not the white placeholder.
		t.check("%s has a glb" % id, ResourceLoader.exists(spec.visual_scene_path),
				"= %s" % spec.visual_scene_path)
		var packed: PackedScene = load(spec.visual_scene_path) as PackedScene
		if packed == null:
			continue
		var model: Node3D = packed.instantiate() as Node3D
		if model == null:
			continue
		# The wheel mounts: the mount is the wheel centre plus REST_LEN - STATIC_SAG.
		for i in 4:
			var node: Node3D = model.find_child(CarMesh.WHEEL_NAMES[i], true, false) as Node3D
			if node == null:
				t.check("%s %s exists" % [id, CarMesh.WHEEL_NAMES[i]], false)
				continue
			var mount_error: float = spec.wheel_mounts[i].distance_to(CarMesh.wheel_mount(model, i))
			t.check("%s %s mount" % [id, CarMesh.WHEEL_NAMES[i]], mount_error < 0.02,
					"= %.4f m" % mount_error)
			var radius_error: float = absf(spec.wheel_radii[i] - CarMesh.wheel_radius(node))
			t.check("%s %s radius" % [id, CarMesh.WHEEL_NAMES[i]], radius_error < 0.02,
					"= %.4f m" % radius_error)
		# The body box: the size and the height of the Body AABB.
		var box: Dictionary = CarMesh.body_box(model)
		if not box.is_empty():
			var aabb_size: Vector3 = box["size"]
			var size_error: float = spec.body_size.distance_to(aabb_size)
			var height_error: float = absf(spec.body_center_y - float(box["centre_y"]))
			# The collision box only has to be close to the mesh: the car model unit still moves
			# the panels, and a few centimetres do not show.
			t.check("%s the body box" % id, size_error < 0.10 and height_error < 0.05,
					"= %.4f m size, %.4f m height" % [size_error, height_error])
		model.free()
	t.finish()

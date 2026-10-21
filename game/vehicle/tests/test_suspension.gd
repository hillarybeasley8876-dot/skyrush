extends Node
## Every preset settles on its wheels (the round 2 review): the suspension of a car is scaled
## with its mass, so a heavy car does not sit on its bump stops with its tyres inside the
## arches. The car is dropped 0.3 m above the road and has to carry its own weight within
## a second, with its wheel centres where the glb put them.
## Run: tools/godot.sh test res://vehicle/tests/test_suspension.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const CarMesh := preload("res://vehicle/specs/car_mesh.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

## The presets of the game.
const CARS: Array[String] = ["roadster", "sedan", "hatch_ev", "suv", "taxi", "van", "truck",
		"bus", "robotaxi", "patrol", "interceptor", "heavy_suv"]


func _ready() -> void:
	_run.call_deferred()


## The wheel centres of the glb of a car, in the car local space.
func _glb_centres(spec: CarSpec) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var packed: PackedScene = load(spec.visual_scene_path) as PackedScene
	if packed == null:
		return out
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return out
	for i in 4:
		out.append(CarMesh.wheel_centre(model, i))
	model.free()
	return out


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var index: int = 0
	for id: String in CARS:
		index += 1
		var spec: CarSpec = t.spec(id)
		if spec == null:
			t.check("%s has a preset" % id, false, "= missing")
			continue
		var centres: Array[Vector3] = _glb_centres(spec)
		var car: ArcadeCar = await t.spawn_car(spec, Vector3(float(index) * 20.0, 0.3, 0.0), 0.0)
		await t.run(1.0)
		# The wheels have to carry the car.
		var load: float = 0.0
		for w in car.wheels:
			load += w.load
		var weight: float = spec.mass * SuspensionTuning.GRAVITY
		t.check("%s carries its weight" % id, load >= 0.95 * weight,
				"= %.0f N of %.0f N" % [load, weight])
		# The wheel centres have to be where the glb put them.
		var error: float = 0.0
		for i in mini(4, centres.size()):
			var expected: Vector3 = car.global_position + centres[i]
			error = maxf(error, car.wheels[i].wheel_center.distance_to(expected))
		t.check_range("%s the wheel centres" % id, error, 0.0, 0.02)
		# The car has to be still.
		t.check_range("%s the vertical speed" % id, absf(car.linear_velocity.y), 0.0, 0.02)
		car.queue_free()
		await t.run(0.3)
	t.finish()

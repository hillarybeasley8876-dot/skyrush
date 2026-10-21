extends Node
## The visual binding: the front wheels steer to the right, the calipers follow the wheels and the
## wing takes the poses of the glb (CONTRACTS.md 6, the roadster glb metadata).
## Run: tools/godot.sh test res://vehicle/tests/test_visual.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	var visual: Node3D = car.get_visual_root()
	t.check("the model is there", visual.get_node_or_null(^"Model") != null)
	# The front wheels turn to the right when the car steers right.
	t.set_speed(car, 40.0)
	car.set_controls(0.3, 0.0, 1.0, false)
	await t.run(0.6)
	var fl: Node3D = visual.find_child("Wheel_FL", true, false) as Node3D
	t.check("the front wheel is there", fl != null)
	if fl != null:
		var axis: Vector3 = car.global_transform.basis.inverse() * fl.global_transform.basis.x
		# A wheel that points to the right has a negative yaw.
		var yaw: float = rad_to_deg(atan2(-axis.z, axis.x))
		t.check("the front wheel steers right", yaw < -5.0, "= %.1f deg" % yaw)
		# The caliper follows the wheel but does not spin.
		var caliper: Node3D = visual.find_child("Caliper_FL", true, false) as Node3D
		t.check("the caliper is there", caliper != null)
		if caliper != null:
			var gap: float = caliper.global_position.distance_to(fl.global_position)
			t.check("the caliper follows the wheel", gap < 0.35, "= %.3f m" % gap)
	# The wing: the poses come from the glb metadata and the angle changes within 0.25 s.
	var wing: Node3D = visual.find_child("Wing", true, false) as Node3D
	t.check("the wing is there", wing != null)
	if wing != null:
		t.check("the wing has the poses", wing.has_meta("extras"), "= %s" % str(wing.get_meta_list()))
		# Braking at speed deploys the air brake.
		t.set_speed(car, 207.0)
		car.set_controls(0.0, 1.0, 0.0, false)
		await t.run(1.5)
		var pose: StringName = visual.get("_pose_name")
		t.check("the air brake deploys", pose == &"air_brake", "= %s" % pose)
		var angle: float = float(visual.get("_pose_angle"))
		t.check("the wing angle", angle > 50.0, "= %.1f deg" % angle)
		# The trailing edge goes up with a positive pitch.
		t.check("the wing pitches up", wing.rotation.x < 0.0, "= %.3f rad" % wing.rotation.x)
	# The brake lights: the bar and the brake box are lit with the strength the glb was
	# authored with, and they flare up to BRAKE_LIGHT_RATIO times that while braking.
	var lights: Object = visual.get("lights")
	var bar_authored: float = float((lights.get("bar") as Object).get("idle"))
	var box_authored: float = float((lights.get("box") as Object).get("idle"))
	t.check("the bar is authored with an emission", bar_authored > 0.0, "= %.2f" % bar_authored)
	t.check("the brake box is authored with an emission", box_authored > 0.0,
			"= %.2f" % box_authored)
	car.set_controls(0.0, 0.0, 0.0, false)
	await t.run(0.5)
	t.check_close("the bar at rest", float(lights.bar_energy()), bar_authored, 0.05)
	t.check_close("the brake box at rest", float(lights.box_energy()), box_authored, 0.05)
	car.set_controls(0.0, 1.0, 0.0, false)
	await t.run(0.3)
	t.check_close("the bar while braking", float(lights.bar_energy()),
			bar_authored * VisualTuning.BRAKE_LIGHT_RATIO, 0.05)
	t.check_close("the brake box while braking", float(lights.box_energy()),
			box_authored * VisualTuning.BRAKE_LIGHT_RATIO, 0.05)
	car.set_controls(0.0, 0.0, 0.0, false)
	await t.run(0.3)
	t.check_close("the bar is back", float(lights.bar_energy()), bar_authored, 0.05)
	t.check_close("the brake box is back", float(lights.box_energy()), box_authored, 0.05)
	# The NPC cars: the brake lamp of the traffic flares up while braking.
	var sedan: ArcadeCar = await t.spawn_car(t.spec("sedan"), Vector3(0.0, 0.15, 200.0), 0.0)
	await t.run(0.6)
	var npc_lights: Object = (sedan.get_visual_root() as Node3D).get("lights")
	var idle: float = float(npc_lights.lamp_energy())
	t.check("the NPC car has a brake lamp", idle > 0.0, "= %.2f" % idle)
	sedan.set_controls(0.0, 1.0, 0.0, false)
	await t.run(0.3)
	t.check("the NPC brake lamp flares up", float(npc_lights.lamp_energy()) > idle,
			"= %.2f (was %.2f)" % [float(npc_lights.lamp_energy()), idle])
	sedan.set_controls(0.0, 0.0, 0.0, false)
	await t.run(0.3)
	t.check_close("the NPC brake lamp is back", float(npc_lights.lamp_energy()), idle, 0.1)
	# The placeholder: a car whose glb is missing still gets a body from its spec, a cabin and
	# four wheels (ART 5: no flat untextured surface).
	var plain := CarSpec.new()
	plain.id = &"plain"
	plain.body_size = Vector3(1.90, 1.31, 4.78)
	plain.body_center_y = 0.81
	plain.wheel_radii = [0.33, 0.33, 0.33, 0.33]
	var plain_car: ArcadeCar = await t.spawn_car(plain, Vector3(0.0, 0.15, 400.0), 0.0)
	await t.run(0.6)
	var plain_visual: Node3D = plain_car.get_visual_root()
	var body: MeshInstance3D = plain_visual.find_child("Body", true, false) as MeshInstance3D
	t.check("the placeholder has a body", body != null)
	if body != null:
		var arrays: Array = body.mesh.surface_get_arrays(0)
		t.check("the body has normals", arrays[Mesh.ARRAY_NORMAL] != null)
		t.check("the body has UVs", arrays[Mesh.ARRAY_TEX_UV] != null)
		t.check_range("the body is the size of the spec", body.mesh.get_aabb().size.x, 1.5, 2.2)
	var wheels: int = 0
	for name: String in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		if plain_visual.find_child(name, true, false) != null:
			wheels += 1
	t.check("the placeholder has four wheels", wheels == 4, "= %d" % wheels)
	t.finish()

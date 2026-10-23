extends Node
## A kerb at the height of the car's lower edge must not launch it. The box of the Roadster starts 0.22 m above the road;
## at 240 km/h the downforce presses the car about 5 cm down, so a 17 cm kerb meets the lower front edge of the box
## exactly (the kerbs and the planter islands of the city are 15 cm). The solver then gets an ambiguous contact normal and
## turned a third of the speed of the car into vertical speed in one tick (31 m/s: the car flew 30 m high, pitched 85 degrees,
## and landed on its roof; the planter islands of the city did it 30 times in 40 passes). The speed away from the ground is
## capped now (ImpactTuning.SOLVER_KICK_UP). The box is not raised: its floor is what stops the car after a hard landing.
## Run: python tools/gd.py test res://vehicle/tests/test_kerb_graze.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const ImpactTuning := preload("res://vehicle/tuning/impact_tuning.gd")

## The ride height drop at top speed (m): the kerbs below graze the box.
const RIDE_DROP := 0.05
## The offsets (m) of the kerb tops from the graze height: one of them hits the edge on the nail.
const OFFSETS: Array[float] = [-0.03, -0.015, 0.0, 0.015, 0.03]
const LAUNCH_PITCH := 25.0
const LAUNCH_HEIGHT := 1.2


func _ready() -> void:
	_run.call_deferred()


func _kerb(world: Node, z: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	# a trimesh like the road tiles have: a closed slab, 6 m wide and 1.2 m deep
	var mesh := BoxMesh.new()
	mesh.size = Vector3(6.0, height, 1.2)
	shape.shape = mesh.create_trimesh_shape()
	shape.position = Vector3(0.0, height * 0.5, z)
	body.add_child(shape)
	world.add_child(body)
	return body


## The lowest point of the collision box of a spawned car (m above the road at rest).
func _box_bottom(car: ArcadeCar) -> float:
	var shape := car.get_node("Body") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	return shape.position.y - box.size.y * 0.5


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var tuning: Script = ImpactTuning
	var kick: float = tuning.get_script_constant_map().get("SOLVER_KICK_UP", -1.0)
	t.check("the tuning caps the speed away from the ground", kick > 0.5 and kick < 4.0, "(%.1f m/s)" % kick)
	# the grazing kerb
	var car := await t.spawn_car(t.roadster(), Vector3(0.0, 0.3, 0.0), 0.0)
	car.player_controlled = true
	var graze := _box_bottom(car) - RIDE_DROP
	var worst_pitch := 0.0
	var worst_height := 0.0
	for offset in OFFSETS:
		car.reset_to(Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)))
		await t.step()
		t.set_speed(car, 200.0)
		Input.action_press(&"accelerate")
		await t.run(5.0)
		var kerb := _kerb(t.world, car.global_position.z - 40.0, graze + offset)
		var pitch := 0.0
		var height := -1.0
		for i in 120:
			await t.run(0.02)
			var b := car.global_transform.basis
			pitch = maxf(pitch, absf(rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0)))))
			height = maxf(height, car.global_position.y)
			if car.global_position.z < kerb.get_child(0).position.z - 15.0:
				break
		Input.action_release(&"accelerate")
		worst_pitch = maxf(worst_pitch, pitch)
		worst_height = maxf(worst_height, height)
		kerb.queue_free()
		await t.step()
	t.check("a kerb at the lower edge of the box (%.0f cm +-3) does not pitch the car over %.0f degrees" % [graze * 100.0, LAUNCH_PITCH],
		worst_pitch < LAUNCH_PITCH, "= %.1f deg" % worst_pitch)
	t.check("and does not throw it higher than %.0f m" % LAUNCH_HEIGHT, worst_height < LAUNCH_HEIGHT, "= %.2f m" % worst_height)
	car.queue_free()
	t.finish()

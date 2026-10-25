extends Node
## A kerb is climbed by the wheels, it is not a wall for the body. The wheels are probes that follow the ground with their
## springs; the collision box has its floor at least SuspensionTuning.MIN_BOX_BOTTOM above the road, so a kerb or a median
## strip of the city (15 cm) never meets the box, however the car pitches and sags at 250 km/h. With the box floor at 22 cm a
## kerb of 17 cm or more stopped the car dead (a loss of 150 to 250 km/h in two ticks) and the median strip of the Lujiazui
## ring road killed a car at 250 km/h; a wall that is really high (50 cm) still stops it.
## The floor of the box is out of reach of the road, so the stop of the suspension takes the landings: it springs and damps
## (SuspensionTuning.BUMPSTOP_DAMP_TIME), or a hard landing would give its energy back as a bounce.
## Run: python tools/gd.py test res://vehicle/tests/test_kerb_climb.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

## The kerb heights (m): the kerbs of the city are 15 cm; the rest is the margin.
const HEIGHTS: Array[float] = [0.10, 0.15, 0.19, 0.24]
## The widths (m): a strip of the median passes between the wheels, a slab as wide as the road is climbed by all of them.
const WIDTHS: Array[float] = [1.0, 6.0]
const SPEEDS: Array[float] = [150.0, 250.0]
## The most a kerb may take from the speed (km/h), the most vertical speed and pitch it may give.
const MAX_LOSS_KMH := 15.0
const MAX_VY := 3.5
const MAX_PITCH := 10.0
## A wall this high is a wall.
const WALL_HEIGHT := 0.55
const WALL_MIN_LOSS_KMH := 100.0


func _ready() -> void:
	_run.call_deferred()


## A slab like the strips of the city: a closed trimesh, sunk 30 cm into the road.
func _slab(world: Node, at: Vector3, height: float, width: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height + 0.30, 1.0)
	shape.shape = mesh.create_trimesh_shape()
	shape.position = Vector3(0.0, (height - 0.30) * 0.5, 0.0)
	body.add_child(shape)
	body.position = at
	world.add_child(body)
	return body


## Drives at `kmh` over a slab 40 m ahead. Returns {"loss", "vy", "pitch"}: the speed lost (km/h), the highest vertical speed
## (m/s) and the largest pitch (degrees).
func _cross(t: T, car: ArcadeCar, kmh: float, height: float, width: float) -> Dictionary:
	car.reset_to(Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)))
	await t.step()
	t.set_speed(car, kmh)
	Input.action_press(&"accelerate")
	await t.run(4.0)
	var slab := _slab(t.world, Vector3(car.global_position.x, 0.0, car.global_position.z - 40.0), height, width)
	var v0 := car.linear_velocity.length()
	var slowest := v0
	var vy := 0.0
	var pitch := 0.0
	for i in 150:
		await t.run(0.02)
		var b := car.global_transform.basis
		pitch = maxf(pitch, absf(rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0)))))
		vy = maxf(vy, car.linear_velocity.y)
		slowest = minf(slowest, Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z).length())
		if car.global_position.z < slab.position.z - 15.0:
			break
	Input.action_release(&"accelerate")
	slab.queue_free()
	await t.step()
	return {"loss": (v0 - slowest) * 3.6, "vy": vy, "pitch": pitch}


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car := await t.spawn_car(t.roadster(), Vector3(0.0, 0.3, 0.0), 0.0)
	car.player_controlled = true
	var shape := car.get_node("Body") as CollisionShape3D
	var bottom := shape.position.y - (shape.shape as BoxShape3D).size.y * 0.5
	var tuning: Script = SuspensionTuning
	var floor_min: float = tuning.get_script_constant_map().get("MIN_BOX_BOTTOM", 0.0)
	t.check("the floor of the box is out of reach of the kerbs", bottom >= 0.30 and floor_min >= 0.30,
		"(box floor %.2f m, rule %.2f m)" % [bottom, floor_min])
	var worst_loss := 0.0
	var worst_vy := 0.0
	var worst_pitch := 0.0
	var worst_case := ""
	for kmh in SPEEDS:
		for height in HEIGHTS:
			for width in WIDTHS:
				var r := await _cross(t, car, kmh, height, width)
				if float(r["loss"]) > worst_loss:
					worst_loss = float(r["loss"])
					worst_case = "%.0f km/h, kerb %.0f cm, %.0f m wide" % [kmh, height * 100.0, width]
				worst_vy = maxf(worst_vy, float(r["vy"]))
				worst_pitch = maxf(worst_pitch, float(r["pitch"]))
	t.check("a kerb of up to %.0f cm takes at most %.0f km/h from the car" % [HEIGHTS[HEIGHTS.size() - 1] * 100.0, MAX_LOSS_KMH],
		worst_loss <= MAX_LOSS_KMH, "(worst %.1f km/h: %s)" % [worst_loss, worst_case])
	t.check("and throws it up at most %.1f m/s" % MAX_VY, worst_vy <= MAX_VY, "(%.1f m/s)" % worst_vy)
	t.check("and pitches it at most %.0f degrees" % MAX_PITCH, worst_pitch <= MAX_PITCH, "(%.1f deg)" % worst_pitch)
	# a wall is still a wall: the box meets what is higher than the kerbs
	var wall := await _cross(t, car, 150.0, WALL_HEIGHT, 6.0)
	t.check("a wall of %.0f cm still stops the car" % (WALL_HEIGHT * 100.0), float(wall["loss"]) >= WALL_MIN_LOSS_KMH,
		"(lost %.0f km/h)" % float(wall["loss"]))
	# the landing: the floor of the box does not take it any more, the stop of the suspension does, and it does not bounce
	var worst_bounce := 0.0
	for drop in [1.0, 2.0, 4.0]:
		car.reset_to(Transform3D(Basis(), Vector3(0.0, 0.3 + drop, 0.0)))
		await t.step()
		var landed := false
		var bounce := 0.0
		for i in Engine.physics_ticks_per_second * 3:
			await t.step()
			if car.dynamics.grounded >= 2:
				landed = true
			if landed and car.linear_velocity.y > 0.5 and car.global_position.y > 0.45:
				bounce = maxf(bounce, car.global_position.y - 0.45)
		worst_bounce = maxf(worst_bounce, bounce)
	t.check("a landing from 4 m does not bounce the car back up (a bounce over 30 cm)", worst_bounce <= 0.30,
		"(%.2f m)" % worst_bounce)
	t.check("the stop of the suspension is damped", float(tuning.get_script_constant_map().get("BUMPSTOP_DAMP_TIME", 0.0)) > 0.0)
	car.queue_free()
	t.finish()

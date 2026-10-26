extends Node
## The wheel probes stay inside the collision box. A probe that reaches past the side of the box meets what the box leans
## on: the Roadster's probes were cast from its wheel mounts, 0.976 m out, while its box is 0.95 m a side (it was 1.05 m
## until the box was made 1.9 m wide, the car the oracles measure with). A car that scraped a parapet had the probes of that
## side in the wall: they met its face, so that side lost its springs and its grip, and once the car bounced 0.3 m they stood
## on its top, the bump stops threw that side up and the car climbed the parapet and fell off the deck (fuzz_drive.gd
## --elevated=1: 3 falls in 120 drives, every one so). The probe is cast from inside the box now; the force stays at the mount.
## Run: python tools/gd.py test res://vehicle/tests/test_probe_inside_box.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

## Every car of the game: the player's and the rivals' Roadster, the traffic and the police.
const SPECS: Array[String] = ["roadster", "sedan", "taxi", "suv", "hatch_ev", "van", "heavy_suv", "interceptor", "patrol",
	"robotaxi", "truck", "bus"]
## The wall: as high and as thick as the parapet collider of the elevated roads, along Z, its face at WALL_X.
const WALL_X := 6.0
const WALL_H := 1.0
const WALL_T := 0.46
## The drop: the side of the box stands GAP from the face of the wall, the car DROP over its rest height.
const GAP := 0.01
const DROP := 0.35
## The scrape: the car drives into the wall at SCRAPE_DEG and SCRAPE_KMH, the throttle held for SCRAPE_S.
const SCRAPE_DEG := 6.0
const SCRAPE_KMH := 140.0
const SCRAPE_S := 3.0


func _ready() -> void:
	_run.call_deferred()


func _wall(world: Node) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	# a trimesh like the road tiles have
	var mesh := BoxMesh.new()
	mesh.size = Vector3(WALL_T, WALL_H + 0.6, 600.0)
	shape.shape = mesh.create_trimesh_shape()
	shape.position = Vector3(WALL_X + WALL_T * 0.5, (WALL_H - 0.6) * 0.5, 0.0)
	body.add_child(shape)
	world.add_child(body)
	return body


## The half width of the collision box of a car.
func _box_half(car: ArcadeCar) -> float:
	return ((car.get_node("Body") as CollisionShape3D).shape as BoxShape3D).size.x * 0.5


## The roll of the car in degrees.
func _roll(car: ArcadeCar) -> float:
	return rad_to_deg(asin(clampf(car.global_transform.basis.x.y, -1.0, 1.0)))


## The wheels whose probe met the wall this tick (a probe must never meet what the box leans on).
func _probes_in(car: ArcadeCar, wall: StaticBody3D) -> int:
	var n := 0
	for w in car.wheels:
		if w.probe.is_colliding() and w.probe.get_collider(0) == wall:
			n += 1
	return n


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# every car: the probe spheres inside the box
	var k := 0
	for id in SPECS:
		k += 1
		var spec: CarSpec = t.roadster() if id == "roadster" else t.spec(id)
		var car := await t.spawn_car(spec, Vector3(-40.0, 0.5, -30.0 + float(k) * 14.0), 0.0)
		var out := -INF
		for w in car.wheels:
			out = maxf(out, absf(w.probe.position.x) + SuspensionTuning.PROBE_RADIUS - _box_half(car))
		t.check("%s: the wheel probes lie inside the box" % id, out <= 0.0, "(the sphere reaches %+.3f m past its side)" % out)
		car.queue_free()
		await t.step()
	var wall := _wall(t.world)
	# the drop: a car that bounced up beside a parapet comes down on its wheels, not on the parapet
	var car := await t.spawn_car(t.roadster(), Vector3(0.0, DROP, 0.0), 0.0)
	car.reset_to(Transform3D(Basis(), Vector3(WALL_X - _box_half(car) - GAP, DROP, 0.0)))
	var met := 0
	var peak := 0.0
	for i in int(1.5 * Engine.physics_ticks_per_second):
		await t.step()
		met += _probes_in(car, wall)
		peak = maxf(peak, absf(_roll(car)))
	t.check("dropped beside the wall, no wheel probe meets it", met == 0, "(%d probe ticks in the wall)" % met)
	t.check("and the car settles level", absf(_roll(car)) < 3.0 and peak < 10.0,
		"(roll %.1f deg, peak %.1f deg)" % [_roll(car), peak])
	# the scrape: along the wall with the throttle held, the wheels of the wall side keep the road
	car.reset_to(Transform3D(Basis(Vector3.UP, -deg_to_rad(SCRAPE_DEG)), Vector3(WALL_X - _box_half(car) - 2.0, 0.05, 250.0)))
	await t.step()
	t.set_speed(car, SCRAPE_KMH)
	Input.action_press(&"accelerate")
	met = 0
	var touched := 0
	var top := -INF
	var past := -INF
	peak = 0.0
	for i in int(SCRAPE_S * Engine.physics_ticks_per_second):
		await t.step()
		met += _probes_in(car, wall)
		if car.get_colliding_bodies().has(wall):
			touched += 1
		top = maxf(top, car.global_position.y)
		past = maxf(past, car.global_position.x - (WALL_X - _box_half(car)))
		peak = maxf(peak, absf(_roll(car)))
	Input.action_release(&"accelerate")
	t.check("the car scrapes the wall", touched > 10, "(%d ticks in touch)" % touched)
	t.check("while it scrapes, no wheel probe meets the wall", met == 0, "(%d probe ticks in the wall)" % met)
	t.check("and it stays on the road beside the wall", top < 0.4 and past < 0.05 and peak < 15.0,
		"(highest %.2f m, the side of the box %.2f m into the wall, peak roll %.1f deg)" % [top, past, peak])
	wall.queue_free()
	car.queue_free()
	t.finish()

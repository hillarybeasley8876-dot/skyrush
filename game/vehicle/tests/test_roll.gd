extends Node
## The barrel roll: a full 360 degrees in 0.70 +- 0.05 s and a clean landing.
## Run: tools/godot.sh test res://vehicle/tests/test_roll.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


## The roll angle of the car about its own forward axis, in degrees (-180..180).
func _roll_angle(car: ArcadeCar) -> float:
	var basis: Basis = car.global_transform.basis
	var fwd: Vector3 = -basis.z
	var up: Vector3 = basis.y
	# The world up projected on the car's plane, and the axis in that plane.
	var ref: Vector3 = Vector3.UP - fwd * Vector3.UP.dot(fwd)
	if ref.length() < 0.01:
		return 0.0
	ref = ref.normalized()
	var side: Vector3 = fwd.cross(ref).normalized()
	return rad_to_deg(atan2(up.dot(side), up.dot(ref)))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	# Get airborne with a hop.
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	for i in 60:
		await t.step()
		if car.telemetry.airborne:
			break
	t.check("the car is airborne", car.telemetry.airborne)
	var n2_before: float = car.boost.n2
	var rolled: bool = car.request_roll(1)
	t.check("the roll starts", rolled)
	t.check_close("the roll costs 20 N2", n2_before - car.boost.n2, 20.0, 0.5)
	# The angle is accumulated from the steps, the raw angle wraps at 90 degrees.
	var angle: float = 0.0
	var duration: float = 0.0
	var previous: float = _roll_angle(car)
	for i in 120 * 2:
		await t.step()
		duration += 1.0 / 120.0
		var now: float = _roll_angle(car)
		angle += wrapf(now - previous, -180.0, 180.0)
		previous = now
		if not car.thruster.rolling:
			break
	t.check_range("the roll angle", angle, 355.0, 365.0)
	t.check_range("the roll time", duration, 0.65, 0.75)
	# The car lands upright.
	for i in 120 * 3:
		await t.step()
		if car.telemetry.grounded_wheels >= 3 and not car.telemetry.airborne:
			break
	t.check("the car landed", car.telemetry.grounded_wheels >= 3,
			"= %d wheels" % car.telemetry.grounded_wheels)
	t.check_range("the car is upright", absf(car.telemetry.pitch_deg), 0.0, 15.0)
	t.check_range("the car is level", absf(car.telemetry.roll_deg), 0.0, 15.0)
	t.finish()

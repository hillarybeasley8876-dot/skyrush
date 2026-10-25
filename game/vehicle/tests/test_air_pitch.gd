extends Node
## The air control (dossier 4.8): the motor and the brakes do not work in the air, and a
## throttle that was held through the take-off must not dive the nose. The nose only dives
## after a fresh press that is held for a moment (a tap in the air is the 空喷).
## Run: tools/godot.sh test res://vehicle/tests/test_air_pitch.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


## Hops the car and returns the measurements of the jump.
## keys: {"pitch": deg at the touchdown, "quality": the landing quality, "window": the
## landing window, "delta": the forward speed change in the air, "drop": the height}.
func _hop(t: T, kmh: float, throttle: bool, big: bool = false) -> Dictionary:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	t.set_speed(car, kmh)
	car.set_controls(1.0 if throttle else 0.0, 0.0, 0.0, false)
	await t.run(0.2)
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	if big:
		for i in Engine.physics_ticks_per_second / 3:
			await t.step()
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	var air_start: float = car.telemetry.forward_speed_kmh
	var flew: bool = false
	var out: Dictionary = {"pitch": 0.0, "quality": &"clean", "window": false, "delta": 0.0}
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.telemetry.airborne:
			if not flew:
				# The measurement starts when the car is really in the air.
				flew = true
				air_start = car.telemetry.forward_speed_kmh
		elif flew:
			out["pitch"] = car.telemetry.pitch_deg
			out["quality"] = car.dynamics.landing_quality
			out["window"] = car.telemetry.mini_window
			out["delta"] = car.telemetry.forward_speed_kmh - air_start
			break
	out["car"] = car
	return out


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The hop at 120 km/h with the throttle held: the nose must stay level.
	var held: Dictionary = await _hop(t, 120.0, true)
	t.check_range("the pitch at the touchdown", absf(float(held["pitch"])), 0.0, 8.0)
	t.check("the landing is clean", StringName(held["quality"]) == &"clean",
			"= %s" % str(held["quality"]))
	t.check("the landing window is open", bool(held["window"]))
	# The same jump without the throttle: the motor must not change the air speed.
	var free: Dictionary = await _hop(t, 120.0, false)
	t.check_range("the air speed change with the throttle", float(held["delta"]), -1.0, 1.0)
	t.check_range("the air speed change without the throttle", float(free["delta"]), -1.0, 1.0)
	t.check_range("the difference of the air speed", float(held["delta"]) - float(free["delta"]),
			-1.0, 1.0)
	# A fresh press in the air dives the nose.
	var car: ArcadeCar = held["car"]
	car.boost.n2 = BoostTuning.N2_MAX
	# The Big Hop: the flight is long enough to see the steady pitch rate.
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	for i in Engine.physics_ticks_per_second / 3:
		await t.step()
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	# In the air: release the throttle, then press it again and hold it.
	var phase: int = 0
	var max_rate: float = 0.0
	var left_ground: bool = false
	for i in Engine.physics_ticks_per_second * 2:
		await t.step()
		if not car.telemetry.airborne:
			if left_ground:
				break
			continue
		left_ground = true
		if phase == 0 and i >= 12:
			car.set_controls(0.0, 0.0, 0.0, false)
			phase = 1
			continue
		if phase == 1 and i >= 12 + 20:
			car.set_controls(1.0, 0.0, 0.0, false)
			phase = 2
			continue
		if phase == 2:
			var rate: float = car.angular_velocity.dot(car.global_transform.basis.x)
			max_rate = minf(max_rate, rate)
	t.check("the fresh press dives the nose", max_rate <= -1.2, "= %.2f rad/s" % max_rate)
	t.finish()

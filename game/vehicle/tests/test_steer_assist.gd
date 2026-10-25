extends Node
## The steering assist of the player (Drive.assist, DriveTuning.STEER_GRIP_*): the full wheel is the angle where the front tyres give
## the most. A keyboard only knows the full wheel, and the linear fall of the wheel angle (32 deg at rest to 7 deg at the top speed)
## left the front tyres far past their grip: at 80-120 km/h the full wheel turned the car 20-24 % less than a third of it
## (vehicle/tests/steer_report.gd). The player reported that "the handling is terrible".
## Run: python tools/gd.py test res://vehicle/tests/test_steer_assist.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SPEEDS := [80.0, 120.0]
const PARTS := [0.3, 0.5, 0.7]
## The full wheel turns the car at least this share of the best part of the wheel.
const FULL_SHARE := 0.97
## Where every run starts (open ground west of the loop of the sandbox).
const START := Vector3(-1000.0, 0.15, -1000.0)

var _t: T


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_t = T.new(get_tree())
	await _t.build_world()
	for kmh: float in SPEEDS:
		var full := await _yaw(kmh, 1.0)
		var best := 0.0
		for part: float in PARTS:
			best = maxf(best, await _yaw(kmh, part))
		print("ASSIST %3.0f km/h: the full wheel %.1f deg/s, the best part of it %.1f deg/s" % [kmh, full, best])
		_t.check("at %.0f km/h the full wheel turns the car the most (%.0f %% of the best part at least)" % [kmh,
				FULL_SHARE * 100.0], full >= best * FULL_SHARE, "(%.1f of %.1f deg/s)" % [full, best])
	_t.finish()


## The yaw rate (deg/s) of the car of the player after 1-2 s with the wheel held at `input` at `kmh` (the speed held by the throttle).
func _yaw(kmh: float, input: float) -> float:
	await _t.step()
	var car: ArcadeCar = await _t.spawn_car(_t.roadster(), START, -PI * 0.5)
	car.steering_assist = true
	await _t.run(0.3)
	var target := kmh / 3.6
	car.linear_velocity = -car.global_transform.basis.z * target
	var total := 0.0
	for i in Engine.physics_ticks_per_second * 2:
		car.set_controls(1.0 if car.linear_velocity.length() < target else 0.0, 0.0, input, false)
		await _t.step()
		if i >= Engine.physics_ticks_per_second:
			total += -rad_to_deg(car.angular_velocity.y)
	car.queue_free()
	return total / float(Engine.physics_ticks_per_second)

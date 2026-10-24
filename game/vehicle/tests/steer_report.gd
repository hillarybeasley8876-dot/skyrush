extends Node
## The steering report: how the car answers the wheel (the player's report: "the handling is terrible"). Not a test: it prints the
## numbers, the brief has no targets for them yet.
##
## For every speed the car drives straight, then the wheel is held right (as a keyboard does: the full input, ramped by
## DriveTuning.STEER_RAMP) and released: the yaw rate (deg/s) it builds, how fast (the time to 63 % of its plateau), the lateral
## acceleration (g), the slip angle of the body, the speed it keeps after 2 s, and after the release how long the yaw takes to settle
## and how far it swings back. Then the sweep: the input from 0.1 to 1.0 at the same speeds, the plateau yaw rate of each - when a
## part of the wheel turns the car harder than the full wheel, the front tyres are past their grip at the full wheel (a keyboard
## only knows the full wheel).
## Run: python tools/gd.py test res://vehicle/tests/steer_report.gd -- --timeout=300

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SPEEDS := [40.0, 80.0, 120.0, 160.0, 200.0]
const INPUTS := [0.1, 0.2, 0.3, 0.5, 0.7, 1.0]
## Where every run starts (it faces +X and turns right, towards +Z: open ground of the sandbox).
const ROW_X := -1000.0
const ROW_Z0 := -1000.0

var _t: T
var _row := 0
## The cars of the report have the steering assist of the player (--assist=0: without it, as the AI cars drive).
var _assist := true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_t = T.new(get_tree())
	await _t.build_world()
	_assist = Game.option("assist", "1") != "0"
	print("STEER the steering assist of the player is %s" % ("on" if _assist else "off (the AI cars)"))
	print("STEER speed | yaw plateau | t63 | lateral | body slip | speed kept 2 s | settle | swing back")
	for kmh: float in SPEEDS:
		var r := await _turn(kmh, 1.0, true)
		print("STEER %3.0f km/h | %5.1f deg/s | %.2f s | %.2f g | %4.1f deg | %3.0f %% | %.2f s | %5.1f deg/s" % [kmh,
			r["plateau"], r["t63"], r["lateral"], r["slip"], r["kept"] * 100.0, r["settle"], r["swing"]])
	print("SWEEP speed | the plateau yaw rate (deg/s) for the inputs %s" % str(INPUTS))
	for kmh: float in SPEEDS:
		var line := "SWEEP %3.0f km/h |" % kmh
		var best := 0.0
		var best_input := 0.0
		for input: float in INPUTS:
			var r := await _turn(kmh, input, false)
			line += " %5.1f" % r["plateau"]
			if r["plateau"] > best:
				best = r["plateau"]
				best_input = input
		print("%s | the most at %.1f" % [line, best_input])
	_t.finish()


## The start of every run: open ground west of the loop of the sandbox (the car of a run is gone before the next starts).
func _next_row() -> Vector3:
	_row += 1
	await _t.step()
	return Vector3(ROW_X, 0.15, ROW_Z0)


## Drives at `kmh`, holds the wheel at `input` for 2 s (the speed held by the throttle), then releases it (when `release`).
func _turn(kmh: float, input: float, release: bool) -> Dictionary:
	var at: Vector3 = await _next_row()
	var car: ArcadeCar = await _t.spawn_car(_t.roadster(), at, -PI * 0.5)
	car.steering_assist = _assist
	await _t.run(0.3)
	var target := kmh / 3.6
	car.linear_velocity = -car.global_transform.basis.z * target
	for i in 30:
		car.set_controls(1.0 if car.linear_velocity.length() < target else 0.0, 0.0, 0.0, false)
		await _t.step()
	var start_speed := car.linear_velocity.length()
	var yaws: Array[float] = []
	var lateral_sum := 0.0
	var slip_peak := 0.0
	var samples := 0
	for i in 240:
		car.set_controls(1.0 if car.linear_velocity.length() < target else 0.0, 0.0, input, false)
		await _t.step()
		var yaw := rad_to_deg(car.angular_velocity.y) * -1.0
		yaws.append(yaw)
		if i >= 120:
			var v := car.linear_velocity
			lateral_sum += absf(car.angular_velocity.y) * Vector2(v.x, v.z).length() / 9.81
			samples += 1
		slip_peak = maxf(slip_peak, absf(car.telemetry.slip_angle_deg))
	var plateau := 0.0
	for i in range(120, 240):
		plateau += yaws[i]
	plateau /= 120.0
	var t63 := -1.0
	for i in yaws.size():
		if yaws[i] >= plateau * 0.63:
			t63 = float(i) / 120.0
			break
	var kept := car.linear_velocity.length() / maxf(start_speed, 0.1)
	var settle := -1.0
	var swing := 0.0
	if release:
		for i in 180:
			car.set_controls(1.0 if car.linear_velocity.length() < target else 0.0, 0.0, 0.0, false)
			await _t.step()
			var yaw := rad_to_deg(car.angular_velocity.y) * -1.0
			swing = minf(swing, yaw)
			if settle < 0.0 and absf(yaw) < 5.0:
				settle = float(i) / 120.0
	car.queue_free()
	return {"plateau": plateau, "t63": t63, "lateral": lateral_sum / maxf(float(samples), 1.0), "slip": slip_peak,
		"kept": kept, "settle": settle, "swing": -swing}

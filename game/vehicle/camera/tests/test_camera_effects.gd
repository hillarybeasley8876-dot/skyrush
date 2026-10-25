extends Node
## The camera unit's effect tests: the boost state and the N2 punch, the wall pull-in as it
## is drawn, the suppression of the effects in the takedown shot and on pause, and the
## radial blur's centre.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const Report := preload("res://vehicle/camera/tests/camera_test_report.gd")
const Helpers := preload("res://vehicle/camera/tests/camera_test_helpers.gd")

const CHASE_SPEED := 20.0        ## m/s, the speed the boost test drives at
const TOP_SPEED := 69.44         ## m/s, 250 km/h

var _report: Report = null
var _helpers := Helpers.new()


func run(host: Node, report: Report) -> void:
	_report = report
	await _test_boost(host)
	await _test_punch(host)
	await _test_pull_in(host)
	await _test_effects(host)
	await _test_blur_centre(host)


## The camera's internal state (see the camera's get_debug_state).
func _state() -> Dictionary:
	return _helpers.cam_root.call("get_debug_state") as Dictionary


func _test_boost(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	var car := _helpers.car
	car.linear_velocity = Vector3(0, 0, -CHASE_SPEED)
	car.telemetry.speed_kmh = CHASE_SPEED * 3.6
	car.telemetry.boost_kind = &"nitro"
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	car.telemetry.boost_kind = &""
	var last_blur := 0.0
	var max_step := 0.0
	for i in Engine.physics_ticks_per_second * 3 / 2:
		car.linear_velocity = Vector3(0, 0, -CHASE_SPEED)
		await host.get_tree().physics_frame
		var blur := float(_state()["blur_strength"])
		max_step = maxf(max_step, absf(blur - last_blur))
		last_blur = blur
	var expected := CameraMath.FOV_BASE + CameraMath.FOV_PER_MPS * CHASE_SPEED
	_report.near("the nitro fov is released with the boost", _helpers.cam.fov, expected, 0.3)
	_report.check("the blur never jumps", max_step <= 0.02, "max step %.4f" % max_step)
	car.telemetry.boost_kind = &"nitro"
	car.telemetry.speed_kmh = 150.0
	car.linear_velocity = Vector3(0, 0, -41.6)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	_report.near("no blur at 150 km/h in nitro", float(_state()["blur_strength"]), 0, 0.01)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_punch(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	var car := _helpers.car
	# (a) the N2 runs for three seconds, then it ends.
	car.telemetry.boost_kind = &"nitro"
	Events.boost_started.emit(car, &"nitro")
	var worst_step := 0.0
	var last := 0.0
	var punch_at_29 := 0.0
	for i in Engine.physics_ticks_per_second * 29 / 10:            # 2.9 s
		await host.get_tree().physics_frame
		var punch := float(_state()["punch"])
		worst_step = maxf(worst_step, absf(punch - last))
		last = punch
		punch_at_29 = punch
	car.telemetry.boost_kind = &""
	for i in Engine.physics_ticks_per_second * 7 / 6:            # 1.15 s
		await host.get_tree().physics_frame
		var punch := float(_state()["punch"])
		worst_step = maxf(worst_step, absf(punch - last))
		last = punch
	_report.near("the punch holds at +0.4 m while the N2 runs", punch_at_29, 0.4, 0.01)
	_report.check("the punch returns to zero after the N2", absf(last) <= 0.01, "%.4f m" % last)
	# (b) the boost event without the telemetry: the punch still comes back.
	Events.boost_started.emit(car, &"nitro")
	for i in Engine.physics_ticks_per_second * 5 / 3:            # 1.6 s
		await host.get_tree().physics_frame
		var punch := float(_state()["punch"])
		worst_step = maxf(worst_step, absf(punch - last))
		last = punch
	_report.check("a boost event without the telemetry still releases", absf(last) <= 0.01,
			"%.4f m" % last)
	# (c) the N2 ends in the middle of the kick.
	car.telemetry.boost_kind = &"nitro"
	Events.boost_started.emit(car, &"nitro")
	for i in Engine.physics_ticks_per_second / 5:             # 0.2 s
		await host.get_tree().physics_frame
		var punch := float(_state()["punch"])
		worst_step = maxf(worst_step, absf(punch - last))
		last = punch
	car.telemetry.boost_kind = &""
	for i in Engine.physics_ticks_per_second * 7 / 6:            # 1.15 s
		await host.get_tree().physics_frame
		var punch := float(_state()["punch"])
		worst_step = maxf(worst_step, absf(punch - last))
		last = punch
	_report.check("the punch releases when the N2 ends mid-kick", absf(last) <= 0.01,
			"%.4f m" % last)
	# 6 m/s: 0.05 m a tick at 120 Hz
	_report.check("the punch never moves faster than 6 m/s", worst_step <= 6.0 / Engine.physics_ticks_per_second, "%.4f m a tick" % worst_step)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_pull_in(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	# A wall 3.5 m behind the car: the camera may not be drawn inside it.
	var wall := _helpers.box(host, Vector3(30, 6, 0.5), Vector3(0, 3, 3.75))
	var sampler := Helpers.Sampler.new()
	sampler.cam = _helpers.cam
	host.add_child(sampler)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	_report.check("the drawn camera stops in front of the wall", sampler.worst >= 3.15,
			"z=%.3f over %d frames" % [sampler.worst, sampler.frames])
	sampler.queue_free()
	wall.queue_free()
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_effects(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	var car := _helpers.car
	var streaks := _helpers.cam_root.get_node_or_null(^"Overlay/SpeedLines") as ColorRect
	for i in Engine.physics_ticks_per_second:
		car.linear_velocity = Vector3(0, 0, -TOP_SPEED)
		car.telemetry.speed_kmh = 250.0
		await host.get_tree().physics_frame
	_report.check("the streaks are on at 250 km/h", streaks != null and streaks.visible)
	var victim := _helpers.new_car(host, Vector3(0, 0, 30), Vector3(0, 0, -15))
	Events.takedown.emit(victim, &"police")
	await _helpers.tick(host, Engine.physics_ticks_per_second / 6)
	_report.check("the streaks are hidden during the takedown", streaks != null and not streaks.visible)
	_report.near("the blur is off during the takedown", float(_state()["blur_strength"]), 0.0, 0.001)
	var last := 0.0
	var max_step := 0.0
	for i in Engine.physics_ticks_per_second * 10 / 3:
		await host.get_tree().physics_frame
		var blur := float(_state()["blur_strength"])
		max_step = maxf(max_step, absf(blur - last))
		last = blur
		if not _helpers.cam_root.call("is_takedown_active") and blur > 0.0:
			break
	_report.check("the blur ramps back after the cut", max_step <= 0.02, "max step %.4f" % max_step)
	_report.check("the blur comes back after the cut", float(_state()["blur_strength"]) > 0.0)
	# The pause hides the streaks at once: the camera does not tick while the game is paused.
	Game.set_paused(true)
	await host.get_tree().process_frame
	_report.check("the pause hides the streaks", streaks != null and not streaks.visible)
	Game.set_paused(false)
	await host.get_tree().process_frame
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_blur_centre(host: Node) -> void:
	Game.options["camera_preset"] = "bumper"
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	var centre := _state()["blur_centre"] as Vector2
	_report.check("the blur centre stays on the screen",
			centre.x >= 0.15 and centre.x <= 0.85 and centre.y >= 0.15 and centre.y <= 0.85, str(centre))
	_report.check("the hood view centres the blur on the vanishing point",
			centre.distance_to(Vector2(0.5, 0.5)) < 0.08, str(centre))
	Game.options.erase("camera_preset")
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame

extends Node
## The sky lane: the launch pad, the flight inside the tube, the N2 rings, the bank, the early
## exit and the boost that ends while the car is still in the lane.
## Run: tools/godot.sh test res://vehicle/tests/test_sky_lane.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const LaneTuning := preload("res://vehicle/tuning/lane_tuning.gd")

## The landing events of the car.
var _landed: Array[Dictionary] = []
## The toasts of the game.
var _toasts: Array[String] = []
## The moments the boost ended.
var _boost_ended: Array[float] = []
var _clock: float = 0.0
## The car of the current part of the test (the landing handler reads its altitude).
var _car: ArcadeCar = null


func _ready() -> void:
	_run.call_deferred()


## Spawns the car on the launch pad of the sandbox lane.
func _spawn_on_pad(t: T) -> ArcadeCar:
	# The sandbox lane starts at (250, 0, -30) and runs towards -X; the pad is at x = 265.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(320.0, 0.3, -30.0), PI * 0.5)
	await t.run(0.4)
	car.boost.n2 = 100.0
	t.set_speed(car, 150.0)
	return car


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.landed.connect(func(v: VehicleBase, airtime: float, impact: float,
			quality: StringName) -> void:
		if v != _car:
			return
		_landed.append({"airtime": airtime, "impact": impact, "quality": quality,
			"altitude": _car.telemetry.altitude_m}))
	events.toast.connect(func(text: String, _style: StringName) -> void: _toasts.append(text))
	events.boost_ended.connect(func(v: VehicleBase) -> void:
		if v == _car:
			_boost_ended.append(_clock))
	# --- the flight in the tube -------------------------------------------------------------
	var car: ArcadeCar = await _spawn_on_pad(t)
	_car = car
	var flew: bool = false
	var max_lateral: float = 0.0
	var max_jump: float = 0.0
	var rings: int = 0
	var last_n2: float = car.boost.n2
	var prev: Vector3 = car.global_position
	var bank: float = 0.0
	var pitch_error: float = 0.0
	for i in Engine.physics_ticks_per_second * 14:
		car.set_controls(0.0, 0.0, 1.0, false)
		await t.step()
		_clock += 1.0 / Engine.physics_ticks_per_second
		max_jump = maxf(max_jump, car.global_position.distance_to(prev))
		prev = car.global_position
		if car.telemetry.flying:
			flew = true
			max_lateral = maxf(max_lateral, absf(car.sky.lateral))
			if car.boost.n2 > last_n2 + 20.0:
				rings += 1
			last_n2 = car.boost.n2
			# The bank of the car and the slope of the lane it flies in (the take-off blend
			# is not part of the steady flight).
			if not car.sky.transitioning and absf(car.telemetry.roll_deg) > absf(bank):
				bank = car.telemetry.roll_deg
				# The lane frame errors past the end of the curve (core), so the offset is
				# clamped to the last two metres of the lane.
				var frame: Transform3D = car.sky.lane.frame_at(
						clampf(car.sky.offset, 0.0, car.sky.lane.length() - 2.0))
				var slope: float = rad_to_deg(asin(clampf(-frame.basis.z.y, -1.0, 1.0)))
				pitch_error = absf(car.telemetry.pitch_deg - slope)
		elif flew:
			break
	t.check("the car took off", flew)
	t.check("the car stayed in the tube", max_lateral <= 7.5, "= %.2f m off the centre" % max_lateral)
	t.check("the rings refilled the tank", rings >= 1, "= %d rings" % rings)
	t.check("the flight ended", not car.telemetry.flying)
	# The flight never teleports: the per tick move stays close to the speed.
	var limit: float = 1.5 * car.telemetry.speed_kmh / 3.6 / 120.0
	t.check("no teleport in the flight", max_jump <= limit + 0.05,
			"= %.2f m (limit %.2f m)" % [max_jump, limit])
	# The bank: the car leans into the move (the right side goes down), the pitch follows the
	# slope of the lane.
	t.check_range("the bank of the car", absf(bank), 29.0, 34.0)
	t.check("the bank leans into the move", bank < 0.0, "= %.1f deg" % bank)
	t.check_range("the pitch against the lane slope", pitch_error, 0.0, 2.0)
	# After the flight the car is back on the ground.
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.telemetry.grounded_wheels >= 3 and not car.telemetry.airborne:
			break
	t.check("the car landed", car.telemetry.grounded_wheels >= 3,
			"= %d wheels" % car.telemetry.grounded_wheels)
	car.queue_free()
	await t.run(0.3)
	# --- the early exit ---------------------------------------------------------------------
	_landed.clear()
	_toasts.clear()
	var car2: ArcadeCar = await _spawn_on_pad(t)
	_car = car2
	Game.player = car2
	# The exit happens at the crest of the lane, high above the road.
	for i in Engine.physics_ticks_per_second * 6:
		await t.step()
		_clock += 1.0 / Engine.physics_ticks_per_second
		if car2.telemetry.flying and car2.telemetry.altitude_m > 15.0:
			break
	t.check("the car took off again", car2.telemetry.flying)
	var altitude: float = car2.telemetry.altitude_m
	# The flight key leaves the tube: the car glides down instead of ending in mid air.
	Input.action_press(&"flight")
	await t.step()
	await t.step()
	Input.action_release(&"flight")
	t.check("the car left the tube", car2.sky.gliding, "= %.1f m high" % altitude)
	for i in Engine.physics_ticks_per_second * 12:
		await t.step()
		_clock += 1.0 / Engine.physics_ticks_per_second
		if not car2.telemetry.flying:
			break
	t.check("the flight ended on the ground", not car2.telemetry.flying)
	t.check("one landing", _landed.size() == 1, "= %s" % str(_landed))
	if _landed.size() == 1:
		t.check_range("the altitude of the landing", float(_landed[0]["altitude"]), 0.0, 0.5)
		t.check_range("the impact of the landing", float(_landed[0]["impact"]), 0.0, 6.0)
		# The glide time is reported (the airtime is read before the touchdown resets it).
		t.check("the glide time is reported", float(_landed[0]["airtime"]) > 0.5,
				"= %.2f s" % float(_landed[0]["airtime"]))
		# The quality is judged from the alignment of the car with the road.
		t.check("the landing quality is judged", String(_landed[0]["quality"]) in ["clean",
				"wobble", "crash"], "= %s" % String(_landed[0]["quality"]))
	var hard: int = 0
	for text: String in _toasts:
		if text.contains("HARD LANDING"):
			hard += 1
	t.check("no hard landing toast", hard == 0, "= %s" % str(_toasts))
	# The landing window (落地喷) is open after the touchdown.
	for i in Engine.physics_ticks_per_second:
		await t.step()
		if car2.telemetry.mini_window:
			break
	t.check("the landing window is open", car2.telemetry.mini_window)
	car2.queue_free()
	Game.player = null
	await t.run(0.3)
	# --- the boost that ends in the lane ----------------------------------------------------
	_boost_ended.clear()
	var car3: ArcadeCar = await _spawn_on_pad(t)
	_car = car3
	Game.player = car3
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		_clock += 1.0 / Engine.physics_ticks_per_second
		if car3.telemetry.flying:
			break
	car3.boost.n2 = BoostTuning.N2_MAX
	t.check("the nitro fires in the lane", car3.use_nitro())
	var fired_at: float = _clock
	for i in Engine.physics_ticks_per_second * 6:
		await t.step()
		_clock += 1.0 / Engine.physics_ticks_per_second
		if _boost_ended.size() > 0:
			break
	t.check("the boost ended once", _boost_ended.size() == 1, "= %s" % str(_boost_ended))
	if _boost_ended.size() == 1:
		t.check_range("the boost lasted", _boost_ended[0] - fired_at, 2.95, 3.05)
	Game.player = null
	t.finish()

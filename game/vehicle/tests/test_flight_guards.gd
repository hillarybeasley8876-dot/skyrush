extends Node
## The flight guards: no roll in the sky lane, a toast when the take-off is refused and the
## obstacle hit of the lane (dossier 5.4, 5.6).
## Run: tools/gd.py test res://vehicle/tests/test_flight_guards.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")

## The toasts of the game (the refusals and the obstacle hit).
var _toasts: Array[String] = []
## The style of every toast.
var _styles: Array[StringName] = []
## The damage amounts of the car of the current part.
var _damage: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


## Spawns the car on the launch pad of the sandbox lane (the pad is at x = 265).
func _spawn_on_pad(t: T) -> ArcadeCar:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(320.0, 0.3, -30.0), PI * 0.5)
	await t.run(0.4)
	car.boost.n2 = 100.0
	t.set_speed(car, 150.0)
	return car


## The lane of the sandbox.
func _lane(t: T) -> SkyLane:
	return t.world.get_node_or_null(^"SkyLane") as SkyLane


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.toast.connect(func(text: String, style: StringName) -> void:
		_toasts.append(text)
		_styles.append(style))
	await _roll_in_lane(t)
	await _roll_in_air(t)
	await _refusal(t)
	await _hit(t)
	t.finish()


## 1. In the lane the car flies on the rails: the roll is never seen, so it is refused and it
## costs no N2.
func _roll_in_lane(t: T) -> void:
	var car: ArcadeCar = await _spawn_on_pad(t)
	Game.player = car
	for i in 120 * 6:
		car.set_controls(1.0, 0.0, 0.0, false)
		await t.step()
		if car.telemetry.flying:
			break
	t.check("the car took off into the lane", car.telemetry.flying)
	var n2_before: float = car.boost.n2
	var rolled: bool = car.api.request_roll(car, 1)
	t.check("the roll in the lane is refused", not rolled)
	t.check("the refused roll costs no N2", absf(car.boost.n2 - n2_before) < 0.01,
			"= %.1f (was %.1f)" % [car.boost.n2, n2_before])
	t.check("the car does not roll in the lane", not car.thruster.rolling)
	car.queue_free()
	Game.player = null
	await t.run(0.2)


## 2. The control: a car in the air (a hop outside the lane) still rolls and pays 20 N2.
func _roll_in_air(t: T) -> void:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	car.boost.n2 = 100.0
	t.check("the hop starts", car.request_hop())
	for i in 120 * 2:
		await t.step()
		if car.thruster.airborne:
			break
	t.check("the car is in the air", car.thruster.airborne)
	var n2_before: float = car.boost.n2
	var rolled: bool = car.api.request_roll(car, 1)
	t.check("the roll in the air works", rolled)
	t.check("the roll costs 20 N2",
			absf(n2_before - car.boost.n2 - AirTuning.ROLL_COST) < 0.01,
			"= %.1f (was %.1f)" % [car.boost.n2, n2_before])
	t.check("the car rolls", car.thruster.rolling)
	car.queue_free()
	await t.run(0.2)


## 3. A refused take-off tells the player why: the speed limit or the empty tank.
## 5. The toast is throttled: one every 3 s, so a second pass over the pad is quiet.
func _refusal(t: T) -> void:
	# An AI car over the pad: no toast at all.
	_toasts.clear()
	_styles.clear()
	var ai: ArcadeCar = await _spawn_on_pad(t)
	Game.player = null
	for i in 120 * 5:
		ai.set_controls(0.0, 0.0, 0.0, false)
		t.set_speed(ai, 60.0)
		await t.step()
		if ai.telemetry.flying:
			break
	t.check("the AI car does not fly", not ai.telemetry.flying)
	t.check("no toast for an AI car", _toasts.is_empty(), "= %s" % str(_toasts))
	ai.queue_free()
	await t.run(0.2)
	# The player is too slow for the pad (it needs 120 km/h).
	_toasts.clear()
	_styles.clear()
	var slow: ArcadeCar = await _spawn_on_pad(t)
	Game.player = slow
	for i in 120 * 5:
		slow.set_controls(0.0, 0.0, 0.0, false)
		t.set_speed(slow, 60.0)
		await t.step()
		if _toasts.size() > 0:
			break
	t.check("the slow car does not fly", not slow.telemetry.flying)
	t.check("one toast for the slow take-off", _toasts.size() == 1, "= %s" % str(_toasts))
	if _toasts.size() == 1:
		t.check("the toast names the speed limit", _toasts[0].contains("120"),
				"= %s" % _toasts[0])
		t.check("the refusal toast is info", _styles[0] == &"info", "= %s" % str(_styles[0]))
	# The same pad a second time: one toast every 3 s, so the second one is quiet.
	var lane: SkyLane = _lane(t)
	t.check("the sandbox has a lane", lane != null)
	slow.api.try_flight(slow, lane)
	t.check("no second toast", _toasts.size() == 1, "= %s" % str(_toasts))
	await t.run(3.2)
	slow.api.try_flight(slow, lane)
	t.check("a new toast after 3 s", _toasts.size() == 2, "= %s" % str(_toasts))
	slow.queue_free()
	Game.player = null
	await t.run(0.2)
	# The tank is too empty for the pad (it needs 25 N2).
	_toasts.clear()
	_styles.clear()
	var dry: ArcadeCar = await _spawn_on_pad(t)
	Game.player = dry
	dry.boost.n2 = 5.0
	for i in 120 * 5:
		dry.set_controls(1.0, 0.0, 0.0, false)
		await t.step()
		if _toasts.size() > 0:
			break
	t.check("the dry car does not fly", not dry.telemetry.flying)
	t.check("one toast for the dry take-off", _toasts.size() == 1, "= %s" % str(_toasts))
	if _toasts.size() == 1:
		t.check("the toast names the tank", _toasts[0].contains("25"), "= %s" % _toasts[0])
		t.check("the tank toast is info", _styles[0] == &"info", "= %s" % str(_styles[0]))
	dry.queue_free()
	Game.player = null
	await t.run(0.2)


## 6. The obstacle in the lane: 15 HP, 30 % of the speed, never a wreck, once per second.
func _hit(t: T) -> void:
	_toasts.clear()
	_styles.clear()
	_damage.clear()
	var car: ArcadeCar = await _spawn_on_pad(t)
	Game.player = car
	car.damaged.connect(func(amount: float, _point: Vector3, _source: Node3D) -> void:
		_damage.append(amount))
	for i in 120 * 6:
		car.set_controls(1.0, 0.0, 0.0, false)
		await t.step()
		if car.telemetry.flying and not car.sky.transitioning:
			break
	t.check("the car took off into the lane", car.telemetry.flying)
	if not car.api.has_method("flight_hit"):
		t.check("the car has the obstacle hit API", false)
		return
	var health_before: float = car.health
	var speed_before: float = car.sky.speed
	t.check("the obstacle hit counts", car.api.flight_hit(car))
	t.check("the hit costs 15 HP", absf(health_before - car.health - 15.0) < 0.1,
			"= %.1f (was %.1f)" % [car.health, health_before])
	t.check("the hit takes 30 % of the speed",
			absf(car.sky.speed - speed_before * 0.7) <= speed_before * 0.03,
			"= %.1f m/s (was %.1f m/s)" % [car.sky.speed, speed_before])
	t.check("the lane speed stays above 120 km/h", car.sky.speed * 3.6 >= 120.0,
			"= %.0f km/h" % (car.sky.speed * 3.6))
	t.check("the car is not wrecked", not car.is_wrecked)
	t.check("the hit raises the damage event", _damage.size() == 1 and absf(_damage[0] - 15.0) < 0.1,
			"= %s" % str(_damage))
	t.check("the hit has a toast", _toasts.size() == 1 and _toasts[0].contains("HIT"),
			"= %s" % str(_toasts))
	t.check("the hit toast is danger", _styles.size() == 1 and _styles[0] == &"danger",
			"= %s" % str(_styles))
	# The car keeps flying.
	for i in 60:
		await t.step()
	t.check("the car still flies after the hit", car.telemetry.flying)
	# A second hit right away does nothing.
	var health_now: float = car.health
	var speed_now: float = car.sky.speed
	t.check("the second hit is refused", not car.api.flight_hit(car))
	t.check("the refused hit changes nothing",
			absf(car.health - health_now) < 0.01 and absf(car.sky.speed - speed_now) < 0.01,
			"= %.1f HP, %.1f m/s" % [car.health, car.sky.speed])
	# After the immunity the hit counts again.
	for i in 120 * 2:
		await t.step()
	t.check("the third hit counts", car.api.flight_hit(car))
	t.check("the third hit costs 15 HP", absf(health_now - car.health - 15.0) < 0.1,
			"= %.1f" % car.health)
	# The obstacle never wrecks the car: the health stops at 1 HP.
	await t.run(1.2)
	car.health = 5.0
	t.check("the last hit counts", car.api.flight_hit(car))
	t.check("the car keeps 1 HP", absf(car.health - 1.0) < 0.01, "= %.2f" % car.health)
	t.check("the lane speed stops at 120 km/h", absf(car.sky.speed * 3.6 - 120.0) < 1.0,
			"= %.0f km/h" % (car.sky.speed * 3.6))
	t.check("the car is still not wrecked", not car.is_wrecked)
	t.check("the health gauge follows", absf(car.telemetry.health_norm - 0.01) < 0.001,
			"= %.3f" % car.telemetry.health_norm)
	car.queue_free()
	Game.player = null
	await t.run(0.2)

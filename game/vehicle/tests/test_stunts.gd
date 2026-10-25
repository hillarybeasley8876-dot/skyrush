extends Node
## The stunts of the player (SPEC section 3): the fly-overs pay N2, and the long airtime, the
## barrel roll and the drift chain are stunts of their own.
## The long jump is made by throwing the car up with a vertical speed (like a ramp): the test
## needs a flight of about 2.5 s and a Big Hop alone only reaches 1.9 s.
## Run: python tools/gd.py test res://vehicle/tests/test_stunts.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

## The vertical speed of the test jump (m/s): about 2.5 s of airtime.
const JUMP_VY := 24.0

## The stunts the game reported: {"kind": StringName, "points": int}.
var _stunts: Array[Dictionary] = []
## The airtimes of the landings of the car.
var _landings: Array[float] = []
## The durations of the drifts of the car.
var _drifts: Array[float] = []
## The car of the current part of the test.
var _car: ArcadeCar = null


func _ready() -> void:
	_run.call_deferred()


func _on_stunt(kind: StringName, points: int, _label: String) -> void:
	_stunts.append({"kind": kind, "points": points})


func _on_landed(vehicle: VehicleBase, airtime: float, _impact: float, _quality: StringName) -> void:
	if vehicle != _car:
		return
	_landings.append(airtime)


func _on_drift_ended(vehicle: VehicleBase, duration: float, _clean: bool, _gained: float) -> void:
	if vehicle != _car:
		return
	_drifts.append(duration)


## The stunts of one kind.
func _of_kind(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in _stunts:
		if s["kind"] == kind:
			out.append(s)
	return out


## Spawns the player car and clears the records. The car before is freed: the player car reads
## the keyboard, so two player cars would fight over the same keys.
func _player(t: T, pos: Vector3, yaw: float) -> ArcadeCar:
	Game.player = null
	if _car != null:
		_car.queue_free()
		await t.step()
	_car = await t.spawn_car(t.roadster(), pos, yaw)
	Game.player = _car
	_stunts.clear()
	_landings.clear()
	_drifts.clear()
	await t.run(0.4)
	return _car


## Throws the car up and waits for the landing. Returns the airtime (-1 when it did not land).
func _jump(t: T, vy: float) -> float:
	_landings.clear()
	_car.linear_velocity = Vector3(0.0, vy, 0.0)
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		if _landings.size() > 0:
			return _landings[0]
	return -1.0


## Waits until the car is off the ground. Returns false when it did not get there in time.
func _wait_air(t: T) -> bool:
	for i in Engine.physics_ticks_per_second * 2:
		await t.step()
		if _car.telemetry.airborne:
			return true
	return false


## Drifts for the given time and ends the drift with a counter steer. Returns the duration the
## game reported (-1 when the drift did not end).
## The player car reads the keyboard, so the drift uses the keys and not the AI controls.
func _drift(t: T, seconds: float) -> float:
	_drifts.clear()
	t.set_speed(_car, 200.0)
	Input.action_press(&"drift")
	Input.action_press(&"steer_right")
	await t.run(seconds)
	Input.action_release(&"drift")
	Input.action_release(&"steer_right")
	Input.action_press(&"steer_left")
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if _drifts.size() > 0:
			break
	Input.action_release(&"steer_left")
	return _drifts[0] if _drifts.size() > 0 else -1.0


## Waits until the drift is over and the car is in grip again.
func _wait_grip(t: T) -> void:
	for i in Engine.physics_ticks_per_second * 3:
		if _car.drift.state == &"grip":
			return
		await t.step()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.stunt.connect(_on_stunt)
	events.landed.connect(_on_landed)
	events.drift_ended.connect(_on_drift_ended)
	# --- 1. the fly-overs pay N2 --------------------------------------------------------------
	var car: ArcadeCar = await _player(t, Vector3(0.0, 0.15, 0.0), 0.0)
	car.boost.n2 = 50.0
	events.stunt.emit(&"fly_over_gas", 800, "飞跃加油站!")
	t.check_close("the fly-over N2", car.boost.n2, 90.0, 0.01)
	# The kinds that pay on their own never pay twice.
	car.boost.n2 = 50.0
	events.stunt.emit(&"takedown", 100, "t")
	events.stunt.emit(&"trick", 15, "t")
	events.stunt.emit(&"escape", 100, "t")
	t.check_close("no N2 for the other stunts", car.boost.n2, 50.0, 0.01)
	# --- 2. the long airtime ------------------------------------------------------------------
	car.boost.n2 = 150.0
	var airtime: float = await _jump(t, JUMP_VY)
	t.check("the car landed", airtime > 0.0, "= %.2f s" % airtime)
	t.check_range("the airtime of the jump", airtime, 2.0, 3.5)
	var jumps: Array[Dictionary] = _of_kind(&"airtime")
	t.check("one airtime stunt", jumps.size() == 1, "= %s" % str(_stunts))
	if jumps.size() == 1:
		t.check("the airtime points", int(jumps[0]["points"]) == int(airtime * 100.0),
				"= %d (the airtime is %.2f s)" % [int(jumps[0]["points"]), airtime])
		t.check_range("the airtime points", float(jumps[0]["points"]), 200.0, 320.0)
	t.check_close("the airtime N2", car.boost.n2, 170.0, 0.5)
	# --- 3. the barrel roll -------------------------------------------------------------------
	# A fresh car for every part: a hard landing leaves the car in the ground.
	car = await _player(t, Vector3(0.0, 0.15, 0.0), 0.0)
	car.boost.n2 = 150.0
	car.linear_velocity = Vector3(0.0, JUMP_VY, 0.0)
	t.check("the car is in the air", await _wait_air(t))
	t.check("the roll starts", car.request_roll(1))
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		if _of_kind(&"barrel_roll").size() > 0:
			break
	var rolls: Array[Dictionary] = _of_kind(&"barrel_roll")
	t.check("one barrel roll stunt", rolls.size() == 1, "= %s" % str(_stunts))
	if rolls.size() == 1:
		t.check("the barrel roll points", int(rolls[0]["points"]) == 200,
				"= %d" % int(rolls[0]["points"]))
	# Two rolls in one flight: two stunts.
	car = await _player(t, Vector3(0.0, 0.15, 0.0), 0.0)
	car.boost.n2 = 150.0
	car.linear_velocity = Vector3(0.0, JUMP_VY, 0.0)
	await _wait_air(t)
	t.check("the first roll starts", car.request_roll(1))
	for i in Engine.physics_ticks_per_second * 2:
		await t.step()
		if not car.thruster.rolling:
			break
	t.check("the second roll starts", car.request_roll(-1))
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		if _of_kind(&"barrel_roll").size() >= 2:
			break
	t.check("two barrel roll stunts", _of_kind(&"barrel_roll").size() == 2, "= %s" % str(_stunts))
	# --- 4. a short flight is no airtime ------------------------------------------------------
	car = await _player(t, Vector3(0.0, 0.15, 0.0), 0.0)
	# The wheel probes reach 0.9 m below the car, so the car has to be lifted further than that
	# to leave the ground.
	car.linear_velocity = Vector3.ZERO
	car.global_position.y += 1.5
	var short_airtime: float = -1.0
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if _landings.size() > 0:
			short_airtime = _landings[0]
			break
	t.check_range("the airtime of the short flight", short_airtime, 0.0, 1.0)
	t.check("no airtime stunt for the short flight", _of_kind(&"airtime").is_empty(),
			"= %s" % str(_stunts))
	# --- 5. the drift chain -------------------------------------------------------------------
	await _player(t, Vector3(0.0, 0.15, 300.0), 0.0)
	for i in 3:
		var duration: float = await _drift(t, 1.6)
		t.check_range("the drift %d lasted" % (i + 1), duration, 1.0, 2.0)
		await _wait_grip(t)
	t.check("one drift chain", _of_kind(&"drift_chain").size() == 1, "= %s" % str(_stunts))
	# Two drifts are not a chain.
	await _player(t, Vector3(0.0, 0.15, 300.0), 0.0)
	for i in 2:
		await _drift(t, 1.6)
		await _wait_grip(t)
	t.check("no drift chain after two drifts", _of_kind(&"drift_chain").is_empty(),
			"= %s" % str(_stunts))
	# Three drifts with a pause of 15 s between them: not a chain.
	await _player(t, Vector3(0.0, 0.15, 300.0), 0.0)
	await _drift(t, 1.6)
	await _wait_grip(t)
	# The pause: the car coasts to a stop and the chain window runs out.
	await t.run(15.0)
	await _drift(t, 1.6)
	await _wait_grip(t)
	await _drift(t, 1.6)
	await _wait_grip(t)
	t.check("no drift chain with a 15 s pause", _of_kind(&"drift_chain").is_empty(),
			"= %s" % str(_stunts))
	# --- 6. the sky lane has its own rules ----------------------------------------------------
	await _player(t, Vector3(320.0, 0.3, -30.0), PI * 0.5)
	_car.boost.n2 = 100.0
	t.set_speed(_car, 150.0)
	for i in Engine.physics_ticks_per_second * 20:
		await t.step()
		if _car.telemetry.flying:
			break
	t.check("the car took off", _car.telemetry.flying)
	for i in Engine.physics_ticks_per_second * 20:
		await t.step()
		if not _car.telemetry.flying and _landings.size() > 0:
			break
	t.check("no airtime stunt in the sky lane", _of_kind(&"airtime").is_empty(),
			"= %s" % str(_stunts))
	Game.player = null
	if _car != null:
		_car.queue_free()
	t.finish()

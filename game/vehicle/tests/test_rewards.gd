extends Node
## The N2 rewards of dossier 5.2: a takedown is worth 50 and +25 per streak step, a near miss 5
## and a clean trick landing 15 (the lead note V-INT3). The trick is paid out once per jump:
## a plain hop and a road crest never pay out the trick of an earlier jump.
## Run: tools/godot.sh test res://vehicle/tests/test_rewards.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const RewardTuning := preload("res://vehicle/tuning/reward_tuning.gd")

## The hop events of the car.
var _hops: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


## A hop through the player input (the InputMap path): a tap, a Big Hop (the key is held) or a
## roll. Returns the kind of the hop.
func _hop(t: T, car: ArcadeCar, big: bool) -> StringName:
	_hops.clear()
	Input.action_press(&"hop")
	await t.step()
	if big:
		for i in Engine.physics_ticks_per_second / 3:
			await t.step()
	Input.action_release(&"hop")
	# The impulse fires after the spool (0.08 s / 0.15 s).
	for i in Engine.physics_ticks_per_second / 2:
		await t.step()
		if _hops.size() > 0:
			break
	return _hops[0] if _hops.size() > 0 else &""


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	var toasts: Array[String] = []
	events.toast.connect(func(text: String, _style: StringName) -> void: toasts.append(text))
	var stunts: Array[Dictionary] = []
	events.stunt.connect(func(kind: StringName, points: int, label: String) -> void:
		stunts.append({"kind": kind, "points": points, "label": label}))
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	Game.player = car
	events.hop.connect(func(v: VehicleBase, kind: StringName) -> void:
		if v == car:
			_hops.append(kind))
	# The takedown: +50.
	car.boost.n2 = 0.0
	events.takedown.emit(car, &"rival")
	t.check_close("the takedown", car.boost.n2, RewardTuning.TAKEDOWN_N2, 0.01)
	# A second takedown inside the streak window: +75.
	await t.run(3.0)
	car.boost.n2 = 0.0
	events.takedown.emit(car, &"rival")
	t.check_close("the takedown streak", car.boost.n2,
			RewardTuning.TAKEDOWN_N2 + RewardTuning.TAKEDOWN_STREAK_N2, 0.01)
	# A takedown after the window: +50 again.
	await t.run(RewardTuning.TAKEDOWN_STREAK_WINDOW + 2.0)
	car.boost.n2 = 0.0
	events.takedown.emit(car, &"rival")
	t.check_close("the takedown after the window", car.boost.n2, RewardTuning.TAKEDOWN_N2, 0.01)
	# The near miss: +5.
	car.boost.n2 = 0.0
	events.near_miss.emit(car, car)
	t.check_close("the near miss", car.boost.n2, RewardTuning.NEAR_MISS_N2, 0.01)
	# The trick: a clean Big Hop landing is worth 15 and shows one pop-up (the stunt event).
	car.boost.n2 = 0.0
	toasts.clear()
	stunts.clear()
	# The Big Hop through the thruster (the car is the player here). The tank is filled right
	# before the release, so the hop can pay for itself.
	car.boost.n2 = 100.0
	var kind: StringName = await _hop(t, car, true)
	t.check("the Big Hop fired", kind == &"big_hop", "= %s" % kind)
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.dynamics.landed:
			break
	t.check("the car landed", car.dynamics.landed, "= %d wheels" % car.telemetry.grounded_wheels)
	t.check_close("the trick landing", car.boost.n2,
			100.0 - AirTuning.BIG_HOP_COST + RewardTuning.TRICK_N2, 1.0)
	# The trick is one pop-up: the stunt event, not a toast of its own.
	t.check("one trick stunt", stunts.size() == 1 and String(stunts[0]["kind"]) == "trick",
			"= %s" % str(stunts))
	if stunts.size() == 1:
		t.check("the trick points", int(stunts[0]["points"]) == 15, "= %s" % str(stunts[0]))
	t.check("no trick toast", toasts.is_empty(), "= %s" % str(toasts))
	# A plain hop is no trick: the Big Hop of the jump before must not pay out again.
	stunts.clear()
	car.boost.n2 = 100.0
	var tap: StringName = await _hop(t, car, false)
	t.check("the tap hop fired", tap == &"hop", "= %s" % tap)
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.dynamics.landed:
			break
	t.check("no trick for a plain hop", stunts.is_empty(), "= %s" % str(stunts))
	t.check_close("the N2 after a plain hop", car.boost.n2, 100.0 - AirTuning.HOP_COST, 1.0)
	# Three 0.6 m drops (a road crest): no trick and no N2. The tank is full, so the
	# self-filling compressor does not change it either.
	stunts.clear()
	car.boost.n2 = 200.0
	var before: float = car.boost.n2
	for i in 3:
		car.global_position.y += 0.6
		await t.run(1.2)
	t.check("no trick for the drops", stunts.is_empty(), "= %s" % str(stunts))
	t.check_close("the N2 after the drops", car.boost.n2, before, 0.01)
	# A barrel roll and a clean landing: one trick.
	stunts.clear()
	car.boost.n2 = 100.0
	var roll_kind: StringName = await _hop(t, car, false)
	t.check("the roll hop fired", roll_kind == &"hop", "= %s" % roll_kind)
	# The roll starts in the air and ends before the touchdown.
	for i in Engine.physics_ticks_per_second:
		await t.step()
		if car.telemetry.airborne:
			break
	t.check("the car is in the air", car.telemetry.airborne, "= %.2f m" % car.telemetry.altitude_m)
	t.check("the roll starts", car.request_roll(1))
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.dynamics.landed:
			break
	t.check("the car landed after the roll", car.dynamics.landed,
			"= %d wheels" % car.telemetry.grounded_wheels)
	t.check("one trick for the roll", stunts.size() == 1, "= %s" % str(stunts))
	# The events the HUD shows itself must not pop up twice (one event = one pop-up).
	toasts.clear()
	car.boost.n2 = 0.0
	events.takedown.emit(car, &"rival")
	events.near_miss.emit(car, car)
	events.charge_finished.emit(car, null, 1.0)
	car.events.start_launch()
	car.drift.exit_clean = true
	car.drift.exit_gauge = 1.0
	car.events.on_drift_state_changed()
	t.check("no toast of the car", toasts.is_empty(), "= %s" % str(toasts))
	# A real fall (the deck of the sandbox, 9 m) is a hard landing: one toast, and the car
	# gets no cushion (the cushion belongs to the jumps the car makes itself).
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(80.0, 9.4, 110.0), 0.0)
	Game.player = car2
	t.set_speed(car2, 20.0)
	toasts.clear()
	await t.run(4.0)
	var hard: int = 0
	for text: String in toasts:
		if text.contains("HARD LANDING"):
			hard += 1
	t.check("one hard landing toast", hard == 1, "= %s" % str(toasts))
	Game.player = null
	t.finish()

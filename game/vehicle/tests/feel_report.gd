extends Node
## The feel report: every measured number of the car in one table (dossier 8.1, the brief).
## Run: tools/godot.sh test res://vehicle/tests/feel_report.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const FeelHelpers := preload("res://vehicle/tests/feel_helpers.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")

var _rows: Array = []


func _row(name: String, value: String, want: String) -> void:
	_rows.append([name, value, want])


func _ready() -> void:
	_run.call_deferred()


## The roll angle of the car about its own forward axis, in degrees.
func _roll_angle(car: ArcadeCar) -> float:
	var basis: Basis = car.global_transform.basis
	var fwd: Vector3 = -basis.z
	var up: Vector3 = basis.y
	var ref: Vector3 = Vector3.UP - fwd * Vector3.UP.dot(fwd)
	if ref.length() < 0.01:
		return 0.0
	ref = ref.normalized()
	var side: Vector3 = fwd.cross(ref).normalized()
	return rad_to_deg(atan2(up.dot(side), up.dot(ref)))


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var helper := FeelHelpers.new()
	# --- the acceleration and the top speed -------------------------------------------------
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	car.set_controls(1.0, 0.0, 0.0, false)
	var t100: float = -1.0
	var clock: float = 0.0
	var top: float = 0.0
	for i in 120 * 13:
		await t.step()
		clock += 1.0 / 120.0
		top = maxf(top, car.telemetry.forward_speed_kmh)
		if i % 60 == 0:
			t.keep_on_ground(car)
		if t100 < 0.0 and car.telemetry.forward_speed_kmh >= 100.0:
			t100 = clock
	_row("0-100 km/h", "%.2f s" % t100, "2.3 +- 0.3 s")
	_row("top speed", "%.1f km/h" % top, "250 +- 5 km/h")
	_row("physics CPU (forces)", "%.0f us/tick" % car.cpu_usec, "<= 250 us")
	_row("physics CPU (frame)", "%.0f us/tick" % car.frame_cpu_usec, "<= 250 us")
	# --- the N2 boost -----------------------------------------------------------------------
	car.boost.n2 = BoostTuning.N2_MAX
	car.use_nitro()
	var boosted: float = 0.0
	for i in 120 * 3:
		await t.step()
		boosted = maxf(boosted, car.telemetry.forward_speed_kmh)
	_row("N2 top speed", "%.1f km/h" % boosted, "300 +- 8 km/h")
	for pat: String in ["C", "W", "CW", "WCW", "CWW", "WCWW"]:
		_row("cap %s" % pat, "%.1f km/h" % (BoostMod.cap_for_pattern(DriveTuning.V_TOP, pat) * 3.6),
				"the QQ table")
	# --- the brake -------------------------------------------------------------------------
	t.set_speed(car, 100.0)
	await t.run(0.2)
	var start: Vector3 = car.global_position
	car.set_controls(0.0, 1.0, 0.0, false)
	for i in 120 * 5:
		await t.step()
		if car.telemetry.forward_speed_kmh <= 1.0:
			break
	_row("brake 100-0", "%.1f m" % t.distance_travelled(start, car.global_position), "<= 35 m")
	car.queue_free()
	await t.run(0.3)
	# --- the launch -------------------------------------------------------------------------
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 400.0), 0.0)
	await t.run(0.5)
	car2.set_controls(0.0, 0.0, 0.0, false)
	await t.step()
	car2.set_controls(1.0, 0.0, 0.0, false)
	await t.run(0.2)
	t.events().race_started.emit()
	var launch: float = -1.0
	clock = 0.0
	for i in 120 * 3:
		await t.step()
		clock += 1.0 / 120.0
		if launch < 0.0 and car2.telemetry.forward_speed_kmh >= 100.0:
			launch = clock
	_row("0-100 with the launch", "%.2f s" % launch, "0.9 +- 0.2 s")
	car2.queue_free()
	await t.run(0.3)
	# --- the drift --------------------------------------------------------------------------
	for hold: float in [-1.0, -0.45, 1.0]:
		var car3: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
		await t.run(0.5)
		t.set_speed(car3, 200.0)
		await t.run(0.3)
		car3.boost.n2 = 0.0
		# The drift is entered to the right, the hold steer decides the slip angle.
		car3.set_drift(true)
		car3.set_controls(1.0, 0.0, 1.0, false)
		for i in 36:
			await t.step()
		car3.set_controls(1.0, 0.0, hold, false)
		var beta_sum: float = 0.0
		var beta_samples: int = 0
		var beta_max: float = 0.0
		for i in 120 * 3:
			await t.step()
			var beta: float = absf(car3.telemetry.slip_angle_deg)
			beta_max = maxf(beta_max, beta)
			if i >= 120 * 2:
				beta_sum += beta
				beta_samples += 1
		car3.set_drift(false)
		car3.set_controls(1.0, 0.0, -1.0, false)
		for i in 120 * 3:
			await t.step()
			if car3.telemetry.drift_state == &"grip":
				break
		_row("drift slip (hold %+.1f)" % hold, "%.1f deg (peak %.1f)" % [
				beta_sum / maxf(float(beta_samples), 1.0), beta_max], "26 .. 52 deg")
		# The gauge band of the dossier (95..105 N2) is the one of a drift at about 35 deg of
		# slip; a deeper drift earns more by design (dossier 1.3), so that row is an info row.
		var gauge_target: String = "95 .. 105 N2" if absf(hold) < 0.6 else "—"
		_row("drift gauge (hold %+.1f)" % hold, "%.0f N2" % car3.boost.n2, gauge_target)
		car3.queue_free()
		await t.run(0.3)
	# --- the drift exits ---------------------------------------------------------------------
	# The neutral release and the counter steer: the exit time and the slip after it.
	for exit_kind: String in ["counter", "release"]:
		var carE: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
		await t.run(0.5)
		t.set_speed(carE, 200.0)
		carE.set_controls(1.0, 0.0, 1.0, false)
		carE.set_drift(true)
		await t.run(2.0)
		var steer: float = -0.5 if exit_kind == "counter" else 0.0
		var out: Array = await helper.exit_series(t, carE, steer)
		var series: Array = out[0]
		_row("drift exit (%s)" % exit_kind, "%.2f s" % float(out[1]), "<= 1.0 s")
		_row("drift exit slip (+0.35 s, %s)" % exit_kind,
				"%.1f deg" % helper.slip_at(series, 0.35), "<= 12 deg")
		_row("drift exit slip (+0.60 s, %s)" % exit_kind,
				"%.1f deg" % helper.slip_at(series, 0.60), "<= 5 deg")
		carE.queue_free()
		await t.run(0.3)
	# --- the thrusters -----------------------------------------------------------------------
	# The hop and the Big Hop at every speed: the apex must not depend on the speed (the
	# downforce of the fan car needs the ground under it).
	for kmh: float in [0.0, 150.0, 250.0]:
		var car4: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 600.0), 0.0)
		await t.run(0.6)
		var hop: Array = await helper.hop(t, car4, kmh, false)
		_row("hop apex at %d km/h" % int(kmh), "%.2f m" % float(hop[0]), "3.1 +- 0.3 m")
		await t.run(0.5)
		var big: Array = await helper.hop(t, car4, kmh, true)
		_row("Big Hop apex at %d km/h" % int(kmh), "%.2f m" % float(big[0]), "7.8 +- 0.4 m")
		if kmh > 0.0:
			_row("Big Hop above 7 m at %d km/h" % int(kmh), "%.2f s" % float(big[1]), ">= 0.5 s")
		car4.queue_free()
		await t.run(0.3)
	# The barrel roll.
	var car5: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 800.0), 0.0)
	await t.run(0.6)
	car5.boost.n2 = BoostTuning.N2_MAX
	car5.thruster.hop_held = true
	car5.thruster.hop_pressed = true
	await t.step()
	car5.thruster.hop_pressed = false
	car5.thruster.hop_held = false
	car5.thruster.hop_released = true
	await t.step()
	car5.thruster.hop_released = false
	for i in 60:
		await t.step()
		if car5.telemetry.airborne:
			break
	car5.request_roll(1)
	var angle: float = 0.0
	var duration: float = 0.0
	var previous: float = _roll_angle(car5)
	for i in 120 * 2:
		await t.step()
		duration += 1.0 / 120.0
		var now: float = _roll_angle(car5)
		angle += wrapf(now - previous, -180.0, 180.0)
		previous = now
		if not car5.thruster.rolling:
			break
	_row("barrel roll", "%.0f deg in %.2f s" % [angle, duration], "360 deg in 0.70 s")
	car5.queue_free()
	await t.run(0.3)
	# --- the landing -------------------------------------------------------------------------
	var car6: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 8.0, 0.0), 0.0)
	await t.run(0.2)
	t.set_speed(car6, 150.0)
	var drop_start: Vector3 = car6.global_position
	for i in 120 * 3:
		await t.step()
		if car6.telemetry.grounded_wheels >= 3 and car6.telemetry.airtime == 0.0:
			break
	var forward: Vector3 = -car6.global_transform.basis.z
	var along: Vector3 = Vector3(car6.global_position.x - drop_start.x, 0.0,
			car6.global_position.z - drop_start.z)
	_row("landing lateral drift", "%.3f m" % absf(along.dot(Vector3(forward.z, 0.0, -forward.x))),
			"< 0.3 m")
	car6.queue_free()
	await t.run(0.3)
	# --- the stability -----------------------------------------------------------------------
	var car7: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	car7.set_controls(1.0, 0.0, 0.0, false)
	for i in 120 * 10:
		await t.step()
		if i % 60 == 0:
			t.keep_on_ground(car7)
	car7.boost.n2 = BoostTuning.N2_MAX
	car7.use_nitro()
	for i in 120 * 3:
		await t.step()
		if i % 60 == 0:
			t.keep_on_ground(car7)
	var top_stable: float = car7.telemetry.forward_speed_kmh
	var max_roll: float = 0.0
	for steer: float in [0.8, -0.8]:
		car7.set_controls(1.0, 0.0, steer, false)
		for i in 120 * 2:
			await t.step()
			max_roll = maxf(max_roll, absf(car7.telemetry.roll_deg))
			if i % 60 == 0:
				t.keep_on_ground(car7)
	_row("stability speed", "%.0f km/h" % top_stable, "300 km/h")
	_row("stability at 300 km/h", "max roll %.1f deg" % max_roll, "< 25 deg")
	car7.queue_free()
	await t.run(0.3)
	# --- the sky lane ------------------------------------------------------------------------
	var car8: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(320.0, 0.3, -30.0), PI * 0.5)
	await t.run(0.4)
	car8.boost.n2 = 100.0
	t.set_speed(car8, 150.0)
	var max_lateral: float = 0.0
	var max_jump: float = 0.0
	var prev_pos: Vector3 = car8.global_position
	for i in 120 * 12:
		car8.set_controls(0.0, 0.0, 1.0, false)
		await t.step()
		max_jump = maxf(max_jump, car8.global_position.distance_to(prev_pos))
		prev_pos = car8.global_position
		if car8.telemetry.flying:
			max_lateral = maxf(max_lateral, absf(car8.sky.lateral))
		elif i > 10 and car8.telemetry.speed_kmh > 0.0 and max_lateral > 0.0:
			break
	_row("sky lane lateral", "%.2f m" % max_lateral, "<= 7.5 m")
	_row("sky lane per tick move", "%.2f m" % max_jump, "<= 1.5 x v x dt")
	car8.queue_free()
	await t.run(0.3)
	# --- the charge bay ----------------------------------------------------------------------
	var car9: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(-450.0, 0.3, -224.0),
			-PI * 0.5)
	await t.run(0.4)
	car9.boost.n2 = 20.0
	car9.power.battery = 0.4
	t.set_speed(car9, 100.0)
	for i in 120 * 3:
		await t.step()
		if car9.boost.n2 >= BoostTuning.N2_MAX:
			break
	_row("charge bay", "%.0f N2, battery %.2f" % [car9.boost.n2, car9.power.battery],
			"200 N2, battery 1.0")
	# --- the table ---------------------------------------------------------------------------
	print("")
	print("%-26s %-20s %s" % ["MEASURE", "VALUE", "TARGET"])
	print("%-26s %-20s %s" % ["--------------------------", "------------------", "------------------"])
	for row: Array in _rows:
		print("%-26s %-20s %s" % [row[0], row[1], row[2]])
	print("")
	t.finish()

extends Node
## The QQ drift: the slip angle follows the steer input (the counter steer holds the shallow end
## of the band, the full steer the deep end), a 3 s drift fills one N2 slot (95-105 units) and
## the car never spins out (dossier 4.6). The exits are checked too: a released drift has to
## end, the nose has to be straight again before the 小喷, and one 断位 must not change the
## next drift.
## Run: tools/godot.sh test res://vehicle/tests/test_drift.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

## The heading of the car in degrees.
func _heading(car: ArcadeCar) -> float:
	var f: Vector3 = -car.global_transform.basis.z
	return rad_to_deg(atan2(f.x, -f.z))


## Drifts to the right and then holds the given steer. Returns the settled slip angle (the
## average of the last second), the peak slip and the peak yaw rate.
func _drift(t: T, car: ArcadeCar, hold: float) -> Array:
	car.set_drift(true)
	car.set_controls(1.0, 0.0, 1.0, false)
	# The drift is entered to the right, then the steer decides the slip angle.
	for i in 36:
		await t.step()
	car.set_controls(1.0, 0.0, hold, false)
	var sum: float = 0.0
	var samples: int = 0
	var peak: float = 0.0
	var spin: float = 0.0
	for i in 120 * 3:
		await t.step()
		var beta: float = absf(rad_to_deg(car.drift.beta))
		spin = maxf(spin, absf(car.angular_velocity.y))
		if i >= 48:
			peak = maxf(peak, beta)
		if i >= 120 * 2:
			sum += beta
			samples += 1
	return [sum / maxf(float(samples), 1.0), peak, spin]


## Puts the car on the road at 200 km/h and starts a drift to the right.
func _at_speed(t: T, car: ArcadeCar) -> void:
	await t.run(0.5)
	t.set_speed(car, 200.0)
	car.set_controls(1.0, 0.0, 1.0, false)
	car.set_drift(true)
	await t.run(2.0)


## The slip series of the exit: every 0.05 s from the exit to +1.0 s. Returns the series, the
## time of the exit and the mini window when the slip fell below 12 degrees.
## mode: &"counter" (the counter steer), &"release" (the neutral release) or &"cut" (the 断位).
func _exit_series(t: T, car: ArcadeCar, mode: String) -> Array:
	var series: Array[float] = []
	var exited: float = -1.0
	var start: float = 0.0
	var window_at_straight: float = -1.0
	var ticks: int = 0
	if mode == "cut":
		# The 断位: release the drift and press it again inside the window.
		car.set_drift(false)
		await t.step()
		car.set_drift(true)
		await t.step()
		# The button is released again, so the new drift does not start right away.
		car.set_drift(false)
	else:
		car.set_drift(false)
		var steer: float = -0.5 if mode == "counter" else 0.0
		car.set_controls(1.0, 0.0, steer, false)
	# The exit: the state leaves the drift.
	for i in 120 * 3:
		await t.step()
		if exited < 0.0 and car.drift.state != &"drift":
			exited = float(i) / 120.0
			start = float(i) / 120.0
			series.append(rad_to_deg(car.drift.beta))
			continue
		if exited >= 0.0:
			ticks += 1
			if ticks % 6 == 0:
				var beta: float = rad_to_deg(car.drift.beta)
				series.append(beta)
				if window_at_straight < 0.0 and absf(beta) < 12.0:
					window_at_straight = maxf(car.boost.mini_window, car.telemetry.mini_window)
			if float(i) / 120.0 - start >= 1.0:
				break
	return [series, exited, window_at_straight]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The counter steer holds the shallow end of the band, the full steer the deep end.
	for hold: float in [-1.0, 1.0]:
		var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
		await t.run(0.5)
		if hold < 0.0:
			# The roll up to 200 km/h is checked once (the other parts set the speed).
			car.set_controls(1.0, 0.0, 0.0, false)
			for i in 120 * 10:
				await t.step()
				if car.telemetry.forward_speed_kmh >= 200.0:
					break
			t.check_range("the roll up to 200 km/h", car.telemetry.forward_speed_kmh, 195.0, 220.0)
		else:
			t.set_speed(car, 200.0)
			await t.run(0.3)
		# The tank starts empty, so the gain is not clamped.
		car.boost.n2 = 0.0
		var res: Array = await _drift(t, car, hold)
		var settled: float = res[0]
		var peak: float = res[1]
		var spin: float = res[2]
		if hold < 0.0:
			t.check_range("the counter steer slip", settled, 26.0, 32.0)
		else:
			t.check_range("the full steer slip", settled, 46.0, 52.0)
		t.check("the slip stays in the band", peak < 56.0, "= %.1f deg" % peak)
		t.check("no spin out", spin < 2.4, "= %.2f rad/s" % spin)
		# The exit: release the drift and pull the nose straight with a full counter steer.
		car.set_drift(false)
		car.set_controls(1.0, 0.0, -1.0, false)
		for i in 120 * 3:
			await t.step()
			if car.telemetry.drift_state == &"grip":
				break
		t.check("the drift ended", car.telemetry.drift_state == &"grip",
				"= %s" % car.telemetry.drift_state)
		car.queue_free()
		await t.run(0.3)
	# The gauge: a 3 s drift at about 35 degrees of slip fills one slot.
	var car3: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	t.set_speed(car3, 200.0)
	await t.run(0.3)
	car3.boost.n2 = 0.0
	var res3: Array = await _drift(t, car3, -0.45)
	t.check_range("the gauge slip", res3[0], 30.0, 40.0)
	car3.set_drift(false)
	car3.set_controls(1.0, 0.0, -1.0, false)
	for i in 120 * 3:
		await t.step()
		if car3.telemetry.drift_state == &"grip":
			break
	t.check_range("the committed N2", car3.boost.n2, 95.0, 105.0)
	t.check("the mini window opened", car3.boost.mini_window > 0.0
			or car3.telemetry.mini_window, "= %.2f s" % car3.boost.mini_window)
	car3.queue_free()
	await t.run(0.3)
	# --- the exits ---------------------------------------------------------------------------
	# 1. The released drift ends: the button is released and the steer is neutral.
	var car4: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 200.0), 0.0)
	await _at_speed(t, car4)
	t.check("the drift runs", car4.drift.state == &"drift", "= %s" % car4.drift.state)
	var heading0: float = _heading(car4)
	car4.set_drift(false)
	car4.set_controls(1.0, 0.0, 0.0, false)
	var left: float = -1.0
	var turned: float = 0.0
	var prev: float = heading0
	for i in 120 * 3:
		await t.step()
		var h: float = _heading(car4)
		turned += absf(wrapf(h - prev, -180.0, 180.0))
		prev = h
		if left < 0.0 and car4.drift.state != &"drift":
			left = float(i) / 120.0
	t.check("the released drift ends", left >= 0.0 and left <= 1.0,
			"= %.2f s after the release" % left)
	t.check("the heading change after the release", turned <= 90.0, "= %.0f deg" % turned)
	car4.queue_free()
	await t.run(0.3)
	# 2. The released drift with the steer held into the drift keeps the arc.
	var car5: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 260.0), 0.0)
	await _at_speed(t, car5)
	car5.set_drift(false)
	car5.set_controls(1.0, 0.0, 1.0, false)
	await t.run(2.0)
	t.check("the held steer keeps the drift", car5.drift.state == &"drift",
			"= %s, beta %.1f deg" % [car5.drift.state, rad_to_deg(car5.drift.beta)])
	car5.queue_free()
	await t.run(0.3)
	# 3. The counter steer exits into the recover, and the nose is straight again.
	for mode: String in ["counter", "release", "cut"]:
		var car6: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 320.0), 0.0)
		await _at_speed(t, car6)
		var label: String = "the drift cut" if mode == "cut" else "the " + mode
		var out: Array = await _exit_series(t, car6, mode)
		var series: Array = out[0]
		var exited: float = out[1]
		var window_at_straight: float = out[2]
		# The counter steer and the cut snap into the recover (0.3 s), the neutral release
		# unwinds the arc (1.0 s).
		var limit: float = 1.0 if mode == "release" else 0.3
		t.check("%s exits the drift" % label, exited >= 0.0 and exited <= limit,
				"= %.2f s (the limit is %.1f s)" % [exited, limit])
		if exited < 0.0:
			car6.queue_free()
			await t.run(0.3)
			continue
		# The slip series from the exit to +1.0 s.
		var line: String = ""
		for i in series.size():
			line += "%.0f:%.1f " % [float(i) * 0.05, series[i]]
		print("SLIP %s (the exit at %.2f s): %s" % [label, exited, line])
		# The slip at +0.35 s and +0.6 s after the exit.
		var at35: float = absf(series[mini(7, series.size() - 1)])
		var at60: float = absf(series[mini(12, series.size() - 1)])
		t.check("the slip at +0.35 s after %s" % label, at35 <= 12.0, "= %.1f deg" % at35)
		t.check("the slip at +0.60 s after %s" % label, at60 <= 5.0, "= %.1f deg" % at60)
		# The slip never grows by more than a degree between two samples.
		var growth: float = 0.0
		for i in range(1, series.size()):
			growth = maxf(growth, series[i] - series[i - 1])
		t.check("the slip does not grow after %s" % label, growth <= 1.0,
				"= %.2f deg per 0.05 s" % growth)
		# No overshoot to the other side.
		var overshoot: float = 0.0
		for value: float in series:
			overshoot = minf(overshoot, value)
		t.check("no overshoot after %s" % label, overshoot >= -5.0, "= %.1f deg" % overshoot)
		# The 小喷 window is open while the nose is straight.
		t.check("the mini window is open when the nose is straight after %s" % label,
				window_at_straight > 0.0, "= %.2f s" % window_at_straight)
		car6.queue_free()
		await t.run(0.3)
	# 4. One 断位 does not change the next drift.
	var car7: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 380.0), 0.0)
	await t.run(0.5)
	t.set_speed(car7, 200.0)
	await t.run(0.3)
	var first: Array = await _drift(t, car7, -0.45)
	# The cut: release the drift and press it again inside the window.
	car7.set_drift(false)
	await t.step()
	car7.set_drift(true)
	await t.step()
	for i in 120 * 3:
		await t.step()
		if car7.drift.state != &"drift":
			break
	t.check("the cut ended the drift", car7.drift.state != &"drift", "= %s" % car7.drift.state)
	t.check("the cut timer is over", car7.drift.state != &"drift" or car7.drift.time > 0.0,
			"= %s" % car7.drift.state)
	# Three seconds of grip, then the same drift again.
	car7.set_drift(false)
	car7.set_controls(1.0, 0.0, 0.0, false)
	await t.run(3.0)
	t.set_speed(car7, 200.0)
	await t.run(0.3)
	var second: Array = await _drift(t, car7, -0.45)
	t.check_close("the slip after a cut", float(second[0]), float(first[0]), 1.0)
	t.finish()

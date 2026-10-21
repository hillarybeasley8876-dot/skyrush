extends RefCounted
## The measurements of the feel report: the hop apex at a speed and the slip series of a drift
## exit. The report script (feel_report.gd) only prints the table.

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


## The apex of a hop (or a Big Hop) at the given speed and the time it spends above 7 m.
## The hop is fired through the thruster of the car (the AI path does not read the hop key).
## Returns [the apex in metres, the seconds above 7 m].
func hop(t: T, car: ArcadeCar, kmh: float, big: bool) -> Array:
	car.boost.n2 = BoostTuning.N2_MAX
	if kmh > 0.0:
		t.set_speed(car, kmh)
		car.set_controls(0.2, 0.0, 0.0, false)
		await t.run(0.2)
		car.set_controls(0.0, 0.0, 0.0, false)
	var ground: float = car.global_position.y
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	if big:
		# The Big Hop: the key is held for the charge.
		for i in 40:
			await t.step()
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	var apex: float = 0.0
	var above: float = 0.0
	var flew: bool = false
	for i in 120 * 3:
		await t.step()
		var height: float = car.global_position.y - ground
		apex = maxf(apex, height)
		if height > 7.0:
			above += 1.0 / 120.0
		if car.telemetry.airborne:
			flew = true
		elif flew and car.telemetry.grounded_wheels >= 3:
			break
	return [apex, above]


## The slip series of a drift exit: every 0.05 s from the exit to +1.0 s, and the time of the
## exit. The steer is the input after the release: 0 is the neutral release, -0.5 the counter
## steer. Returns [the series, the exit time in seconds].
func exit_series(t: T, car: ArcadeCar, steer: float) -> Array:
	var series: Array[float] = []
	var exited: float = -1.0
	var start: float = 0.0
	var ticks: int = 0
	car.set_drift(false)
	car.set_controls(1.0, 0.0, steer, false)
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
				series.append(rad_to_deg(car.drift.beta))
			if float(i) / 120.0 - start >= 1.0:
				break
	return [series, exited]


## The slip angle in degrees at the given time after the exit (the series is sampled every
## 0.05 s, so the index is the time divided by 0.05).
func slip_at(series: Array, seconds: float) -> float:
	var index: int = int(round(seconds / 0.05))
	return absf(series[mini(index, series.size() - 1)])

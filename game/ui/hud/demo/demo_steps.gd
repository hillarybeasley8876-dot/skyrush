extends RefCounted
## The demo's event timeline. Kept apart from `hud_demo.gd` so both stay small.
##
## Every HUD state is fired once per loop: the countdown, every boost kind, the toasts, the
## takedown streaks (x2 and x5), a traffic takedown, the heat levels 1..5, the pursuit phases
## (chase / search / cooldown / busted / escaped), the race finish, the pause, the flight gauges
## and the armed Big Hop.

const LOOP_TIME := 27.0


## steps: Array of [time: float, action: Callable].
static func build(demo: Node) -> Array:
	var steps: Array = []
	var car: VehicleBase = demo.get("car")
	_add(steps, 0.0, demo._reset_state)
	_add(steps, 1.0, func() -> void: Events.race_countdown.emit(3))
	_add(steps, 1.5, func() -> void: Events.race_countdown.emit(2))
	_add(steps, 2.0, func() -> void: Events.race_countdown.emit(1))
	_add(steps, 2.5, func() -> void: Events.race_countdown.emit(0))
	_add(steps, 3.0, func() -> void:
		Events.race_started.emit()
		Events.boost_started.emit(car, &"launch"))
	_add(steps, 3.8, func() -> void: Events.stunt.emit(&"fly_over_gas", 800, "飞跃加油站!"))
	_add(steps, 4.4, func() -> void: Events.toast.emit("压线操作", &"info"))
	_add(steps, 5.0, func() -> void: Events.drift_ended.emit(car, 3.2, true, 100.0))
	_add(steps, 5.8, func() -> void: Events.boost_started.emit(car, &"mini"))
	_add(steps, 6.4, func() -> void: Events.near_miss.emit(car, null))
	_add(steps, 7.0, func() -> void: Events.boost_started.emit(car, &"air_mini"))
	_add(steps, 7.6, func() -> void: Events.boost_started.emit(car, &"landing"))
	_add(steps, 8.2, func() -> void: Events.boost_started.emit(car, &"nitro"))
	_add(steps, 8.8, func() -> void: Events.boost_started.emit(car, &"charge"))
	_add(steps, 9.4, func() -> void: Events.charge_finished.emit(car, null, 1.0))
	_add(steps, 10.0, func() -> void: Events.n2_ring.emit(car, null))
	# The takedown banner, then a x2 streak, a traffic takedown and a x5 streak.
	_add(steps, 10.6, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 11.0, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 11.4, func() -> void: Events.takedown.emit(car, &"traffic"))
	_add(steps, 11.8, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 12.0, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 12.2, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 12.4, func() -> void: Events.takedown.emit(car, &"police"))
	_add(steps, 12.6, func() -> void: Events.takedown.emit(car, &"police"))
	# The pursuit: heat 1 -> 3 -> 5, chase, search, cooldown, busted, escaped.
	_add(steps, 13.2, func() -> void: Events.heat_changed.emit(1))
	_add(steps, 13.8, func() -> void: Events.pursuit_state_changed.emit(&"chase"))
	_add(steps, 14.6, func() -> void: Events.heat_changed.emit(3))
	_add(steps, 15.4, func() -> void: Events.heat_changed.emit(5))
	_add(steps, 16.2, func() -> void: Events.pursuit_state_changed.emit(&"search"))
	_add(steps, 17.4, func() -> void: Events.pursuit_state_changed.emit(&"cooldown"))
	_add(steps, 18.8, func() -> void: Events.pursuit_state_changed.emit(&"busted"))
	_add(steps, 19.8, func() -> void: Events.pursuit_state_changed.emit(&"escaped"))
	_add(steps, 20.6, func() -> void: Events.race_finished.emit([
		{"name": "Roadster", "time": 118.4, "position": 1, "is_player": true}]))
	_add(steps, 21.4, func() -> void: Events.game_paused.emit(true))
	_add(steps, 22.0, func() -> void: Events.game_paused.emit(false))
	return steps


static func _add(steps: Array, time: float, action: Callable) -> void:
	steps.append([time, action])

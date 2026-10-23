class_name RaceSession
extends Node3D
## A race: the grid, the 3-2-1-GO countdown, the checkpoint gates, the laps, the live order
## and the results (the QQ race flow of dossier 1).
##
## The session owns the rules; the rival director owns the cars. The two talk through the
## `Events` bus and through the racer list. The gates live in `RaceGates` and the order and the
## results in `RaceResults`.
##
## A route with a closed racing line is a circuit (the lap ends when the racer comes back to
## its start gate); an open line is a sprint (one lap, the race ends at the last gate).

enum State { IDLE, COUNTDOWN, RUNNING, FINISHED }

const COUNTDOWN_STEP := 1.0   ## s per number of the countdown
const FINISH_WAIT := 15.0      ## s: the session waits this long after the leader is home
const CRUISE_FACTOR := 0.6     ## the rivals cruise at this share of their speed after the line

## The race is over and the results are ready.
signal finished(results: Array)

var route: RaceRoute = null
var laps: int = 2
var difficulty: StringName = &"normal"
var state: int = State.IDLE
var elapsed: float = 0.0
var racers: Array[RaceRacer] = []
var gates: Array[RaceGate] = []
var player: VehicleBase = null
var rival_director: Node = null
var records: GameRecords = null
var route_id: String = ""
## True when the route is a sprint (an open racing line).
var sprint: bool = false
## True when the time of the player is a new record (the results screen shows it).
var new_record: bool = false

var _gate_builder := RaceGates.new()
var _results := RaceResults.new()
## The status of the race for the HUD.
var _status: ModeStatus = ModeStatus.new(self)
var _countdown_number: int = 3
var _countdown_left: float = 0.0
var _player_slot: Transform3D = Transform3D.IDENTITY
var _player_home_at: float = -1.0
var _field_home_at: float = -1.0


## Sets the race up: the gates, the grid, the player and the rivals.
func setup(new_route: RaceRoute, new_laps: int, level: StringName, new_player: VehicleBase,
		new_records: GameRecords, director: Node, options: Dictionary) -> void:
	route = new_route
	route_id = String(route.id)
	difficulty = level
	player = new_player
	records = new_records
	rival_director = director
	# The rivals go first: they build the racing line the grid and the gates stand on.
	_place_cars(options)
	# The rivals built the racing line: now the session knows if the route is a circuit.
	sprint = not _line_is_closed()
	laps = 1 if sprint else maxi(1, new_laps)
	_build_gates()
	state = State.COUNTDOWN
	_countdown_number = 3
	_countdown_left = 0.0
	elapsed = 0.0
	new_record = false
	_player_home_at = -1.0
	_field_home_at = -1.0
	_hold_player_on_grid()


## True when the racing line of the route is a loop.
func _line_is_closed() -> bool:
	if rival_director == null:
		return true
	if rival_director.has_method("is_circuit"):
		return bool(rival_director.call("is_circuit"))
	return true


## Builds one hologram gate per checkpoint.
func _build_gates() -> void:
	_gate_builder.build(self, route, not sprint)
	gates = _gate_builder.gates
	for gate in gates:
		gate.passed.connect(_on_gate_passed)


## Puts the field on the grid and hands the other slots to the rivals.
func _place_cars(options: Dictionary) -> void:
	var start := RaceStart.place(route, difficulty, player, rival_director, options)
	racers = start.racers
	_player_slot = start.player_slot
	for racer in racers:
		_set_next_gate(racer)


## The race clock: the countdown, then the laps and the order.
func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_hold_player_on_grid()
			_tick_countdown(delta)
			_push_status(delta)
		State.RUNNING:
			elapsed += delta
			_update_progress()
			_push_status(delta)
			_check_finished()


## The status of the race for the HUD: the lap and the place of the player, the laps of this
## race and the number of racers.
func _push_status(delta: float) -> void:
	_results.racers = racers
	_status.push(&"race", _results.live_status(laps), delta)


## Holds the player on its grid slot through the countdown (the menu may unfreeze it).
func _hold_player_on_grid() -> void:
	if player == null:
		return
	player.freeze = true
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.global_transform = _player_slot


## The 3-2-1-GO countdown (dossier 1: the number is on the screen for a second each).
func _tick_countdown(delta: float) -> void:
	_countdown_left -= delta
	if _countdown_left > 0.0:
		return
	_countdown_left = COUNTDOWN_STEP
	if _countdown_number > 0:
		Events.race_countdown.emit(_countdown_number)
		_countdown_number -= 1
		return
	Events.race_countdown.emit(0)
	_start_race()


## The green light: the clock starts and the cars are released.
func _start_race() -> void:
	state = State.RUNNING
	elapsed = 0.0
	for racer in racers:
		racer.lap_start = 0.0
	if player != null:
		player.freeze = false
	if rival_director != null:
		rival_director.set("on_grid", false)
	Events.race_started.emit()


## A car passed a gate.
func _on_gate_passed(vehicle: VehicleBase, gate_index: int) -> void:
	if state != State.RUNNING:
		return
	var racer := _racer_of(vehicle)
	if racer == null or racer.is_finished():
		return
	var total := gates.size()
	if total == 0 or gate_index != racer.next_cp:
		return
	_count_gate(racer, gate_index)


## Counts a gate for a racer and tells the brain which gate comes next.
func _count_gate(racer: RaceRacer, gate_index: int) -> void:
	var total := gates.size()
	racer.cp_count += 1
	racer.next_cp = (gate_index + 1) % total
	Events.checkpoint_passed.emit(racer.vehicle, gate_index, total)
	_set_next_gate(racer)
	if racer.is_player:
		_gate_builder.set_next_gate(racer.next_cp)
		_gate_builder.fade(gate_index)
	_check_lap(racer, gate_index)


## The lap (or the sprint) is over when a racer comes home.
##
## The gate of a racer that drove past its trigger is counted by the safety net of the brain:
## the lap has to be counted there as well, or the racer never finishes its race.
func _check_lap(racer: RaceRacer, gate_index: int) -> void:
	var total := gates.size()
	if sprint:
		# A sprint is one lap: the race ends at the last gate of the route.
		if racer.next_cp == 0 and racer.cp_count >= total - racer.start_cp:
			_finish_racer(racer)
		return
	if gate_index != racer.start_cp:
		return
	if racer.passed_start:
		_complete_lap(racer)
	else:
		racer.passed_start = true


## Tells the brain of a racer which gate it has to pass next (the rescue uses it).
func _set_next_gate(racer: RaceRacer) -> void:
	var car := racer.vehicle as RivalCar
	if car == null or car.brain == null:
		return
	car.brain.set_next_gate(racer.next_cp)


## The racer came home: a lap is counted and the race may be over.
func _complete_lap(racer: RaceRacer) -> void:
	racer.lap += 1
	var lap_time := elapsed - racer.lap_start
	racer.lap_start = elapsed
	if racer.best_lap < 0.0 or lap_time < racer.best_lap:
		racer.best_lap = lap_time
	Events.lap_completed.emit(racer.vehicle, racer.lap, lap_time)
	if racer.is_player and records != null:
		records.record_lap(route_id, lap_time)
	if racer.lap >= laps:
		_finish_racer(racer)


## The racer crossed the line for the last time.
##
## The session does not end here: the field still has to come home, so the rivals that cross in
## the next seconds get their real time and the ones that do not get an estimate.
func _finish_racer(racer: RaceRacer) -> void:
	if racer.is_finished():
		return
	racer.finish_time = elapsed
	racer.lap = maxi(racer.lap, laps)
	_set_cruise(racer, true)
	_update_positions()
	# A racer that is home has no gate left to pass.
	var car := racer.vehicle as RivalCar
	if car != null and car.brain != null:
		car.brain.set_next_gate(-1)
	if racer.is_player:
		_player_home_at = elapsed
		if records != null:
			# The record is written before the results are built, so the flag is kept here:
			# the time of the player is the record itself afterwards.
			new_record = records.record_time(route_id, elapsed)
		Events.toast.emit("完赛！ FINISH", &"great")
	elif _rivals_left() == 0:
		_field_home_at = elapsed


## The rivals that have not come home yet.
func _rivals_left() -> int:
	var left := 0
	for racer in racers:
		if racer.is_player or racer.is_finished():
			continue
		left += 1
	return left


## The rivals cruise at 60 % of their speed after the line.
func _set_cruise(racer: RaceRacer, cruising: bool) -> void:
	var car := racer.vehicle as RivalCar
	if car == null or car.brain == null:
		return
	car.brain.cruise_factor = CRUISE_FACTOR if cruising else 1.0


## The race ends when the leader is home and the field is home too, or after the wait.
func _check_finished() -> void:
	if racers.is_empty():
		_finish_race()
		return
	var left := _rivals_left()
	if left == 0 and _field_home_at < 0.0:
		_field_home_at = elapsed
	if _player_home_at >= 0.0:
		# The player is home: the session waits for the field, but not forever.
		if left == 0 or elapsed - _player_home_at >= FINISH_WAIT:
			_finish_race()
		return
	# The field is home and the player is still out: the player gets a moment to come in.
	if _field_home_at >= 0.0 and elapsed - _field_home_at >= FINISH_WAIT:
		_finish_race()


## The order of the racers and the progress of the race.
func _update_progress() -> void:
	for racer in racers:
		if rival_director != null and rival_director.has_method("progress_of"):
			racer.progress = float(rival_director.call("progress_of", racer.vehicle))
		racer.push_sample(elapsed, racer.progress)
		_check_missed_gate(racer)
	_update_positions()
	_sync_results()
	if rival_director != null:
		rival_director.set("race_fraction", _race_fraction())


## A rival that drove past a gate without hitting the trigger still counts it.
func _check_missed_gate(racer: RaceRacer) -> void:
	var car := racer.vehicle as RivalCar
	if car == null or car.brain == null or racer.is_finished():
		return
	var missed := car.brain.missed_gate
	if missed < 0:
		return
	car.brain.missed_gate = -1
	if missed != racer.next_cp:
		return
	_count_gate(racer, missed)


## Writes the position of every racer (the order comes from the results helper).
func _update_positions() -> void:
	_results.racers = racers
	_results.assign_positions()


## Hands the state of the race to the results helper.
func _sync_results() -> void:
	_results.racers = racers
	_results.elapsed = elapsed
	_results.laps = laps
	_results.sprint = sprint
	_results.new_record = new_record
	var line := _racing_line()
	_results.line_length = line.length if line != null else 0.0
	if rival_director != null:
		_results.gate_offsets = rival_director.get("gate_offsets") as PackedFloat32Array


## The time gap of a racer to the leader (the live order of the race).
func gap_to_leader(racer: RaceRacer) -> float:
	return _results.gap_to_leader(racer)


## True when the time of the player is a new record.
func is_new_record() -> bool:
	return new_record


## The results of the race (the contract of `Events.race_finished`).
func build_results() -> Array:
	_sync_results()
	_update_positions()
	return _results.build()


## How much of the race the player has done (0..1).
func _race_fraction() -> float:
	var racer := _player_racer()
	if racer == null:
		return 0.0
	var total := maxi(1, gates.size())
	if sprint:
		return clampf(float(racer.cp_count) / float(total), 0.0, 1.0)
	var fraction := (float(racer.lap) + float(racer.next_cp) / float(total)) / float(maxi(1, laps))
	return clampf(fraction, 0.0, 1.0)


## The entry of a car in the race (null when the car is not racing).
func _racer_of(vehicle: VehicleBase) -> RaceRacer:
	for racer in racers:
		if racer.vehicle == vehicle:
			return racer
	return null


## The entry of the player.
func _player_racer() -> RaceRacer:
	for racer in racers:
		if racer.is_player:
			return racer
	return null


## The racing line of the route (null when the rivals unit is not loaded).
func _racing_line() -> RivalLine:
	if rival_director == null or not rival_director.has_method("get_line"):
		return null
	return rival_director.call("get_line") as RivalLine


## Ends the race and hands the results to the bus.
func _finish_race() -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	_update_positions()
	var results := build_results()
	Events.race_finished.emit(results)
	finished.emit(results)


## The player must not stay frozen when the race is over.
func _exit_tree() -> void:
	if player != null and is_instance_valid(player):
		player.freeze = false

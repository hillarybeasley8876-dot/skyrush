extends Node
## The race flow (dossier 1): the countdown, the start, the laps, the order and the results.
##
## The test runs a full race on the sandbox loop and checks the things that broke in the
## first round: the finish times of the results, the gates every racer counted, the rescues,
## the passes, the drifting corners and the hits between the rivals.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const CONTACT_LIMIT := 800.0   ## N*s: a hit over this counts as a crash
const SAMPLE := 0.25           ## s: the interval of the order samples
const SWAP_HOLD := 3.0         ## s: a pass must last this long
const LATERAL_SWAP := 2.0       ## m: the lateral offset must change by this much
const DRIFT_KAPPA := 0.006      ## 1/m: the corner that is worth drifting

var _failures: int = 0
var _countdown: Array[int] = []
var _started: bool = false
var _results: Array = []
var _lap_times: Dictionary = {}     ## the vehicle id -> the time of its last lap
var _contacts: int = 0
var _order: Array[int] = []
var _passes: int = 0
var _candidates: Array[Dictionary] = []
var _lateral: Dictionary = {}      ## the vehicle id -> the lateral offset of the car
var _corners: int = 0
var _drifts: int = 0
var _drifting: Dictionary = {}     ## the vehicle id -> the drift state of the last sample
var _corners_seen: Dictionary = {}  ## the vehicle id -> the corner state of the last sample


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	var modes := (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(modes)
	Events.race_countdown.connect(_on_countdown)
	Events.race_started.connect(_on_started)
	Events.race_finished.connect(_on_finished)
	Events.lap_completed.connect(_on_lap)
	Events.vehicle_collided.connect(_on_collision)
	var ok := modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 2,
		"difficulty": "normal"})
	_expect(ok, "the race starts")
	_expect(Game.mode == &"race", "the game mode is race")
	var session := modes.session as RaceSession
	_expect(session != null, "the race session exists")
	await _watch(session)
	_check_results(session)


## Watches the race until it is over.
func _watch(session: RaceSession) -> void:
	var waited := 0.0
	while _results.is_empty() and waited < 400.0:
		await get_tree().create_timer(SAMPLE).timeout
		waited += SAMPLE
		_sample(session)


## One sample of the order, the lateral offsets, the corners and the drifts.
func _sample(session: RaceSession) -> void:
	var order: Array[int] = []
	for i in session.racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return session.racers[a].progress > session.racers[b].progress)
	_check_passes(session, order)
	for i in session.racers.size():
		var racer := session.racers[i]
		if racer.is_player:
			continue
		var rival := racer.vehicle as RivalCar
		if rival == null or rival.brain == null:
			continue
		_lateral[racer.vehicle.get_instance_id()] = _lateral_offset(rival)
		_count_corner(rival)
	_order = order


## The lateral distance of a rival from its own line (m).
func _lateral_offset(rival: RivalCar) -> float:
	var brain := rival.brain
	var line := brain.line
	if line == null:
		return 0.0
	var right := line.right_at(brain.offset)
	return (rival.global_position - line.point_at(brain.offset) - right * brain.lane_offset).dot(right)


## Counts the corners and the drifts of a rival (the rising edges).
func _count_corner(rival: RivalCar) -> void:
	var brain := rival.brain
	var line := brain.line
	if line == null:
		return
	var id := rival.get_instance_id()
	var corner := line.max_curvature_ahead(brain.offset, 30.0) > DRIFT_KAPPA
	var was_corner := bool(_corners_seen.get(id, false))
	if corner and not was_corner:
		_corners += 1
	_corners_seen[id] = corner
	var was := bool(_drifting.get(id, false))
	if brain.drifting and not was:
		_drifts += 1
	_drifting[id] = brain.drifting


## Counts a pass when two cars swap and the swap holds.
func _check_passes(session: RaceSession, order: Array[int]) -> void:
	if not _order.is_empty() and order != _order:
		for i in order.size():
			for j in order.size():
				if i == j:
					continue
				var a := order[i]
				var b := order[j]
				var before_a := _order.find(a)
				var before_b := _order.find(b)
				if before_a < 0 or before_b < 0:
					continue
				if before_b < before_a:
					_candidates.append({
						"passer": a,
						"target": b,
						"time": session.elapsed,
						"lateral": float(_lateral.get(session.racers[a].vehicle.get_instance_id(), 0.0)),
					})
	# A candidate that still holds after the hold time is a pass.
	var alive: Array[Dictionary] = []
	for candidate in _candidates:
		if session.elapsed - float(candidate["time"]) < SWAP_HOLD:
			alive.append(candidate)
			continue
		var passer := session.racers[int(candidate["passer"])]
		var target := session.racers[int(candidate["target"])]
		if passer.progress > target.progress:
			var now := float(_lateral.get(passer.vehicle.get_instance_id(), 0.0))
			if absf(now - float(candidate["lateral"])) >= LATERAL_SWAP:
				_passes += 1
	_candidates = alive


## The results must hold every racer with a unique position and the real finish times.
func _check_results(session: RaceSession) -> void:
	_expect(_countdown == [3, 2, 1, 0], "the countdown runs 3-2-1-GO (%s)" % str(_countdown))
	_expect(_started, "the race started")
	_expect(_results.size() == 6, "the results hold 6 racers (%d)" % _results.size())
	var positions: Array[int] = []
	var times_ok := true
	var lap_ok := true
	for row in _results:
		var entry := row as Dictionary
		positions.append(int(entry.get("position", 0)))
		var time := float(entry.get("time", -1.0))
		if time <= 0.0:
			times_ok = false
		# The result holds the total time of the racer; its last lap is shorter.
		var recorded := float(_lap_times.get(entry.get("name", ""), 0.0))
		if recorded > 0.0 and (time < recorded - 0.05 or time > recorded + 200.0):
			times_ok = false
			print("   the time of %s is %.2f but its last lap was %.2f" % [entry.get("name", ""),
				time, recorded])
	positions.sort()
	var unique := true
	for i in positions.size():
		if positions[i] != i + 1:
			unique = false
	_expect(unique, "the positions are 1..%d (%s)" % [positions.size(), str(positions)])
	_expect(times_ok, "the results hold the real finish times")
	# Every racer must have counted the same number of gates.
	var counts: Array[int] = []
	for racer in session.racers:
		if racer.is_player:
			continue
		counts.append(racer.cp_count)
	var same := true
	for count in counts:
		if count != counts[0]:
			same = false
	_expect(same and counts[0] >= session.laps * session.gates.size(),
		"every racer counted the gates (%s)" % str(counts))
	# The spread between the first and the fifth car.
	var sorted_times: Array[float] = []
	for row in _results:
		sorted_times.append(float((row as Dictionary).get("time", 0.0)))
	sorted_times.sort()
	if sorted_times.size() >= 5:
		_expect(sorted_times[4] - sorted_times[0] < 15.0,
			"the field is within 15 s (%.1f s)" % (sorted_times[4] - sorted_times[0]))
	# The rescues, the passes, the drifts and the hits.
	var rescues := 0
	for racer in session.racers:
		var rival := racer.vehicle as RivalCar
		if rival != null and rival.brain != null:
			rescues += rival.brain.rescues
			print("   %s pos %d time %.1f progress %.0f rescues %d" % [racer.name,
				racer.position, racer.finish_time, racer.progress, rival.brain.rescues])
	_expect(rescues == 0, "no rival needed the marshal (%d)" % rescues)
	_expect(_passes >= 6, "the field made at least 6 passes (%d)" % _passes)
	if _corners > 0:
		var ratio := float(_drifts) / float(_corners)
		_expect(ratio >= 0.6, "60 %% of the corners are drifts (%.0f %% of %d)" % [ratio * 100.0, _corners])
	else:
		_expect(false, "the rivals met at least one corner")
	_expect(_contacts == 0, "no rival hit a rival over %.0f N*s (%d)" % [CONTACT_LIMIT, _contacts])
	print("RACE FLOW TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _on_countdown(seconds_left: int) -> void:
	_countdown.append(seconds_left)


func _on_started() -> void:
	_started = true
	# The player does not drive in this test: it stands on the grid and the field has to
	# lap it (a stationary player may never hold the field up).
	if Game.player != null:
		Game.player.freeze = true


func _on_finished(results: Array) -> void:
	_results = results


## The time of the last lap of a racer.
func _on_lap(vehicle: VehicleBase, _lap: int, lap_time: float) -> void:
	_lap_times[vehicle.display_name] = lap_time


## A hit between two rivals over the limit.
func _on_collision(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3,
		_normal: Vector3) -> void:
	if impulse < CONTACT_LIMIT:
		return
	var other_car := other as VehicleBase
	if vehicle.team == VehicleBase.Team.RIVAL and other_car != null \
			and other_car.team == VehicleBase.Team.RIVAL:
		# The signal is sent for both bodies of a contact: a contact counts once.
		if vehicle.get_instance_id() < other_car.get_instance_id():
			_contacts += 1
		if _contacts <= 8:
			print("CONTACT %s x %s impulse %.0f at %s" % [vehicle.display_name,
				(other as VehicleBase).display_name, impulse, str(point.snapped(Vector3(1, 1, 1)))])


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

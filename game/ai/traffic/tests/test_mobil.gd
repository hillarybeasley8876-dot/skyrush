extends Node
## The MOBIL-lite lane change of the traffic and the reaction to a fast player.
##
##   tools/godot.sh test res://ai/traffic/tests/test_mobil.gd
##
## The test drives a car that is stuck behind a slow car on a three lane road: it has to move
## into the free lane, and the indicator has to blink before the move. The second part of the
## test puts a fast player behind a hundred cars: a fifth of them have to move out of the way
## and a tenth have to brake.

const DT := 1.0 / 120.0
const CHANGE_LIMIT := 6.0   ## s: the car has to change the lane within this time
const INDICATOR_LEAD := 1.0 ## s: the indicator has to be on this long before the move
const REACTION_ROUNDS := 1000
const SETTLE_TIME := 20.0     ## s: how long the car has to settle behind the slow one
const JUMP_LIMIT := 0.3        ## m: how far the body may jump when the lane changes
const PLAYER_GAP := 30.0     ## m: the player is this far behind the car
const PLAYER_SPEED := 25.0   ## m/s: the speed of the player
const CAR_SPEED := 5.0       ## m/s: the speed of the car

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_ctx = DriveContext.new()
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 20260220
	_test_change_behind_a_slow_car()
	_test_reaction_to_the_player()
	print("MOBIL TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A fast car that is stuck behind a slow one has to move into the free lane next to it.
func _test_change_behind_a_slow_car() -> void:
	var graph := _ctx.graph
	var slow := _make_car(graph, 1, 100.0, &"van_ev")
	slow.speed = 4.0
	slow.desired_speed = 4.0
	var fast := _make_car(graph, 1, 40.0, &"sedan_ev")
	fast.speed = 25.0
	fast.desired_speed = 25.0
	var changed := false
	var indicator_time := 0.0
	var indicator_before := 0.0
	var worst_jump := 0.0
	var previous := fast.global_position
	var start_lane := fast.follower.lane
	for step in int(SETTLE_TIME / DT):
		_ctx.hash.clear()
		_ctx.hash.insert(slow.follower.lane, slow.follower.s, slow)
		_ctx.hash.insert(fast.follower.lane, fast.follower.s, fast)
		# The jump is what the body moves more than the speed allows. A far car is updated
		# every second tick and covers the distance of both ticks in one go, so the speed it
		# had before the tick is the one that counts.
		var speed_before := fast.speed
		slow.tick(DT)
		fast.tick(DT)
		var expected := speed_before * fast.last_dt
		worst_jump = maxf(worst_jump, fast.global_position.distance_to(previous) - expected)
		previous = fast.global_position
		if fast.lane_change.indicator_side != 0:
			indicator_time += DT
		if fast.follower.lane != start_lane and not changed:
			changed = true
			indicator_before = indicator_time
	_check(changed, "the car changes the lane within %.0f s" % SETTLE_TIME)
	_check(indicator_before >= INDICATOR_LEAD - 0.05,
		"the indicator is on %.2f s before the move" % indicator_before)
	_check(fast.follower.lane != start_lane, "the car is in the lane next to it")
	_check(worst_jump <= JUMP_LIMIT,
		"the body does not jump when the lane changes (%.2f m)" % worst_jump)


## A fast player behind a car: a fifth of the cars move out of the way, a tenth brake.
func _test_reaction_to_the_player() -> void:
	var graph := _ctx.graph
	var player := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate()
	add_child(player)
	_ctx.player = player as VehicleBase
	var car := _make_car(graph, 1, 60.0, &"sedan_ev")
	var moved := 0
	var braked := 0
	for round in REACTION_ROUNDS:
		car.lane_change = TrafficLaneChange.new()
		car.lane_change.start(_ctx.rng)
		car.place(1, 60.0)
		car.speed = CAR_SPEED
		player.global_position = car.global_position - Vector3(PLAYER_GAP, 0.0, 0.0)
		(player as RigidBody3D).linear_velocity = Vector3(PLAYER_SPEED, 0.0, 0.0)
		car.lane_change.update(DT, _ctx, car.follower, car.speed, car.desired_speed,
				car.car_length, car.global_position)
		if car.lane_change.reaction_brake < 0.0:
			braked += 1
		elif car.lane_change.indicator_side != 0:
			moved += 1

	var move_share := float(moved) / float(REACTION_ROUNDS)
	var brake_share := float(braked) / float(REACTION_ROUNDS)
	_check(move_share >= 0.15 and move_share <= 0.25,
		"%.0f %% of the cars move out of the way" % (move_share * 100.0))
	_check(brake_share >= 0.05 and brake_share <= 0.15,
		"%.0f %% of the cars brake" % (brake_share * 100.0))


## A traffic car on the test road.
func _make_car(graph: LaneGraph, lane: int, s: float, model: StringName) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, model, Color.WHITE, _ctx.rng.randi())
	car.place(lane, s)
	# The car of the test is next to the player: it ticks every frame, not every fourth.
	car.player_distance = 0.0
	return car

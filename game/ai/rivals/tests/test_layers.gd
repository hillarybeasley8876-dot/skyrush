extends Node
## The rivals only react to the cars on their own level.
##
## The map has two levels a few metres apart in height: the Yan'an street runs under the
## Yan'an deck (10 m apart). A rival that drives on the deck must not brake for the cars
## on the street below it, must not swerve for them and must not get their slipstream.
##
## Every check has two halves: the same level keeps the old behaviour, the other level
## does nothing at all.

const STUB := preload("res://core/stubs/stub_car.tscn")
const DECK := 10.2       ## m: the height of the elevated deck
const STREET := 0.6      ## m: the height of the street under the deck
const TRAFFIC_AHEAD := 30.0  ## m: the traffic this far ahead is seen (AVOID_DISTANCE is 40 m)
const PLAYER_AHEAD := 50.0   ## m: the player this far ahead is seen (FOLLOW_DISTANCE is 80 m)
const SIDE := 2.0        ## m: the car stands this far beside the rival

var _fails: int = 0
var _line: RivalLine = null
var _car: ArcadeCar = null
var _ctx: RivalContext = null


func _ready() -> void:
	_line = _make_line()
	_car = _make_rival()
	_ctx = RivalContext.new()
	_check_blocker_same_level()
	_check_blocker_below()
	_check_player()
	_check_avoidance()
	_check_slipstream()
	if _fails == 0:
		print("RIVAL LAYER TESTS OK (%d failures)" % _fails)
		get_tree().quit(0)
	else:
		print("RIVAL LAYER TESTS FAILED")
		get_tree().quit(1)


## The line of the race: a straight along +X on the elevated deck.
func _make_line() -> RivalLine:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, DECK, 0.0))
	curve.add_point(Vector3(100.0, DECK, 0.0))
	curve.add_point(Vector3(200.0, DECK, 0.0))
	return RivalLine.new(curve)


## The rival that drives the line.
func _make_rival() -> ArcadeCar:
	var car := ArcadeCar.new()
	add_child(car)
	car.gravity_scale = 0.0
	car.global_position = Vector3(0.0, DECK, 0.0)
	return car


## A car of the traffic: a stub that drives where it is put.
func _make_stub(pos: Vector3) -> VehicleBase:
	var stub := STUB.instantiate() as VehicleBase
	add_child(stub)
	stub.gravity_scale = 0.0
	stub.global_position = pos
	stub.linear_velocity = Vector3(12.0, 0.0, 0.0)
	return stub


## The cars the rival has to keep clear of (the near list of the director).
func _set_near(cars: Array[Node3D]) -> void:
	_ctx.near.clear()
	var list: Array[Node3D] = cars
	_ctx.near[_car.get_instance_id()] = list


## A car on the same level in front of the rival blocks it.
##
## The traffic is seen within AVOID_DISTANCE (40 m), not within FOLLOW_DISTANCE (80 m,
## the reach of the cars on the racing line): a traffic car 50 m ahead is out of the reach
## of the old code as well, so the "below" half of the check would pass for the wrong
## reason.
func _check_blocker_same_level() -> void:
	var stub := _make_stub(Vector3(TRAFFIC_AHEAD, DECK, 0.0))
	_set_near([stub])
	var avoid := RivalAvoid.new()
	avoid.update_blocker(_car, _ctx, 0.0, _line, 0.0, 30.0, 0.1)
	_expect(avoid.block_node == stub, "a car on the same level blocks the rival")
	_expect_range("the blocker stands 30 m ahead", avoid.block_distance,
		TRAFFIC_AHEAD - 3.0, TRAFFIC_AHEAD + 3.0)


## A car on the street under the deck is not a car in front of the rival.
func _check_blocker_below() -> void:
	var low := _make_stub(Vector3(TRAFFIC_AHEAD, STREET, 0.0))
	_set_near([low])
	var avoid := RivalAvoid.new()
	avoid.update_blocker(_car, _ctx, 0.0, _line, 0.0, 30.0, 0.1)
	_expect(avoid.block_node == null, "a car on the street below is not a blocker")
	_expect(is_inf(avoid.block_distance), "a car on the street below has no distance")


## The player on the street below is not a blocker either, the player on the deck is.
func _check_player() -> void:
	_set_near([])
	var low := _make_stub(Vector3(PLAYER_AHEAD, STREET, 0.0))
	_ctx.player = low
	_ctx.player_offset = PLAYER_AHEAD
	var avoid := RivalAvoid.new()
	avoid.update_blocker(_car, _ctx, 0.0, _line, 0.0, 30.0, 0.1)
	_expect(avoid.block_node == null, "the player on the street below is not a blocker")

	var deck := _make_stub(Vector3(PLAYER_AHEAD, DECK + 0.4, 0.0))
	_ctx.player = deck
	avoid.update_blocker(_car, _ctx, 0.0, _line, 0.0, 30.0, 0.1)
	_expect(avoid.block_node == deck, "the player on the deck is a blocker")
	_expect_range("the player stands 50 m ahead", avoid.block_distance,
		PLAYER_AHEAD - 3.0, PLAYER_AHEAD + 3.0)


## A car beside the rival: on the street below it must not make the rival swerve.
##
## The sideways avoidance shifts nothing today, for any car: a car that counts for it stands
## at most AVOID_BAND (2.2 m) beside the rival and the clearance it needs (AVOID_CLEARANCE,
## 2.5 m) is bigger than that, so the free space on the blocked side is negative and the
## shift is clamped to 0. The level test is in the loop all the same, and the test states
## the behaviour of the function as it is.
func _check_avoidance() -> void:
	var avoid := RivalAvoid.new()
	var side := _make_stub(Vector3(12.0, DECK, SIDE))
	_set_near([side])
	var same_level := avoid._avoid_offset(_car, _ctx, 0.0, _line, 0.0)
	var low := _make_stub(Vector3(12.0, STREET, SIDE))
	_set_near([low])
	var below := avoid._avoid_offset(_car, _ctx, 0.0, _line, 0.0)
	print("avoid: same level %.3f, street below %.3f" % [same_level, below])
	_expect(is_zero_approx(below), "a car on the street below does not make the rival swerve")
	_expect(is_zero_approx(same_level), "the sideways avoidance shifts nothing today")


## The slipstream: a car on the street below gives no wake.
func _check_slipstream() -> void:
	var speed := RivalSpeed.new()
	speed.line = _line
	var tangent := _line.tangent_at(0.0)
	var right := _line.right_at(0.0)
	var same := _make_stub(Vector3(15.0, DECK, 0.0))
	var low := _make_stub(Vector3(15.0, STREET, 0.0))
	_expect(speed._in_wake(same, _car.global_position, tangent, right),
		"a car 15 m ahead on the same level is in the wake")
	_expect(not speed._in_wake(low, _car.global_position, tangent, right),
		"a car 10 m below is not in the wake")
	_ctx.rivals = [same]
	_expect(absf(speed._slipstream(_car, _ctx, 0.0) - 1.04) < 0.001,
		"the car on the same level gives the slipstream")
	_ctx.rivals = [low]
	_expect(absf(speed._slipstream(_car, _ctx, 0.0) - 1.0) < 0.001,
		"the car on the street below gives no slipstream")


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS " + label)
	else:
		_fails += 1
		print("FAIL " + label)


## Checks that a number lies in a range.
func _expect_range(label: String, value: float, low: float, high: float) -> void:
	_expect(value >= low and value <= high, "%s (%.2f in %.2f..%.2f)" % [
		label, value, low, high])

extends Node
## Unit tests of the traffic IDM, the MOBIL-lite lane-change test and the per-lane car index.
##
##   tools/godot.sh test res://ai/traffic/tests/test_idm.gd

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_test_acceleration()
	_test_gap()
	_test_lane_change()
	_test_platoon()
	_test_lane_hash()
	print("IDM TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The IDM accelerates from a standstill, coasts at its desired speed and brakes for a leader.
func _test_acceleration() -> void:
	var free := IDM.acceleration(0.0, 20.0, 100.0, 0.0)
	_check(free > 1.9 and free <= IDM.A_MAX, "a free car accelerates at a_max (%.2f)" % free)
	var cruise := IDM.acceleration(20.0, 20.0, 500.0, 0.0)
	_check(absf(cruise) < 0.05, "a car at its desired speed coasts (%.3f)" % cruise)
	var blocked := IDM.acceleration(20.0, 20.0, 4.0, 20.0)
	_check(blocked < -1.0, "a car with a close leader brakes (%.2f)" % blocked)
	var too_close := IDM.acceleration(10.0, 20.0, 0.05, 10.0)
	_check(too_close <= -IDM.EMERGENCY, "a car with no room brakes at the emergency cap")


## The desired gap grows with the speed and with the closing speed.
func _test_gap() -> void:
	_check(absf(IDM.desired_gap(0.0, 0.0) - IDM.S0) < 0.001, "the standing gap is s0")
	_check(absf(IDM.desired_gap(20.0, 0.0) - (IDM.S0 + 20.0 * IDM.T)) < 0.001,
		"the gap grows with the time headway")
	_check(IDM.desired_gap(20.0, 5.0) > IDM.desired_gap(20.0, 0.0),
		"the gap grows when the leader is slower")
	_check(IDM.stopping_distance(20.0) > 60.0, "the stopping distance is sane")


## MOBIL-lite: a gain of more than 0.3 m/s^2 changes the lane, but never at the cost of a
## follower that has to brake harder than 3 m/s^2.
func _test_lane_change() -> void:
	_check(IDM.should_change_lane(0.0, 0.5, 0.0), "a clear gain changes the lane")
	_check(not IDM.should_change_lane(0.0, 0.2, 0.0), "a small gain does not")
	_check(not IDM.should_change_lane(0.0, 2.0, 5.0), "a frightened follower blocks the change")


## A platoon of 30 cars must not overlap and must settle down.
func _test_platoon() -> void:
	var count := 30
	var speeds: Array[float] = []
	var gaps: Array[float] = []
	for i in count:
		speeds.append(20.0)
		gaps.append(25.0)
	var dt := 0.1
	var spread_mid := 0.0
	var spread_end := 0.0
	for step in 1800:  # 180 s
		for i in range(1, count):
			var accel := IDM.acceleration(speeds[i], 20.0, gaps[i], speeds[i] - speeds[i - 1])
			speeds[i] = clampf(speeds[i] + accel * dt, 0.0, 30.0)
		for i in range(1, count):
			gaps[i] -= (speeds[i] - speeds[i - 1]) * dt
			if gaps[i] < 0.0:
				gaps[i] = 0.0
		if step == 600:
			spread_mid = _spread(speeds)
		if step == 1800:
			spread_end = _spread(speeds)
	var min_gap := INF
	for gap in gaps:
		min_gap = minf(min_gap, gap)
	var max_speed := 0.0
	var min_speed := INF
	for s in speeds:
		max_speed = maxf(max_speed, s)
		min_speed = minf(min_speed, s)
	_check(min_gap > 0.5, "the platoon never overlaps (min gap %.2f m)" % min_gap)
	_check(min_speed > 10.0 and max_speed < 21.0,
		"the platoon keeps its speed (%.1f .. %.1f m/s)" % [min_speed, max_speed])
	_check(spread_end <= spread_mid + 0.01,
		"the platoon damps out (spread %.2f -> %.2f)" % [spread_mid, spread_end])


## The difference between the fastest and the slowest car of a list.
func _spread(values: Array[float]) -> float:
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


## The per-lane index must find the leader and the follower of every car.
func _test_lane_hash() -> void:
	var hash := LaneHash.new()
	var cars: Array[Node] = []
	for i in 5:
		var car := Node.new()
		car.name = "car%d" % i
		cars.append(car)
		hash.insert(0, float(i) * 30.0, car)
	var other := Node.new()
	hash.insert(1, 10.0, other)
	_check(hash.count(0) == 5, "the hash counts the cars of a lane")
	_check(hash.leader(0, 5.0) == cars[1], "the leader is the next car ahead")
	_check(hash.follower(0, 5.0) == cars[0], "the follower is the car behind")
	_check(hash.leader(0, 100.0) == cars[4], "the leader is the last car of the lane")
	_check(hash.leader(0, 130.0) == null, "no leader at the end of the lane")
	_check(hash.follower(0, 0.0) == null, "no follower at the start of the lane")
	_check(absf(hash.leader_gap(0, 5.0, 5.0) - 20.0) < 0.01, "the leader gap is bumper to bumper")
	_check(absf(hash.follower_distance(0, 35.0) - 5.0) < 0.01, "the follower distance is right")
	_check(hash.leader(1, 5.0) == other, "the lanes are separate")
	for car in cars:
		car.free()
	other.free()

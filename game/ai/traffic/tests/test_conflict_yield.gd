extends Node
## Two cars of lanes that cross, merge or lie over each other: the younger one yields (TrafficCarDriving._conflict_gap).
## The lane hash knows the cars of ONE lane, so cars of different lanes never saw each other: in the traffic soak
## (tools/soak_traffic.gd) cars of crossing lanes drove through each other at the junctions and cars of lanes that lie over each
## other stood pressed together for ever. The test places cars by hand and asks every car for its conflict gap.
## Run: python tools/gd.py test res://ai/traffic/tests/test_conflict_yield.gd

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()
var _graph: LaneGraph = LaneGraph.new()
var _cars: Array[TrafficCar] = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _lane(from: Vector3, to: Vector3) -> LanePath:
	var path := LanePath.new()
	path.road_id = &"test_road"
	path.speed_limit_kmh = 50.0
	path.lane_width = 3.5
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(from)
	curve.add_point(to)
	path.curve = curve
	return path


## A car with a body in the tree, frozen where the test puts it, on `lane` at `s`.
func _car(lane: int, s: float, level: float = 0.0) -> TrafficCar:
	var car := TrafficCar.new()
	car.freeze = true
	add_child(car)
	car.car_length = 4.6
	car.car_width = 1.85
	car.speed = 10.0
	car.mode = TrafficCar.Mode.NEAR
	car.follower = LaneFollower.new()
	car.follower.setup(_graph, lane, s, 1)
	var at := _graph.position_at(lane, s)
	car.global_position = Vector3(at.x, level, at.z)
	car.set("_driving", null)
	var driving := TrafficCarDriving.new()
	driving.ctx = _ctx
	driving.body = car
	driving.follower = car.follower
	driving.car_length = car.car_length
	driving.speed = car.speed
	car.set("_driving", driving)
	_cars.append(car)
	return car


func _publish() -> void:
	_ctx.cells.clear()
	for car in _cars:
		var key := DriveContext.cell_key(car.global_position.x, car.global_position.z)
		if not _ctx.cells.has(key):
			_ctx.cells[key] = []
		(_ctx.cells[key] as Array).append(car)


func _gap(car: TrafficCar) -> float:
	return (car.get("_driving") as TrafficCarDriving)._conflict_gap()


func _run() -> void:
	var lanes: Array[LanePath] = [
		_lane(Vector3(-100.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0)),       # 0: east along X
		_lane(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, 100.0)),       # 1: south along Z (crosses lane 0 at the origin)
		_lane(Vector3(-100.0, 0.0, 3.5), Vector3(100.0, 0.0, 3.5)),       # 2: east, one lane width beside lane 0
		_lane(Vector3(-100.0, 0.0, 0.5), Vector3(100.0, 0.0, 0.5)),       # 3: east, lies over lane 0 (half a metre beside it)
	]
	_graph.build(lanes)
	_ctx.graph = _graph
	# the crossing: B (older) drives along lane 1 and is 1 m before the crossing, A (younger) comes along lane 0, 6 m before it
	var older := _car(1, 99.0)
	var younger := _car(0, 94.0)
	_publish()
	var gap_young := _gap(younger)
	_check(gap_young < 3.0 and gap_young >= 0.0, "the younger car yields to the older one in its way", "(gap %.2f m)" % gap_young)
	_check(_gap(older) == INF, "the older car does not look at the younger one", "(%s)" % str(_gap(older)))
	# the cars far apart do not bother each other
	younger.global_position = Vector3(-60.0, 0.0, 0.0)
	_publish()
	_check(_gap(younger) == INF, "a car 60 m away is no conflict")
	# parallel lanes, side by side: no conflict
	for car in _cars:
		car.queue_free()
	_cars.clear()
	var beside_old := _car(2, 100.0)
	var beside_young := _car(0, 100.0)
	_publish()
	_check(_gap(beside_young) == INF, "a car on the lane beside it is no conflict", "(%s)" % str(_gap(beside_young)))
	# lanes that lie over each other: the younger yields to the older that is ahead of it
	for car in _cars:
		car.queue_free()
	_cars.clear()
	var ahead_old := _car(3, 110.0)
	var behind_young := _car(0, 100.0)
	_publish()
	var gap_over := _gap(behind_young)
	_check(gap_over > 0.0 and gap_over < 6.0, "a car on a lane that lies over its own yields to the older car ahead", "(gap %.2f m)" % gap_over)
	_check(_gap(ahead_old) == INF, "the older car ahead does not yield to the car behind it")
	# the same lane is the business of the lane hash
	for car in _cars:
		car.queue_free()
	_cars.clear()
	var lead_old := _car(0, 110.0)
	var follow_young := _car(0, 100.0)
	_publish()
	_check(_gap(follow_young) == INF, "a car of the same lane is left to the lane hash")
	# another level: a deck over the street is no conflict
	for car in _cars:
		car.queue_free()
	_cars.clear()
	var deck_old := _car(3, 110.0, 6.0)
	var street_young := _car(0, 100.0)
	_publish()
	_check(_gap(street_young) == INF, "a car on a deck over the street is no conflict")
	# a wreck is yielded to whatever its age
	for car in _cars:
		car.queue_free()
	_cars.clear()
	var driver := _car(0, 100.0)
	var wreck := _car(3, 112.0)
	wreck.mode = TrafficCar.Mode.WRECK
	_publish()
	var gap_wreck := _gap(driver)
	_check(gap_wreck > 0.0 and gap_wreck < 8.0, "a wreck in the way is yielded to, whatever its age", "(gap %.2f m)" % gap_wreck)
	print("CONFLICT TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

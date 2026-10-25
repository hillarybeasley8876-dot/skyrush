extends Node
## A traffic car does not drive into a lane that ends at once when it has another way to go.
##
##   python tools/gd.py test res://ai/traffic/tests/test_dead_end_choice.gd
##
## The lane graph of the city has lanes without a successor (the end of a road at a junction, the
## edge of the map): a car that takes one stops at its end and waits there. The junction before it
## offers another way (a turn, or straight on): LaneFollower.choose_next takes that one. A lane that
## only has dead ends ahead still picks one of them, and a junction without dead ends is chosen as it
## always was (the same random numbers, the same lanes).

const DRAWS := 400

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# lane 0 runs east into a junction at x = 100: straight on (lane 1) or right (lane 2, south)
	# lane 1 is a dead end, lane 2 goes on into lane 3; lane 4 is a left turn (north) that dead-ends
	var east := _lane(Vector3.ZERO, Vector3(100, 0, 0))
	var straight_dead := _lane(Vector3(100, 0, 0), Vector3(200, 0, 0))
	var right_live := _lane(Vector3(100, 0, 0), Vector3(100, 0, 100))
	var onwards := _lane(Vector3(100, 0, 100), Vector3(100, 0, 200))
	var left_dead := _lane(Vector3(100, 0, 0), Vector3(100, 0, -100))
	right_live.next_lanes = PackedInt32Array([3])

	# A: straight on dead-ends, the right turn goes on: always the turn
	east.next_lanes = PackedInt32Array([1, 2])
	var picks := _draw(_graph([east, straight_dead, right_live, onwards]), 0)
	_check(picks.get(2, 0) == DRAWS, "straight on dead-ends: the car turns into the lane that goes on (%s)" % str(picks))

	# B: straight on goes on (lane 1 now leads on), the left turn dead-ends: always straight on
	var straight_live := _lane(Vector3(100, 0, 0), Vector3(200, 0, 0))
	var beyond := _lane(Vector3(200, 0, 0), Vector3(300, 0, 0))
	straight_live.next_lanes = PackedInt32Array([2])
	east.next_lanes = PackedInt32Array([1, 3])
	picks = _draw(_graph([east, straight_live, beyond, left_dead]), 0)
	_check(picks.get(1, 0) == DRAWS, "the left turn dead-ends: the car goes straight on (%s)" % str(picks))

	# C: everything dead-ends: the car still picks a lane (it has to go somewhere)
	east.next_lanes = PackedInt32Array([1, 2])
	var dead_turn := _lane(Vector3(100, 0, 0), Vector3(100, 0, 100))
	picks = _draw(_graph([east, straight_dead, dead_turn]), 0)
	_check(picks.get(1, 0) + picks.get(2, 0) == DRAWS and picks.get(1, 0) > 0,
		"every way dead-ends: the car still picks one, mostly straight on (%s)" % str(picks))

	# D: no dead end: straight on with 1 - TURN_CHANCE, the turn with TURN_CHANCE
	var right_on := _lane(Vector3(100, 0, 0), Vector3(100, 0, 100))
	var right_beyond := _lane(Vector3(100, 0, 100), Vector3(100, 0, 200))
	right_on.next_lanes = PackedInt32Array([4])
	straight_live.next_lanes = PackedInt32Array([2])
	east.next_lanes = PackedInt32Array([1, 3])
	picks = _draw(_graph([east, straight_live, beyond, right_on, right_beyond]), 0)
	var share := float(picks.get(3, 0)) / float(DRAWS)
	_check(absf(share - LaneFollower.TURN_CHANCE) < 0.08,
		"no dead end: the turn takes its share (%.2f, TURN_CHANCE %.2f)" % [share, LaneFollower.TURN_CHANCE])
	print("DEAD END CHOICE TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## The next lanes a car on `lane` picks in DRAWS tries: {lane index: count}.
func _draw(graph: LaneGraph, lane: int) -> Dictionary:
	var follower := LaneFollower.new()
	follower.setup(graph, lane, 50.0, 7)
	var out := {}
	for i in DRAWS:
		var pick := follower.choose_next()
		out[pick] = int(out.get(pick, 0)) + 1
	return out


func _graph(lanes: Array) -> LaneGraph:
	var list: Array[LanePath] = []
	for lane in lanes:
		list.append((lane as LanePath).duplicate())
	var graph := LaneGraph.new()
	graph.build(list)
	return graph


func _lane(from: Vector3, to: Vector3) -> LanePath:
	var path := LanePath.new()
	path.road_id = &"test"
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(from)
	curve.add_point(to)
	path.curve = curve
	return path


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1

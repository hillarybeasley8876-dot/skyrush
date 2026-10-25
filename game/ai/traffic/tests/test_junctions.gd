extends Node
## The traffic lights of the traffic: only a street has a light, and a car stops at a red one.
##
##   tools/godot.sh test res://ai/traffic/tests/test_junctions.gd -- --timeout=290
##
## The city has an elevated deck, ramps and bridges. A traffic light on a deck looks broken (the
## light of a junction in the plan view is somewhere else in the city), so only a surface street
## at ground level gets one. The second part of the test drives a car to a red light and checks
## that it stops in front of the line and goes on when the light turns green.

const WORLD := "res://world/world.tscn"
## s: the physics step of the engine (the tests wait its ticks)
var DT: float = 1.0 / Engine.physics_ticks_per_second
const STOP_GAP := 4.0     ## m: how far in front of the line the car may stand
const APPROACH := 30.0    ## m: the car starts this far before the line

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()
var _graph: LaneGraph = null


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	if not ResourceLoader.exists(WORLD):
		print("FAIL the city is not built (", WORLD, ")")
		get_tree().quit(1)
		return
	var world := (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	await Game.world_ready()
	var lanes := (Game.world as WorldBase).get_lane_paths()
	_check(not lanes.is_empty(), "the city has lanes (%d)" % lanes.size())
	if lanes.is_empty():
		get_tree().quit(1)
		return
	_graph = LaneGraph.new()
	_graph.build(lanes)
	_ctx.graph = _graph
	_ctx.world = Game.world
	_ctx.rng.seed = 99
	var junctions := TrafficJunctions.new()
	_ctx.junctions = junctions.resolve(Game.world, _graph)
	_check(junctions.resolved > 0, "the city has lanes with a light (%d)" % junctions.resolved)
	_audit_lights()
	_test_stop_at_a_red_light()
	print("JUNCTION TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## No lane of a deck, of a ramp or of a bridge may have a traffic light.
func _audit_lights() -> void:
	var elevated := 0
	var ramp := 0
	var above_ground := 0
	var street := 0
	for i in _graph.lane_count():
		if _ctx.junctions[i] == "":
			continue
		var path := _graph.lanes[i]
		if path.elevated:
			elevated += 1
		if String(path.road_id).contains("ramp"):
			ramp += 1
		if _graph.position_at(i, _graph.lane_length(i)).y > 2.0:
			above_ground += 1
		street += 1
	_check(elevated == 0, "no lane of a deck has a light (%d)" % elevated)
	_check(ramp == 0, "no lane of a ramp has a light (%d)" % ramp)
	_check(above_ground == 0, "no lane above the ground has a light (%d)" % above_ground)
	print("LIGHTS %d lanes of the city" % street)


## A car that drives to a red light has to stop in front of the line and go on when it turns
## green.
func _test_stop_at_a_red_light() -> void:
	var lane := _lane_with_a_light()
	_check(lane >= 0, "the city has a lane that ends at a light")
	if lane < 0:
		return
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, 3)
	car.player_distance = 0.0
	var length := _graph.lane_length(lane)
	car.place(lane, maxf(length - APPROACH, 0.0))
	var stopped_at := -1.0
	var saw_red := false
	for step in Engine.physics_ticks_per_second * 30:
		# The signal controller runs in the process of the world: the frames have to pass.
		await get_tree().physics_frame
		car.tick(DT)
		var state := _light_state(lane)
		if state == 0:
			saw_red = true
		if saw_red and car.speed < 0.2 and stopped_at < 0.0:
			stopped_at = length - car.follower.s
			break
	_check(saw_red, "the light of the lane turns red")
	_check(stopped_at >= 0.0, "the car stops at the red light")
	if stopped_at >= 0.0:
		_check(stopped_at <= STOP_GAP,
			"the car stops %.1f m before the line (at most %.1f m)" % [stopped_at, STOP_GAP])
	# The light turns green again: the car has to go on.
	var moved := false
	for step in Engine.physics_ticks_per_second * 30:
		await get_tree().physics_frame
		car.tick(DT)
		if car.speed > 3.0:
			moved = true
			break
	_check(moved, "the car goes on when the light turns green")


## A lane of the city that ends at a traffic light.
func _lane_with_a_light() -> int:
	for i in _graph.lane_count():
		if _ctx.junctions[i] == "":
			continue
		if _graph.lane_length(i) < APPROACH:
			continue
		return i
	return -1


## The state of the light of the lane (0 red, 1 amber, 2 green).
func _light_state(lane: int) -> int:
	var junction := _ctx.junction_of(lane)
	if junction == &"":
		return 2
	return _ctx.signal_state(junction, _graph.lanes[lane].road_id)

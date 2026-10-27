extends Node
## The long run: 70 cars on the lanes of a world for 120 s of simulated time at 4x speed.
##
##   tools/godot.sh test res://ai/traffic/tests/test_lanes_world.gd -- --timeout=290
##
## The test runs on the core sandbox AND on the real city (res://world/world.tscn) and checks
## that the cars keep their path, never jump, never fall through the road, never drive through
## each other and that the traffic stays inside its performance budget (dossier 7.7: 1.0 ms per
## frame for 70 cars).
##
## The city part waits for the world to be built (CONTRACTS 4): a world without lanes is a
## failure, never a skip. The measurements are in LanesWorldProbe, this file is the run and
## the report.

const CARS := 70
const SIM_SECONDS := 120.0
## The game runs this much faster than the clock in the test: a tick covers 33 ms of game time (4x at 120 Hz, 2x at 60 Hz).
## --time-scale=1 runs it as the game does (the ticks of the game, 120 s of the clock).
var TIME_SCALE: float = float(Game.option("time-scale", str(4.0 * float(Engine.physics_ticks_per_second) / 120.0)))
const BUDGET_MS := 0.5         ## ms per tick (the traffic, tick and physics together)
const P99_BUDGET_MS := 2.0     ## ms: the slowest tick of the run
const P10_BUDGET_MS := 0.25    ## ms: the fastest tenth of the ticks (a busy machine)
const SPAWN_BUDGET_MS := 0.1   ## ms: a spawn out of the pool
const WORLDS := ["res://core/sandbox/sandbox.tscn", "res://world/world.tscn"]
const NEAR_LANE_RADIUS := 300.0 ## m: the lanes around the player the test puts its cars on
const CHANGE_PER_MINUTE := 1.0   ## lane changes per car and minute
const OVERLAP_LIMIT := 0         ## cars of a lane that may drive through each other


## Counts the engine errors of the traffic itself (the world and the vehicle have their own).
class AiErrorCounter extends Logger:
	var errors: int = 0
	var first: PackedStringArray = PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		if not file.begins_with("res://ai/"):
			return
		errors += 1
		if first.size() < 10:
			first.append("%s:%d %s(): %s" % [file, line, function,
					rationale if rationale != "" else code])


var _failures: int = 0
var _counter: AiErrorCounter = null
var _probe: LanesWorldProbe = LanesWorldProbe.new()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_counter = AiErrorCounter.new()
	OS.add_logger(_counter)
	for world_path: String in WORLDS:
		if not ResourceLoader.exists(world_path):
			_check(false, "%s exists" % world_path)
			continue
		await _run_world(world_path)
	_check(_counter.errors == 0, "no engine error in res://ai/ (%d: %s)"
			% [_counter.errors, ", ".join(_counter.first)])
	print("LANES/WORLD TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Runs the simulation on one world.
func _run_world(world_path: String) -> void:
	_probe.reset()
	var world_scene := load(world_path) as PackedScene
	var world := world_scene.instantiate()
	add_child(world)
	await get_tree().process_frame
	# The real city builds over several seconds: the lanes only exist when it is done.
	await Game.world_ready()
	var lanes: Array[LanePath] = (world as WorldBase).get_lane_paths()
	_check(not lanes.is_empty(), "%s has lanes (%d)" % [world_path.get_file(), lanes.size()])
	if lanes.is_empty():
		world.queue_free()
		return
	var director := (load("res://ai/traffic/traffic_director.tscn") as PackedScene).instantiate()
	add_child(director)
	await get_tree().physics_frame
	# The player drives in the first lane, so the traffic reacts to it.
	var player := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate()
	add_child(player)
	Game.player = player
	player.reset_to((world as WorldBase).get_spawn_transform(&"player", 0))
	# The test puts its own cars on the road: the ring of the traffic does not add any.
	director.set("density_override", 0)
	# The cars of the test stay on the road.
	director.set("despawn_distance", 100000.0)
	var graph: LaneGraph = director.get("ctx").get("graph")
	if graph == null:
		_check(false, "%s has a lane graph" % world_path.get_file())
		return
	var near_lanes: Array[int] = []
	for i in graph.lane_count():
		if graph.is_duplicate(i):
			continue
		var middle := graph.position_at(i, graph.lane_length(i) * 0.5)
		if middle.distance_to(player.global_position) < NEAR_LANE_RADIUS:
			near_lanes.append(i)
	near_lanes.sort_custom(func(a: int, b: int) -> bool:
		return graph.lane_length(a) > graph.lane_length(b))
	if near_lanes.is_empty():
		near_lanes.append(0)
	var lane_count := maxi(mini(near_lanes.size(), 4), 1)
	var per_lane := int(ceil(float(CARS) / float(lane_count)))
	for k in lane_count:
		# The cars of a lane are spread over it, so they do not start on top of each other.
		var length := graph.lane_length(near_lanes[k])
		var spacing := length / float(per_lane)
		for i in per_lane:
			var started := Time.get_ticks_usec()
			director.call("spawn_car_at", near_lanes[k], fposmod(float(i) * spacing, length))
			_probe.spawn_costs.append(float(Time.get_ticks_usec() - started) / 1000.0)
	await get_tree().physics_frame
	_check(director.get("cars").size() >= CARS, "%s has %d cars" % [world_path.get_file(),
			director.get("cars").size()])
	_check(director.get("ctx").get("player") != null,
			"%s: the traffic sees the player" % world_path.get_file())
	director.connect("car_removed", _probe.on_car_removed)
	await _run_seconds(director, world_path)
	_report(world_path, director)
	# The nodes have to leave the tree before they are freed, or they tick once more with
	# their cars already gone.
	remove_child(director)
	remove_child(player)
	remove_child(world)
	director.queue_free()
	player.queue_free()
	world.queue_free()
	await get_tree().physics_frame


## Runs the simulation and samples it every frame.
func _run_seconds(director: Node, world_path: String) -> void:
	TrafficCar.measure_cost = true
	Engine.time_scale = TIME_SCALE
	var seconds := SIM_SECONDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
	var frames := int(seconds * Engine.physics_ticks_per_second / TIME_SCALE)
	for i in frames:
		await get_tree().physics_frame
		_probe.sample(director, 1.0 / (Engine.physics_ticks_per_second / TIME_SCALE))
	Engine.time_scale = 1.0
	TrafficCar.measure_cost = false


## The report of one world: the path, the jumps, the standstill, the overlaps and the cost.
func _report(world_path: String, director: Node) -> void:
	var name := world_path.get_file()
	var live: Array = director.get("cars")
	# The cars that reach the end of a dead end road leave the traffic (they wait there until
	# they are out of sight), so the fleet may shrink a little.
	_check(live.size() >= CARS * 7 / 10,
		"%s: %d of %d cars are still on the road" % [name, live.size(), CARS])
	_check(_probe.worst_deviation <= LanesWorldProbe.MAX_DEVIATION,
		"%s: no car leaves its path by more than %.1f m (worst %.2f m)"
		% [name, LanesWorldProbe.MAX_DEVIATION, _probe.worst_deviation])
	_check(_probe.worst_jump <= LanesWorldProbe.JUMP_LIMIT,
		"%s: no car moves more than %.1f m more than its own step (worst %.2f m)"
		% [name, LanesWorldProbe.JUMP_LIMIT, _probe.worst_jump])
	print("JUMP %s: %s" % [name, _probe.worst_jump_where])
	_check(_probe.lowest_y > -1.5, "%s: no car falls through the road (lowest %.2f m under its lane)"
		% [name, _probe.lowest_y])
	_check(_probe.worst_height <= LanesWorldProbe.MAX_DEVIATION,
		"%s: no car is more than %.1f m above or below its path (worst %.2f m)"
		% [name, LanesWorldProbe.MAX_DEVIATION, _probe.worst_height])
	var by_count := _probe.overlap_counts.keys()
	by_count.sort_custom(func(x, y): return int(_probe.overlap_counts[x]) > int(_probe.overlap_counts[y]))
	for key in by_count.slice(0, 12):
		print("OVERLAP %s: %d samples, first %s" % [name, int(_probe.overlap_counts[key]), _probe.overlap_lanes[key]])
	_check(_probe.overlaps == OVERLAP_LIMIT,
		"%s: no two cars of a lane drive through each other (%d, worst %.2f m)"
		% [name, _probe.overlaps, _probe.worst_overlap])
	_check(_probe.longest_still <= LanesWorldProbe.STANDSTILL_LIMIT,
		"%s: no car stands still for more than %.0f s on a free lane (longest %.1f s on the %s)"
		% [name, LanesWorldProbe.STANDSTILL_LIMIT, _probe.longest_still, _probe.longest_why])
	_check(_probe.v0_errors == 0,
		"%s: every car drives at the speed limit of its road (%d wrong, worst %.2f m/s)"
		% [name, _probe.v0_errors, _probe.worst_v0])
	if _probe.multi_minutes > 0.0:
		_check(_probe.multi_changes >= CHANGE_PER_MINUTE * _probe.multi_minutes,
			"%s: the cars of a multi-lane road change the lane (%.2f per car and minute)"
			% [name, _probe.multi_changes / _probe.multi_minutes])
	else:
		print("INFO %s: the world has no road with more than one lane" % name)
	_report_cost(name)
	print("REMOVED %s: %d cars left the traffic, %d of them stood still at the end of a road"
		% [name, _probe.removed, _probe.removed_stopped])


## The cost of the traffic: the raw time of every tick, the parts and the load of the machine.
func _report_cost(name: String) -> void:
	var sorted: Array[float] = _probe.tick_costs.duplicate()
	sorted.sort()
	if sorted.is_empty():
		print("PERF %s: no tick" % name)
		return
	var p10 := sorted[int(float(sorted.size()) * 0.1)]
	var median := sorted[sorted.size() / 2]
	var p99 := sorted[mini(int(float(sorted.size()) * 0.99), sorted.size() - 1)]
	var load := _load_average()
	print("PERF %s: %.3f ms per tick (median), %.3f ms (p99), %.3f ms (p10), %d ticks, load %.1f"
		% [name, median, p99, p10, sorted.size(), load])
	var parts: Array[String] = []
	for part in ["index", "cars", "modes", "events", "ring", "physics"]:
		parts.append("%s %.3f" % [part, _median_of(_probe.part_costs.get(part, [] as Array[float]))])
	print("COST %s: %s ms (median of %d ticks)" % [name, ", ".join(parts), _probe.tick_costs.size()])
	print("CARS %s: think %.1f us, move %.1f us, lamp %.1f us over %d calls (plan %.1f speed %.1f lane %.1f)"
		% [name, TrafficCar.t_think, TrafficCar.t_move, TrafficCar.t_lamp, TrafficCar.t_calls,
			TrafficCar.t_plan, TrafficCar.t_speed, TrafficCar.t_lane])
	TrafficCar.t_plan = 0.0
	TrafficCar.t_speed = 0.0
	TrafficCar.t_lane = 0.0
	TrafficCar.t_think = 0.0
	TrafficCar.t_move = 0.0
	TrafficCar.t_lamp = 0.0
	TrafficCar.t_calls = 0
	_check(median <= BUDGET_MS, "%s: the traffic stays inside its %.1f ms/tick budget (%.3f ms)"
		% [name, BUDGET_MS, median])
	_check(p99 <= P99_BUDGET_MS, "%s: no tick takes longer than %.1f ms (%.3f ms)"
		% [name, P99_BUDGET_MS, p99])
	if load > 10.0:
		# The machine is busy: the fastest tenth of the ticks is the number that counts.
		_check(p10 <= P10_BUDGET_MS, "%s: the fastest tenth of the ticks is %.3f ms (at most %.3f)"
			% [name, p10, P10_BUDGET_MS])
	_report_spawn_cost(name)


## The cost of a spawn out of the pool: a spawn must not build a car in the middle of the game.
func _report_spawn_cost(name: String) -> void:
	if _probe.spawn_costs.is_empty():
		return
	var sorted: Array[float] = _probe.spawn_costs.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var worst := sorted[sorted.size() - 1]
	print("SPAWN %s: %.3f ms per spawn (median), %.3f ms (worst), %d spawns"
		% [name, median, worst, sorted.size()])
	_check(median <= SPAWN_BUDGET_MS, "%s: a spawn out of the pool costs %.3f ms (at most %.3f)"
		% [name, median, SPAWN_BUDGET_MS])


## The load average of the machine: the cost of a tick only means something on a machine that
## is not busy with the work of the other units (-1 when it cannot be read).
func _load_average() -> float:
	if OS.get_name() == "Windows":
		return -1.0   # there is no uptime command: asking for it is an engine error
	var out: Array = []
	OS.execute("uptime", [], out)
	for line in out:
		var text := String(line)
		var at := text.find("load averages:")
		if at < 0:
			continue
		var rest := text.substr(at + 14).strip_edges()
		return float(rest.split(" ")[0])
	return -1.0


## The median of a list of costs.
func _median_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])

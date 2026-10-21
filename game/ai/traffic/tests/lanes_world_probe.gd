class_name LanesWorldProbe
extends RefCounted
## The probe of the long traffic run: it watches the cars of the traffic and measures what the
## test asserts (the path, the jumps, the standstill, the overlaps, the cost).
##
## The probe is a helper of the test (see test_lanes_world.gd), not a test of its own: it never
## quits the game and it never prints.

const WARMUP_FRAMES := 240        ## frames: the first two seconds after the world was built
const STANDSTILL_LIMIT := 20.0     ## s: how long a car may stand still on a free lane
const CHANGE_PER_MINUTE := 1.0     ## lane changes per car and minute
const OVERLAP_FACTOR := 0.8        ## x the shorter car: how close two cars may be
const QUEUE_GAP := 30.0            ## m: a car that waits behind another one is not stuck
const MAX_DEVIATION := 1.0         ## m: how far a car may be from its path
const JUMP_LIMIT := 0.3            ## m: how much more than its own step a car may move

## The worst deviation of a car from its path (m).
var worst_deviation: float = 0.0
## The worst jump of a car over its own step (m).
var worst_jump: float = 0.0
## Where the worst jump happened (for the report).
var worst_jump_where: String = ""
## The worst distance of a car above or below its path (m).
var worst_height: float = 0.0
## The lowest a car was under its path (m).
var lowest_y: float = 9999.0
## The time of every tick (ms).
var tick_costs: Array[float] = []
## The time of the parts of every tick (ms).
var part_costs: Dictionary = {}
## How long each car has been standing still.
var still: Dictionary = {}
## The lane entry of every car, to count the changes.
var serials: Dictionary = {}
## The lane changes on a road with more than one lane.
var multi_changes: int = 0
## The car minutes on a road with more than one lane.
var multi_minutes: float = 0.0
## The longest standstill of a car that was not waiting for another car.
var longest_still: float = 0.0
## Where the longest standstill happened.
var longest_why: String = ""
## The cars that drove through each other.
var overlaps: int = 0
## The worst overlap.
var worst_overlap: float = 0.0
## The cars that drive at the wrong speed limit.
var v0_errors: int = 0
## The worst speed limit error.
var worst_v0: float = 0.0
## The cars that left the traffic.
var removed: int = 0
## The cars that left the traffic because the road ended.
var removed_stopped: int = 0
## The cost of the spawns (ms).
var spawn_costs: Array[float] = []

var _frames: int = 0
var _previous: Dictionary = {}
var _previous_mode: Dictionary = {}


## Forgets everything: the probe is used for one world at a time.
func reset() -> void:
	worst_deviation = 0.0
	worst_jump = 0.0
	worst_jump_where = ""
	worst_height = 0.0
	lowest_y = 9999.0
	tick_costs.clear()
	part_costs.clear()
	still.clear()
	serials.clear()
	multi_changes = 0
	multi_minutes = 0.0
	longest_still = 0.0
	longest_why = ""
	overlaps = 0
	worst_overlap = 0.0
	v0_errors = 0
	worst_v0 = 0.0
	removed = 0
	removed_stopped = 0
	spawn_costs.clear()
	_frames = 0
	_previous.clear()
	_previous_mode.clear()


## One sample of the traffic: the cost of the tick, the jumps, the standstill, the lane changes
## and the speed limit of the road the car is on.
func sample(director: Node, dt: float) -> void:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return
	tick_costs.append(float(director.get("tick_last_ms")) + float(director.get("physics_last_ms")))
	for part in ["index", "cars", "modes", "events", "ring", "physics"]:
		if not part_costs.has(part):
			part_costs[part] = [] as Array[float]
		var key := "physics_last_ms" if part == "physics" else "cost_%s_ms" % part
		(part_costs[part] as Array[float]).append(float(director.get(key)))
	var cars: Array = director.get("cars")
	for car: TrafficCar in cars:
		if car.follower == null:
			continue
		_sample_car(car, dt)
	if _frames % 10 == 0:
		sample_overlaps(cars)


## The path, the jump, the standstill and the speed limit of one car.
func _sample_car(car: TrafficCar, dt: float) -> void:
	var follower := car.follower
	# The distance of the body from the path it drives (the lane or the junction connector).
	var offset := car.global_position - follower.position()
	worst_deviation = maxf(worst_deviation, Vector2(offset.x, offset.z).length())
	worst_height = maxf(worst_height, absf(offset.y))
	# A car that sinks under its lane falls through the road.
	lowest_y = minf(lowest_y, offset.y)
	# The jump: what the body moves more than its own step allows.
	var id := car.get_instance_id()
	if _previous.has(id):
		var last: Vector3 = _previous[id]
		var expected := car.step_speed * maxf(car.last_dt, dt)
		var extra := car.global_position.distance_to(last) - expected
		if extra > worst_jump:
			worst_jump = extra
			worst_jump_where = "lane %d s %.1f conn %s mode %d v %.1f dt %.3f" % [
				follower.lane, follower.s, str(follower.on_connector()), car.mode, car.speed,
				car.last_dt]
	_previous[id] = car.global_position
	_previous_mode[id] = car.mode
	# The standstill: a car that waits behind another one is in a queue, not stuck.
	if car.speed < 0.2 and car.mode != TrafficCar.Mode.WRECK and not car.despawn:
		still[id] = float(still.get(id, 0.0)) + dt
		var seconds := float(still[id])
		if seconds > longest_still and _lane_is_free(car) and not _in_a_queue(car):
			longest_still = seconds
			longest_why = "lane %d" % follower.lane
	else:
		still[id] = 0.0
	# The lane changes: only the cars of a road with more than one lane can change.
	var serial: int = follower.lane_serial
	if _on_a_multi_lane(car):
		multi_minutes += dt / 60.0
	if serials.has(id):
		if int(serials[id]) != serial:
			if _on_a_multi_lane(car):
				multi_changes += 1
	serials[id] = serial
	# The speed limit of the road the car drives on.
	var limit := car.desired_speed / maxf(car.driver_factor, 0.01)
	var path_limit := _limit_of(car)
	if path_limit > 0.0:
		var error := absf(limit - path_limit)
		worst_v0 = maxf(worst_v0, error)
		if error > 0.1:
			v0_errors += 1


## True when the lane of the car has no red light in front of it: a car that stands still there
## is stuck, not waiting.
func _lane_is_free(car: TrafficCar) -> bool:
	var ctx: DriveContext = car.ctx
	var lane := car.follower.lane
	# A car that waits at the end of a dead end is not stuck: the road ends there.
	if ctx.graph.is_dead_end(lane):
		return false
	if not ctx.lane_has_signal(lane):
		# A car that queues for the light of the next lane is waiting, not stuck.
		var next_lane := car.follower.planned_next
		if next_lane >= 0 and ctx.lane_has_signal(next_lane) \
				and ctx.graph.lane_length(lane) - car.follower.s < 80.0:
			return false
		return true
	var junction := ctx.junction_of(lane)
	if junction == &"":
		return true
	return ctx.signal_state(junction, ctx.graph.lanes[lane].road_id) == 2


## True when the car waits behind another car that stands still: that is a queue, not a car
## that got stuck on the road.
func _in_a_queue(car: TrafficCar) -> bool:
	var ctx: DriveContext = car.ctx
	var ahead := ctx.hash.leader(car.follower.lane, car.follower.index_s()) as VehicleBase
	if ahead == null:
		return false
	if ahead is TrafficCar and (ahead as TrafficCar).speed > 0.5:
		return false
	return ctx.hash.leader_distance(car.follower.lane, car.follower.index_s()) < QUEUE_GAP


## True when the lane of the car has a neighbour: the road has more than one lane.
func _on_a_multi_lane(car: TrafficCar) -> bool:
	var graph: LaneGraph = car.ctx.graph
	if graph == null:
		return false
	var lane := car.follower.lane
	if lane < 0 or lane >= graph.lane_count():
		return false
	return graph.left[lane] >= 0 or graph.right[lane] >= 0


## The speed limit of the lane the car is on (0 when the lane has none).
func _limit_of(car: TrafficCar) -> float:
	var graph: LaneGraph = car.ctx.graph
	if graph == null:
		return 0.0
	var index := clampi(car.follower.lane, 0, graph.lane_count() - 1)
	return graph.lanes[index].speed_limit_kmh / 3.6


## Two cars of the same lane must not drive through each other.
##
## The test looks at the cars as boxes: two cars that pass each other in a junction are not
## driving through each other, they are simply not on the same piece of road.
func sample_overlaps(cars: Array) -> void:
	for i in cars.size():
		var a := cars[i] as TrafficCar
		if a.mode == TrafficCar.Mode.WRECK:
			continue
		for j in range(i + 1, cars.size()):
			var b := cars[j] as TrafficCar
			if b.mode == TrafficCar.Mode.WRECK:
				continue
			if a.follower.lane != b.follower.lane:
				continue
			if absf(a.global_position.y - b.global_position.y) > 1.5:
				continue
			var local := a.global_transform.affine_inverse() * b.global_position
			if absf(local.x) >= 0.4 * (a.car_width + b.car_width):
				continue
			if absf(local.z) >= 0.4 * (a.car_length + b.car_length):
				continue
			overlaps += 1
			worst_overlap = maxf(worst_overlap, 0.4 * (a.car_length + b.car_length) - absf(local.z))


## A car that left the traffic: the ones that stood still were at the end of a dead end road.
func on_car_removed(car: TrafficCar) -> void:
	removed += 1
	if car.speed < 0.5:
		removed_stopped += 1

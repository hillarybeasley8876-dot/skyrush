class_name TrafficCarDriving
extends RefCounted
## The longitudinal behaviour of one traffic car: the leader in the lane, the leader in the lane
## the car will continue into, the traffic light at the end of the lane and the reaction to the
## player all end up in one acceleration.
##
## The traffic of a junction is the hard part: a car that is 40 m before the end of its lane
## still has to brake for the car that is already on the next lane, and the connector through
## the junction box has to be counted as well.
##
## The helper keeps the gap and the speed of the leader it found in `leader_gap` and
## `leader_speed`, so the hot path does not allocate an array for every car and every tick.

const SIGNAL_AMBER := 1            ## the traffic light states of the world
const SIGNAL_GREEN := 2
const SIGNAL_LOOKAHEAD := 45.0     ## m: how far ahead the car looks for the stop line
const STOP_LINE_MARGIN := 0.5      ## m: the car stops its bumper before the stop line
const BRAKE_OVERRIDE_ACCEL := -2.0 ## m/s^2: the brake of the capture scene
## x the car length: how far around the entry point a car blocks the merge.
const MERGE_WINDOW := 1.5
## s: how long before the merge point the car starts to yield.
const MERGE_BRAKE_TIME := 2.0
## The conflict with a car of another lane: how far ahead (s of driving, with a floor and a ceiling in m), how far above or
## below (m) and how much room besides the two half widths (m).
const CONFLICT_TIME := 1.5
const CONFLICT_MIN_REACH := 8.0
const CONFLICT_MAX_REACH := 30.0
const CONFLICT_LEVEL := 2.5
const CONFLICT_MARGIN := 0.3

var ctx: DriveContext = null
## The car that drives (its body is where the conflicts are looked for).
var body: TrafficCar = null
## The lane state of the car.
var follower: LaneFollower = null
## The length of the car, used for the gaps.
var car_length: float = 4.6
## The gap to the car ahead of this one (m) and the speed of that car (m/s).
var leader_gap: float = INF
var leader_speed: float = 0.0
## The speed the car drives with (m/s).
var speed: float = 0.0
## The speed of the leader the junction lookup found.
var _found_speed: float = 0.0


## The acceleration of the car (m/s^2). Positive = accelerate, negative = brake.
##
## `speed` is the current speed, `desired_speed` the speed the car aims for, `reaction_brake`
## the extra brake of a driver that was startled by the player and `brake_override` the brake of
## the capture scene.
func acceleration(speed: float, desired_speed: float, reaction_brake: float,
		brake_override: bool) -> float:
	self.speed = speed
	var lane := follower.lane
	var gap := INF
	var lead_speed := 0.0
	# The place of the car in the per-lane index: on a connector that is the end of the lane it
	# came from, so the car does not find itself as its own leader.
	var here := follower.index_s()
	var index := ctx.hash.leader_index(lane, here)
	if index >= 0:
		gap = ctx.hash.distance_at(index) - here - car_length
		lead_speed = _speed_of(ctx.hash.object_at(index) as VehicleBase)
	# The leader may already be on the next lane: look through the junction.
	var ahead := _next_lane_gap(lane)
	if ahead < gap:
		gap = ahead
		lead_speed = _found_speed
	# A car of another lane that is in the way: the lanes cross, merge or lie over each other.
	var conflict := _conflict_gap()
	if conflict < gap:
		gap = conflict
		lead_speed = _found_speed
	# The stop line is the end of the lane; a red or amber light puts a stopped leader there.
	var signal_gap := _signal_gap(lane, speed)
	if signal_gap < gap:
		gap = signal_gap
		lead_speed = 0.0
	leader_gap = gap
	leader_speed = lead_speed
	var dv := speed - lead_speed
	var accel := IDM.acceleration(speed, desired_speed, gap, dv)
	if brake_override:
		accel = minf(accel, BRAKE_OVERRIDE_ACCEL)
	if reaction_brake < 0.0:
		accel = minf(accel, reaction_brake)
	return accel


## The gap to a car of ANOTHER lane that stands in the way of this one. Two lanes cross in a junction (a left turn against the
## oncoming traffic), converge at a merge or lie over each other at the end of a lane; the lane hash knows the cars of a lane, so
## such cars never saw each other and drove through each other, or stood pressed against each other for ever (the traffic soak:
## 6 overlaps and jams in 8 sites). The YOUNGER car yields, and only to older cars, so two cars never wait for each other (the
## order is a total order: no ring of cars that wait for each other). A wreck is yielded to whatever its age.
func _conflict_gap() -> float:
	if body == null or body.mode != TrafficCar.Mode.NEAR:
		return INF
	var here := body.global_position
	var forward := follower.direction()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var reach := clampf(speed * CONFLICT_TIME + car_length, CONFLICT_MIN_REACH, CONFLICT_MAX_REACH)
	var my_id := body.get_instance_id()
	var best := INF
	for other_object in ctx.cars_around(here.x, here.z):
		var other := other_object as TrafficCar
		if other == null or other == body:
			continue
		var wreck := other.mode == TrafficCar.Mode.WRECK
		if not wreck and other.get_instance_id() > my_id:
			continue
		if other.follower == null or absf(other.global_position.y - here.y) > CONFLICT_LEVEL:
			continue
		# the cars of the same lane see each other in the lane hash
		var same_lane := other.follower.lane == follower.lane and not follower.on_connector() \
				and not other.follower.on_connector()
		if not wreck and same_lane:
			continue
		var off := other.global_position - here
		var ahead := off.x * forward.x + off.z * forward.z
		var side := absf(off.x * right.x + off.z * right.z)
		var gap := ahead - 0.5 * (car_length + other.car_length)
		if gap > reach or ahead < 0.0:
			continue
		if side > 0.5 * (body.car_width + other.car_width) + CONFLICT_MARGIN:
			continue
		if gap < best:
			best = maxf(gap, 0.05)
			_found_speed = 0.0 if wreck else maxf(other.speed * other.follower.direction().dot(forward), 0.0)
	return best


## The gap to the car ahead in the lane the car is driving into.
##
## A car that is still on its lane looks into the lane it will continue into, a car that is on a
## connector looks into the lane it is merging into. The distance is measured along the whole
## way: the rest of the current lane, the connector through the junction box and the part of the
## next lane the leader is on.
func _next_lane_gap(lane: int) -> float:
	if follower.on_connector():
		return _merge_gap(follower.connector_target, follower.connector_entry)
	if follower.planned_next < 0:
		return INF
	var nxt := follower.planned_next
	var entry_offset := follower.planned_entry
	var index := ctx.hash.leader_index(nxt, entry_offset)
	if index < 0:
		return INF
	var distance := ctx.hash.distance_at(index) - entry_offset
	var path := (ctx.graph.lane_length(lane) - follower.s) + follower.planned_connector + distance
	_found_speed = _speed_of(ctx.hash.object_at(index) as VehicleBase)
	return path - car_length


## The gap of a car that drives through a junction into `target`.
##
## The car that is already on the target lane has the right of way: the merging car looks for
## the leader in the target lane, and if the target lane is occupied around the entry point it
## stops at the merge point and waits for a gap (a zipper, when both lanes queue).
func _merge_gap(target: int, entry: float) -> float:
	var gap := _gap_in(target, follower.index_s_target())
	var window := MERGE_WINDOW * car_length + speed * MERGE_BRAKE_TIME
	if not ctx.hash.any_in(target, entry - window, entry + window):
		return gap
	# The target lane is busy around the entry point: the car waits at the merge point.
	var to_merge := follower.connector_length - follower.connector_s
	return minf(gap, maxf(to_merge - car_length * 0.5, 0.0))


## The gap to the car ahead of `here` in `lane`.
func _gap_in(lane: int, here: float) -> float:
	var index := ctx.hash.leader_index(lane, here)
	if index < 0:
		return INF
	_found_speed = _speed_of(ctx.hash.object_at(index) as VehicleBase)
	return ctx.hash.distance_at(index) - here - car_length


## The speed of the leader along the lane. A traffic car reports the speed it drives with, so
## the tangent of the lane is not needed for it.
func _speed_of(leader: VehicleBase) -> float:
	if leader == null:
		return 0.0
	if leader is TrafficCar:
		return (leader as TrafficCar).speed
	return maxf(leader.linear_velocity.dot(follower.direction()), 0.0)


## The gap to the stop line at the end of the lane, when the light says the car has to stop.
##
## A car that is already inside the junction box (or past the stop line) does not see the light
## any more: the light is behind it, and a red light there would freeze the car in the box.
func _signal_gap(lane: int, speed: float) -> float:
	if follower.on_connector():
		return INF
	var to_end := ctx.graph.lane_length(lane) - follower.s
	if to_end < 0.0 or to_end > SIGNAL_LOOKAHEAD:
		return INF
	if not ctx.lane_has_signal(lane):
		return INF
	var junction := ctx.junction_of(lane)
	var lane_path := ctx.graph.lanes[lane]
	if lane_path == null:
		return INF
	var state := ctx.signal_state(junction, lane_path.road_id)
	if state == SIGNAL_GREEN:
		return INF
	if state == SIGNAL_AMBER and speed * speed / (2.0 * IDM.B_COMF) >= to_end:
		# The car cannot stop before the line any more, so it goes through.
		return INF
	return to_end - car_length * 0.5 - STOP_LINE_MARGIN

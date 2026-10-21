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

var ctx: DriveContext = null
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

class_name TrafficLaneChange
extends RefCounted
## The lane change of one traffic car (MOBIL-lite, dossier 6.1) and the reaction to a player
## that comes up fast from behind.
##
## Every two to four seconds the car looks at the lane next to it and changes when the gain in
## IDM acceleration is worth it (more than 0.3 m/s^2) and the car behind would not have to brake
## harder than 3 m/s^2. The gain is measured on the TARGET lane, at the point of the target
## lane that lies beside the car - the two lanes do not run for the same length, so the same
## number of metres along them is not the same place on the road.
##
## The indicator blinks one second before the move, and the move itself is the S-curve of the
## shared LaneFollower.

const LANE_CHANGE_MIN := 2.0     ## s: shortest gap between two lane-change attempts
const LANE_CHANGE_MAX := 4.0     ## s: longest gap
const INDICATOR_LEAD := 1.0      ## s: the indicator blinks this long before the move
const MERGE_CLEARANCE := 8.0     ## m: the target lane must be this clear next to the car
const GAP_MIN := 2.8             ## m: the narrowest gap between two lanes a car may cross
const GAP_MAX := 4.5             ## m: the widest gap between two lanes a car may cross
const MAX_LEVEL_DIFFERENCE := 0.3 ## m: the two lanes must be at the same height at the car
const MAX_HEADING_ANGLE := 0.262  ## rad (15 deg): the two lanes must point the same way
const PLAYER_REACT_RANGE := 40.0 ## m: the player counts as "approaching" inside this range
const PLAYER_REACT_CLOSING := 15.0 ## m/s: closing speed that makes traffic react
const REACT_MOVE_CHANCE := 0.20  ## a fifth of the cars move out of the way
const REACT_BRAKE_CHANCE := 0.10 ## a tenth of the cars brake instead
const REACT_BRAKE_ACCEL := -2.0  ## m/s^2: the extra brake of a startled driver
const STUCK_LIMIT := 2.5         ## m: the lane error that counts as "stuck"
const REACT_FORGET_DISTANCE := 70.0 ## m: the player is out of sight at this distance
const STUCK_TIME := 3.0          ## s: how long a blocked lane change is given before it is given up

## -1 = the indicator shows left, +1 = right, 0 = off.
var indicator_side: int = 0
## The length of the car, used for the gaps of the lane it wants to change into.
var car_length: float = 4.6
## The extra brake of a startled driver (m/s^2), 0 when the car does not react.
var reaction_brake: float = 0.0

var _timer: float = 0.0
var _pending_dir: int = 0
var _pending_gap: float = 0.0
var _pending_timer: float = 0.0
var _reaction: int = 0
var _reacting: bool = false
var _stuck_time: float = 0.0


## Starts the logic: the first attempt comes after two to four seconds.
func start(rng: RandomNumberGenerator) -> void:
	_timer = rng.randf_range(LANE_CHANGE_MIN, LANE_CHANGE_MAX)


## One step of the lane change logic.
##
## `speed` and `desired_speed` are the current and the wanted speed of the car, `car_length` its
## length and `position` where it is on the road.
func update(dt: float, ctx: DriveContext, follower: LaneFollower, speed: float,
		desired_speed: float, own_length: float, position: Vector3) -> void:
	car_length = own_length
	_react_to_player(ctx, follower, position, speed)
	if _pending_dir != 0:
		_pending_timer -= dt
		indicator_side = _pending_dir
		if _pending_timer <= 0.0:
			indicator_side = 0
			_start_change(ctx, follower, _pending_dir, _pending_gap)
			_pending_dir = 0
		return
	indicator_side = 0
	_timer -= dt
	if _timer <= 0.0 and not follower.is_changing():
		_timer = ctx.rng.randf_range(LANE_CHANGE_MIN, LANE_CHANGE_MAX)
		var current := _accel_in_lane(ctx, follower.lane, follower.s, speed, desired_speed,
				car_length)
		for dir: int in [-1, 1]:
			var target := _neighbour(ctx, follower, dir)
			if target < 0:
				continue
			var s_t := ctx.graph.aligned_offset(follower.lane, target, follower.s)
			if not _neighbour_ok(ctx, follower, target, s_t):
				continue
			if not _lane_clear(ctx, target, s_t, car_length):
				continue
			var candidate := _accel_in_lane(ctx, target, s_t, speed, desired_speed, car_length)
			var brake := _follower_brake(ctx, target, s_t, car_length, desired_speed, speed)
			if not IDM.should_change_lane(current, candidate, brake):
				continue
			_pending_dir = dir
			_pending_gap = _neighbour_gap(ctx, follower, dir)
			_pending_timer = INDICATOR_LEAD
			indicator_side = dir
			return
	# A driver that was startled by the player moves out of the way right away, not at the next
	# lane-change attempt.
	if _reaction == 1 and not follower.is_changing():
		_force_lane_change(ctx, follower, car_length)


## Gives up a lane change that does not work out: the car goes back to the lane it came from
## instead of standing diagonally across two lanes.
func check_stuck(dt: float, follower: LaneFollower, lane_error: float) -> void:
	if not follower.is_changing():
		_stuck_time = 0.0
		return
	if lane_error <= STUCK_LIMIT:
		_stuck_time = 0.0
		return
	_stuck_time += dt
	if _stuck_time > STUCK_TIME:
		follower.revert_lane()
		_stuck_time = 0.0


## How the car reacts to a player that comes up fast from behind: a fifth move out of the way,
## a tenth brake, the rest carry on.
func _react_to_player(ctx: DriveContext, follower: LaneFollower, position: Vector3,
		speed: float) -> void:
	var player := ctx.player
	if player == null or not is_instance_valid(player):
		return
	var delta := player.global_position - position
	var distance := delta.length()
	if distance > REACT_FORGET_DISTANCE:
		_reacting = false
		_reaction = 0
		reaction_brake = 0.0
		return
	var tangent := ctx.graph.tangent_at(follower.lane, follower.s)
	if _reacting:
		reaction_brake = REACT_BRAKE_ACCEL if _reaction == 2 else 0.0
		return
	var player_velocity := player.linear_velocity
	var closing := maxf(player_velocity.length(), player_velocity.dot(tangent)) - speed
	var ahead := delta.dot(tangent)
	if ahead < 0.0 and distance < PLAYER_REACT_RANGE and closing > PLAYER_REACT_CLOSING:
		_reacting = true
		var roll := ctx.rng.randf()
		if roll < REACT_MOVE_CHANCE:
			_reaction = 1
		elif roll < REACT_MOVE_CHANCE + REACT_BRAKE_CHANCE:
			_reaction = 2
		else:
			_reaction = 3
		reaction_brake = REACT_BRAKE_ACCEL if _reaction == 2 else 0.0


## The IDM acceleration the car would have in `lane` at `s_on_lane`.
func _accel_in_lane(ctx: DriveContext, lane: int, s_on_lane: float, speed: float,
		desired_speed: float, car_length: float) -> float:
	var gap := ctx.hash.leader_gap(lane, s_on_lane, car_length)
	var lead := ctx.hash.leader(lane, s_on_lane) as VehicleBase
	var leader_speed := ctx.speed_of(lead, ctx.graph.tangent_at(lane, s_on_lane))
	return IDM.acceleration(speed, desired_speed, gap, speed - leader_speed)


## How hard the car behind would have to brake if this car moved into its lane.
func _follower_brake(ctx: DriveContext, lane: int, s_on_lane: float, car_length: float,
		desired_speed: float, speed: float) -> float:
	var behind := ctx.hash.follower(lane, s_on_lane) as VehicleBase
	if behind == null:
		return 0.0
	var distance := ctx.hash.follower_distance(lane, s_on_lane)
	var behind_speed := ctx.speed_of(behind, ctx.graph.tangent_at(lane, s_on_lane))
	var gap := maxf(distance - car_length, 0.5)
	return IDM.required_brake(behind_speed, desired_speed, gap, behind_speed - speed)


## True when the lane next to the car is free enough to merge into.
func _lane_clear(ctx: DriveContext, lane: int, s_on_lane: float, car_length: float) -> bool:
	if ctx.hash.leader_gap(lane, s_on_lane, car_length) < MERGE_CLEARANCE:
		return false
	return ctx.hash.follower_distance(lane, s_on_lane) > MERGE_CLEARANCE


## True when the neighbour lane really is next to this one where the car is: the gap between the
## centres is a lane width, the two lanes are at the same height and they point the same way.
func _neighbour_ok(ctx: DriveContext, follower: LaneFollower, target: int, s_t: float) -> bool:
	var gap := ctx.graph.neighbour_gap(follower.lane, target, follower.s)
	if gap < GAP_MIN or gap > GAP_MAX:
		return false
	var here := ctx.graph.position_at(follower.lane, follower.s)
	var there := ctx.graph.position_at(target, s_t)
	if absf(there.y - here.y) > MAX_LEVEL_DIFFERENCE:
		return false
	var heading := ctx.graph.tangent_at(follower.lane, follower.s) \
			.angle_to(ctx.graph.tangent_at(target, s_t))
	return heading <= MAX_HEADING_ANGLE


## The lane to the left (-1) or to the right (+1) of the current one, -1 when there is none.
func _neighbour(ctx: DriveContext, follower: LaneFollower, dir: int) -> int:
	if dir < 0:
		return ctx.graph.left[follower.lane]
	return ctx.graph.right[follower.lane]


## The distance between the centres of the current lane and its neighbour, measured where the
## car is.
func _neighbour_gap(ctx: DriveContext, follower: LaneFollower, dir: int) -> float:
	var target := _neighbour(ctx, follower, dir)
	if target < 0:
		return 0.0
	return ctx.graph.neighbour_gap(follower.lane, target, follower.s)


## Moves out of the way of a fast approaching player.
func _force_lane_change(ctx: DriveContext, follower: LaneFollower, car_length: float) -> void:
	var best := 0
	var best_gap := 0.0
	for dir: int in [-1, 1]:
		var target := _neighbour(ctx, follower, dir)
		if target < 0:
			continue
		var s_t := ctx.graph.aligned_offset(follower.lane, target, follower.s)
		if not _neighbour_ok(ctx, follower, target, s_t):
			continue
		if not _lane_clear(ctx, target, s_t, car_length):
			continue
		var gap := _neighbour_gap(ctx, follower, dir)
		if gap > best_gap:
			best_gap = gap
			best = dir
	if best == 0:
		return
	_pending_dir = best
	_pending_gap = best_gap
	_pending_timer = INDICATOR_LEAD
	indicator_side = best


## Performs the lane change: the car moves to the neighbouring lane and drives the S-curve.
##
## The car takes the place on the new lane that lies beside it, so the car does not jump
## forward or back when the change starts. The target lane is looked at again: while the
## indicator was on, another car may have moved into it, and a car that changes into an
## occupied lane ends up side by side with it.
func _start_change(ctx: DriveContext, follower: LaneFollower, dir: int, gap: float) -> void:
	var target := _neighbour(ctx, follower, dir)
	if target < 0:
		return
	var s_t := ctx.graph.aligned_offset(follower.lane, target, follower.s)
	if not _neighbour_ok(ctx, follower, target, s_t):
		return
	if not _lane_clear(ctx, target, s_t, car_length):
		# The lane is not free any more: the car stays where it is and tries again later.
		_timer = ctx.rng.randf_range(LANE_CHANGE_MIN, LANE_CHANGE_MAX)
		return
	follower.s = s_t
	follower.start_change(dir, gap, target)

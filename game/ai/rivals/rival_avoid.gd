class_name RivalAvoid
extends RefCounted
## The obstacles around a rival: the traffic, the other rivals and the player. It holds the
## sideways shift that keeps the rival out of the way and the pass that overtakes a slower car
## (dossier 6.2: the target moves to the side, in the frame of the racing line).
##
## The cars of the field are ordered by the distance they have covered on the racing line: a
## car that is ahead on the line is ahead of the other one. The order cannot be cyclic, so a
## pack of cars that stands still cannot lock each other up (the deadlock of round 3, where
## two cars each saw the other as the car in front and the field never started).
##
## The traffic of the city does not drive on the racing line: it is measured in the frame of
## the tangent of the rival.

const AVOID_DISTANCE := 40.0     ## m: a car this far ahead is avoided
const FOLLOW_DISTANCE := 80.0    ## m: the distance at which a rival starts to follow
const AVOID_BAND := 2.2          ## m: the half width of the band the rival drives in
const AVOID_SHIFT := 2.0         ## m: the sideways shift of the avoidance (dossier 6.2)
const AVOID_CLEARANCE := 2.5     ## m: the space two cars need next to each other
const RIVAL_AVOID_DISTANCE := 15.0  ## m: the rivals this far ahead are kept clear of
const PASS_MIN_GAP := 20.0      ## m: a pass only starts when the car ahead is this far away
const PASS_DISTANCE := 60.0      ## m: a car this far ahead can be passed
const PASS_SHIFT := 6.0           ## m: the distance between the centres of two passing cars
const PASS_LANE := 9.0           ## m: the distance between the two lanes of the field
const PASS_CLOSING := 1.5        ## m/s: the rival must be this much faster to pass
const PASS_HOLD := 8.0           ## m: the pass holds until the car is this far behind
const PASS_MERGE := 1.2          ## s: the time the rival needs to change the lane
const PASS_RATE := 3.5           ## m/s: the speed of the sideways move
const PASS_SIDE_BAND := 8.0        ## m: the cars this close limit the spot of a pass
const PASS_ERROR := 0.6           ## m: the room the cars need for their line error
const PASS_ACTIVE := 0.05        ## m: the shift above which a pass counts as under way
const AVOID_LEVEL_BAND := 6.0    ## m: the cars this close beside the rival are avoided too
const PLAYER_BAND := 4.5          ## m: the width of the band the player is seen in
const PASS_CORNER_MARGIN := 3.0  ## m/s: the rival may not pass when it has to slow down
const PASS_MAX_TIME := 10.0      ## s: the longest a pass may take
const CORNER_LOOKAHEAD := 40.0   ## m: no pass when a slow corner is this close
const CORNER_SPEED_LIMIT := 30.0 ## m/s: the corner speed below which a pass is refused
const STATIONARY_SPEED := 2.0    ## m/s: a car below this counts as stopped
const DEADLOCK_SPEED := 4.0      ## m/s: the speed below which a car counts as stuck
const DEADLOCK_TIME := 3.0       ## s: the time a pack may stand still before it breaks up
const CAR_WIDTH := 1.95          ## m: the width of a car (the gap between two of them)
const TYRE_LIMIT := 14.2          ## m/s^2: the lateral grip of the Roadster's tyres
const MIN_AHEAD := 1.0           ## m: a car closer than this is not in front

## The sideways shift of the pass (m).
var pass_shift: float = 0.0
## False while the rivals keep the column of their grid slot (the first metres of a race).
var pass_enabled: bool = true
## The car the rival is passing (null when it keeps its line).
var pass_node: Node3D = null
## The car in front of the rival (null when the way is clear).
var block_node: Node3D = null
## The speed of the car in front of the rival (INF when the way is clear).
var block_speed: float = INF
## The distance to the car in front of the rival (INF when the way is clear).
var block_distance: float = INF
## The speed of the car the rival is passing (INF when it passes nobody).
var pass_speed: float = INF
## The distance to the car the rival is passing (INF when it passes nobody).
var pass_distance: float = INF
## The car the rival has to drive around (a car that stands still in its way).
var round_node: Node3D = null
## True when the rival has to brake hard (it gave a pass up in front of a car).
var emergency: bool = false

var _pass_side: float = 0.0
var _pass_target: float = 0.0
var _pass_time: float = 0.0
var _stopped_time: float = 0.0


## The sideways shift the rival aims for: the car in front is avoided or passed.
##
## The pass and the avoidance have their own clamps: the pass needs 4.45 m between the
## centres of the two cars (a car is 1.95 m wide and it needs 2.5 m of clearance), and the
## old shared clamp of 2 m left 5 cm between two cars that ran side by side.
func update(delta: float, car: ArcadeCar, ctx: RivalContext, offset: float, speed: float,
		line: RivalLine, lane_offset: float, potential: float, road: Vector3) -> float:
	var pass_offset := _pass_shift(delta, car, ctx, offset, speed, line, lane_offset,
		potential, road)
	if absf(pass_offset) > PASS_ACTIVE:
		# The pass decides where the car goes: the avoidance would fight it.
		return pass_offset
	return clampf(_avoid_offset(car, ctx, offset, line, lane_offset), -AVOID_SHIFT, AVOID_SHIFT)


## The speed of the car in front of the rival and the distance to it.
##
## The cars of the field are ordered by the distance they have covered on the racing line, so
## the relation "in front of" cannot be cyclic.
func update_blocker(car: ArcadeCar, ctx: RivalContext, offset: float, line: RivalLine,
		lane_offset: float, speed: float, delta: float) -> void:
	block_node = null
	block_speed = INF
	block_distance = INF
	pass_speed = INF
	pass_distance = INF
	for node in ctx.near_of(car):
		if not is_instance_valid(node):
			continue
		if node == pass_node and pass_shift >= AVOID_CLEARANCE:
			# The car that is being passed does not set the pace: the rival is already
			# moving over to its side. A rival that has not yet cleared the car keeps
			# following it: a car that accelerates before it is beside the car it
			# passes drives into the back of it.
			var passed := node as VehicleBase
			pass_speed = passed.linear_velocity.length() if passed != null else INF
			pass_distance = _relation(node, car, ctx, line, offset, lane_offset).x
			continue
		_consider(node, car, ctx, line, offset, lane_offset)
	if is_instance_valid(ctx.player):
		_consider(ctx.player, car, ctx, line, offset, lane_offset)
	_update_deadlock(delta, car, ctx, speed)


## Remembers the nearest car in front of the rival.
##
## The band is the lane the rival drives right now: a car that is in the lane the rival
## moves into is the car it has to keep its distance to, and the car it passes (in the lane
## it comes from) is not.
func _consider(node: Node3D, car: ArcadeCar, ctx: RivalContext, line: RivalLine,
		offset: float, lane_offset: float) -> void:
	var vehicle := node as VehicleBase
	if vehicle == null:
		return
	# Only the cars on the level of the rival are in its way: a car on the street under the
	# deck the rival drives on is not a car in front of it.
	if not RivalContext.on_my_level(car, node):
		return
	var rel := _relation(node, car, ctx, line, offset, lane_offset)
	if rel.x < MIN_AHEAD:
		return
	var reach := FOLLOW_DISTANCE if _on_line(node, ctx) else AVOID_DISTANCE
	if rel.x > reach:
		return
	# The player may be anywhere on the road: it is a car of the race and it is not on
	# the racing line, so the band around it is wider.
	var band := PLAYER_BAND if node == ctx.player else AVOID_BAND
	# The band follows the lane the rival drives and the lane it moves into: a car in
	# the lane of the pass is a car it has to keep its distance to from the start.
	if absf(rel.y - pass_shift) > band and absf(rel.y - _pass_target) > band:
		return
	if rel.x >= block_distance:
		return
	block_node = node
	block_distance = rel.x
	block_speed = vehicle.linear_velocity.length()


## The relation of another car to the rival: x = how far ahead it is (m), y = how far to the
## side it stands (m, positive = to the right of the rival's own line).
func _relation(node: Node3D, car: ArcadeCar, ctx: RivalContext, line: RivalLine,
		offset: float, lane_offset: float) -> Vector2:
	if _on_line(node, ctx):
		var other_offset := _offset_of(node, ctx)
		var other_right := line.right_at(other_offset)
		var other_lateral := (node.global_position - line.point_at(other_offset)).dot(other_right)
		return Vector2(_forward(offset, other_offset, line), other_lateral - lane_offset)
	var rel := node.global_position - car.global_position
	var tangent := line.tangent_at(offset)
	var right := line.right_at(offset)
	return Vector2(rel.dot(tangent), rel.dot(right))


## The forward distance from one offset of the line to the other (m).
##
## The distance is measured on the closed line and not on the distance the cars have
## covered: a car that stands still (a player that never moves) is at its place on the
## line in every lap, and the field has to see it.
func _forward(from: float, to: float, line: RivalLine) -> float:
	if line.closed and line.length > 1.0:
		return fposmod(to - from, line.length)
	return to - from


## True when the node drives on the racing line (a rival or the player).
func _on_line(node: Node3D, ctx: RivalContext) -> bool:
	return node is RivalCar or node == ctx.player


## The offset of a node on the racing line (m).
func _offset_of(node: Node3D, ctx: RivalContext) -> float:
	if node is RivalCar:
		var rival := node as RivalCar
		if rival.brain != null:
			return rival.brain.offset
		return 0.0
	return ctx.player_offset


## The deadlock breaker: a pack that stands still has to break up.
##
## When the car in front of the rival stands still and the rival stands still with it, the
## rival goes around it. A car that stands still in the way of the field (a player that
## parked on the track) is never allowed to hold the race up.
func _update_deadlock(delta: float, car: ArcadeCar, ctx: RivalContext, speed: float) -> void:
	round_node = null
	if block_node == null:
		_stopped_time = 0.0
		return
	var stopped := block_speed < DEADLOCK_SPEED
	if not stopped:
		_stopped_time = 0.0
		return
	if block_node == ctx.player:
		# A player that stands still is driven around at once: it may stay there for the
		# whole race, and the field may not wait for it.
		round_node = block_node
		block_distance = INF
		block_speed = INF
		return
	if speed >= DEADLOCK_SPEED:
		_stopped_time = 0.0
		return
	_stopped_time += delta
	if _stopped_time < DEADLOCK_TIME:
		return
	# The rival stands still: it drives around the car in front, whatever that car does.
	# A player that never moves must not hold the field up.
	round_node = block_node
	block_distance = INF
	block_speed = INF


## The sideways shift that avoids the car in front (0 when the way is clear).
##
## The traffic and the other rivals count: on a route with sharp corners the cars of a column
## drift into each other, and the one that has the room moves.
func _avoid_offset(car: ArcadeCar, ctx: RivalContext, offset: float, line: RivalLine,
		lane_offset: float) -> float:
	var left_block := INF
	var right_block := INF
	for node in ctx.near_of(car):
		if not is_instance_valid(node):
			continue
		# Only the cars on the level of the rival take its space: a car on the street under
		# the deck it drives on does not make it swerve.
		if not RivalContext.on_my_level(car, node):
			continue
		var rel := node.global_position - car.global_position
		# The cheap test first: the square of the distance rejects most of the cars.
		if rel.length_squared() > RIVAL_AVOID_DISTANCE * RIVAL_AVOID_DISTANCE:
			continue
		var ahead := rel.dot(line.tangent_at(offset))
		# The cars that stand beside the rival are avoided as well: two cars that drive
		# side by side need the room between them.
		if ahead < -AVOID_LEVEL_BAND:
			continue
		# The rivals keep their distance to each other, the traffic is avoided further away.
		var reach := RIVAL_AVOID_DISTANCE if node is RivalCar else AVOID_DISTANCE
		if ahead > reach:
			continue
		# The real distance between the two cars: a car that is off its own line still
		# takes the space it stands on.
		var side := rel.dot(line.right_at(offset))
		if absf(side) < 0.5:
			# The car is in the same column: it does not take the side away.
			continue
		if absf(side) > AVOID_BAND:
			continue
		if side > 0.0:
			right_block = minf(right_block, side)
		else:
			left_block = minf(left_block, -side)
	var free_right := right_block - AVOID_CLEARANCE
	var free_left := left_block - AVOID_CLEARANCE
	if free_right == INF and free_left == INF:
		return 0.0
	if free_right == INF:
		# The left is blocked: the rival moves to the right.
		return clampf(free_left, 0.0, AVOID_SHIFT)
	if free_left == INF:
		# The right is blocked: the rival moves to the left.
		return -clampf(free_right, 0.0, AVOID_SHIFT)
	if free_right >= free_left:
		return clampf(free_right, 0.0, AVOID_SHIFT)
	return -clampf(free_left, 0.0, AVOID_SHIFT)


## The sideways shift of a pass (0 when the rival keeps its line).
func _pass_shift(delta: float, car: ArcadeCar, ctx: RivalContext, offset: float, speed: float,
		line: RivalLine, lane_offset: float, potential: float, road: Vector3) -> float:
	if not pass_enabled:
		pass_node = null
		pass_shift = 0.0
		return 0.0
	var blocker := _pass_blocker(car, ctx, offset, speed, line, potential)
	if blocker == null and pass_node != null and is_instance_valid(pass_node):
		# The pass is over when the car that was passed is behind.
		var behind := _distance_behind(car, pass_node, offset, line)
		if behind > PASS_HOLD or behind < -PASS_DISTANCE:
			# The car that was passed is behind the rival, or it has pulled away again.
			# A pass of a car 160 m ahead is not a pass: it is a lane change that never
			# ends, and two rivals that never end their lane change meet in the middle
			# of the road.
			pass_node = null
			_pass_side = 0.0
			_pass_target = 0.0
		elif _pass_time > PASS_MAX_TIME:
			# The rival is slower and never gets past: it gives the pass up, or it would
			# drive 6 m off its lane for the rest of the race. It brakes at once: the car
			# it was passing is right in front of it.
			pass_node = null
			_pass_side = 0.0
			_pass_target = 0.0
			emergency = true
	elif blocker == null and round_node != null and is_instance_valid(round_node):
		# The car in the way stands still: the rival goes around it, whatever the gap.
		blocker = round_node
	if blocker != null:
		if blocker != pass_node:
			pass_node = blocker
			_pass_time = 0.0
			_pass_side = _pass_side_of(car, ctx, blocker, offset, line, lane_offset, road)
		_pass_target = _pass_target_of(car, ctx, blocker, offset, line, lane_offset, road)
		if _pass_target == 0.0 and absf(pass_shift) >= AVOID_CLEARANCE:
			# The lane the rival moves into is not free any more. It keeps the lane it
			# is in until the car it passes is behind it: merging back into a lane with
			# a car in it is a side swipe.
			_pass_target = pass_shift
	elif pass_node != null and not is_instance_valid(pass_node):
		pass_node = null
		_pass_side = 0.0
		_pass_target = 0.0
	elif pass_node != null:
		# The pass holds until the car is behind.
		if _distance_behind(car, pass_node, offset, line) > PASS_HOLD:
			pass_node = null
			_pass_side = 0.0
			_pass_target = 0.0
		else:
			var target := _pass_target_of(car, ctx, pass_node, offset, line, lane_offset,
				road)
			if target != 0.0:
				_pass_target = target
	else:
		_pass_target = 0.0
	_pass_time += delta
	# The sideways move of a pass: 3.5 m/s, so the 4.5 m of a lane change takes the
	# 1.2 s of PASS_MERGE. A quicker move puts the car into the lane of the car it
	# passes before it is clear of it.
	var rate := PASS_RATE
	if pass_shift < _pass_target:
		pass_shift = minf(_pass_target, pass_shift + rate * delta)
	else:
		pass_shift = maxf(_pass_target, pass_shift - rate * delta)
	return pass_shift


## The car the rival wants to pass: a slower car ahead in its band.
##
## The rival starts a pass with the speed it could drive if the way were clear (its corner
## limit and its top speed), not with the speed the car in front lets it drive: the model of
## the car following holds a follower at the speed of the leader, and a pass would never
## start.
func _pass_blocker(car: ArcadeCar, ctx: RivalContext, offset: float, speed: float,
		line: RivalLine, potential: float) -> Node3D:
	# No pass when the rival has to slow down for the corner ahead: it would be at the
	# side of the road in the middle of the corner.
	#
	# The measure is the corner speed of the line and not the target of the rival: the
	# target of a car on a straight is its top speed, and the top speed is never more
	# than the speed of the car plus the margin. With the target as the measure no
	# rival ever passed: the field ran as a train for the whole race.
	var corner := line.corner_speed(offset + CORNER_LOOKAHEAD, TYRE_LIMIT)
	if corner < speed + PASS_CORNER_MARGIN:
		return null
	# No pass into a slow corner.
	if corner < CORNER_SPEED_LIMIT:
		return null
	var best: Node3D = null
	var best_distance := INF
	for node in ctx.rivals:
		if not is_instance_valid(node) or node == car:
			continue
		# A car that changes the lane itself is not passed: two cars that change the lane
		# at the same time meet in the middle of the road.
		var other := node as RivalCar
		if other != null and other.brain != null and other.brain.avoid.pass_node == car:
			# The car is passing me: two cars that change the lane at the same time meet
			# in the middle of the road.
			continue
		if _is_slower_ahead(node, car, ctx, offset, line, potential, best_distance):
			best = node
			best_distance = node.global_position.distance_to(car.global_position)
	if is_instance_valid(ctx.player):
		if _is_slower_ahead(ctx.player, car, ctx, offset, line, potential, best_distance):
			best = ctx.player
	return best


## True when the node is a slower car in the band ahead of the rival.
##
## A car that has stopped counts as slower: a pack that stands still would never start
## again, and the pass is what gets the rival out of the way.
func _is_slower_ahead(node: VehicleBase, car: ArcadeCar, ctx: RivalContext, offset: float,
		line: RivalLine, potential: float, best_distance: float) -> bool:
	var rel := node.global_position - car.global_position
	var ahead := rel.dot(line.tangent_at(offset))
	if ahead < PASS_MIN_GAP or ahead > PASS_DISTANCE or ahead > best_distance:
		return false
	# The car has to be in the lane of the rival: a car in the other lane is not in the way.
	var side := _ribbon_lateral(node, ctx, line, offset) - _lane_of(car, ctx, line, offset)
	if absf(side) > AVOID_BAND:
		return false
	var other := node.linear_velocity.length()
	if other < STATIONARY_SPEED:
		return true
	return potential > other + PASS_CLOSING


## The lateral distance of a car from the racing line (m, positive = to the right).
##
## The distance is measured in the frame of the line at the place of the car, so the cars
## that drive on a curve are compared on the same ribbon.
func _ribbon_lateral(node: Node3D, ctx: RivalContext, line: RivalLine,
		offset: float) -> float:
	if _on_line(node, ctx):
		var other_offset := _offset_of(node, ctx)
		var right := line.right_at(other_offset)
		return (node.global_position - line.point_at(other_offset)).dot(right)
	var right := line.right_at(offset)
	return (node.global_position - line.point_at(offset)).dot(right)


## The cars the rival has to keep clear of (the rivals, the traffic and the player).
func _others(car: ArcadeCar, ctx: RivalContext) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in ctx.near_of(car):
		out.append(node)
	if is_instance_valid(ctx.player):
		out.append(ctx.player)
	return out


## The lane a car drives on (m from the racing line).
##
## The lane of a rival is the line it drives, the lane of the player is where it stands.
func _lane_of(node: Node3D, ctx: RivalContext, line: RivalLine, offset: float) -> float:
	if node is RivalCar:
		var rival := node as RivalCar
		if rival.brain != null:
			return rival.brain.lane_offset
		return 0.0
	return _ribbon_lateral(node, ctx, line, offset)


## The lane a pass drives into (m from the racing line).
##
## The field drives in two lanes that are 9 m apart, on the two sides of the middle of the
## road: a pass goes to the middle of the road, where the car of the rival has the clearance
## of both lanes. A pass that drove into the lane of the car in front would be a side
## swipe, and a pass that stayed in its own lane would be a rear-end.
func _pass_lane(road: Vector3) -> float:
	return road.z


## The side of the pass (-1 = to the left, 1 = to the right, 0 = no clean pass is possible).
func _pass_side_of(car: ArcadeCar, ctx: RivalContext, blocker: Node3D, offset: float,
		line: RivalLine, lane_offset: float, road: Vector3) -> float:
	var mine := _lane_of(car, ctx, line, offset)
	var target := _pass_lane(road)
	if not _pass_fits(car, ctx, blocker, offset, line, road, target):
		return 0.0
	return signf(target - mine)


## The shift the pass aims for (m).
##
## The spot is checked every tick: a car that comes into the lane the rival changes into
## ends the pass, or the rival drives into it.
func _pass_target_of(car: ArcadeCar, ctx: RivalContext, blocker: Node3D, offset: float,
		line: RivalLine, lane_offset: float, road: Vector3) -> float:
	if _pass_side == 0.0:
		return 0.0
	var mine := _lane_of(car, ctx, line, offset)
	var target := _pass_lane(road)
	if not _pass_fits(car, ctx, blocker, offset, line, road, target):
		return 0.0
	return clampf(target - lane_offset, -PASS_SHIFT, PASS_SHIFT)


## True when the lateral position is free for a pass.
##
## The spot has to be on the road and it has to keep the clearance of a car body to every
## car that drives near it: a pass that ends in a side swipe is no pass at all.
func _pass_fits(car: ArcadeCar, ctx: RivalContext, blocker: Node3D, offset: float,
		line: RivalLine, road: Vector3, target: float) -> bool:
	if target < road.x or target > road.y:
		return false
	for node in _others(car, ctx):
		if node == blocker or not is_instance_valid(node):
			continue
		var rel := _relation(node, car, ctx, line, offset, 0.0)
		# The lane change sweeps over the cars beside the rival and the ones right
		# behind it. The cars ahead count as well: the rival catches them while it
		# passes, and a pass into a lane with a car in it ends in a side swipe.
		if rel.x < -PASS_SIDE_BAND or rel.x > PASS_DISTANCE:
			continue
		# A car that is changing lanes is heading for its own target: the lane it
		# goes to is the one the pass may not use.
		var lateral := _aim_lateral(node, ctx, line, offset)
		if absf(target - lateral) < CAR_WIDTH + PASS_ERROR:
			return false
	return true


## The lateral position a car is heading for (m from the racing line).
##
## A car that is changing lanes drives for its own target: the pass may not use the
## lane the car is going to, or the two cars meet in the middle of the road.
func _aim_lateral(node: Node3D, ctx: RivalContext, line: RivalLine, offset: float) -> float:
	var lane := _lane_of(node, ctx, line, offset)
	var rival := node as RivalCar
	if rival != null and rival.brain != null:
		lane += rival.brain.avoid.pass_shift
	return lane


## How far the passed car is behind the rival (0 when it is still ahead).
func _distance_behind(car: ArcadeCar, node: Node3D, offset: float, line: RivalLine) -> float:
	if not is_instance_valid(node):
		return PASS_HOLD
	var tangent := line.tangent_at(offset)
	return (car.global_position - node.global_position).dot(tangent)



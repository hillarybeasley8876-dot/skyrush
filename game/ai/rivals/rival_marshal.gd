class_name RivalMarshal
extends RefCounted
## The race control of a rival: the watchdog and the rescue.
##
## The marshal picks a car up when it does not get anywhere, when it drives off its line, when
## it goes faster than its car can or when it leaves the road. The car is put back on the road
## of the world, on its own line, and never behind a gate it has already passed.

const WATCHDOG_TIME := 4.0      ## s: the window the travel of a rival is measured over
const WATCHDOG_TRAVEL := 15.0   ## m: a rival that covers less than this in the window is stuck
const WATCHDOG_OFF_LINE := 2.0  ## s: the time a rival may be off its line before the rescue
const WATCHDOG_SPEED := 1.05    ## the share of the hard cap a rival may not pass
const OVER_CAP_TIME := 2.0      ## s: the time a car may be above its cap before the rescue
const OFF_LINE_HEIGHT := 4.0    ## m: the car is off the road when it is this far from the line
const OFF_LINE_CROSS := 6.0     ## m: the cross-track error that counts as off the road
const OFF_LINE := 15.0          ## m: the rival is off its line when it is this far from it
const QUEUE_DISTANCE := 14.0    ## m: a rival this close to the car in front is in a queue
const QUEUE_SPEED := 3.0        ## m/s: the car in front has to move for the queue to hold
const QUEUE_HOLD := 8.0         ## s: the longest a rival may wait in a queue
const ROAD_RESCUE_TIME := 25.0  ## s: the time a rival may drive on the road before the rescue
const RESCUE_LOOKAHEAD := 6.0   ## m: the rescue puts the car this far ahead on the line
const RESCUE_ROAD_LIMIT := 6.0  ## m: the road the car is put on may not be further away
const RESCUE_SPEED := 8.0       ## m/s: the speed the rescued car gets
const RESCUE_CLEARANCE := 8.0   ## m: the rescue spot must be this far from every car
const RESCUE_STEP := 10.0       ## m: the step along the line when the spot is taken

## The number of times the marshal had to rescue the rival.
var rescues: int = 0

var _watch_start: float = 0.0
var _watch_time: float = 0.0
var _off_line_time: float = 0.0
var _queue_time: float = 0.0
var _over_cap_time: float = 0.0


## The watchdog: true when the car was rescued (the caller stops the tick).
func check(brain: RivalBrain, delta: float, car: ArcadeCar, ctx: RivalContext) -> bool:
	var cross := absf(brain.cross_track(car))
	# 1: the car does not get anywhere.
	_watch_time += delta
	if _watch_time >= WATCHDOG_TIME:
		# A car that waits in a queue behind another one does not get anywhere: that is
		# racing, not a car that is stuck. The exemption only holds while the car in
		# front moves, and for eight seconds at most: a pack that stands still has to
		# break up (the gridlock of round 3).
		var queued := _in_queue(brain, delta)
		if not queued and brain.distance - _watch_start < WATCHDOG_TRAVEL:
			rescue(brain, car, ctx, "stuck")
			return true
		_watch_time = 0.0
		_watch_start = brain.distance
	# 2: the car is off its line for too long (at any speed).
	if cross > OFF_LINE:
		_off_line_time += delta
		var off_limit := ROAD_RESCUE_TIME if brain.road.on_road else WATCHDOG_OFF_LINE
		if _off_line_time > off_limit:
			rescue(brain, car, ctx, "off the line")
			return true
	else:
		_off_line_time = 0.0
	# 3: the car drives faster than the hard cap of its own car: it is falling.
	# A car that comes back under its cap is not picked up: the nitro of a car ends and
	# the cap pull of the car brings it back under its cap within a second.
	var limit := _hard_cap(car) * WATCHDOG_SPEED
	if brain.speed > limit:
		_over_cap_time += delta
		if _over_cap_time > OVER_CAP_TIME:
			rescue(brain, car, ctx, "too fast")
			return true
	else:
		_over_cap_time = 0.0
	# 4: the car is off the road: it is high above its line and far away from it.
	var here := brain.line.point_at(brain.offset)
	if absf(car.global_position.y - here.y) > OFF_LINE_HEIGHT and cross > OFF_LINE_CROSS:
		rescue(brain, car, ctx, "off the road")
		return true
	return false


## True when the rival waits in a queue behind the car in front.
##
## The exemption holds while the car in front moves (at least 3 m/s) and for eight seconds
## at most. After that the watchdog picks the car up.
func _in_queue(brain: RivalBrain, delta: float) -> bool:
	var close := brain.avoid.block_distance < QUEUE_DISTANCE
	# A rival that drives around a car that stands still is not stuck.
	if brain.avoid.round_node != null:
		return true
	var moving := brain.avoid.block_speed >= QUEUE_SPEED
	if close and moving:
		_queue_time += delta
	else:
		_queue_time = 0.0
	return close and moving and _queue_time <= QUEUE_HOLD


## The highest speed the car of this rival may drive (its own top speed).
##
## The nitro counts: a car that burns its N2 may drive as fast as its boost cap allows,
## and the marshal may not pick it up for that.
func _hard_cap(car: ArcadeCar) -> float:
	if car.spec == null:
		return INF
	return maxf(car.spec.top_speed, car.boost.speed_cap)


## Puts the rival back on the road, on its own line.
func rescue(brain: RivalBrain, car: ArcadeCar, ctx: RivalContext, reason: String) -> void:
	rescues += 1
	push_warning("[rivals] %s was rescued (%s): v=%.1f blk=%.1f@%.1f round=%s road=%s travel=%.1f" % [
		brain.car_name, reason, brain.speed, brain.avoid.block_distance,
		brain.avoid.block_speed, str(brain.avoid.round_node != null),
		str(brain.road.on_road), brain.distance - _watch_start])
	var spot := _rescue_offset(brain, ctx)
	var right := brain.line.right_at(spot)
	var point := brain.line.point_at(spot) + right * brain.lane_offset
	var xform := _rescue_transform(brain, point, spot)
	car.reset_to(xform)
	car.linear_velocity = -xform.basis.z * RESCUE_SPEED
	# The car is back on the road: it starts from its line again, a little behind the
	# place where it was picked up.
	brain.travelled -= brain.offset - spot
	brain.offset = spot
	brain.road.on_road = false
	brain.road.follower = null
	_watch_start = brain.distance
	_watch_time = 0.0
	_off_line_time = 0.0
	_over_cap_time = 0.0


## The spot the rescued car is put on: the road of the world at the point of the line.
##
## The car is not dropped 0.35 m above its line: it stands on the tarmac, and it keeps the
## direction of the line (the road it is put on may run the other way).
func _rescue_transform(brain: RivalBrain, point: Vector3, spot: float) -> Transform3D:
	var world := Game.world
	var position := point
	if world != null and Game.world_built():
		var road := RivalGrid.ground_spot(world.nearest_road_transform(point), world)
		if road.origin.distance_to(point) <= RESCUE_ROAD_LIMIT:
			position = road.origin
		else:
			# The nearest road is not the road of the line: the car keeps its place on the
			# line and only takes the height of the ground under it.
			position = RivalGrid.ground_spot(Transform3D(Basis.IDENTITY, point), world).origin
	var basis := Basis.looking_at(brain.line.tangent_at(spot), Vector3.UP)
	return Transform3D(basis, position)


## The offset of the line the rival is put back on: free of cars and between its gates.
func _rescue_offset(brain: RivalBrain, ctx: RivalContext) -> float:
	var best := brain.offset
	for step in 8:
		var candidate := brain.offset - float(step) * RESCUE_STEP
		if _spot_is_free(brain, candidate, ctx) and _before_gate(brain, candidate) \
				and _after_last_gate(brain, candidate):
			return candidate
	return best


## True when the spot on the line is far enough from every car.
func _spot_is_free(brain: RivalBrain, spot: float, ctx: RivalContext) -> bool:
	var point := brain.line.point_at(spot)
	for node in ctx.rivals:
		if not is_instance_valid(node):
			continue
		if node.global_position.distance_to(point) < RESCUE_CLEARANCE:
			return false
	for node in ctx.traffic:
		if not is_instance_valid(node):
			continue
		if node.global_position.distance_to(point) < RESCUE_CLEARANCE:
			return false
	return true


## True when the spot is before the gate the rival has to pass next.
func _before_gate(brain: RivalBrain, spot: float) -> bool:
	if brain.next_gate < 0 or brain.next_gate >= brain.gate_offsets.size():
		return true
	var gate := brain.gate_offsets[brain.next_gate]
	if brain.line.closed:
		var here := fposmod(spot, brain.line.length)
		var there := fposmod(gate, brain.line.length)
		return here <= there
	return spot <= gate


## True when the spot is between the gate the rival has passed last and the next one.
##
## A car that is put back behind the gate it has just passed drives over that gate again: on
## a circuit that counts an extra lap.
func _after_last_gate(brain: RivalBrain, spot: float) -> bool:
	if brain.next_gate < 0 or brain.next_gate >= brain.gate_offsets.size():
		return true
	var last := brain.next_gate - 1
	if last < 0:
		last = brain.gate_offsets.size() - 1
	var gate := brain.gate_offsets[last]
	if brain.line.closed:
		var span := fposmod(brain.gate_offsets[brain.next_gate] - gate, brain.line.length)
		var here := fposmod(spot - gate, brain.line.length)
		return here <= span
	return spot >= gate

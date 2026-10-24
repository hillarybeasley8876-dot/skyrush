class_name RivalRoad
extends RefCounted
## The road mode of a rival: when it loses its racing line it drives on the road of the
## world until it finds the line again.
##
## The racing line of a city route is a walk through the lanes: a car that is pushed off it
## would drive into the next block if it kept aiming at the line. On the road it follows the
## lane network of the world (the same lane graph the traffic drives on) and rejoins the line
## as soon as it is close to it again.

const OFF_LINE := 15.0       ## m: the rival is off its line when it is this far from it
const ROAD_MARGIN := 1.25     ## m: the room the car keeps to the edge of the road
const LANE_NEAR := 25.0      ## m: only the lanes this close to the line count for the road
const LOOKAHEAD_BASE := 18.0  ## m: the look-ahead at a standstill
const LOOKAHEAD_PER_SPEED := 1.25  ## m per m/s
const LOOKAHEAD_MIN := 10.0
const LOOKAHEAD_MAX := 120.0
const STEER_KP := 2.2         ## the PD gain on the heading error
const STEER_KD := 0.25        ## the PD damping on the yaw rate
const STEER_LIMIT := 0.8      ## the AI never asks for more than this much lock
const STANLEY_K := 1.0        ## the cross-track gain (the lane centre)
const STANLEY_LIMIT := 0.4    ## rad
const CROSS_TRACK_MIN_SPEED := 5.0  ## m/s
const ROAD_SPEED := 0.75      ## the share of the limit of the lane the rival drives on
const DEFAULT_ROAD_HALF := 6.0  ## m: the half width of a road when the graph does not know it

## The lane graph of the world (null when the world has no lanes).
var graph: LaneGraph = null
## The lane state of the rival while it drives on the road.
var follower: LaneFollower = null
## True while the rival drives on the road instead of on its racing line.
var on_road: bool = false

var _rng := RandomNumberGenerator.new()


## Drives the rival on the road. Returns true when it drives on the road.
func update(brain: RivalBrain, delta: float, car: ArcadeCar) -> bool:
	if graph == null:
		return false
	var cross := absf(brain.cross_track(car))
	if cross > OFF_LINE:
		if not on_road:
			_enter_road(car, brain.line, brain.offset)
		if on_road:
			_advance(delta, car)
			return true
		return false
	if on_road:
		# The car is back near its line: it drives the line again.
		on_road = false
		follower = null
	return false


## Puts the rival on the lane of the world that is nearest to it.
##
## The road is two way: the lane of the oncoming traffic is often the lane that is nearest
## to the car, and a rival that drives the oncoming lane drives the wrong way. Its
## progress on the racing line goes backwards, it never finds the line again and it is
## the marshal that has to put it back on the track. The lane of the rival is the lane
## that drives the way of the race.
func _enter_road(car: ArcadeCar, line: RivalLine, offset: float) -> void:
	var direction := Vector3.ZERO
	if line != null:
		direction = line.tangent_at(offset)
	var lane := _nearest_lane(car.global_position, direction)
	if lane < 0:
		return
	follower = LaneFollower.new()
	follower.setup(graph, lane, 0.0, _rng.randi())
	follower.s = graph.closest_offset(lane, car.global_position)
	on_road = true


## The lane of the world whose centre is nearest to the point.
##
## With a direction, the lanes that drive the other way are the second best: the rival
## drives the way of the race.
func _nearest_lane(pos: Vector3, direction: Vector3 = Vector3.ZERO, skip_connectors: bool = false) -> int:
	var best := -1
	var best_distance := INF
	var against := -1
	var against_distance := INF
	for i in graph.lane_count():
		var length := graph.lane_length(i)
		if length <= 0.0:
			continue
		if skip_connectors and graph.lanes[i].get_meta("connector", false):
			continue
		var offset := graph.closest_offset(i, pos)
		var point := graph.position_at(i, offset)
		var distance := point.distance_squared_to(pos)
		if direction.length_squared() > 0.0 and graph.tangent_at(i, offset).dot(direction) < 0.0:
			# The lane drives the other way: it is the second best.
			if distance < against_distance:
				against_distance = distance
				against = i
			continue
		if distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return against
	return best


## Moves the lane state of the rival forward on the road.
func _advance(delta: float, car: ArcadeCar) -> void:
	follower.plan_next()
	follower.advance(maxf(car.get_forward().dot(car.linear_velocity), 5.0) * delta)


## The speed the rival may hold while it drives on the road (the limit of its lane).
func speed_cap() -> float:
	if not on_road or follower == null:
		return INF
	var lane := follower.lane
	if lane < 0 or lane >= graph.lanes.size():
		return INF
	return graph.lanes[lane].speed_limit_kmh / 3.6 * ROAD_SPEED


## The carriageway around the point (m from the point: x = the left edge, y = the right
## edge, z = the middle of the road).
##
## The racing line of a city route runs along the lanes, but the line of a route that
## drives against the traffic hugs the kerb: on the Bund it runs a metre behind the kerb,
## in the footway. A car that drives that line drives on the kerb and into the buildings of
## the Bund, so the column of the car is kept inside the carriageway.
##
## The edges are the edges of the lanes of the road, so the car keeps the room of its own
## width on the carriageway.
func road_frame(point: Vector3, line: RivalLine, offset: float) -> Vector3:
	if graph == null or graph.lanes.is_empty():
		return Vector3(-INF, INF, 0.0)
	# The carriageway is the carriageway of the lanes of the road: a connector (the turn into a cross street, the curve of a
	# junction) lies far outside it and would widen it by the width of the junction (the rivals of the Bund drove 14 m to the
	# side at the Beijing Rd junction, at 120 km/h, into the kerb).
	var lane := _nearest_lane(point, Vector3.ZERO, true)
	if lane < 0:
		return Vector3(-INF, INF, 0.0)
	var road := graph.lanes[lane].road_id
	var right := line.right_at(offset)
	var line_dir := line.tangent_at(offset)
	var lo := INF
	var hi := -INF
	var centres: Array[float] = []
	var lats: Array[float] = []
	var has_offset := false
	for i in graph.lane_count():
		if graph.lanes[i].road_id != road or graph.lanes[i].get_meta("connector", false):
			continue
		var o := graph.closest_offset(i, point)
		var p := graph.position_at(i, o)
		if p.distance_to(point) > LANE_NEAR:
			# The lane is not beside the point: the road bends away from it here.
			continue
		var lat := (p - point).dot(right)
		var w := graph.lanes[i].lane_width * 0.5
		lo = minf(lo, lat - w)
		hi = maxf(hi, lat + w)
		lats.append(lat)
		has_offset = has_offset or graph.lanes[i].has_meta("offset")
		centres.append(_centre_of_road(i, p, point, right, line_dir))
	if lo == INF:
		return Vector3(-INF, INF, 0.0)
	# The middle of the road is the middle of the estimates of the lanes: the estimate of
	# a lane does not depend on the lane, so the middle of them is the middle of the road.
	# (The nearest lane changes from one tick to the next, the middle of the road does not.)
	#
	# A lane of a road that knows its own offset (the roads of the city) knows where the
	# middle of its road is. A lane of a road that does not (the loop of the sandbox) is
	# the middle of the road itself: the middle of the lanes is the middle of the road,
	# and with two lanes the middle is the half way between them, not the outer one.
	if has_offset:
		return Vector3(lo, hi, _median(centres))
	return Vector3(lo, hi, _median(lats))


## The middle of a list of values (the half way between the two middle ones when the
## count is even).
func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var count := values.size()
	if count % 2 == 1:
		return values[count / 2]
	return (values[count / 2 - 1] + values[count / 2]) * 0.5


## The middle of the road, seen from the lane (m, in the frame of the racing line).
##
## The lanes of a road know how far they lie from the centre line of their road, so every
## lane of the road knows where the middle of the road is. A rival that drives the middle
## of the road is on the road, whatever the racing line of the route does.
func _centre_of_road(lane: int, point: Vector3, from: Vector3, right: Vector3,
		line_dir: Vector3) -> float:
	var path := graph.lanes[lane]
	var s := graph.closest_offset(lane, point)
	var lane_dir := graph.tangent_at(lane, s)
	# The offset of a lane is measured to the right of the direction of the forward lanes:
	# a lane that drives the other way lies on the other side of the centre line.
	var sign := 1.0 if lane_dir.dot(line_dir) >= 0.0 else -1.0
	var side := float(path.get_meta("offset", 0.0)) * float(path.get_meta("dir", 1)) * sign
	return (point - from).dot(right) - side


## The steering while the rival drives on the road: it follows the lane, not the racing line.
func steering(car: ArcadeCar) -> float:
	var look := clampf(LOOKAHEAD_BASE + LOOKAHEAD_PER_SPEED * _speed_of(car),
		LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var aim := follower.lookahead(look)
	var err := -AISteering.heading_error(car.get_forward(), aim - car.global_position)
	var lateral := graph.lateral_offset(follower.lane, follower.s, car.global_position)
	err += clampf(-atan(STANLEY_K * lateral / maxf(_speed_of(car), CROSS_TRACK_MIN_SPEED)),
		-STANLEY_LIMIT, STANLEY_LIMIT)
	return clampf(STEER_KP * err + STEER_KD * car.angular_velocity.y, -STEER_LIMIT, STEER_LIMIT)


## The forward speed of the car (m/s).
func _speed_of(car: ArcadeCar) -> float:
	return maxf(car.get_forward().dot(car.linear_velocity), 0.0)

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
			_enter_road(car)
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
func _enter_road(car: ArcadeCar) -> void:
	var lane := _nearest_lane(car.global_position)
	if lane < 0:
		return
	follower = LaneFollower.new()
	follower.setup(graph, lane, 0.0, _rng.randi())
	follower.s = graph.closest_offset(lane, car.global_position)
	on_road = true


## The lane of the world whose centre is nearest to the point.
func _nearest_lane(pos: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for i in graph.lane_count():
		var length := graph.lane_length(i)
		if length <= 0.0:
			continue
		var offset := graph.closest_offset(i, pos)
		var point := graph.position_at(i, offset)
		var distance := point.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = i
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


## The half width of the road around the point (m), from the lane graph.
##
## A pass needs 4.45 m between the centres of two cars: the road has to be wide enough for
## it, or the rival has to slow down and follow instead of trying to squeeze past.
func road_half_width(pos: Vector3) -> float:
	if graph == null or graph.lanes.is_empty():
		return DEFAULT_ROAD_HALF
	var lane := _nearest_lane(pos)
	if lane < 0 or lane >= graph.lanes.size():
		return DEFAULT_ROAD_HALF
	var road := graph.lanes[lane].road_id
	var width := 0.0
	var nearest := INF
	var furthest := -INF
	for i in graph.lane_count():
		if graph.lanes[i].road_id != road:
			continue
		width = maxf(width, graph.lanes[i].lane_width)
		var offset := graph.closest_offset(i, pos)
		var lateral := graph.lateral_offset(i, offset, pos)
		nearest = minf(nearest, lateral)
		furthest = maxf(furthest, lateral)
	if nearest == INF:
		return DEFAULT_ROAD_HALF
	# The road is as wide as the spread of its lanes and one lane more.
	return (furthest - nearest) * 0.5 + width * 0.5


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

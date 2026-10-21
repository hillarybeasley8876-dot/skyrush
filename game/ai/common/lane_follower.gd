class_name LaneFollower
extends RefCounted
## The lane state of one AI car: which lane it is in, how far along it, and the lane-change
## S-curve it is currently driving. Shared by traffic, police and rivals.
##
## The lateral offset is always relative to the *current* lane centre: 0 = on the centre line,
## positive = to the right of the driving direction.
##
## When a car reaches the end of its lane it does not jump to the start of the next one: it
## drives the connector curve of the link (see LaneGraph), which leads from the end of its lane
## through the junction box to the point where it enters the next lane. Only a lane that really
## ends (a dead end) stops the car.
##
## A car that is within PLAN_DISTANCE of the end of its lane picks the lane it will continue into
## right away and keeps that choice, so the traffic can look for a leader in the next lane before
## it gets there.

const CHANGE_DURATION := 2.5      ## s: length of the lane-change S-curve (dossier 6.1)
const INDICATOR_LEAD := 1.0       ## s: the indicator blinks this long before the move
const TURN_CHANCE := 0.30         ## weight of "turn" against "straight on" at a lane end
const LATERAL_SPEED := 1.4        ## m/s: how fast a car moves sideways in a lane change
const PLAN_DISTANCE := 100.0      ## m: this far from the lane end the next lane is chosen

var graph: LaneGraph = null
var lane: int = 0
var s: float = 0.0
var lateral: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## -1 = changing left, +1 = changing right, 0 = not changing.
var change_dir: int = 0
var change_time: float = 0.0
var change_duration: float = CHANGE_DURATION
var change_from: float = 0.0
var change_to: float = 0.0
## The sideways speed the S-curve asks for right now (m/s).
var lateral_rate: float = 0.0
## The lane the car came from, so it can give up a lane change that does not work out.
var previous_lane: int = -1
## The distance along that lane, so the car goes back to the place it came from.
var previous_s: float = 0.0
## The curve the car drives through a junction (null while it is on a lane).
var connector: Curve3D = null
## How far the car has driven on the connector and how long the connector is.
var connector_s: float = 0.0
var connector_length: float = 0.0
## The lane the connector leads to and the distance along it where the car enters.
var connector_target: int = 0
var connector_entry: float = 0.0
## The lane the connector starts from and how long that lane is.
var connector_from: int = -1
var connector_from_length: float = 0.0
## The lane the car will continue into at the end of its lane (-1 when it is not planned yet).
var planned_next: int = -1
## Where the car enters the planned lane and how long the connector through the junction is.
var planned_entry: float = 0.0
var planned_connector: float = 0.0
## Counts the lane entries, so the car knows when it drives on a new road.
var lane_serial: int = 0


func setup(lane_graph: LaneGraph, lane_index: int, distance: float, seed_value: int) -> void:
	graph = lane_graph
	lane = lane_index
	s = distance
	lateral = 0.0
	change_dir = 0
	change_time = 0.0
	rng.seed = seed_value


## Starts a lane change towards `dir` (-1 left, +1 right) across `gap` metres into `target`.
func start_change(dir: int, gap: float, target: int) -> void:
	if dir == 0 or is_changing() or target < 0:
		return
	previous_lane = lane
	previous_s = s
	lane = target
	lane_serial += 1
	change_dir = dir
	change_time = 0.0
	# A wide gap needs more time: the car moves sideways at about 1.4 m/s, like a real one.
	change_duration = maxf(CHANGE_DURATION, gap / LATERAL_SPEED)
	change_from = -float(dir) * gap
	change_to = 0.0
	lateral = change_from


func is_changing() -> bool:
	return change_dir != 0


## True while the car drives through a junction box.
func on_connector() -> bool:
	return connector != null


## Gives up a lane change: the car goes back to the lane it came from.
##
## The distance along that lane is the one it had before the change: the car does not jump
## half a lane to the side, and the road it is on again is the one it takes the speed limit of.
func revert_lane() -> void:
	if previous_lane >= 0:
		lane = previous_lane
		# The car stays where it is: the distance along the old lane is the one that belongs
		# to the place the body is at now.
		s = previous_s
		if graph != null:
			s = graph.closest_offset_near(previous_lane, position(), previous_s, 60.0)
		lane_serial += 1
	previous_lane = -1
	lateral = 0.0
	lateral_rate = 0.0
	change_dir = 0
	change_time = 0.0


## Seconds until the current lane change is finished (0 when idle).
func change_time_left() -> float:
	if change_dir == 0:
		return 0.0
	return maxf(change_duration - change_time, 0.0)


## Advances the lane-change S-curve. Returns true while the car is still moving sideways.
func tick(dt: float) -> bool:
	if change_dir == 0:
		lateral_rate = 0.0
		return false
	change_time += dt
	var t := clampf(change_time / change_duration, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	lateral = lerpf(change_from, change_to, eased)
	lateral_rate = (change_to - change_from) * (6.0 * t * (1.0 - t) / change_duration)
	if t >= 1.0:
		change_dir = 0
		lateral = change_to
		lateral_rate = 0.0
		return false
	return true


## The world position of the car: the lane centre plus the lateral offset, or the point on the
## connector while the car drives through a junction.
func position() -> Vector3:
	if graph == null:
		return Vector3.ZERO
	if connector != null:
		return connector.sample_baked(clampf(connector_s, 0.0, connector_length), true)
	return graph.position_at(lane, s) + graph.right_at(lane, s) * lateral


## The transform of the car on its path: the lane centre plus the lateral offset, with -Z along
## the lane. The hot path (a far car is put on its lane every tick) does not allocate an array.
func transform() -> Transform3D:
	if graph == null:
		return Transform3D.IDENTITY
	if connector != null:
		var point := position()
		var ahead := direction()
		var right := ahead.cross(Vector3.UP)
		right.y = 0.0
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		return Transform3D(Basis(right, Vector3.UP, -ahead), point)
	return graph.transform_at(lane, s, lateral)


## The place and the direction of the car, worked out in one go: the traffic asks for both
## every time it puts a car on the road.
func frame() -> Array:
	if graph == null:
		return [Vector3.ZERO, Vector3.FORWARD]
	if connector != null:
		return [position(), direction()]
	var tangent := graph.tangent_at(lane, s)
	var point := graph.position_at(lane, s) + graph.right_of(tangent) * lateral
	return [point, tangent]


## The direction of travel of the car.
func direction() -> Vector3:
	if graph == null:
		return Vector3.FORWARD
	if connector != null:
		var a := connector.sample_baked(clampf(connector_s, 0.0, connector_length), true)
		var b := connector.sample_baked(clampf(connector_s + 1.0, 0.0, connector_length), true)
		var d := b - a
		d.y = 0.0
		return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	return graph.tangent_at(lane, s)


## The rise of the road under the car per metre it drives (0 on a flat road).
##
## A car has to climb with the road: on a ramp it has to follow the grade, or it drives into the
## road or off the deck.
func slope() -> float:
	if graph == null:
		return 0.0
	if connector != null:
		var a := connector.sample_baked(clampf(connector_s, 0.0, connector_length), true)
		var b := connector.sample_baked(clampf(connector_s + 1.0, 0.0, connector_length), true)
		return b.y - a.y
	return graph.slope_at(lane, s)


## A point `distance` metres ahead on the lane, used as the steering target.
func lookahead(distance: float) -> Vector3:
	if graph == null:
		return Vector3.ZERO
	if connector != null:
		return connector.sample_baked(clampf(connector_s + distance, 0.0, connector_length), true)
	return graph.position_at(lane, s + distance)


## Picks the lane the car will continue into, when it is close enough to the end of its lane.
## The choice is kept until the car reaches the end, so every car of the queue takes the same
## turn and the traffic does not change its mind in the junction box.
func plan_next(turn_chance: float = TURN_CHANCE) -> void:
	if graph == null or planned_next >= 0 or on_connector():
		return
	var length := graph.lane_length(lane)
	if length - s > PLAN_DISTANCE:
		return
	planned_next = choose_next(turn_chance)
	if planned_next >= 0:
		planned_entry = graph.entry_offset(lane, planned_next)
		planned_connector = graph.connector_length(lane, planned_next)


## The distance along the lane where the car is, as the per-lane index sees it.
##
## A car that drives through a junction is at the end of the lane it came from, plus the
## distance it has driven on the connector. Without this the car would find ITSELF as its own
## leader and brake to a standstill in the junction box.
func index_s() -> float:
	if connector != null and connector_from >= 0:
		return connector_from_length + connector_s
	return s


## The distance along the lane the car will enter, as the per-lane index sees it.
func index_s_target() -> float:
	if connector == null:
		return 0.0
	return connector_entry - (connector_length - connector_s)


## Advances `ds` metres along the lane and rolls over to the next lane at a lane end.
##
## At the end of a lane the car starts the connector of the link it takes, so it turns through the
## junction box; when the connector is done the car is on the next lane at the entry point.
## Returns the lane the car is on, or -1 when the road ends (a dead end: the car stops there).
func advance(ds: float, turn_chance: float = TURN_CHANCE) -> int:
	if graph == null:
		return -1
	if connector != null:
		connector_s += ds
		if connector_s < connector_length:
			return connector_target
		# The connector is done: the rest of the step is spent on the next lane.
		ds = connector_s - connector_length
		lane = connector_target
		s = connector_entry
		connector = null
		connector_s = 0.0
		connector_length = 0.0
		connector_from = -1
		lane_serial += 1
	s += ds
	var guard := 0
	while s >= graph.lane_length(lane) and guard < 4:
		guard += 1
		var next_lane := planned_next
		planned_next = -1
		planned_entry = 0.0
		planned_connector = 0.0
		if next_lane < 0:
			next_lane = choose_next(turn_chance)
		if next_lane < 0:
			s = graph.lane_length(lane)
			return -1
		var entry := graph.entry_offset(lane, next_lane)
		var curve := graph.connector_of(lane, next_lane)
		if curve == null or curve.get_baked_length() < 0.1:
			# The lanes meet: the car simply continues on the next lane.
			lane = next_lane
			s = entry
			lane_serial += 1
			continue
		connector = curve
		connector_s = 0.0
		connector_length = curve.get_baked_length()
		connector_target = next_lane
		connector_entry = entry
		connector_from = lane
		connector_from_length = graph.lane_length(lane)
		return next_lane
	return lane


## Picks the lane this car continues into at the end of its lane.
##
## "Straight on" carries the weight `1 - turn_chance`; every turning option shares
## `turn_chance`. The straight continuation and the turns are worked out once per lane by the
## graph, so this is a lookup and not a search.
func choose_next(turn_chance: float = TURN_CHANCE) -> int:
	if graph == null:
		return -1
	var options := graph.next_lanes[lane]
	if options.is_empty():
		return -1
	if options.size() == 1:
		return options[0]
	var straight := graph.straight_next[lane]
	var turns := graph.turn_next[lane]
	if turns.is_empty():
		return straight
	if straight < 0:
		straight = options[0]
	if rng.randf() >= turn_chance:
		return straight
	return turns[rng.randi() % turns.size()]

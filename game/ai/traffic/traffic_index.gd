class_name TrafficIndex
extends RefCounted
## The per-lane index of the traffic: which car is where on the road.
##
## The director refills the index every tick, so the leader and the follower of a car are a
## binary search away (see LaneHash) and every car of the unit sees the same road.
##
## A car that drives through a junction is on two lanes at once: it is at the end of the lane it
## came from and it is on its way to the lane it will enter. The car behind it sees it on the
## first lane, the car that is already on the second lane sees it on the second one.

const WRECK_LANE_DISTANCE := 3.0  ## m: how far a wreck may be from its lane
const WRECK_LANE_RADIUS := 8.0    ## m: how far the lane of a wreck is looked up
const PLAYER_PROJECTION := 8.0    ## m: how far the player may be from its lane
const PLAYER_LANE_RADIUS := 60.0  ## m: how far the lane of the player is looked up
const PLAYER_LANE_TOLERANCE := 4.0 ## m: how far the player may be from the centre of its lane

var ctx: DriveContext = null
var grid: LaneGrid = null


## Fills the index with the traffic.
func rebuild(cars: Array[TrafficCar]) -> void:
	ctx.hash.clear()
	ctx.cells.clear()
	for car in cars:
		if car.follower == null:
			continue
		index_car(car)
		if car.mode != TrafficCar.Mode.FAR:
			var key := DriveContext.cell_key(car.global_position.x, car.global_position.z)
			if not ctx.cells.has(key):
				ctx.cells[key] = []
			(ctx.cells[key] as Array).append(car)


## The place of a car in the index.
func index_car(car: TrafficCar) -> void:
	var follower := car.follower
	if car.mode == TrafficCar.Mode.WRECK:
		index_wreck(car)
		return
	if follower.on_connector() and follower.connector_from >= 0:
		var from_s := follower.connector_from_length + follower.connector_s
		ctx.hash.insert(follower.connector_from, from_s, car)
		var to_s := follower.connector_entry - (follower.connector_length - follower.connector_s)
		ctx.hash.insert(follower.connector_target, to_s, car)
		return
	ctx.hash.insert(follower.lane, follower.s, car)


## The place of a wreck in the index: the body, not the place where it was hit. A wreck that left
## its lane is indexed on the lane it now lies on.
##
## The lane has to be on the level of the body: a wreck that was hit on the Nanpu approach and
## fell to the street 30 m below is an obstacle of the street, not a phantom obstacle of the
## deck above it. When there is no lane under the body, the wreck blocks nothing.
##
## The lane distance of the wreck is measured by the car itself (see TrafficCarModes.tick_wreck),
## so it is not measured twice per tick.
func index_wreck(car: TrafficCar) -> void:
	var follower := car.follower
	var body := car.global_position
	var s := follower.s
	if ctx.graph.position_at(follower.lane, s).distance_to(body) <= WRECK_LANE_DISTANCE:
		ctx.hash.insert(follower.lane, s, car)
		return
	# The body left the lane it was hit on: it is indexed on the lane it really lies on, and
	# only on a lane that is on its level. A wreck that fell off a deck to the street is an
	# obstacle of the street, not a phantom obstacle of the deck above it. Where there is no
	# lane under the body, the wreck blocks nothing.
	var other := TrafficLevel.nearest_lane_at_level(grid, body, WRECK_LANE_RADIUS)
	if other < 0:
		return
	ctx.hash.insert(other, ctx.graph.closest_offset(other, body), car)


## The player is an obstacle in the lane it is driving on, so the traffic brakes for it.
##
## Returns the lane and the distance of the player on it ([lane, s]), or an empty array when the
## player is not on a lane at all.
func insert_player(player: VehicleBase, lane: int, s: float) -> Array:
	if player == null or not is_instance_valid(player):
		return []
	var near := ctx.graph.closest_offset_near(lane, player.global_position, s, PLAYER_PROJECTION)
	if ctx.graph.position_at(lane, near).distance_to(player.global_position) > PLAYER_LANE_TOLERANCE:
		# The player left its lane (it is flying, hopping or on the pavement): look for the lane
		# again, but not every tick - the search walks the lanes of the city.
		lane = grid.nearest_lane(player.global_position, PLAYER_LANE_RADIUS)
		if lane < 0:
			return []
		near = ctx.graph.closest_offset(lane, player.global_position)
		if ctx.graph.position_at(lane, near).distance_to(player.global_position) > PLAYER_LANE_TOLERANCE:
			return []
	ctx.hash.insert(lane, near, player)
	return [lane, near]

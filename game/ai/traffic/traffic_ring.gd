class_name TrafficRing
extends RefCounted
## The spawn ring of the traffic: the places where a car may appear, how many cars the road
## around the player can hold, and when a car is removed again.
##
## The ring is measured in slices, so the scan of the city never costs a frame: one tick works
## through MEASURE_CELL_BUDGET cells of the lane grid and no more.
##
## The ring is weighted to the road of the player: the traffic of a road is organised around
## the road the player drives on, so the player meets other cars instead of an empty road. The
## rest of the ring (the other roads of the city) keeps some of the cars.

const SPAWN_MIN := 25.0         ## m: the closest a car may spawn (the ring is prefilled)
const SPAWN_MAX := 350.0        ## m: the furthest a car may spawn
const KEEP_MIN := 120.0         ## m: the inner edge of the band the density is measured over
const DESPAWN_DISTANCE := 420.0 ## m: beyond this a car is a candidate for removal
const ROAD_DISTANCE := 350.0     ## m: the road of the player is measured this far ahead
const SPACING_EXPRESSWAY := 45.0 ## m per car on an elevated deck
const SPACING_SURFACE := 60.0   ## m per car on a surface road
const POPULATION_INTERVAL := 2.0 ## s: how often the ring is measured
const MEASURE_CELL_BUDGET := 8  ## cells of the lane grid per tick
const AHEAD_SHARE := 0.7        ## the share of the new cars that appear in front of the player
const ON_ROAD_SHARE := 0.6      ## the share of the cars on the road of the player
const ON_ROAD_AHEAD_SHARE := 0.7 ## the share of those in front of the player
const OTHER_SHARE := 0.4        ## the share of the cars on the other roads
const LEVEL_TOLERANCE := 4.0    ## m: only the road at the height of the player counts
const HEADING_TOLERANCE := 0.52  ## rad (30 deg): the heading of the road of the player

## The number of cars the road around the player should hold.
var target_count: int = 0
## The places a car may appear: {lane, s, pos, on_road}.
var spots: Array[Dictionary] = []

## The spots sorted by where they lie (on the road of the player or not, ahead or behind), and where the player was then. The
## sort of every spot of the ring for every spawn attempt (thousands of spots, up to six attempts a tick) cost 0.2-0.3 ms a tick.
const SORT_MOVE := 10.0       ## m: the player moved this far since the sort
const SORT_TURN_COS := 0.966  ## cos(15 deg): the player turned this far since the sort
var _on_road_ahead: Array[Dictionary] = []
var _on_road_behind: Array[Dictionary] = []
var _other_ahead: Array[Dictionary] = []
var _other_behind: Array[Dictionary] = []
var _sorted_count: int = -1
var _sorted_at: Vector3 = Vector3.ZERO
var _sorted_forward: Vector3 = Vector3.ZERO
## The spots of the measurement that is running: `spots` keeps the last whole ring until it is done.
var _building: Array[Dictionary] = []

var _cells: Array[Vector2i] = []
var _cell_cursor: int = 0
var _measure_timer: float = 0.0
var _measuring: bool = false
var _road_metres: float = 0.0
var _other_metres: float = 0.0


## Starts a new measurement around `player_pos`.
func begin_measurement(grid: LaneGrid, player_pos: Vector3) -> void:
	_cells = grid.cells_around(player_pos, DESPAWN_DISTANCE)
	_cell_cursor = 0
	_measuring = true
	_road_metres = 0.0
	_other_metres = 0.0
	_building = []


## Works on the measurement for one slice of the work. Returns true when the ring is measured.
##
## The target is only written when the measurement finishes, so a tick that does not measure does
## not throw the number away.
func measure(grid: LaneGrid, graph: LaneGraph, player_pos: Vector3, player_forward: Vector3,
		player_road: String, spacing: float, scale: float, cap: int) -> bool:
	if not _measuring:
		return true
	var budget := MEASURE_CELL_BUDGET
	while budget > 0 and _cell_cursor < _cells.size():
		var cell := _cells[_cell_cursor]
		_cell_cursor += 1
		budget -= 1
		for entry in grid.samples_in(cell):
			var point: Vector3 = entry[2]
			# Only the road at the height of the player: the traffic under an elevated deck
			# would not be seen from it.
			if absf(point.y - player_pos.y) > LEVEL_TOLERANCE:
				continue
			var distance := point.distance_to(player_pos)
			if distance < SPAWN_MIN or distance > DESPAWN_DISTANCE:
				continue
			var lane: int = entry[0]
			# The world builds some roads twice: the traffic uses the first copy only.
			if graph.is_duplicate(lane):
				continue
			var s: float = entry[1]
			var on_road := _on_player_road(graph, lane, s, player_road, player_forward)
			_building.append({"lane": lane, "s": s, "pos": point, "on_road": on_road})
			if on_road:
				if distance <= ROAD_DISTANCE:
					_road_metres += grid.sample_step
			else:
				_other_metres += grid.sample_step
	if _cell_cursor < _cells.size():
		return false
	_measuring = false
	spots = _building
	_building = []
	_sorted_count = -1
	# The number of cars the road can hold: the lane metres in the band, one car per spacing.
	# The road of the player carries the traffic; the other roads of the city never carry more
	# than the road of the player, or the city would be a car park.
	var on_road := _road_metres / maxf(spacing, 1.0)
	var other := _other_metres / maxf(spacing, 1.0) * OTHER_SHARE
	target_count = clampi(int(round((on_road + minf(other, on_road)) * scale)), 0, cap)
	return true


## True when the lane runs on the road of the player and in the same direction.
func _on_player_road(graph: LaneGraph, lane: int, s: float, player_road: String,
		player_forward: Vector3) -> bool:
	if player_road == "":
		return false
	if lane < 0 or lane >= graph.lanes.size():
		return false
	var lane_path := graph.lanes[lane]
	if lane_path == null or String(lane_path.road_id) != player_road:
		return false
	return graph.tangent_at(lane, s).angle_to(player_forward) <= HEADING_TOLERANCE


## True while the ring is still being measured.
func measuring() -> bool:
	return _measuring


## Counts the time until the next measurement.
func tick_timer(dt: float) -> void:
	_measure_timer -= dt


## True when the ring has to be measured again.
func due() -> bool:
	return _measure_timer <= 0.0


## The timer is set for the next measurement.
func restart_timer() -> void:
	_measure_timer = POPULATION_INTERVAL


## A spawn spot in the ring, chosen at random.
##
## Three sixths of the new cars appear on the road of the player and seven tenths of those in
## front of the player, so the road ahead of the player is not empty. The rest of the cars fill
## the other roads of the city.
func pick_spot(rng: RandomNumberGenerator, player_forward: Vector3,
		player_pos: Vector3) -> Dictionary:
	if spots.is_empty():
		return {}
	_sort_spots(player_forward, player_pos)
	var on_road_ahead := _on_road_ahead
	var on_road_behind := _on_road_behind
	var other_ahead := _other_ahead
	var other_behind := _other_behind
	var pool: Array[Dictionary] = []
	if rng.randf() < ON_ROAD_SHARE:
		pool = _pick(rng, on_road_ahead, on_road_behind, ON_ROAD_AHEAD_SHARE)
	else:
		pool = _pick(rng, other_ahead, other_behind, AHEAD_SHARE)
	if pool.is_empty():
		pool = _pick(rng, on_road_ahead, on_road_behind, ON_ROAD_AHEAD_SHARE)
	if pool.is_empty():
		pool = _pick(rng, other_ahead, other_behind, AHEAD_SHARE)
	if pool.is_empty():
		return {}
	return pool[rng.randi() % pool.size()]


## Sorts the spots by where they lie, unless they were sorted for (about) this place and heading of the player.
func _sort_spots(player_forward: Vector3, player_pos: Vector3) -> void:
	if _sorted_count == spots.size() and player_pos.distance_to(_sorted_at) < SORT_MOVE \
			and player_forward.dot(_sorted_forward) > SORT_TURN_COS:
		return
	_sorted_count = spots.size()
	_sorted_at = player_pos
	_sorted_forward = player_forward
	_on_road_ahead = []
	_on_road_behind = []
	_other_ahead = []
	_other_behind = []
	for spot in spots:
		var to_spot: Vector3 = (spot["pos"] as Vector3) - player_pos
		var ahead := to_spot.dot(player_forward) >= 0.0
		if bool(spot["on_road"]):
			if ahead:
				_on_road_ahead.append(spot)
			else:
				_on_road_behind.append(spot)
		else:
			if ahead:
				_other_ahead.append(spot)
			else:
				_other_behind.append(spot)


## The spots ahead of the player, or the ones behind when there are none ahead.
func _pick(rng: RandomNumberGenerator, ahead: Array[Dictionary], behind: Array[Dictionary],
		ahead_share: float) -> Array[Dictionary]:
	if ahead.is_empty():
		return behind
	if behind.is_empty():
		return ahead
	return ahead if rng.randf() < ahead_share else behind

class_name TrafficDirector
extends Node3D
## Spawns, drives and removes the AI traffic of the world.
##
## The population lives in a ring around the player: the ring is prefilled on the first frame and
## after a teleport, new cars appear 180-350 m away (mostly in front of the player, never in the
## view of the camera) and a car is removed once it is more than 420 m away and has been out of
## sight for two seconds (dossier 6.1). The ring is weighted to the road the player drives on,
## so the road ahead of the player is not empty. The density follows the road: one car per 45 m
## on an elevated deck, one per 60 m on a surface road, scaled by `Settings.feature("traffic")`.
## The hard cap is 90 cars.
##
## Every second physics tick (TICK_PERIOD) the director rebuilds the per-lane car index, ticks the
## cars with a double step, switches them between the FAR (frozen) and NEAR (dynamic) modes and
## looks for the near misses of the player. The dynamic cars move in every tick: their integrate
## runs in the engine with the speed and the lane of the last decision.

const HARD_CAP := 90              ## cars: the traffic never has more than this
## The traffic thinks THINK_HZ times a second: every tick_period physics ticks, with a step that long (2 at 120 Hz). The index of the lanes, the
## decisions of the cars, the modes, the near misses and the ring cost 1-1.5 ms, at 120 Hz a quarter of the physics of the game,
## and every millisecond of a tick is paid two to eight times a frame (a long frame runs more ticks).
const THINK_HZ := 60.0
## m: beyond this a car is a candidate for removal.
var despawn_distance: float = 420.0
const HIDDEN_TIME := 2.0          ## s: how long a car has to be out of sight before it goes
const WRECK_MIN_DISTANCE := 60.0  ## m: a wreck this close to the player stays on the road
const TELEPORT_DISTANCE := 60.0   ## m: a jump of the player this far means a respawn
const PREFILL_PER_TICK := 8       ## cars: how many cars the prefill adds per tick
const OTHER_VEHICLES_INTERVAL := 2.0 ## s: how often the police and the rivals are looked up
const PREFILL_TIME := 8.0        ## s: how long the ring is filled with the close cars
const SPAWN_ATTEMPTS := 6         ## how many places in the ring one spawn tries
const SPAWN_CLEARANCE := 30.0     ## m: the free space a new car needs on the lane
const SPAWN_MIN_DISTANCE := 180.0 ## m: a car that appears out of the blue stays that far away
const SPAWN_GUARD := 8            ## the number of spawn attempts per tick
const PLAYER_ROAD_RADIUS := 40.0  ## m: how far the road of the player is looked up
## ticks of the traffic: a spawn that found no place is tried again after this many (outside the prefill). A ring that is short of
## cars tried every tick: six spots, a view check and a ray through the city, 120 times a second.
const SPAWN_RETRY_TICKS := 3

## A car appeared in the ring. The other units (audio, HUD) can watch this.
signal car_spawned(car: TrafficCar)
## A car was removed again.
signal car_removed(car: TrafficCar)

var ctx: DriveContext = DriveContext.new()
var cars: Array[TrafficCar] = []
## The time the last tick took (ms), averaged over the ticks. The debug overlay reads it.
var tick_ms: float = 0.0
## The time the last tick took (ms), without the average.
var tick_last_ms: float = 0.0
## The time the physics of the near cars took in the last tick (ms).
var physics_last_ms: float = 0.0
## The time the parts of the last tick took (ms): the index, the cars, the modes, the events.
var cost_index_ms: float = 0.0
var cost_cars_ms: float = 0.0
var cost_modes_ms: float = 0.0
var cost_events_ms: float = 0.0
var cost_ring_ms: float = 0.0
## A fixed number of cars, ignoring the density measurement (-1 = measure it).
var density_override: int = -1
## True when the traffic thought in this physics tick (the cost fields are the ones of this tick then).
var ran_this_tick: bool = false
## The physics ticks between two thinks (THINK_HZ at the rate of the engine; tools/frame_probe.gd sets 1 to compare).
var tick_period: int = maxi(1, roundi(float(Engine.physics_ticks_per_second) / THINK_HZ))
var _tick_counter: int = 0
## The lane grid of the world: the fast "which lane is near this point" index.
var grid: LaneGrid = LaneGrid.new()

var _ring: TrafficRing = TrafficRing.new()
var _junctions: TrafficJunctions = TrafficJunctions.new()
var _player_events: TrafficPlayerEvents = TrafficPlayerEvents.new()
var _player: VehicleBase = null
var _world: WorldBase = null
var _camera: Camera3D = null
var _other_vehicles: Array[Node3D] = []
var _player_lane: int = 0
var _player_s: float = 0.0
var _last_player_position: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _warned_no_junction: bool = false
## True while the ring is being filled (the cars may appear close to the player).
var _prefill_pending: bool = true
## How long the ring has been filled.
var _prefill_timer: float = 0.0
var _vehicles_timer: float = 0.0
var _spawn_wait: int = 0
## The per-lane index of the traffic.
var _index: TrafficIndex = TrafficIndex.new()
## The cars that wait for their next turn.
var _pool: TrafficPool = TrafficPool.new()


func _ready() -> void:
	add_to_group(&"traffic_director")
	# --seed=N: the same traffic every run (tools/frame_probe.gd compares two runs)
	if Game.has_option("seed"):
		_rng.seed = int(Game.option("seed"))
	else:
		_rng.randomize()
	ctx.rng.seed = _rng.randi()
	Events.race_started.connect(_on_race_started)
	Events.pursuit_state_changed.connect(_on_pursuit_state_changed)
	TrafficVisual.preload_models()
	_index.ctx = ctx
	_index.grid = grid
	_pool.ctx = ctx
	_pool.parent = self
	# The pool is built while the world is still loading: the first car of a model takes
	# 28 ms, and the traffic must not pay for it while the player drives.
	_pool.prefill(HARD_CAP)
	_refresh_world()


## The world the traffic drives in. The director follows `Game.world` so it survives a change of
## world (menu -> city).
func _refresh_world() -> void:
	_world = Game.world
	_player = Game.player
	ctx.player = _player if _player != null and is_instance_valid(_player) else null
	if _world == null:
		return
	var lanes := _world.get_lane_paths()
	if lanes.is_empty():
		return
	ctx.graph = LaneGraph.new()
	ctx.graph.build(lanes)
	grid.build(ctx.graph)
	ctx.world = _world
	ctx.junctions = _junctions.resolve(_world, ctx.graph)
	if _junctions.resolved == 0 and not _warned_no_junction:
		_warned_no_junction = true
		push_warning("[traffic] no lane of the world ends at a traffic light junction - the traffic "
				+ "does not stop at the lights. See status/traffic.md (Requests).")
	_ring.restart_timer()
	_prefill()


## One tick of the traffic (every tick_period physics ticks, with a step that long).
func _physics_process(delta: float) -> void:
	# The player is set every physics tick, also in the ticks the traffic does not think in: the game creates the player car
	# before the traffic, so the director must not wait for the player to change.
	_player = Game.player
	ctx.player = _player if _player != null and is_instance_valid(_player) else null
	_tick_counter += 1
	ran_this_tick = _tick_counter % tick_period == 0
	if not ran_this_tick:
		return
	delta *= float(tick_period)
	var started := Time.get_ticks_usec()
	if ctx.graph == null or ctx.graph.lane_count() == 0:
		if _world != Game.world or ctx.graph == null:
			_refresh_world()
		return
	ctx.time += delta
	if _world != Game.world:
		_clear_cars()
		_refresh_world()
		return
	var mark := Time.get_ticks_usec()
	_index.rebuild(cars)
	_insert_player()
	cost_index_ms = float(Time.get_ticks_usec() - mark) / 1000.0
	mark = Time.get_ticks_usec()
	# The modes come first: a car that turns dynamic in this frame has to be moved by the
	# physics and not by the lane as well, or it jumps forward.
	var near_cars := TrafficModes.update(cars, _player_position(), _other_vehicles)
	cost_modes_ms = float(Time.get_ticks_usec() - mark) / 1000.0
	mark = Time.get_ticks_usec()
	for car in cars:
		car.tick(delta)
	cost_cars_ms = float(Time.get_ticks_usec() - mark) / 1000.0
	mark = Time.get_ticks_usec()
	_player_events.update(delta, ctx.player, near_cars)
	_remove_dead(delta)
	cost_events_ms = float(Time.get_ticks_usec() - mark) / 1000.0
	mark = Time.get_ticks_usec()
	_update_ring(delta)
	_spawn_missing(delta)
	cost_ring_ms = float(Time.get_ticks_usec() - mark) / 1000.0
	tick_last_ms = float(Time.get_ticks_usec() - started) / 1000.0
	physics_last_ms = TrafficCar.integrate_total_ms
	TrafficCar.integrate_total_ms = 0.0
	tick_ms = lerpf(tick_ms, tick_last_ms, 0.15)


## The player is an obstacle in the lane it drives on, so the traffic brakes for it.
func _insert_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var found := _index.insert_player(_player, _player_lane, _player_s)
	if found.is_empty():
		return
	_player_lane = int(found[0])
	_player_s = float(found[1])


## Removes the wrecks that lived long enough and the cars that left the ring.
##
## Nothing disappears in the view of the player: a car that reached the end of the road waits
## until it is out of sight, and a wreck stays until it has lived long enough AND is out of
## sight AND is far away.
func _remove_dead(delta: float) -> void:
	for i in range(cars.size() - 1, -1, -1):
		var car := cars[i]
		if car.mode == TrafficCar.Mode.WRECK:
			if car.wreck_time < TrafficCarPhysics.WRECK_LIFETIME:
				continue
			if _in_view(car.global_position) or car.player_distance < WRECK_MIN_DISTANCE:
				car.off_screen_time = 0.0
				continue
			car.off_screen_time += delta
			if car.off_screen_time > HIDDEN_TIME:
				_remove_car(i)
			continue
		if car.despawn:
			# The car reached the end of the road: it waits until it is out of sight.
			car.off_screen_time = 0.0 if _in_view(car.global_position) \
					else car.off_screen_time + delta
			if car.off_screen_time > HIDDEN_TIME:
				_remove_car(i)
			continue
		if car.player_distance > despawn_distance:
			car.off_screen_time = 0.0 if _in_view(car.global_position) \
					else car.off_screen_time + delta
			if car.off_screen_time > HIDDEN_TIME:
				_remove_car(i)
		else:
			car.off_screen_time = 0.0


func _remove_car(index: int) -> void:
	var car := cars[index]
	cars.remove_at(index)
	car_removed.emit(car)
	_pool.release(car)


## The ring around the player: how many cars the road holds and where the new ones appear.
func _update_ring(delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	# The other AI cars are looked up every two seconds, not every tick: walking the scene tree
	# for the groups of a city with thousands of nodes costs more than the traffic itself.
	if _vehicles_timer <= 0.0:
		_vehicles_timer = OTHER_VEHICLES_INTERVAL
		_other_vehicles.clear()
		for node in get_tree().get_nodes_in_group("police"):
			_other_vehicles.append(node as Node3D)
		for node in get_tree().get_nodes_in_group("rivals"):
			_other_vehicles.append(node as Node3D)
	_vehicles_timer -= delta
	# A player that teleports (a respawn) needs a new ring around it.
	var ppos := _player_position()
	if ppos.distance_to(_last_player_position) > TELEPORT_DISTANCE:
		_last_player_position = ppos
		_ring.restart_timer()
		_prefill()
		return
	_last_player_position = ppos
	_ring.tick_timer(delta)
	if _ring.due() and not _ring.measuring():
		_ring.begin_measurement(grid, ppos)
		_ring.restart_timer()
	# The measurement works through the city in slices: it never costs a frame.
	var scale := float(Settings.feature("traffic")) * ctx.density_scale
	if not _ring.measure(grid, ctx.graph, ppos, _player_forward(), _player_road(),
			_spacing_of_the_road(), scale, HARD_CAP):
		return
	if density_override >= 0:
		_ring.target_count = min(density_override, HARD_CAP)


## The direction the player is looking: the traffic is organised around it.
func _player_forward() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return -_player.global_transform.basis.z
	return Vector3.FORWARD


## The road the player is driving on.
##
## The player is not always exactly on a lane (it flies, hops or drives on the pavement), so the
## closest lane is asked for: the traffic belongs to the road the player is on, not to the lane
## the player was on a moment ago. The lane of the player is only kept while the player is on
## its level (see TrafficLevel.player_road).
func _player_road() -> String:
	return TrafficLevel.player_road(ctx.graph, grid, _player_lane, _player_s, _player_position(),
			PLAYER_ROAD_RADIUS)


## The distance the cars of the road around the player should keep (m).
func _spacing_of_the_road() -> float:
	if _player_lane < 0 or _player_lane >= ctx.graph.lanes.size():
		return TrafficRing.SPACING_SURFACE
	return TrafficRing.SPACING_EXPRESSWAY if ctx.graph.lanes[_player_lane].elevated \
			else TrafficRing.SPACING_SURFACE


## Marks the ring for a fresh fill: on the first frame and after a respawn the road in front of
## the player is empty otherwise, and the player drives through a ghost town. The cars are added
## over the next ticks, so the fill never costs a frame.
func _prefill() -> void:
	_prefill_pending = true
	_prefill_timer = 0.0
	_ring.restart_timer()


## Spawns the cars the population is missing.
##
## While the ring is being filled (the world has just loaded, the player has just respawned) the
## cars may appear close to the player: the player is looking at a loading screen then.
func _spawn_missing(delta: float) -> void:
	var budget := PREFILL_PER_TICK if _prefill_pending else SPAWN_GUARD
	var guard := 0
	_spawn_wait -= 1
	while cars.size() < _ring.target_count and guard < budget and (_prefill_pending or _spawn_wait <= 0):
		guard += 1
		if not _spawn_car(_prefill_pending):
			_spawn_wait = SPAWN_RETRY_TICKS
			break
	if _prefill_pending:
		# The fill ends when the road holds as many cars as it should, or after a few seconds -
		# a road that cannot hold them all is full.
		_prefill_timer += delta
		if cars.size() >= _ring.target_count or _prefill_timer > PREFILL_TIME:
			_prefill_pending = false


## Spawns one car at a free place in the ring. Returns false when there is no room.
##
## `prefill` is true when the whole ring is filled at once (the first frame, a respawn): then a
## car may appear close to the player, because the player is looking at a loading screen.
func _spawn_car(prefill: bool) -> bool:
	var spot: Dictionary = {}
	for attempt in SPAWN_ATTEMPTS:
		spot = _ring.pick_spot(_rng, _player_forward(), _player_position())
		if not spot.is_empty():
			break
	if spot.is_empty():
		return false
	var lane: int = spot["lane"]
	var s: float = spot["s"]
	var pos: Vector3 = spot["pos"]
	# The ring was measured a moment ago: check the distance and the view again.
	var distance := pos.distance_to(_player_position())
	if distance < TrafficRing.SPAWN_MIN or distance > TrafficRing.SPAWN_MAX:
		return false
	if not prefill and distance < SPAWN_MIN_DISTANCE:
		return false
	if _in_view(pos) and not (prefill or _view_blocked(pos)):
		return false
	# The spot must be free: the cars need about a car length plus the IDM gap to drive on.
	if ctx.hash.leader_gap(lane, s, SPAWN_CLEARANCE * 0.5) < SPAWN_CLEARANCE:
		return false
	if ctx.hash.follower_distance(lane, s) < SPAWN_CLEARANCE:
		return false
	# A model that is in the pool: a spawn never builds a car in the middle of the game.
	var model := _pool.pooled_model(ctx.rng)
	if model == &"":
		model = StringName(String(TrafficFleet.pick_model(ctx.rng)["id"]))
	var colour := TrafficFleet.pick_colour(ctx.rng, TrafficFleet.MODELS[model]["type"])
	return spawn_car_at(lane, s, model, colour, prefill) != null


## Spawns one car at a given place on a lane. The tests and the modes unit use it to place
## traffic where they want it.
func spawn_car_at(lane: int, s: float, model: StringName = &"", colour: Color = Color.WHITE,
		prefill: bool = false) -> TrafficCar:
	if model == &"":
		model = _pool.pooled_model(ctx.rng)
		if model == &"":
			model = StringName(String(TrafficFleet.pick_model(ctx.rng)["id"]))
		colour = TrafficFleet.pick_colour(ctx.rng, TrafficFleet.MODELS[model]["type"])
	var car := _pool.spawn_at(lane, s, model, colour)
	car.prefill = prefill
	cars.append(car)
	# The new car has to be in the index right away, or the next spawn of the same tick would
	# put a second car on the same spot.
	ctx.hash.insert(lane, s, car)
	car_spawned.emit(car)
	return car


## True when the point is inside the camera frustum (a spawn must not be in view).
func _in_view(pos: Vector3) -> bool:
	if _camera == null:
		return false
	return _camera.is_position_in_frustum(pos)


## True when something stands between the camera and the point, so the point is not really in
## view even though the frustum says so.
func _view_blocked(pos: Vector3) -> bool:
	if _camera == null:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, pos)
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


## The point the traffic is organised around: the player, or the origin without one.
func _player_position() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return Vector3.ZERO


func _clear_cars() -> void:
	for car in cars:
		car.queue_free()
	cars.clear()
	ctx.hash.clear()


## During a race or a pursuit the road is emptier (dossier 6.1).
func _on_race_started() -> void:
	ctx.density_scale = 0.7


func _on_pursuit_state_changed(state: StringName) -> void:
	ctx.density_scale = 0.7 if state == &"chase" else 1.0

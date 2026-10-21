class_name RivalDirector
extends Node3D
## Spawns the rival racers, gives them the racing line and keeps the context they drive on.
##
## The director owns the race from the AI side: the grid, the cars, the shared context
## (the player, the traffic, the race progress) and the projection of the player onto the
## racing line. The mode session owns the rules (the countdown, the checkpoints, the laps,
## the results); the director only drives the cars.

const CAR_SCENE := preload("res://ai/rivals/rival_car.tscn")
const TRAFFIC_REFRESH := 0.25   ## s: how often the traffic list is rebuilt
const TRAFFIC_RANGE := 60.0     ## m: only the traffic this close to a rival is kept
const PROJECT_WINDOW := 60.0    ## m: the window of the local projection
const PROJECT_LIMIT := 25.0     ## m: the player is off the line when it is this far from it
const FAR_TICK := 2             ## the far rivals are ticked every other physics frame
const FAR_DISTANCE := 150.0     ## m: a rival further away than this is ticked at half the rate
const NEAR_REFRESH := 0.1       ## s: the near list of a rival is rebuilt at 10 Hz
const NEAR_RANGE := 95.0        ## m: the cars this close to a rival are in its near list
const LANE_LIMIT := 4.5         ## m: the personal line never leaves this far from the line
const LANE_SLOT := 3.0           ## m: the personal lines of the field are two lanes apart
const DEFAULT_SEED := 0          ## the seed of a race when none is given

## The rivals of the current race.
var cars: Array[RivalCar] = []
## The racing line of the current route.
var line: RivalLine = null
## The difficulty of the current race.
var difficulty: StringName = &"normal"
## How much of the race is over (0..1). The rubber band stops in the last 10 %.
var race_fraction: float = 0.0
## True while the cars wait on the start grid.
var on_grid: bool = true
## The context the rivals drive on.
var ctx: RivalContext = RivalContext.new()
## The offset of every gate of the route on the racing line (m).
var gate_offsets: PackedFloat32Array = PackedFloat32Array()
## The route of the current race.
var route: RaceRoute = null
## The position of every gate of the route (the rivals aim at the gate when they are close).
var gate_positions: PackedVector3Array = PackedVector3Array()
## The lane graph of the world (a rival that loses its line drives on the road).
var graph: LaneGraph = null

var _player_offset: float = 0.0
var _player_travelled: float = 0.0
var _traffic_timer: float = 0.0
var _near_timer: float = 0.0
var _frame: int = 0
## The time the director's own tick took (ms).
var tick_ms: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"rival_director")


## Starts a race: the rivals take the grid slots of the route (the one of the player is
## left for him) and drive the route.
func start_race(route: RaceRoute, level: StringName, player_slot: int = -1,
		seed_value: int = DEFAULT_SEED) -> void:
	if not Game.world_built():
		push_error("[rivals] the race was started before the city was built")
		return
	stop_race()
	difficulty = level
	race_fraction = 0.0
	on_grid = true
	self.route = route
	line = RivalLine.new(route.racing_line)
	gate_offsets = checkpoint_offsets(route)
	gate_positions = _gate_positions(route)
	graph = _lane_graph()
	_player_offset = 0.0
	_player_travelled = 0.0
	# The field of a race is seeded by the route and the difficulty: the same race is the
	# same race every time (the tests rely on it). A seed may be given for a different
	# field of the same route.
	var salt := seed_value if seed_value != DEFAULT_SEED else 0
	_rng.seed = hash("%s|%s|%d" % [String(route.id), String(level), salt])
	var preset := RivalFleet.preset(level)
	var field := RivalFleet.field_of(String(route.id), level)
	var slots := grid_slots()
	var offsets := RivalGrid.offsets_of(route, line)
	var skip := player_slot if player_slot >= 0 else slots.size() - 1
	var slot := 0
	for i in field.size():
		var index := field[i]
		var car := _spawn_car(index, preset)
		if car == null:
			continue
		while slot == skip:
			slot += 1
		if slot < slots.size():
			car.reset_to(RivalGrid.ground_spot(slots[slot]))
			# The car knows where it stands on the line: the local projection would pick
			# the wrong branch of a line that wanders back over the start.
			if car.brain != null and slot < offsets.size():
				car.brain.set_line_offset(offsets[slot])
			_set_personal_line(car, slot)
		slot += 1
		cars.append(car)


## Gives the rival the line it keeps for the race: the column of its grid slot (so the pack
## does not cross itself) plus the lane it drives once the pack has spread out.
##
## The field drives in two lanes that are 4.4 m apart: a car is 1.95 m wide and it needs
## 2.5 m of clearance, so a pass from one lane into the other is clean. The cars of one lane
## are 8 m apart on the grid and stand 20 m apart at the pace of the race.
func _set_personal_line(car: RivalCar, slot: int) -> void:
	if car.brain == null or line == null or line.length < 1.0:
		return
	# The lateral distance is measured in the frame of the racing line: the cars of one column
	# keep the same distance to the line, so the pack does not cross itself.
	var offset := car.brain.offset
	var lateral := (car.global_position - line.point_at(offset)).dot(line.right_at(offset))
	var grid_lane := clampf(lateral, -LANE_LIMIT, LANE_LIMIT)
	# The personal line: the lane of the grid column of the car.
	var lane := LANE_SLOT if slot % 2 == 0 else -LANE_SLOT
	car.brain.set_lanes(grid_lane, lane)


## The rivals of the current race.
func get_cars() -> Array[RivalCar]:
	return cars


## The racing line of the current race.
func get_line() -> RivalLine:
	return line


## True when the route is a circuit (a closed racing line) and not a sprint.
func is_circuit() -> bool:
	return line != null and line.closed


## The grid of the route: two columns behind the start line.
func grid_slots() -> Array[Transform3D]:
	if not Game.world_built():
		push_error("[rivals] the grid was asked for before the city was built")
		return []
	if route == null or line == null:
		return []
	return RivalGrid.slots_of(route, line, Game.world)


## Removes the rivals of the last race.
func stop_race() -> void:
	for car in cars:
		if is_instance_valid(car):
			car.queue_free()
	cars.clear()
	line = null
	route = null
	gate_offsets = PackedFloat32Array()
	on_grid = true


## Creates one rival car with its paint, its name and its brain.
func _spawn_car(index: int, preset: Dictionary) -> RivalCar:
	var car := CAR_SCENE.instantiate() as RivalCar
	if car == null:
		return null
	car.rival_name = RivalFleet.name_of(index)
	car.paint = RivalFleet.colour_of(index)
	car.index = index
	add_child(car)
	var brain := RivalBrain.new()
	brain.setup(preset, RivalFleet.skill_of(index), RivalFleet.pace_of(index), line,
		_rng.randi(), RivalFleet.lane_offset_of(index))
	brain.car_name = car.rival_name
	brain.gate_offsets = gate_offsets
	brain.gate_positions = gate_positions
	brain.graph = graph
	if car.spec != null:
		brain.set_physical_grip(car.spec.mu_front * 9.81)
	car.brain = brain
	return car


## The position of every checkpoint of the route (the rivals aim at the gate when they are
## close to it: the line of a city route does not always run through the checkpoint).
func _gate_positions(route: RaceRoute) -> PackedVector3Array:
	var out := PackedVector3Array()
	if route == null:
		return out
	for cp in route.checkpoints:
		out.append(cp.origin)
	return out


## The lane graph of the world: a rival that loses its line drives on the road until it finds
## the line again.
##
## The traffic and the police unit already built one for the world: it is reused, so the race
## does not pay for a second one.
func _lane_graph() -> LaneGraph:
	for group in [&"traffic_director", &"police_director"]:
		var node := get_tree().get_first_node_in_group(group)
		if node == null:
			continue
		var found := _graph_of(node)
		if found != null:
			return found
	if not Game.world_built():
		return null
	var built := LaneGraph.new()
	built.build(Game.world.get_lane_paths())
	return built


## The lane graph of another AI unit (null when it has none).
func _graph_of(node: Node) -> LaneGraph:
	var context: Object = null
	if "ctx" in node:
		context = node.get("ctx") as Object
	if context == null and "spawner" in node:
		var spawner := node.get("spawner") as Object
		if spawner != null and "ctx" in spawner:
			context = spawner.get("ctx") as Object
	if context == null or not ("graph" in context):
		return null
	return context.get("graph") as LaneGraph


func _physics_process(delta: float) -> void:
	if line == null:
		return
	var started := Time.get_ticks_usec()
	_frame += 1
	_refresh_context(delta)
	for car in cars:
		if not is_instance_valid(car):
			continue
		# The far rivals are ticked at half the rate (dossier 7.7: the far AI cars hold their
		# last controls in between).
		if _frame % FAR_TICK != 0 and _far_from_camera(car):
			continue
		car.set_context(ctx)
		car.tick_brain(delta)
	tick_ms = lerpf(tick_ms, float(Time.get_ticks_usec() - started) / 1000.0, 0.15)


## True when the car is too far from the camera to be worth a tick every frame.
func _far_from_camera(car: RivalCar) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	return camera.global_position.distance_to(car.global_position) > FAR_DISTANCE


## Fills the context the rivals read this tick.
func _refresh_context(delta: float) -> void:
	ctx.player = Game.player
	ctx.player_travelled = _player_progress()
	ctx.race_fraction = race_fraction
	ctx.on_grid = on_grid
	ctx.elapsed += delta
	_traffic_timer -= delta
	if _traffic_timer <= 0.0:
		_traffic_timer = TRAFFIC_REFRESH
		_refresh_traffic()
	ctx.rivals.clear()
	for car in cars:
		if is_instance_valid(car):
			ctx.rivals.append(car)
	_refresh_travelled()
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = NEAR_REFRESH
		_refresh_near()


## Fills the distance every car has covered on the racing line.
##
## The cars of the field are ordered by that distance: a car that is ahead on the line is
## ahead of the other one, and the order cannot be cyclic.
func _refresh_travelled() -> void:
	ctx.travelled.clear()
	for car in cars:
		if is_instance_valid(car) and car.brain != null:
			ctx.travelled[car.get_instance_id()] = car.brain.travelled
	if is_instance_valid(Game.player):
		ctx.travelled[Game.player.get_instance_id()] = ctx.player_travelled
	ctx.player_offset = _player_offset


## Rebuilds the near list of every rival: the cars it has to keep clear of.
##
## The list is refreshed at 10 Hz and not every tick: the cars of a race are few, but the
## avoidance is the part of the brain that runs for every car of the field.
func _refresh_near() -> void:
	ctx.near.clear()
	for car in cars:
		if not is_instance_valid(car):
			continue
		var list: Array[Node3D] = []
		var pos := car.global_position
		for other in ctx.rivals:
			if other == car or not is_instance_valid(other):
				continue
			if other.global_position.distance_squared_to(pos) <= NEAR_RANGE * NEAR_RANGE:
				list.append(other)
		for other in ctx.traffic:
			if not is_instance_valid(other):
				continue
			if other.global_position.distance_squared_to(pos) <= NEAR_RANGE * NEAR_RANGE:
				list.append(other)
		ctx.near[car.get_instance_id()] = list


## Rebuilds the list of the traffic cars the rivals have to avoid.
##
## Only the traffic near a rival is kept: the list is scanned by every rival, every tick.
func _refresh_traffic() -> void:
	ctx.traffic.clear()
	for node in get_tree().get_nodes_in_group("traffic"):
		var vehicle := node as VehicleBase
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		if _near_a_rival(vehicle.global_position):
			ctx.traffic.append(vehicle)


## True when a rival is close to the point.
func _near_a_rival(point: Vector3) -> bool:
	for car in cars:
		if not is_instance_valid(car):
			continue
		if car.global_position.distance_to(point) < TRAFFIC_RANGE:
			return true
	return false


## The distance the player has covered on the racing line (m), unwrapped.
func _player_progress() -> float:
	var player := Game.player
	if player == null or line == null or line.length < 1.0:
		return 0.0
	var offset := line.project(_player_offset, player.global_position, PROJECT_WINDOW)
	if line.point_at(offset).distance_to(player.global_position) > PROJECT_LIMIT:
		# The player was teleported (the grid): find it on the line again.
		_player_offset = line.curve.get_closest_offset(player.global_position)
		_player_travelled = _player_offset
		return _player_travelled
	var step := offset - _player_offset
	if line.closed:
		if step < -line.length * 0.5:
			_player_travelled += line.length
		elif step > line.length * 0.5:
			_player_travelled -= line.length
	_player_travelled += step
	_player_offset = offset
	return _player_travelled


## The offset of every checkpoint of the route on the racing line (m).
func checkpoint_offsets(route: RaceRoute) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not Game.world_built():
		push_error("[rivals] the checkpoints were asked for before the city was built")
		return out
	if line == null or route == null:
		return out
	for cp in route.checkpoints:
		out.append(line.curve.get_closest_offset(cp.origin))
	return out


## The index of the checkpoint a car meets next when it drives on from its position.
func first_checkpoint_ahead(route: RaceRoute, position: Vector3) -> int:
	var offsets := checkpoint_offsets(route)
	if offsets.is_empty() or line == null:
		return 0
	var here := line.curve.get_closest_offset(position)
	var best := 0
	var best_delta := INF
	for i in offsets.size():
		var delta := offsets[i] - here
		if delta < 0.0:
			delta += line.length
		if delta < best_delta:
			best_delta = delta
			best = i
	return best


## The distance a vehicle has covered on the racing line (m), unwrapped.
func progress_of(vehicle: Node3D) -> float:
	if vehicle == Game.player:
		return _player_progress()
	var car := vehicle as RivalCar
	if car != null:
		return car.progress()
	return 0.0

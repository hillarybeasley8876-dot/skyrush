extends Node3D
## A capture scene for the traffic unit: the real city, the traffic and a camera.
##
##   tools/godot.sh shot --scene=res://ai/traffic/demo/traffic_demo.tscn --out=traffic --deck
##       --times=8,16 --warm 240
##
## The modes:
##   --deck    the player drives on the Yan'an elevated deck at 110 km/h, the camera is the chase
##             camera behind it: the traffic ahead of the player is what the shot is about.
##   --close   the camera is five metres behind a traffic car: the rear lamps, cruise and brake.
##   --brake   the same, but the car in front is braking, so the brake lamps are on.
##   --wreck   the player rams a traffic car: the wreck, four frames of the hit.
##   --sandbox the core sandbox loop instead of the city (it can be combined with every
##             other mode).

const DIRECTOR := preload("res://ai/traffic/traffic_director.tscn")
const PLAYER_CAR := preload("res://vehicle/player_car.tscn")
const DECK_SPEED := 30.0        ## m/s: 108 km/h on the deck
const SANDBOX_SPEED := 20.0    ## m/s: the speed of the traffic, so it stays in the frame
const CLOSE_DISTANCE := 6.0      ## m: the camera behind the car of the --close shot
const CLOSE_HEIGHT := 1.6        ## m: the height of the camera of the --close shot
const DECK_LANE_ROAD := &"yanan_elevated"
const DECK_HEIGHT := 5.0        ## m: the deck is this far above the ground
const PLAYER_SIDE_OFFSET := 6.5 ## m: the player stands next to the road, not in it

var _camera: Camera3D
var _target: Node3D
var _player: Node3D
var _mode: String = "deck"
## The core sandbox instead of the city (the city is slow to build and sometimes broken).
var _sandbox: bool = false
var _world: WorldBase = null
var _lane: int = -1
var _s: float = 0.0
var _graph: LaneGraph = null
var _counter_timer: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		match arg:
			"--deck": _mode = "deck"
			"--close": _mode = "close"
			"--front": _mode = "front"
			"--brake": _mode = "brake"
			"--wreck": _mode = "wreck"
			"--sandbox": _sandbox = true
	var environment := load("res://world/env/environment.tscn") as PackedScene
	if environment != null:
		add_child(environment.instantiate())
	var world_path := "res://core/sandbox/sandbox.tscn" if _sandbox \
			else "res://world/world.tscn"
	var world_scene := load(world_path) as PackedScene
	if world_scene != null:
		add_child(world_scene.instantiate())
	await get_tree().process_frame
	_world = Game.world
	if _world == null:
		push_error("[traffic_demo] no world")
		return
	# The real city builds over several seconds: the lanes only exist when it is done.
	await Game.world_ready()
	# The real player car, or the core stub while the vehicle unit is broken.
	_player = PLAYER_CAR.instantiate()
	if not (_player is Node3D):
		_player = (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate()
	add_child(_player)
	Game.player = _player
	add_child(DIRECTOR.instantiate())
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.far = 4000.0
	add_child(_camera)
	_camera.current = true
	await _wait_for_graph()
	var ctx: DriveContext = null
	for node in get_children():
		if node is TrafficDirector:
			ctx = (node as TrafficDirector).ctx
	if ctx != null:
		_graph = ctx.graph
		_lane = _find_lane()
		_s = 40.0
	_place_player()
	if _mode == "wreck":
		_setup_wreck()
	elif _mode == "close" or _mode == "brake" or _mode == "front":
		_setup_showcase_car()


## Waits until the director has built the lane graph of the world.
func _wait_for_graph() -> void:
	for i in 600:
		var director := _director()
		if director != null and director.ctx.graph != null \
				and director.ctx.graph.lane_count() > 0:
			return
		await get_tree().physics_frame


## The lane the demo drives on: the Yan'an elevated deck (or the first lane of the sandbox).
func _find_lane() -> int:
	if _graph == null:
		return -1
	if _sandbox:
		return 0
	# The deck itself, not one of its ramps: the lane has to be high above the ground.
	for i in _graph.lane_count():
		if _graph.lanes[i].road_id != DECK_LANE_ROAD:
			continue
		if _graph.position_at(i, _graph.lane_length(i) * 0.5).y > DECK_HEIGHT:
			return i
	return 0


## Puts the player on its lane and freezes it: the demo drives it along the lane.
func _place_player() -> void:
	if _player == null or _graph == null or _lane < 0:
		return
	var position := _graph.position_at(_lane, _s)
	var direction := _graph.tangent_at(_lane, _s)
	var right := direction.cross(Vector3.UP).normalized()
	# The player stands next to the road, not in it: a car in the lane would be an obstacle and
	# the traffic would queue up behind it instead of driving past.
	position += right * PLAYER_SIDE_OFFSET
	_player.freeze = true
	_player.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_player.global_transform = Transform3D(Basis.IDENTITY, position).looking_at(
			position + direction, Vector3.UP)


func _process(delta: float) -> void:
	if _camera == null:
		return
	match _mode:
		"close", "brake":
			_follow_car()
		"front":
			_follow_car_front()
		"wreck":
			_follow_wreck()
		_:
			_drive_the_deck(delta)
	_count_traffic(delta)


## Counts the cars of the traffic around the player: how many are in view and how many are ahead
## of the player on its road.
func _count_traffic(delta: float) -> void:
	_counter_timer += delta
	if _counter_timer < 1.0:
		return
	_counter_timer = 0.0
	var director := _director()
	if director == null or _player == null:
		return
	var forward := -(_player as Node3D).global_transform.basis.z
	var in_view := 0
	var ahead := 0
	for entry in director.get("cars"):
		var car := entry as Node3D
		var to_car := car.global_position - (_player as Node3D).global_position
		if to_car.length() < 300.0:
			in_view += 1
		if to_car.dot(forward) > 0.0 and to_car.length() < 150.0:
			ahead += 1
	print("TRAFFIC cars %d in view %d ahead %d target %d lanes %d" % [
		director.get("cars").size(), in_view, ahead, director.get("_ring").get("target_count"),
		director.get("ctx").get("graph").lane_count() if director.get("ctx").get("graph") != null else 0])


## Drives the player along the deck and keeps the chase camera behind it.
func _drive_the_deck(delta: float) -> void:
	if _graph == null or _lane < 0:
		return
	_s += (SANDBOX_SPEED if _sandbox else DECK_SPEED) * delta
	if _s > _graph.lane_length(_lane) - 10.0:
		_s = 10.0
	_place_player()
	var forward := _graph.tangent_at(_lane, _s)
	_camera.global_position = _player.global_position - forward * 7.5 + Vector3.UP * 3.0
	_camera.look_at(_player.global_position + forward * 30.0, Vector3.UP)


## A car of its own for the close-ups: the same car in every run, so the cruise and the brake
## shot can be compared.
func _setup_showcase_car() -> void:
	var director := _director()
	if director == null or _graph == null or _lane < 0:
		return
	_target = director.spawn_car_at(_lane, _s + 40.0, &"sedan_ev", Color("9da3a8"))
	_target.set_mode(TrafficCar.Mode.NEAR)


## The camera five metres behind the traffic car that is closest to the player.
func _follow_car() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _closest_car()
	if _target == null:
		return
	if _target == null:
		return
	if _mode == "brake":
		(_target as TrafficCar).brake_override = true
	var forward := -(_target as Node3D).global_transform.basis.z
	_camera.global_position = (_target as Node3D).global_position - forward * CLOSE_DISTANCE \
			+ Vector3.UP * CLOSE_HEIGHT
	_camera.look_at((_target as Node3D).global_position, Vector3.UP)


## The camera in front of the traffic car, looking back at it: the head lamps and the shadow.
func _follow_car_front() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _closest_car()
	if _target == null:
		return
	var forward := -(_target as Node3D).global_transform.basis.z
	_camera.global_position = (_target as Node3D).global_position + forward * 6.0 \
			+ Vector3.UP * 1.4
	_camera.look_at((_target as Node3D).global_position + Vector3.UP * 0.4, Vector3.UP)


## The camera follows the car the player rams.
func _follow_wreck() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _closest_car()
	if _target == null:
		return
	var forward := -(_target as Node3D).global_transform.basis.z
	_camera.global_position = (_target as Node3D).global_position - forward * 8.0 \
			+ Vector3.UP * 3.0
	_camera.look_at((_target as Node3D).global_position, Vector3.UP)


## The traffic car of the lane of the player that is closest to it.
##
## The car has to be on the road the player is on: the close-up is about the lamps of a car of
## the same road, not about a car somewhere in the city.
func _closest_car() -> Node3D:
	var director := _director()
	if director == null:
		return null
	var cars: Array = director.get("cars")
	if cars.is_empty():
		return null
	var best: Node3D = null
	var best_d := INF
	for entry in cars:
		var car := entry as TrafficCar
		if car == null or car.follower == null:
			continue
		var distance := 9999.0
		if _lane >= 0 and car.follower.lane == _lane:
			distance = absf(car.follower.s - _s)
		else:
			distance = (car as Node3D).global_position.distance_to(
					(_player as Node3D).global_position) * 0.001
		# A bus has no brake lens of its own: the close-up is about a car with brake lamps.
		if not car.lamps.brake_lenses.is_empty():
			distance *= 0.001
		if distance < best_d:
			best_d = distance
			best = car
	return best


func _director() -> TrafficDirector:
	for node in get_children():
		if node is TrafficDirector:
			return node
	return null


## A traffic car on the road with a body that rams it, so the shot shows the wreck.
func _setup_wreck() -> void:
	var director := _director()
	if director == null or _graph == null or _lane < 0:
		return
	var car := director.spawn_car_at(_lane, _s + 26.0)
	if car == null:
		return
	# The car has to be dynamic, otherwise the body drives through it.
	car.set_mode(TrafficCar.Mode.NEAR)
	_target = car
	# The ramming body: it drives into the back of the car at 90 km/h.
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.4, 4.4)
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = 1 << 1
	body.collision_mask = 1 << 1
	body.mass = 1900.0
	add_child(body)
	var position := _graph.position_at(_lane, _s + 20.0)
	var direction := _graph.tangent_at(_lane, _s + 20.0)
	body.global_transform = Transform3D(Basis.IDENTITY, position).looking_at(position + direction,
			Vector3.UP)
	body.linear_velocity = direction * 40.0

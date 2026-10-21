extends Node3D
## The police showcase: one scenario per capture, on the sandbox loop or on the real map.
##
##   tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=police --city=true \
##       --scenario=chase --times=6
##   tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=police_pit \
##       --city=true --scenario=pit --times=8
##
## The scenarios: chase, pit, box, roadblock3, roadblock4, spikes, drone, head_on, toll5.
##
## With `--place=<n>` the player starts on the road at the n-th point of interest of that kind
## (the police stations of the city), so the capture is made on a part of the city that is
## whole. The place has to be a straight road of at least 600 m, or the chase has nowhere to
## run: the n-th police station of the city is on the long straight of the ring road.
##
## Every scenario freezes the scene the moment the tactic is there (the game tree is paused),
## so the capture at any later time shows that moment.

const PLAYER_SPEED := 90.0   ## km/h
## The distance the camera of the demo keeps behind the player (m).
const CAMERA_BACK := 24.0
## The height of the camera of the demo over the road (m).
const CAMERA_HEIGHT := 4.5
## The distance of the camera of the demo to the side of the player (m).
const CAMERA_SIDE := -7.0
## The distance of the player to the point of interest when the scenario starts (m).
const PLACE_APPROACH := 60.0
## The distance the player drives ahead of his lane (m).
const LOOK_AHEAD := 25.0
## The radius the demo looks for a straight road (m).
const LANE_SEARCH_RADIUS := 120.0
## The shortest road the demo drives on (m): the chase needs room and the camera needs road.
const STRAIGHT_MIN := 600.0
## The narrowest lane the demo drives on (m): a footpath in a park is not a road.
const LANE_MIN_WIDTH := 3.0
## The speed below which the player counts as stuck (km/h).
const STUCK_SPEED := 6.0
## The seconds the player has to be stuck before he is put back on his lane (s).
const STUCK_TIME := 1.5
## The distance from his lane the player may not leave (m).
const OFF_LANE := 5.0
## The distance the units of the chase start behind the player (m).
const CHASE_GAP := 8.0
## The distance the units of the box start behind the player (m).
const BOX_START_MIN := 30.0
const BOX_START_MAX := 45.0

var player: VehicleBase = null
var director: PoliceDirector = null
var scenario: StringName = &"chase"
var camera: Camera3D = null
## The camera of the game ("chase") or the camera of the demo ("police").
var camera_mode: StringName = &"police"
var _frozen: bool = false
var _clock: float = 0.0
var _stuck_time: float = 0.0
var _freeze: PoliceDemoFreeze = PoliceDemoFreeze.new()


func _ready() -> void:
	var option := Game.option("scenario")
	scenario = StringName(option) if option != "" else &"chase"
	var rcam := Game.option("rcam")
	camera_mode = StringName(rcam) if rcam != "" else &"police"
	_build_environment()
	_build_world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The world has to be built before it is asked for a spawn (CONTRACTS §4).
	await Game.world_ready()
	_build_player()
	await get_tree().physics_frame
	_build_director()
	_build_camera()
	await _wait_for_road()
	# The player is put on the road of the chosen point of interest, and the dispatcher needs
	# a tick to find the lane he drives on.
	_place_at_poi(&"police_station", PLACE_APPROACH)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_start_scenario()


## The night sky, the fog and the moon of the environment unit.
func _build_environment() -> void:
	var scene := load("res://world/env/environment.tscn") as PackedScene
	if scene == null:
		return
	add_child(scene.instantiate())


## The world: the real city when it is there, the sandbox otherwise.
func _build_world() -> void:
	var path := "res://core/sandbox/sandbox.tscn"
	if Game.option("city") == "true" and ResourceLoader.exists("res://world/world.tscn"):
		path = "res://world/world.tscn"
	var scene := load(path) as PackedScene
	if scene == null:
		return
	add_child(scene.instantiate())


## The player on the road.
func _build_player() -> void:
	var scene := load("res://vehicle/player_car.tscn") as PackedScene
	if scene == null:
		return
	player = scene.instantiate() as VehicleBase
	add_child(player)
	Game.player = player
	var xform := Transform3D.IDENTITY
	if Game.world != null:
		xform = Game.world.get_spawn_transform(&"player", 0)
	player.reset_to(xform)


## Waits for the lanes of the world: the dispatcher can only place its units when they are
## there, and the city is built over a few frames.
func _wait_for_road() -> void:
	for i in 600:
		await get_tree().physics_frame
		if director == null:
			return
		var graph := director.spawner.ctx.graph
		if graph == null or graph.lane_count() == 0:
			continue
		if Game.world != null and Game.world.has_method(&"is_ready"):
			if not bool(Game.world.call(&"is_ready")):
				continue
		return


## The dispatcher of the police.
func _build_director() -> void:
	var scene := load("res://ai/police/police_director.tscn") as PackedScene
	if scene == null:
		return
	director = scene.instantiate() as PoliceDirector
	add_child(director)


## The camera of the capture: the camera of the game or the one of the demo.
##
## The camera of the game sits behind the player, so it shows the police that are IN FRONT of
## him (the block, the strip, the drone, the head-on unit). The camera of the demo stands
## further back, so it shows the units that come from behind (the chase, the PIT, the box).
func _build_camera() -> void:
	if camera_mode == &"chase":
		var scene := load("res://vehicle/camera/chase_camera.tscn") as PackedScene
		if scene != null:
			add_child(scene.instantiate())
		return
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 58.0
	camera.far = 1200.0
	add_child(camera)
	camera.current = true
	# The camera stands behind and beside the player, so it sees the units that chase him and
	# the ones that squeeze him.
	camera.global_position = player.global_position - player.get_forward() * CAMERA_BACK \
			+ player.global_transform.basis.x * CAMERA_SIDE + Vector3.UP * CAMERA_HEIGHT


## The camera follows the player.
func _follow_camera() -> void:
	if camera == null or player == null:
		return
	var forward := -player.global_transform.basis.z
	var side := player.global_transform.basis.x * CAMERA_SIDE
	var wanted := player.global_position - forward * CAMERA_BACK + side + Vector3.UP * CAMERA_HEIGHT
	camera.global_position = camera.global_position.lerp(wanted, 0.08)
	camera.look_at(player.global_position + forward * 4.0 + Vector3.UP * 1.0, Vector3.UP)


## The scenario: the tactic the capture shows.
func _start_scenario() -> void:
	if director == null:
		return
	director.spawn_enabled = false
	match scenario:
		&"chase":
			director.start_pursuit(3)
			# The units are far enough behind the player to be in the frame of the camera.
			_spawn_behind(CHASE_GAP, PoliceFleet.Role.PURSUE)
			_spawn_behind(CHASE_GAP + 7.0, PoliceFleet.Role.RAM)
			_spawn_behind(CHASE_GAP + 14.0, PoliceFleet.Role.PIT)
		&"pit":
			director.start_pursuit(3)
			director.force_role(PoliceFleet.Role.PIT)
			_spawn_in_frame(PoliceFleet.Role.PIT, 3.4, 3.0)
		&"box":
			director.start_pursuit(2)
			director.force_roles([PoliceFleet.Role.BOX_FRONT, PoliceFleet.Role.BOX_SIDE,
					PoliceFleet.Role.BOX_SIDE])
			# The units of the box start BEHIND the player: the box is formed on the road, not
			# placed in the frame of the capture.
			_spawn_in_frame(PoliceFleet.Role.BOX_FRONT, 0.0, BOX_START_MAX)
			_spawn_in_frame(PoliceFleet.Role.BOX_SIDE, -2.4, BOX_START_MIN)
			_spawn_in_frame(PoliceFleet.Role.BOX_SIDE, 2.4, BOX_START_MIN)
		&"roadblock3":
			director.start_pursuit(3)
			_spawn_roadblock(3, 45.0)
		&"roadblock4":
			director.start_pursuit(4)
			_spawn_roadblock(4, 45.0)
		&"spikes":
			director.start_pursuit(4)
			_spawn_strip(30.0)
		&"drone":
			director.start_pursuit(4)
		&"head_on":
			director.start_pursuit(4)
			_spawn_head_on()
		&"toll5":
			_place_at_toll()
			director.start_pursuit(5)


## Puts the player on the road in front of the toll plaza, so the closure is on the camera.
func _place_at_toll() -> void:
	_place_at_poi(&"toll", PLACE_APPROACH, false)


## Puts the player on the road in front of a point of interest of the world.
##
## The demo can be told which point of interest to use (`--place=2`), so the capture can be
## made on a part of the city that is whole.
func _place_at_poi(kind: StringName, distance: float, use_option: bool = true) -> void:
	if Game.world == null or player == null:
		return
	# The option is the number of the point of interest of that kind (the first one by default).
	var wanted := int(Game.option("place")) if use_option else 0
	var seen := 0
	for poi in Game.world.get_points_of_interest():
		if StringName(poi.get("kind", &"")) != kind:
			continue
		if seen < wanted:
			seen += 1
			continue
		var pos: Vector3 = poi.get("position", Vector3.ZERO)
		var spot := _lane_spot_near(pos, distance)
		if spot.is_empty():
			return
		player.reset_to(spot["transform"])
		return


## A place on the road `distance` metres before a point of the world.
##
## The place is on the LONGEST lane near the point: the player needs a straight road of six
## hundred metres, or the chase has nowhere to run and the camera of the demo ends up inside
## a building.
func _lane_spot_near(point: Vector3, distance: float) -> Dictionary:
	if director == null:
		return {}
	var graph := director.spawner.ctx.graph
	if graph == null or graph.lane_count() == 0:
		return {}
	# The point of interest may be on a plaza: the world knows the road next to it, and the
	# player is put on THAT road (the longest road near the point can be a plaza lane).
	var road_point := point
	if Game.world != null:
		road_point = Game.world.nearest_road_transform(point).origin
	var lane := director.spawner.grid.nearest_lane(road_point, 40.0)
	if lane < 0:
		lane = _longest_lane(road_point)
	if lane < 0:
		return {}
	var s := clampf(graph.closest_offset(lane, road_point) - distance, 0.0,
			maxf(graph.lane_length(lane) - 20.0, 0.0))
	print("DEMO place lane=", lane, " len=", graph.lane_length(lane), " s=", s,
			" pos=", graph.position_at(lane, s))
	return {"transform": graph.transform_at(lane, s, 0.0)}


## The longest lane near a point (-1 when there is no straight road there).
func _longest_lane(point: Vector3) -> int:
	var graph := director.spawner.ctx.graph
	var best := -1
	var best_length := 0.0
	for lane: int in director.spawner.grid.lanes_near(point, LANE_SEARCH_RADIUS):
		# Only a road: a footpath in a park or a plaza lane is long enough, but it has no
		# neighbour lane (a road has the lane of the other direction beside it).
		if graph.lanes[lane].lane_width < LANE_MIN_WIDTH:
			continue
		if graph.left[lane] < 0 and graph.right[lane] < 0:
			continue
		var length := graph.lane_length(lane)
		if length > best_length:
			best_length = length
			best = lane
	return best


## A unit behind the player, on his line.
func _spawn_behind(distance: float, role: PoliceFleet.Role) -> void:
	_spawn_in_frame(role, 0.0, distance)


## A unit at a place in the frame of the player (right = metres to the right, behind = metres
## behind him). The unit is put on the road the player is on.
func _spawn_in_frame(role: PoliceFleet.Role, right: float, behind: float) -> void:
	var basis := player.global_transform.basis
	# The nose of a car is -Z, so +Z is behind the player.
	var spot := Transform3D(basis, player.global_position + basis.x * right + basis.z * behind)
	director.spawn_unit_at(spot, role)


## A roadblock in front of the player.
func _spawn_roadblock(heat: int, distance: float) -> void:
	director.blockade.spawn_at(heat, player, director.lane, director.lane_offset, distance)


## A spike strip in front of the player.
func _spawn_strip(distance: float) -> void:
	director.blockade.spawn_strip_at(player, director.lane, director.lane_offset, distance)


## The head-on unit on an oncoming lane.
func _spawn_head_on() -> void:
	var spot: Dictionary = director.spawner.spots.head_on_spot(player, director.lane,
			director.lane_offset)
	if spot.is_empty():
		return
	director.spawn_unit_at(spot["transform"], PoliceFleet.Role.HEAD_ON)


## The tick: the player drives along the road.
func _physics_process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	_drive()
	_follow_camera()
	_check_stuck(delta)
	_check_freeze()


## Holds the speed of the player and keeps him on the lane.
func _drive() -> void:
	var speed := player.get_speed_kmh()
	if speed < PLAYER_SPEED:
		Input.action_press(&"accelerate")
	else:
		Input.action_release(&"accelerate")
	Input.action_release(&"brake")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	var target := _lane_target()
	if target == Vector3.ZERO:
		return
	var forward := -player.global_transform.basis.z
	var to_target := target - player.global_position
	if to_target.length() < 2.0:
		return
	var error := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	if error > 0.03:
		Input.action_press(&"steer_left")
	elif error < -0.03:
		Input.action_press(&"steer_right")


## The point on the lane the player drives towards (25 m ahead).
##
## The route of the player follows the straightest successor of the lane graph, so the demo
## does not drive into a wall at every junction.
func _lane_target() -> Vector3:
	if director == null:
		return Vector3.ZERO
	var graph := director.spawner.ctx.graph
	if graph == null or graph.lane_count() == 0:
		return Vector3.ZERO
	var walk := PoliceRoute.walk(graph, director.lane, director.lane_offset, LOOK_AHEAD)
	if not bool(walk["found"]):
		return Vector3.ZERO
	return walk["position"]


## The player is stuck against a wall or he left the road: he is put back on his lane.
func _check_stuck(delta: float) -> void:
	var graph := director.spawner.ctx.graph if director != null else null
	if graph == null or graph.lane_count() == 0:
		return
	var lane := clampi(director.lane, 0, graph.lane_count() - 1)
	var on_lane := graph.position_at(lane, director.lane_offset)
	var off_road := player.global_position.distance_to(on_lane) > OFF_LANE
	if player.get_speed_kmh() < STUCK_SPEED or off_road:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time < STUCK_TIME:
		return
	_stuck_time = 0.0
	player.reset_to(graph.transform_at(lane, director.lane_offset, 0.0))


## Freezes the scene the moment the tactic is there, so the capture shows it.
func _check_freeze() -> void:
	if _frozen or director == null:
		return
	if not _freeze.ready(scenario, director, player, _clock):
		return
	_frozen = true
	Input.action_release(&"accelerate")
	Input.action_release(&"brake")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	get_tree().paused = true

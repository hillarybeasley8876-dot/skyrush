extends RefCounted
## The shared helper of the police tests: the sandbox world, a scripted player, the dispatcher
## and the PASS/FAIL bookkeeping.
##
## The player is driven with the real input actions (the same keys a human uses), so the police
## fight the same car the player drives.
##
## The helper counts the engine errors (res://tools/error_counter.gd) and fails the suite when
## there is one: a test that runs on a crashing script is not a test.

const ErrorCounter := preload("res://tools/error_counter.gd")
const PoliceErrorLog := preload("res://ai/police/tests/police_error_log.gd")
## The seconds the police stay blind when the test holds the sight block.
const SIGHT_BLOCK := 5.0
## The speed above which the brake key brakes (below it the car reverses).
const REVERSE_SPEED_KMH := 3.6

var tree: SceneTree
var world: Node3D = null
var player: VehicleBase = null
var director: PoliceDirector = null
var checks: int = 0
var failures: int = 0
## The number of checks the suite declares (0 = no declaration).
var expected: int = 0
## The collisions between the player and a police car.
var police_hits: int = 0
## The collisions between two police cars (a unit that pushes another one).
var police_collisions: int = 0
## The number of contacts with every police unit (by its instance id).
var hits_by_unit: Dictionary = {}
## The state of the police car that hit the player last.
var last_hit_state: int = -1
## True while the player is pinned: it cannot be pushed away by the police.
var pinned: bool = false
## The place the pinned player is held.
var pin_xform: Transform3D = Transform3D.IDENTITY
## True while the player is held in the air: the busted meter must not fill.
var airborne: bool = false
## The place the airborne player is held.
var air_xform: Transform3D = Transform3D.IDENTITY
## The highest value the busted meter reached.
var peak_busted: float = 0.0
## The number of Events.infraction events the test has seen.
var infractions: int = 0
## The kinds of the offences the test has seen.
var offence_kinds: Array[StringName] = []
## The stunts the test has seen (the kind and the points).
var stunts: Array[Dictionary] = []
## The engine errors of the police code the suite has seen.
var errors: int = 0
## The engine errors of the whole project the suite has seen.
var all_errors: int = 0
var _error_lines: PackedStringArray = []
var _counter: ErrorCounter = null
var _own_log: PoliceErrorLog = null


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


## Builds the sandbox, the player and the dispatcher.
func build(player_xform: Transform3D) -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	_own_log = PoliceErrorLog.new()
	OS.add_logger(_own_log)
	var world_scene := load("res://core/sandbox/sandbox.tscn") as PackedScene
	world = world_scene.instantiate() as Node3D
	tree.root.add_child(world)
	await tree.physics_frame
	await tree.physics_frame
	var car_scene := load("res://vehicle/player_car.tscn") as PackedScene
	player = car_scene.instantiate() as VehicleBase
	tree.root.add_child(player)
	Game.player = player
	player.reset_to(player_xform)
	await tree.physics_frame
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.infraction.connect(_on_infraction)
	Events.stunt.connect(_on_stunt)
	var director_scene := load("res://ai/police/police_director.tscn") as PackedScene
	director = director_scene.instantiate() as PoliceDirector
	tree.root.add_child(director)
	await tree.physics_frame
	await tree.physics_frame


## Holds the brake until the player has stopped. Returns the seconds it took (-1 when the
## player did not stop in time).
##
## The brake key of the car reverses below walking pace, so it is released at the end.
func brake_until_stopped(seconds: float, yaw: float = 0.0,
		stopped_kmh: float = 5.0) -> float:
	var steps := int(seconds * Engine.physics_ticks_per_second)
	Input.action_release(&"accelerate")
	for i in steps:
		_steer_along(Vector3(cos(yaw), 0.0, sin(yaw)))
		if player.get_speed_kmh() > REVERSE_SPEED_KMH:
			Input.action_press(&"brake")
		else:
			Input.action_release(&"brake")
		await tree.physics_frame
		_pin()
		if player.get_speed_kmh() < stopped_kmh:
			return float(i) / Engine.physics_ticks_per_second
	return -1.0


## Takes the traffic off the road: the tests of the police need a straight without traffic.
##
## A traffic car that the player rear-ends pushes him, and the test of the bust measures the
## player, not the traffic.
func clear_traffic() -> void:
	var director := tree.root.get_tree().get_first_node_in_group(&"traffic_director")
	if director == null:
		return
	director.set("density_override", 0)


## The start line of the north straight of the sandbox, facing +X, on the road.
func straight_start(x: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 0.05, -196.0))


## Drives the player for `seconds` along a straight with the given heading.
##
## `yaw` is the heading of the straight in radians (0 = +X, -PI/2 = -Z). The player keeps the
## speed with the throttle and the brake.
func drive(seconds: float, yaw: float, target_kmh: float = 90.0) -> void:
	var steps := int(seconds * Engine.physics_ticks_per_second)
	for i in steps:
		await drive_frame(yaw, target_kmh)


## One frame of driving.
func drive_frame(yaw: float, target_kmh: float = 90.0) -> void:
	_steer_along(Vector3(cos(yaw), 0.0, sin(yaw)))
	_speed_control(target_kmh)
	await tree.physics_frame
	_pin()


## Keeps the player on the straight.
func _steer_along(desired: Vector3) -> void:
	var forward := -player.global_transform.basis.z
	var error := forward.signed_angle_to(desired, Vector3.UP)
	_press(&"steer_left", error > 0.04)
	_press(&"steer_right", error < -0.04)


## Holds the speed of the player with the throttle and the brake.
func _speed_control(target_kmh: float) -> void:
	var speed := player.get_speed_kmh()
	_press(&"accelerate", speed < target_kmh)
	_press(&"brake", speed > target_kmh + 8.0)


## Presses or releases an input action.
func _press(action: StringName, down: bool) -> void:
	if down:
		Input.action_press(action)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


## Releases every action the test pressed.
func release_all() -> void:
	for action: StringName in [&"accelerate", &"brake", &"steer_left", &"steer_right"]:
		Input.action_release(action)


## Runs the physics for the given number of seconds without touching the input.
##
## `blind` keeps the police from seeing the player (the flash charge of the dossier §3.4).
func idle(seconds: float, blind: bool = false) -> void:
	var steps := int(seconds * Engine.physics_ticks_per_second)
	for i in steps:
		if blind and director != null:
			director.pursuit.sight_block = SIGHT_BLOCK
		await tree.physics_frame
		_pin()
		if director != null:
			peak_busted = maxf(peak_busted, director.busted)


## Starts a pursuit at a given heat (the public API of the dispatcher, the grace does not apply).
func start_pursuit(level: int) -> void:
	director.start_pursuit(level)


## Waits out the grace of the spawn (the offences do not count before it is over).
func wait_grace() -> void:
	await idle(PoliceOffences.SPAWN_GRACE + 0.5)


## The heading of the player in the frame of the world (radians).
func player_heading() -> float:
	return -player.global_transform.basis.z.angle_to(Vector3.RIGHT)


## Holds the player in place, so the police cannot push it away.
func _pin() -> void:
	if player == null:
		return
	if airborne:
		# The player is held in the air: it must not be busted there.
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.global_transform = air_xform
		return
	if not pinned:
		return
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.global_transform = pin_xform


## Holds the player in the air at a given height above the road (m).
func hold_in_air(height: float) -> void:
	airborne = true
	air_xform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-400.0, height, -196.0))
	player.reset_to(air_xform)


## A check with a label.
func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)


## The number of checks the suite will run. The suite fails when fewer checks ran: a check
## that never ran is not a passed check.
func expect(count: int) -> void:
	expected = count


## Removes a police unit through the dispatcher, so the squad does not keep a freed car.
func despawn_unit(unit: PoliceCar) -> void:
	if director != null:
		director.despawn_unit(unit)


## Prints the summary and leaves the test.
func finish() -> void:
	release_all()
	if _counter != null:
		all_errors = _counter.errors
		_error_lines = _counter.first_errors
	if _own_log != null:
		errors = _own_log.errors
	if errors > 0:
		failures += 1
		print("FAIL the suite ran without engine errors (%d in the police code)" % errors)
		for i in mini(5, _own_log.first_errors.size()):
			print("  ENGINE ERROR ", _own_log.first_errors[i])
	elif all_errors > 0:
		print("NOTE %d engine errors of the other units (they are edited in parallel)" % all_errors)
	if expected > 0 and checks < expected:
		failures += 1
		print("FAIL every declared check ran (%d of %d)" % [checks, expected])
	print("POLICE TESTS %s (%d checks, %d failures, %d engine errors of the police code)" % [
		"FAILED" if failures > 0 else "OK", checks, failures, errors])
	tree.quit(1 if failures > 0 else 0)


## Counts the stunts.
func _on_stunt(kind: StringName, points: int, label: String) -> void:
	stunts.append({"kind": kind, "points": points, "label": label})


## Counts the offences.
func _on_infraction(vehicle: VehicleBase, kind: StringName) -> void:
	if vehicle != player:
		return
	infractions += 1
	offence_kinds.append(kind)
	print("  OFFENCE ", kind)


## Counts the hits of the player.
func _on_vehicle_collided(vehicle: VehicleBase, other: Node3D, _impulse: float,
		_point: Vector3, _normal: Vector3) -> void:
	if vehicle is PoliceCar and other is PoliceCar:
		# A police car that pushes another one: the units queue up, they do not shove.
		police_collisions += 1
		return
	if vehicle != player and other != player:
		return
	var cop := other as PoliceCar if vehicle == player else vehicle as PoliceCar
	if cop == null:
		return
	police_hits += 1
	last_hit_state = cop.state
	var id := cop.get_instance_id()
	hits_by_unit[id] = int(hits_by_unit.get(id, 0)) + 1


## The number of contacts between the player and one police unit.
func hits_of(unit: PoliceCar) -> int:
	if unit == null:
		return 0
	return int(hits_by_unit.get(unit.get_instance_id(), 0))

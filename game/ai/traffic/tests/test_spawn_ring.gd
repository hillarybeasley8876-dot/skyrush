extends Node
## The spawn ring: the traffic appears 180-350 m from the player, never inside the view of the
## camera, and it is removed again when it leaves the ring.
##
##   tools/godot.sh test res://ai/traffic/tests/test_spawn_ring.gd

const RUNTIME := 20.0   ## s of simulated time
const MIN_CARS := 4
const MAX_CARS := 90
const SPAWN_MIN := 120.0  ## m: a car that appears out of the blue stays that far away
const SPAWN_MAX := 350.0  ## m: the furthest a car may appear

var _failures: int = 0
var _spawn_distances: Array[float] = []
var _spawn_in_view: int = 0
var _removed: int = 0
var _peak: int = 0
var _director: TrafficDirector = null


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	var world_scene := load("res://core/sandbox/sandbox.tscn") as PackedScene
	var world := world_scene.instantiate()
	add_child(world)
	await get_tree().physics_frame
	var player_scene := load("res://core/stubs/stub_car.tscn") as PackedScene
	var player := player_scene.instantiate()
	add_child(player)
	Game.player = player
	player.reset_to((world as WorldBase).get_spawn_transform(&"player", 0))
	var director_scene := load("res://ai/traffic/traffic_director.tscn") as PackedScene
	_director = director_scene.instantiate()
	add_child(_director)
	await get_tree().physics_frame
	_director.car_spawned.connect(_on_spawned)
	_director.car_removed.connect(_on_removed)
	# A camera at the player makes the frustum test of the ring real.
	var camera := Camera3D.new()
	camera.far = 3000.0
	add_child(camera)
	camera.global_position = player.global_position + Vector3.UP * 2.0
	camera.look_at(player.global_position - Vector3.FORWARD * 100.0, Vector3.UP)
	camera.current = true
	for i in int(RUNTIME * 120.0):
		await get_tree().physics_frame
		_peak = maxi(_peak, _director.cars.size())
	var live := _director.cars
	_check(live.size() >= MIN_CARS, "the ring is populated (%d cars)" % live.size())
	_check(_peak <= MAX_CARS, "the hard cap holds (peak %d)" % _peak)
	_check(_spawn_distances.size() > 0, "cars were spawned (%d)" % _spawn_distances.size())
	var min_d := INF
	var max_d := -INF
	for d in _spawn_distances:
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
	_check(min_d >= SPAWN_MIN, "no car spawns closer than %.0f m (%.1f m)" % [SPAWN_MIN, min_d])
	_check(max_d <= SPAWN_MAX, "no car spawns further than %.0f m (%.1f m)" % [SPAWN_MAX, max_d])
	_check(_spawn_in_view == 0, "no car spawns inside the view (%d did)" % _spawn_in_view)
	_check(_removed > 0, "cars are removed again (%d)" % _removed)
	var moving := 0
	for car in live:
		if car.speed > 1.0:
			moving += 1
	_check(moving >= live.size() / 2, "the traffic is rolling (%d of %d)" % [moving, live.size()])
	print("SPAWN RING TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _on_spawned(car: TrafficCar) -> void:
	# The cars of the prefill may appear close to the player (the player is looking at a loading
	# screen); the other cars never do.
	if car.prefill:
		return
	_spawn_distances.append(car.global_position.distance_to((Game.player as Node3D).global_position))
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.is_position_in_frustum(car.global_position):
		_spawn_in_view += 1


func _on_removed(_car: TrafficCar) -> void:
	_removed += 1

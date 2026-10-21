extends Node3D
## A demo of a race on the sandbox loop: the start grid, the countdown and the pack driving.
##
## It is the capture scene of the modes unit:
##   tools/godot.sh shot --scene=res://modes/demo/race_demo.tscn --out=race --times=2,14,30
##
## The scene builds the core sandbox (no city assets, so it loads in a second), starts a race
## through the mode director and follows the leading rival with the camera.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"

var _camera: Camera3D = null
var _rivals: Node = null
var _modes: ModeDirector = null
## The distance the camera keeps from the first gate (0 = follow the leader).
var _gate_distance: float = 0.0


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	_rivals = (load(RIVAL_DIRECTOR) as PackedScene).instantiate()
	add_child(_rivals)
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 2, "difficulty": "normal"})
	_build_camera()
	_build_light()
	_gate_distance = float(_option("gate", "0"))


## The camera: it follows the leading rival from behind and above.
func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "RaceCamera"
	_camera.fov = 62.0
	_camera.position = Vector3(340.0, 6.0, 215.0)
	add_child(_camera)


## The sandbox has no lights of its own, so the demo adds a moon light and a cold fill.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Moon"
	sun.light_color = Color("9fb4d8")
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("0a0e1a")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("4a5a80")
	atmosphere.ambient_light_energy = 1.5
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = atmosphere
	add_child(env)


func _process(_delta: float) -> void:
	if _gate_distance > 0.0:
		_look_at_gate()
		return
	var leader := _leading_rival()
	if leader == null or _camera == null:
		return
	var target: Vector3 = leader.global_position + Vector3.UP * 1.0
	var back := -leader.global_transform.basis.z
	var wanted: Vector3 = target - back * 13.0 + Vector3.UP * 5.5
	_camera.global_position = _camera.global_position.lerp(wanted, 0.06)
	_camera.look_at(target, Vector3.UP)


## The value of a command line option of the demo.
func _option(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


## Puts the camera in front of the first gate, at the distance of the option.
func _look_at_gate() -> void:
	var session := _modes.session as RaceSession
	if session == null or session.gates.is_empty() or _camera == null:
		return
	var gate := session.gates[0]
	if _gate_distance <= 8.0:
		# Close up: a three-quarter view of a pylon (the plinth, the bolts, the texture).
		var pylon: Vector3 = gate.global_transform * Vector3(-11.5, 1.6, 0.0)
		var wanted: Vector3 = pylon + gate.global_transform.basis.x * 6.0 + Vector3.UP * 1.2
		_camera.global_position = wanted
		_camera.look_at(pylon, Vector3.UP)
		return
	# Further away: the gate from the road.
	var target: Vector3 = gate.global_position + Vector3.UP * 3.0
	var far: Vector3 = target - gate.global_transform.basis.z * _gate_distance
	_camera.global_position = far
	_camera.look_at(target, Vector3.UP)


## The rival that is the closest to the end of the route.
func _leading_rival() -> Node3D:
	var best: Node3D = null
	var best_progress := -INF
	if _rivals == null:
		return null
	for car in _rivals.call("get_cars") as Array:
		var rival := car as RivalCar
		if rival == null:
			continue
		if rival.progress() > best_progress:
			best_progress = rival.progress()
			best = rival
	return best

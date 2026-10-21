extends Node3D
## Scripted showcase of every effect in game/fx/ (brief §8). It is built on the core sandbox, the
## environment unit's environment and the real Roadster, so the effects are judged in the same
## light and on the same road as the game. The car drives north along a wet asphalt strip and
## every effect is fired on a timeline while the camera follows.
##
## The charge flash is not faked: the car drives through the real charge lane of the sandbox at
## 60 km/h, and the sandbox station fires the event.
##
## The beats themselves live in fx_demo_beats.gd, so this file stays a readable timeline.

const SANDBOX := preload("res://core/sandbox/sandbox.tscn")
const DIRECTOR := preload("res://fx/fx_director.tscn")
const ASSETS := preload("res://fx/demo/fx_demo_assets.gd")
const WORLD := preload("res://fx/demo/fx_demo_world.gd")
const BEATS := preload("res://fx/demo/fx_demo_beats.gd")

## The start is on the road strip of the demo, in front of the charge lane of the sandbox
## (the lane is at z = -224, the car needs about 5 s to cover the distance).
const START := Vector3(-420.0, 0.8, -124.0)
const CHASE_OFFSET := Vector3(2.6, 2.4, 7.0)
## The capture tool warms up for 20 frames before the first shot.
const WARMUP_FRAMES := 20
## The drift windows: the car holds the drift key and steers into it, then counter-steers.
## The first window is the opening (the car is still slow there), the second one is at speed:
## that is the one that shows the full tyre plume.
const DRIFT_WINDOWS := [[1.0, 2.4, 3.2, -1.0], [15.0, 15.9, 16.4, 1.0]]
## The vehicle unit applies the gamepad curve to the steering axis, so a key press of this
## strength ends up as a steering value of about 0.5 (the drift needs more than 0.3).
const STEER_PRESS := 0.55

## The ice car (the traffic car) is wrecked at the end of the run.
const WRECK_ICE_AT := 28.0
## The car is straightened again after the drift, so the rest of the demo runs straight.
const STRAIGHTEN_AT := 3.2
## The car is stopped before the wreck: a wrecked car does not drive away at 250 km/h.
const STOP_AT := 19.0
## The car is put back on the road after the second drift.
const DRIFT_STRAIGHTEN_AT := 16.9
## The car coasts from here on (a city street at 260 km/h is not a showcase).
const COAST_AT := 7.5
## The road dries before the skid: the tyre smoke of a dry road is the grey-blue puff of the
## brief, the wet one is the white spray mist.
const DRY_AT := 13.2
## The traffic car has passed: it is sent off down the road, so it does not stand in the frame
## of the later beats.
const TRAFFIC_LEAVES_AT := 14.0
## Before the second drift the car is slowed down to a speed a street can hold.
const SKID_SPEED_AT := 14.0

## The beats of the showcase.
const BEAT_NEAR_MISS := 9.0
const BEAT_HIT := 13.0
const BEAT_SCRAPE := 17.0
const BEAT_WRECK := 21.0
const BEAT_TAKEDOWN := 25.0

var _car: VehicleBase
var _traffic: VehicleBase
var _camera: Camera3D
var _beats: BEATS
var _t: float = 0.0
var _warmup: int = 0
var _fired: Array[bool] = []
## The camera preset of this run (--fxcam=chase|side|far|rear|front|top|ground).
var _cam_mode: StringName = &"chase"
var _assets: ASSETS = null
var _barrier: StaticBody3D = null
var _director_node: Node = null


func _ready() -> void:
	for i in 14:
		_fired.append(false)
	_cam_mode = _camera_mode_from_args()
	_assets = ASSETS.new()

	var world := SANDBOX.instantiate()
	world.name = "Sandbox"
	add_child(world)
	Game.world = world

	var environment := _assets.make_environment()
	add_child(environment)
	_assets.turn_on_rain(environment)

	_car = _assets.make_player_car()
	_car.name = "Roadster"
	add_child(_car)
	_assets.add_roadster_visual(_car)
	_car.global_position = START
	_car.team = VehicleBase.Team.PLAYER
	_car.display_name = "Roadster"
	Game.player = _car

	_traffic = _assets.make_traffic_car()
	if _traffic != null:
		add_child(_traffic)
		_assets.add_traffic_visual(_traffic)
		_traffic.global_position = START + Vector3(4.0, 0.0, 30.0)

	_barrier = WORLD.new().build(self)

	_beats = BEATS.new()
	_beats.name = "Beats"
	add_child(_beats)
	_beats.setup(_car, _traffic, _barrier)

	var director := DIRECTOR.instantiate()
	director.name = "FxDirector"
	add_child(director)
	_director_node = director

	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.fov = 62.0
	_camera.near = 0.05
	_camera.far = 900.0
	_camera.current = true
	add_child(_camera)

	Input.action_press(&"accelerate")
	# The real charge station of the sandbox fires the event when the car drives through it.
	Events.charge_started.connect(_on_charge_started)


func _process(delta: float) -> void:
	# The capture tool shoots after a warm-up of 20 frames; the demo starts its timeline there,
	# so the shot times and the beat times are the same clock.
	_warmup += 1
	if _warmup <= WARMUP_FRAMES:
		_update_camera()
		return
	_t += delta
	_update_camera()
	_print_telemetry()
	# The beats are spread out so that a capture sweep always contains every effect, whatever
	# the clock offset of the capture run is.
	_beat(0, BEAT_NEAR_MISS, _beats.near_miss)
	_beat(1, BEAT_HIT, _beats.hit)
	_beat(2, BEAT_SCRAPE, _beats.scrape)
	_beat(3, BEAT_WRECK, _beats.wreck)
	_beat(4, BEAT_TAKEDOWN, _beats.takedown)
	_beat(5, WRECK_ICE_AT, _beats.wreck_ice)
	_beat(6, STRAIGHTEN_AT, _beats.straighten)
	_beat(7, STOP_AT, _beats.stop)
	# The second drift slides the car to the side of the road: it is put back on it before the
	# scrape, so the scrape really grinds along the barrier.
	_beat(8, DRIFT_STRAIGHTEN_AT, _beats.straighten)
	_beat(9, COAST_AT, _beats.coast)
	_beat(10, SKID_SPEED_AT, _beats.skid_speed)
	_beat(11, DRY_AT, _beats.dry_road)
	_beat(12, TRAFFIC_LEAVES_AT, _beats.traffic_leaves)


## The telemetry of the car, so the captures can be timed on the real slip of the tyres.
func _print_telemetry() -> void:
	if _car == null or fmod(_t, 0.5) > 0.02:
		return
	var tel := _car.telemetry
	print("TELE t=%.1f kmh=%.0f slip=%.2f drift=%s grounded=%d" % [_t, tel.speed_kmh,
			tel.rear_slip, tel.drift_state, tel.grounded_wheels])


func _beat(index: int, at: float, action: Callable) -> void:
	if _t >= at and not _fired[index]:
		_fired[index] = true
		print("BEAT ", index, " at ", snappedf(_t, 0.01))
		action.call()


## The camera of the demo.
##
## The side cameras stand on the open side of the road: the guard rail is on the other side and
## it would hide the car. The top camera uses the direction of the car as its up vector, so the
## view is never straight down (the camera would be colinear with the up).
func _update_camera() -> void:
	if _camera == null or _car == null:
		return
	var basis := _car.global_transform.basis
	var origin := _car.global_position
	var forward := _car.get_forward()
	var target := origin + Vector3(0.0, 0.9, 0.0)
	var up := Vector3.UP
	match _cam_mode:
		&"side":
			# 7 m to the open side of the road, at the height of the roof line.
			_camera.global_position = origin + basis * Vector3(7.0, 1.4, 0.5)
		&"far":
			# 16 m away and 8 m up: the whole trail is in the frame.
			_camera.global_position = origin + basis * Vector3(16.0, 8.0, 6.0)
		&"rear":
			_camera.global_position = origin + basis * Vector3(0.0, 1.1, 4.5)
		&"front":
			# In front of the car, looking back at it.
			_camera.global_position = origin + basis * Vector3(0.5, 1.6, -8.0)
		&"top":
			# 9 m above the road, 6 m behind the car: the skid marks and the spray are read
			# from there.
			_camera.global_position = origin + Vector3.UP * 9.0 - forward * 6.0
			target = origin
			up = forward
		&"ground":
			# 2.2 m above the road, 5 m to the open side of the car, looking down at the
			# surface: the rain splashes are read from there.
			_camera.global_position = origin + basis * Vector3(5.0, 2.2, 4.0)
			target = origin + basis * Vector3(2.0, 0.0, 6.0)
		_:
			_camera.global_position = origin + basis * CHASE_OFFSET
	_camera.look_at(target, up)


## The camera preset of this run: --fxcam=chase|side|far|rear|front|top|ground.
func _camera_mode_from_args() -> StringName:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fxcam="):
			return StringName(arg.trim_prefix("--fxcam="))
	return &"chase"


## The real charge station of the sandbox: the flash happens when the car drives through the
## lane at 60 km/h. The demo only prints the time, so the captures can be timed.
func _on_charge_started(vehicle: VehicleBase, _station: Area3D) -> void:
	if vehicle == _car:
		print("CHARGE at ", snappedf(_t, 0.01))


## The car is driven with the real input, so the vehicle unit produces a real drift (and a real
## rear slip): the fx unit then reacts to the same telemetry the game uses.
##
## The telemetry itself is written by the vehicle unit in its physics tick, so the demo must not
## fake it: a faked rear_slip is overwritten before the fx rig reads it.
func _physics_process(delta: float) -> void:
	_drive_input()
	_beats.step(delta, _t)


## The throttle is always on; the drift key and the steering are only held inside the drift
## window, so the car really breaks the rear tyres loose.
func _drive_input() -> void:
	if _t >= STOP_AT:
		# The car stands still for the wreck beats.
		Input.action_release(&"accelerate")
		return
	if not _beats.throttle_on:
		Input.action_release(&"accelerate")
	else:
		Input.action_press(&"accelerate")
	for window: Array in DRIFT_WINDOWS:
		var start: float = window[0]
		var end: float = window[1]
		var counter_end: float = window[2]
		var dir: float = window[3]
		if _t >= start and _t < end:
			Input.action_press(&"drift")
			Input.action_press(&"steer_left" if dir < 0.0 else &"steer_right", STEER_PRESS)
			return
		if _t >= end and _t < counter_end:
			# counter-steer: the car straightens out again and stays on the road
			Input.action_press(&"steer_right" if dir < 0.0 else &"steer_left", STEER_PRESS)
			return
	Input.action_release(&"drift")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")

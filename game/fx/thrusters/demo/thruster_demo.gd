extends Node3D
## Demo for the cold-gas thruster plumes.
##
## Cycles the situations the game needs the plumes for: idle, hop burst, hover, landing cushion,
## N2 boost and barrel-roll yaw bursts. `--demo-phase=<name>` freezes the demo in one phase so a
## capture can be lined up with the reference photos.

const DemoCar := preload("res://fx/thrusters/demo/demo_car.gd")
const ThrusterSystem := preload("res://fx/thrusters/thruster_system.gd")
const NozzleTable := preload("res://fx/thrusters/lib/nozzle_table.gd")
const ROADSTER_GLB := "res://assets/cars/roadster/roadster.glb"
const STUB_CAR := "res://core/stubs/stub_car.tscn"

const CYCLE := 16.0
## The demo runs at the game's frame rate by default. The vapour emitters pin their own
## simulation to 60 fps, so --demo-fps changes how fast the demo itself runs, not the plume.
const DEFAULT_FPS := 60
## The held landing phase throws up a fresh puff every so often, so a still at any time shows
## one (review SHOULD-FIX 6).
const LANDING_PUFF_PERIOD := 1.0
## The N2 boost: 0 -> 27 m/s in one second.
const BOOST_ACCEL := 27.0
const BOOST_SPEED := 27.0
## Phase ids of the animated sequence.
const P_IDLE := 0
const P_HOP := 1
const P_FALL := 2
const P_LANDED := 3
const P_REST := 4
const P_HOVER := 5
const P_DROP := 6
const P_LANDED_HARD := 7
const P_REST2 := 8
const P_BOOST := 9
const P_ROLL := 10

var _car: VehicleBase
var _system: ThrusterSystem
var _camera: Camera3D
var _t: float = 0.0
var _held: String = ""
var _cam_preset: String = "chase"
var _phase_id: int = -1
var _lift: float = 0.0
var _rear: float = 0.0
var _yaw: float = 0.0
var _yaw_side: float = 1.0
var _cam_pos: Vector3 = Vector3(0, 2.0, 7.0)
## Seconds since the held landing phase last threw up a puff.
var _landing_age: float = 0.0

func _ready() -> void:
	# The game runs at 60 fps. The demo has to run at the game's rate to be representative.
	Engine.max_fps = int(Game.option("demo-fps", str(DEFAULT_FPS)))
	_held = Game.option("demo-phase")
	_cam_preset = Game.option("demo-cam", "chase")
	_camera = get_node_or_null(^"Camera") as Camera3D
	_build_car()
	_system = (load("res://fx/thrusters/thruster_system.tscn") as PackedScene).instantiate() as ThrusterSystem
	_system.name = "ThrusterSystem"
	add_child(_system)
	_system.attach(_car)
	Game.player = _car
	if Game.option("demo-fx") == "core":
		# The particles of the plumes live under the car (the vapour) and under the system
		# (the ground clouds), so both have to be hidden.
		for node in _car.find_children("", "GPUParticles3D", true, false):
			(node as Node3D).visible = false
		for node in _system.find_children("", "GPUParticles3D", true, false):
			(node as Node3D).visible = false


func _build_car() -> void:
	if Game.option("demo-car") == "stub":
		# The core stub car has no nozzle markers, so this exercises the dossier fallback.
		_car = (load(STUB_CAR) as PackedScene).instantiate() as VehicleBase
		_car.name = "StubCar"
		_car.freeze = true
		add_child(_car)
		return
	var car := DemoCar.new()
	car.name = "Roadster"
	var glb: PackedScene = null
	if ResourceLoader.exists(ROADSTER_GLB):
		glb = load(ROADSTER_GLB) as PackedScene
	if glb != null:
		car.build_body = false
		car.build_markers = false
	add_child(car)
	_car = car
	if glb != null:
		var instance := glb.instantiate()
		instance.name = "RoadsterModel"
		car.get_visual_root().add_child(instance)


func _process(delta: float) -> void:
	if _held.is_empty():
		_t = fmod(_t + delta, CYCLE)
		_apply_cycle(_t)
	else:
		_apply_held(_held)
	_write_telemetry()
	_update_camera(delta)


## The animated sequence.
func _apply_cycle(t: float) -> void:
	var pid: int = _phase_at(t)
	if pid != _phase_id:
		_phase_id = pid
		_on_phase(pid)
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	_lift = 0.0
	_rear = 0.0
	_yaw = 0.0
	match pid:
		P_HOP:
			_lift = 1.0
			pos.y = lerpf(0.0, 1.6, (t - 2.0) / 0.8)
		P_FALL:
			_lift = 0.85
			pos.y = lerpf(1.6, 0.15, (t - 2.8) / 0.8)
		P_HOVER:
			_lift = 0.5
			pos.y = 6.0
		P_DROP:
			_lift = 0.9
			pos.y = lerpf(6.0, 0.2, (t - 8.0) / 0.8)
		P_BOOST:
			_rear = 1.0
			# 0 -> 27 m/s in the first second, then steady (photo 29: a 12-13 m trail at t=1 s).
			var bt: float = t - 9.4
			pos.z = -(_boost_distance(bt))
		P_ROLL:
			_lift = 0.35
			_yaw = 1.0
			pos.y = 3.0
			rot.z = deg_to_rad(lerpf(0.0, 360.0, (t - 12.4) / 3.0))
	_car.global_position = pos
	_car.global_rotation = rot
	_yaw_side = 1.0 if fmod(t, 0.8) < 0.4 else -1.0


## Distance travelled by the boost: 0 -> 27 m/s in 1 s, then constant.
func _boost_distance(t: float) -> float:
	if t < 1.0:
		return 0.5 * BOOST_ACCEL * t * t
	return 0.5 * BOOST_ACCEL + BOOST_SPEED * (t - 1.0)


func _phase_at(t: float) -> int:
	if t < 2.0:
		return P_IDLE
	if t < 2.8:
		return P_HOP
	if t < 3.6:
		return P_FALL
	if t < 4.2:
		return P_LANDED
	if t < 4.8:
		return P_REST
	if t < 8.0:
		return P_HOVER
	if t < 8.8:
		return P_DROP
	if t < 9.4:
		return P_LANDED_HARD
	if t < 12.4:
		return P_BOOST
	if t < 15.4:
		return P_ROLL
	return P_REST2


func _on_phase(pid: int) -> void:
	if pid == P_LANDED:
		Events.landed.emit(_car, 1.1, 6.5, &"clean")
	elif pid == P_LANDED_HARD:
		Events.landed.emit(_car, 1.6, 12.0, &"clean")


## A frozen pose, used for the still captures that are lined up with the reference photos.
func _apply_held(name: String) -> void:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	_lift = 0.0
	_rear = 0.0
	_yaw = 0.0
	match name:
		"hop":
			pos.y = 1.6
			_lift = 1.0
		"hover":
			pos.y = 6.0
			_lift = 0.5
		"hover5":
			# 5 m: the lift nozzles are 5.15 m up, inside the 6 m reach, so the plume touches
			# the road (photo 27).
			pos.y = 5.0
			_lift = 0.5
		"landing":
			pos.y = 0.25
			_lift = 0.8
			_landing_age += get_process_delta_time()
			if _phase_id != P_LANDED or _landing_age >= LANDING_PUFF_PERIOD:
				_phase_id = P_LANDED
				_landing_age = 0.0
				Events.landed.emit(_car, 1.1, 8.0, &"clean")
		"boost":
			_rear = 1.0
		"roll":
			pos.y = 3.0
			rot.z = deg_to_rad(30.0)
			_yaw = 1.0
		"core":
			pos.y = 4.0
			_lift = 1.0
		"core_rear":
			# Only the rear nozzles, so the close-up shows the core without the down-plumes.
			pos.y = 2.5
			_rear = 1.0
	_car.global_position = pos
	_car.global_rotation = rot
	_yaw_side = 1.0


## Writes the per-nozzle throttle the plume system reads.
func _write_telemetry() -> void:
	for nozzle_name in NozzleTable.NAMES:
		var cfg: Dictionary = NozzleTable.get_nozzle(nozzle_name)
		var value := 0.0
		match String(cfg["group"]):
			NozzleTable.REAR:
				value = _rear
			NozzleTable.LIFT:
				value = _lift
			NozzleTable.YAW:
				value = _yaw if (nozzle_name == "Nozzle_P5") == (_yaw_side > 0.0) else 0.0
		_car.telemetry.thrusters[nozzle_name] = value


func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	var want: Vector3 = _car.global_position + Vector3(0.0, 1.9, 6.6)
	var look: Vector3 = _car.global_position + Vector3(0.0, 0.8, 0.0)
	match _cam_preset:
		"rear":
			want = _car.global_position + Vector3(0.0, 0.80, 7.5)
			look = _car.global_position + Vector3(0.0, 0.35, 0.0)
		"side":
			want = _car.global_position + Vector3(13.0, 1.0, 0.0)
			look = _car.global_position + Vector3(0.0, -2.6, 0.0)
		"overhead":
			want = _car.global_position + Vector3(0.0, 15.0, 10.0)
			look = _car.global_position + Vector3(0.0, 0.0, 4.0)
		"trail":
			want = _car.global_position + Vector3(7.0, 3.5, 9.0)
			look = _car.global_position + Vector3(0.0, 0.4, 3.0)
		"close":
			want = _car.global_position + Vector3(1.6, 0.35, 2.2)
			look = _car.global_position + Vector3(0.0, 0.1, 0.0)
		"nozzle":
			want = _car.global_position + Vector3(1.9, -0.25, -1.6)
			look = _car.global_position + Vector3(-0.5, -0.45, -1.9)
		"core":
			want = _car.global_position + Vector3(2.6, -0.9, -2.6)
			look = _car.global_position + Vector3(-0.2, -0.75, -1.7)
		"probe":
			want = _car.global_position + Vector3(-1.85, 0.12, -1.95)
			look = _car.global_position + Vector3(-0.57, -0.12, -1.95)
		"core_rear":
			# 1.5 m from the rear nozzles, so the shock diamonds fill the frame.
			want = _car.global_position + Vector3(-1.35, 0.62, 3.15)
			look = _car.global_position + Vector3(-0.2, 0.5, 2.15)
	_cam_pos = _cam_pos.lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	_camera.global_position = _cam_pos
	_camera.look_at(look)

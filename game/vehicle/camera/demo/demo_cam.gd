extends Node3D
## Capture rig for the camera unit: drives the demo car along the sandbox loop in the state
## named by `--demo=<state>` so every camera state can be captured deterministically.
## States: rest, speed, boost, drift, hop, flight, takedown.

const V_TOP := 69.44          # 250 km/h
const V_BOOST := 83.33         # 300 km/h
const ACCEL := 12.0           # m/s^2
const DRIFT_YAW := deg_to_rad(30.0)
const HOP_TIME := 1.12
const HOP_APEX := 3.1
const BOOST_TIME := 3.0        # s, the N2 lasts three seconds (dossier)
## The lamp posts along the demo lane: the strongest speed cue (dossier, speed-feel effects).
const POST_SPACING := 30.0     # m
const POST_OFFSET := 8.0       # m, either side of the lane
const POST_HEIGHT := 3.0       # m
const POST_WIDTH := 0.15       # m

@export var car_path: NodePath = ^"DemoCar"
@export var victim_path: NodePath = ^"Victim"

var _car: VehicleBase = null
var _victim: VehicleBase = null
var _curve: Curve3D = null
var _length: float = 0.0
var _progress: float = 0.0
var _speed: float = 0.0
var _t: float = 0.0
var _state: String = "speed"
var _boosted: bool = false
var _hop_start: float = -1.0
var _hopped: bool = false
var _drifting: bool = false
var _flying: bool = false
var _takedown_done: bool = false
var _takedown_at: float = -1.0
var _jitter: bool = false
var _jitter_samples: Array[Vector2] = []
var _jitter_reported: bool = false
var _boost_kind: StringName = &""
var _key_light: DirectionalLight3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_car = get_node_or_null(car_path) as VehicleBase
	_victim = get_node_or_null(victim_path) as VehicleBase
	_state = Game.option("demo", "speed")
	_jitter = Game.option("jitter") == "1"
	_takedown_at = float(Game.option("takedown_at", "-1.0"))
	Game.player = _car
	_add_lighting()
	var world := Game.world
	if world != null:
		var lanes := world.get_lane_paths()
		if not lanes.is_empty():
			_curve = lanes[0].curve
			_length = _curve.get_baked_length()
	if _victim != null:
		_victim.visible = _state == "takedown" or _takedown_at >= 0.0
		_victim.set_drive(Vector3(0.0, 0.0, 0.0), Vector3.FORWARD, Vector3.ZERO)
	_add_posts()
	_camera = get_node_or_null(^"ChaseCamera/Camera") as Camera3D


func _physics_process(delta: float) -> void:
	_t += delta
	if _curve == null or _car == null:
		return
	_update_scenario(delta)
	var pos := _curve.sample_baked(fmod(_progress, _length), true)
	var ahead := _curve.sample_baked(fmod(_progress + 6.0, _length), true)
	var tangent := (ahead - pos).normalized()
	var heading := tangent
	var height := 0.0
	if _drifting:
		heading = tangent.rotated(Vector3.UP, DRIFT_YAW)
	if _flying:
		height = 12.0
	if _hop_start >= 0.0:
		var k := (_t - _hop_start) / HOP_TIME
		if k < 1.0:
			height = HOP_APEX * 4.0 * k * (1.0 - k)
	_progress += _speed * delta
	_car.set_drive(pos + Vector3.UP * height, heading, tangent * _speed)
	_car.telemetry.drift_state = &"drift" if _drifting else &"grip"
	_car.telemetry.slip_angle_deg = 30.0 if _drifting else 0.0
	_car.telemetry.rear_slip = 0.8 if _drifting else 0.0
	_car.telemetry.airborne = height > 0.05
	_car.telemetry.altitude_m = height
	_car.telemetry.flying = _flying
	_car.telemetry.roll_deg = 22.0 if _flying else 0.0
	_car.telemetry.boost_kind = _boost_kind
	_update_victim(delta)
	_update_key_light()
	_measure_jitter()


## Screen-position jitter of the car over 10 consecutive frames (the camera unit's
## acceptance check: the car must not twitch in the frame at 120 Hz physics / 60 Hz render).
func _measure_jitter() -> void:
	if not _jitter or _car == null:
		return
	# Only measure in the steady state (the camera is still catching up in the first seconds).
	if _t < 6.0:
		return
	var camera := get_node_or_null(^"ChaseCamera/Camera") as Camera3D
	if camera == null:
		return
	var screen := camera.unproject_position(_car.global_position + Vector3.UP * 0.6)
	_jitter_samples.append(screen)
	if _jitter_samples.size() > 10:
		_jitter_samples.remove_at(0)
	if _jitter_samples.size() < 10 or _jitter_reported:
		return
	_jitter_reported = true
	var mean := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in _jitter_samples:
		mean += s
		lo = lo.min(s)
		hi = hi.max(s)
	mean /= float(_jitter_samples.size())
	var variance := Vector2.ZERO
	for s in _jitter_samples:
		variance += (s - mean).abs()
	variance /= float(_jitter_samples.size())
	print("JITTER frames=%d mean=(%.2f, %.2f) mean_abs_dev=(%.3f, %.3f) px spread=(%.3f, %.3f) px" % [
			_jitter_samples.size(), mean.x, mean.y, variance.x, variance.y, hi.x - lo.x, hi.y - lo.y])


func _update_scenario(delta: float) -> void:
	if _takedown_at >= 0.0 and _t > _takedown_at and not _takedown_done:
		_takedown_done = true
		Events.takedown.emit(_victim, &"police")
	match _state:
		"rest":
			_speed = 0.0
		"speed":
			_speed = minf(_speed + ACCEL * delta, V_TOP)
		"boost":
			if _t > 1.2 and not _boosted:
				_boosted = true
				Events.boost_started.emit(_car, &"nitro")
			if _boosted and _t <= 1.2 + BOOST_TIME:
				_speed = V_BOOST
				_boost_kind = &"nitro"
			else:
				_speed = minf(_speed, V_TOP)
				_boost_kind = &""
		"drift":
			_speed = minf(_speed + ACCEL * delta, 40.0)
			if _t > 1.2:
				_drifting = true
		"hop":
			_speed = minf(_speed + ACCEL * delta, 45.0)
			if _t > 1.2 and _hop_start < 0.0:
				_hop_start = _t
			if _hop_start >= 0.0 and not _hopped and _t > _hop_start + HOP_TIME:
				_hopped = true
				Events.landed.emit(_car, HOP_TIME, 11.0, &"clean")
		"flight":
			_speed = minf(_speed + ACCEL * delta, 55.0)
			if _t > 0.8 and not _flying:
				_flying = true
				Events.flight_changed.emit(_car, true, null)
		"takedown":
			_speed = minf(_speed + ACCEL * delta, 40.0)
			if _t > 1.0 and not _takedown_done:
				_takedown_done = true
				Events.takedown.emit(_victim, &"police")


func _update_victim(delta: float) -> void:
	if _victim == null:
		return
	if _state != "takedown" and not _takedown_done:
		return
	var pos := _curve.sample_baked(fmod(_progress + 22.0, _length), true)
	var ahead := _curve.sample_baked(fmod(_progress + 28.0, _length), true)
	var tangent := (ahead - pos).normalized()
	if _takedown_done:
		# The victim tumbles in the slow motion.
		_victim.rotate_object_local(Vector3.RIGHT, delta * 1.6)
		_victim.global_position += Vector3.UP * delta * 0.4
		_victim.linear_velocity = tangent * 12.0
		return
	_victim.set_drive(pos, tangent, tangent * 12.0)


## A key light from the camera side, so the Ano White Roadster reads as the brightest
## object in the frame (ART.md, value hierarchy).
func _update_key_light() -> void:
	if _key_light == null or _camera == null or _car == null:
		return
	var cam_pos := _camera.global_position
	var car_pos := _car.global_position
	if cam_pos.distance_to(car_pos) < 0.5:
		return
	_key_light.look_at_from_position(cam_pos, car_pos, Vector3.UP)


## Two rows of lamp posts along the lane: the strongest speed cue when the road rushes by.
func _add_posts() -> void:
	if _curve == null or _length <= 0.0:
		return
	var count := int(_length / POST_SPACING)
	for i in count:
		var t := float(i) * POST_SPACING
		var pos := _curve.sample_baked(fmod(t, _length), true)
		var ahead := _curve.sample_baked(fmod(t + 2.0, _length), true)
		var right := (ahead - pos).normalized().cross(Vector3.UP).normalized()
		for side in [-1.0, 1.0]:
			_add_post(pos + right * side * POST_OFFSET)


func _add_post(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(POST_WIDTH, POST_HEIGHT, POST_WIDTH)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.09, 0.10, 0.12)
	pole_mat.roughness = 0.6
	pole_mesh.material = pole_mat
	pole.mesh = pole_mesh
	pole.position = pos + Vector3.UP * POST_HEIGHT * 0.5
	add_child(pole)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.4, 0.12, 0.4)
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.85, 0.91, 1.0)
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.85, 0.91, 1.0)     # #D9E8FF
	cap_mat.emission_energy_multiplier = 4.0
	cap_mesh.material = cap_mat
	cap.mesh = cap_mesh
	cap.position = pos + Vector3.UP * POST_HEIGHT
	add_child(cap)


## Minimal night rig so the camera frames are judgeable: the environment unit owns the real
## sky, fog and street lighting in the game; this is only a stand-in for the capture rig.
func _add_lighting() -> void:
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.02, 0.025, 0.06)
	sky_material.sky_horizon_color = Color(0.10, 0.05, 0.16)
	sky_material.ground_horizon_color = Color(0.06, 0.04, 0.10)
	sky_material.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.56, 0.65, 1.0)
	moon.light_energy = 0.7
	moon.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	moon.shadow_enabled = true
	add_child(moon)
	# The key light follows the camera, so the car is always lit from the camera side.
	_key_light = DirectionalLight3D.new()
	_key_light.light_color = Color(0.85, 0.91, 1.0)   # #D9E8FF
	_key_light.light_energy = 0.6
	_key_light.shadow_enabled = true
	add_child(_key_light)

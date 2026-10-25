extends Node
## How smoothly the car and the camera move on the screen: the car drives a straight road at 100 km/h, and every drawn frame
## the probe writes down where the car and the camera were drawn (their interpolated transforms when the physics
## interpolation is on) and how long the frame was. A frame whose step is far from the mean step is a judder: with 60
## physics ticks a second and 120 frames, an object that is not interpolated moves every other frame.
##
##   windowed: Godot (no --headless) -s res://tools/test_host.gd -- --test=res://tools/smooth_probe.gd --stub=audio,menu,traffic,police,rivals
##   [--seconds=6] [--fps=0 (uncapped) | N] [--at=x,z,heading_deg] [--interp=0|1 (the physics interpolation off or on;
##   default: the project setting)]

const MAIN := "res://main.tscn"
const KMH := 100.0

var _car: VehicleBase = null
var _camera: Camera3D = null
var _rows: Array[Vector4] = []      ## per frame: delta, car step, camera step, gap between car and camera
var _last_car := Vector3.INF
var _last_cam := Vector3.INF
var _recording := false
var _direction := Vector3.FORWARD


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var fps := int(Game.option("fps", "0"))
	Engine.max_fps = fps
	if Game.has_option("interp"):
		get_tree().physics_interpolation = Game.option("interp") == "1"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	_car = Game.player
	_car.freeze = false
	var at := String(Game.option("at", "-2150,731,90")).split(",")
	var heading := float(at[2])
	_direction = Vector3(sin(deg_to_rad(heading)), 0.0, -cos(deg_to_rad(heading)))
	var start := Vector3(float(at[0]), 0.6, float(at[1]))
	_car.reset_to(Transform3D(Basis.looking_at(_direction, Vector3.UP), start))
	for i in 30:
		await get_tree().physics_frame
	Input.action_press(&"accelerate")
	for i in 60:
		_car.linear_velocity = _direction * (KMH / 3.6)
		await get_tree().physics_frame
	_camera = get_viewport().get_camera_3d()
	_recording = true
	var seconds := float(Game.option("seconds", "6"))
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await get_tree().process_frame
	_recording = false
	Input.action_release(&"accelerate")
	_report()
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	if _recording and _car != null:
		_car.linear_velocity = _direction * (KMH / 3.6)


func _process(delta: float) -> void:
	if not _recording or _car == null or _camera == null:
		return
	var car := _car.get_global_transform_interpolated().origin
	var cam := _camera.get_global_transform_interpolated().origin
	if _last_car != Vector3.INF:
		_rows.append(Vector4(delta, (car - _last_car).dot(_direction), (cam - _last_cam).dot(_direction), (car - cam).length()))
	_last_car = car
	_last_cam = cam


func _report() -> void:
	var n := _rows.size()
	if n < 20:
		print("SMOOTH too few frames (%d)" % n)
		return
	var deltas: Array[float] = []
	var car_speed: Array[float] = []
	var cam_speed: Array[float] = []
	var gaps: Array[float] = []
	for row in _rows:
		deltas.append(row.x)
		car_speed.append(row.y / maxf(row.x, 0.0001))
		cam_speed.append(row.z / maxf(row.x, 0.0001))
		gaps.append(row.w)
	print("SMOOTH physics %d Hz, interpolation %s, %d frames, frame %s" % [Engine.physics_ticks_per_second,
		get_tree().physics_interpolation, n, _stats(deltas, 1000.0, "ms")])
	print("SMOOTH car speed on screen %s, judder %s" % [_stats(car_speed, 3.6, "km/h"), _judder(car_speed)])
	print("SMOOTH camera speed %s, judder %s" % [_stats(cam_speed, 3.6, "km/h"), _judder(cam_speed)])
	var gap_steps: Array[float] = []
	for i in range(1, gaps.size()):
		gap_steps.append(absf(gaps[i] - gaps[i - 1]))
	print("SMOOTH the gap from the camera to the car: %s, frame to frame change %s" % [_stats(gaps, 1.0, "m"),
		_stats(gap_steps, 100.0, "cm")])


## median and spread of a list (scaled), as text.
func _stats(values: Array[float], scale: float, unit: String) -> String:
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in values:
		mean += v
	mean /= values.size()
	var variance := 0.0
	for v in values:
		variance += (v - mean) * (v - mean)
	var sd := sqrt(variance / values.size())
	return "median %.2f %s (p10 %.2f, p90 %.2f, sd %.2f)" % [sorted[sorted.size() / 2] * scale, unit,
		sorted[sorted.size() / 10] * scale, sorted[sorted.size() * 9 / 10] * scale, sd * scale]


## The share of frames whose speed on the screen is under half or over one and a half times the median.
func _judder(values: Array[float]) -> String:
	var sorted := values.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var bad := 0
	for v in values:
		if v < median * 0.5 or v > median * 1.5:
			bad += 1
	return "%.1f %% of the frames" % (100.0 * bad / values.size())

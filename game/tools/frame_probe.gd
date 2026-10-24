extends Node
## The frame probe: the whole game, the player car driven along the lanes of the city by a simple lane follower (throttle held,
## the wheel turned towards a point 25 m ahead on its lane), and every frame written down: its time, the physics steps it ran,
## the time of the process and of the physics callbacks, the draw calls. A diagnostic tool, not a test: it shows how even the
## frames are (a frame that runs three physics steps moves the car three times as far as one that runs one).
##
##   python tools/gd.py shot --scene=res://tools/frame_probe.tscn --out=fp --stub=menu --times=75 [--vsync=0] [--seconds=45]
##
## Options: seconds (45) the drive; vsync (1) 0 = vsync off (the headroom of the machine); start=x,z (the Bund) where it starts.
##
## Every frame is split: PHYSICS is the time from the start of the first physics tick of the frame to the process step (the ticks
## run back to back), REST is the rest of the frame (the process callbacks, the render, the wait for the GPU or the vsync). The
## viewport render time is measured on the CPU and on the GPU, and the cars report their own physics (cpu_usec per tick).

const MAIN := "res://main.tscn"
## The lane follower: how far ahead it aims (m) and how hard it turns.
const AIM_AHEAD := 25.0
const STEER_GAIN := 2.5
## A frame this long is a hitch (ms).
const HITCH_MS := 25.0

var _frames: Array[Dictionary] = []
## Per physics tick: the traffic director's costs (ms) and the cars; the synthesizers' cost (ms per frame).
var _ticks := 0
var _traffic_sum := {"tick": 0.0, "integrate": 0.0, "index": 0.0, "modes": 0.0, "cars": 0.0, "events": 0.0, "ring": 0.0}
var _traffic_peak := 0.0
var _car_count := 0
var _near_count := 0
var _synth_sum := 0.0
var _last_physics := 0
## The start of every physics tick of the running frame (usec), written by the tick clock (it runs before every other node).
var _tick_starts: PackedInt64Array = PackedInt64Array()
var _last_process_usec := 0
var _car_usec := 0.0
var _car_ticks := 0
var _driving := false
var _lane: LanePath = null
var _offset := 0.0


## The first node of every physics tick: it writes down when the tick starts.
class TickClock:
	extends Node
	var probe: Node = null

	func _ready() -> void:
		process_physics_priority = -1000000

	func _physics_process(_delta: float) -> void:
		probe.call(&"_tick_started", Time.get_ticks_usec())


func _ready() -> void:
	# the probe runs first in the process step: the time from the first tick of the frame to here is the physics of the frame
	process_priority = -1000000
	var clock := TickClock.new()
	clock.probe = self
	add_child(clock)
	_run.call_deferred()


func _tick_started(usec: int) -> void:
	_tick_starts.append(usec)


func _run() -> void:
	if String(Game.option("vsync", "1")) == "0":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(3.0).timeout
	var car := Game.player as ArcadeCar
	var start := String(Game.option("start", "-60,-300")).split(",")
	var at := Vector3(float(start[0]), 0.0, float(start[1]))
	car.freeze = false
	car.reset_to(Game.world.respawn_transform(at, Vector3.FORWARD))
	await get_tree().physics_frame
	_pick_lane(car)
	_last_physics = Engine.get_physics_frames()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_tick_starts.clear()
	_last_process_usec = Time.get_ticks_usec()
	_driving = true
	var seconds := float(Game.option("seconds", "45"))
	var started := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - started) / 1000.0 < seconds:
		await get_tree().process_frame
		_drive(car)
	_driving = false
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	_report()
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	if not _driving:
		return
	var director := get_tree().get_first_node_in_group(&"traffic_director")
	if director == null:
		return
	_ticks += 1
	_traffic_sum["tick"] += float(director.get("tick_last_ms"))
	_traffic_sum["integrate"] += float(director.get("physics_last_ms"))
	for key in ["index", "modes", "cars", "events", "ring"]:
		_traffic_sum[key] += float(director.get("cost_%s_ms" % key))
	_traffic_peak = maxf(_traffic_peak, float(director.get("tick_last_ms")))
	var cars: Array = director.get("cars")
	_car_count += cars.size()
	for vehicle in get_tree().get_nodes_in_group(&"vehicles"):
		if vehicle is ArcadeCar:
			_car_usec += float((vehicle as ArcadeCar).cpu_usec) + float((vehicle as ArcadeCar).frame_cpu_usec)
	_car_ticks += 1
	for car in cars:
		if int(car.get("mode")) == 1:
			_near_count += 1


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if not _driving:
		_tick_starts.clear()
		return
	var physics_usec := now - _tick_starts[0] if not _tick_starts.is_empty() else 0
	var frame_usec := now - _last_process_usec
	_last_process_usec = now
	_tick_starts.clear()
	var vp := get_viewport().get_viewport_rid()
	for synth in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if synth.get("cpu_ms") != null:
			_synth_sum += float(synth.get("cpu_ms"))
	var physics := Engine.get_physics_frames()
	_frames.append({
		"ms": delta * 1000.0,
		"steps": physics - _last_physics,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"frame_split": float(frame_usec) / 1000.0,
		"physics_split": float(physics_usec) / 1000.0,
		"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"render_gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"pos": Game.player.global_position if Game.player != null else Vector3.ZERO,
	})
	_last_physics = physics


## The lane follower: aims at a point AIM_AHEAD along its lane, takes the next lane at the end, starts again after a wreck.
func _drive(car: ArcadeCar) -> void:
	if car.is_wrecked or _lane == null:
		_pick_lane(car)
		return
	var curve := _lane.curve
	_offset = curve.get_closest_offset(car.global_position)
	var length := curve.get_baked_length()
	if _offset + AIM_AHEAD > length:
		var next := _next_lane()
		if next != null:
			_lane = next
			_offset = 0.0
			curve = _lane.curve
		else:
			_pick_lane(car)
			return
	var target := curve.sample_baked(minf(_offset + AIM_AHEAD, curve.get_baked_length()), true)
	var to_target := target - car.global_position
	var forward := car.get_forward()
	var side := car.global_transform.basis.x
	var angle := atan2(to_target.dot(side), to_target.dot(forward))
	var steer := clampf(angle * STEER_GAIN, -1.0, 1.0)
	Input.action_press(&"accelerate")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	if steer > 0.05:
		Input.action_press(&"steer_right", steer)
	elif steer < -0.05:
		Input.action_press(&"steer_left", -steer)


func _pick_lane(car: ArcadeCar) -> void:
	var best: LanePath = null
	var best_distance := INF
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null or lane.curve.get_baked_length() < 30.0:
			continue
		var p := lane.curve.sample_baked(lane.curve.get_closest_offset(car.global_position), true)
		var d := p.distance_to(car.global_position)
		if d < best_distance:
			best_distance = d
			best = lane
	_lane = best


func _next_lane() -> LanePath:
	if _lane == null or _lane.next_lanes.is_empty():
		return null
	var lanes: Array = Game.world.get_lane_paths()
	var pick := _lane.next_lanes[randi() % _lane.next_lanes.size()]
	if pick < 0 or pick >= lanes.size():
		return null
	return lanes[pick] as LanePath


func _report() -> void:
	var count := _frames.size()
	if count == 0:
		print("FRAMES none")
		return
	var times: Array[float] = []
	var steps := {}
	var hitches: Array[Dictionary] = []
	var total := 0.0
	for f in _frames:
		var ms := float(f["ms"])
		times.append(ms)
		total += ms
		var s := int(f["steps"])
		steps[s] = int(steps.get(s, 0)) + 1
		if ms > HITCH_MS:
			hitches.append(f)
	times.sort()
	var p50 := times[count / 2]
	var p99 := times[mini(count - 1, int(float(count) * 0.99))]
	var worst := times[count - 1]
	print("FRAMES %d frames in %.1f s: mean %.1f fps, median %.2f ms, p99 %.2f ms, worst %.2f ms, %d hitches over %.0f ms" % [
		count, total / 1000.0, float(count) / (total / 1000.0), p50, p99, worst, hitches.size(), HITCH_MS])
	var keys := steps.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += " %d steps: %d (%.1f %%)" % [k, steps[k], 100.0 * float(steps[k]) / float(count)]
	print("FRAMES physics steps per frame:%s" % line)
	var process_sum := 0.0
	var physics_sum := 0.0
	var draws_sum := 0.0
	for f in _frames:
		process_sum += float(f["process_ms"])
		physics_sum += float(f["physics_ms"])
		draws_sum += float(f["draws"])
	print("FRAMES mean process %.2f ms, mean physics callback %.2f ms, mean draw calls %.0f" % [process_sum / count,
		physics_sum / count, draws_sum / count])
	# the split of the frames (the first frames of the drive are left out: the probe starts in the middle of a frame)
	var split_frames := _frames.slice(5)
	var split_count := maxi(split_frames.size(), 1)
	var phys_split := 0.0
	var frame_split := 0.0
	var render_cpu := 0.0
	var render_gpu := 0.0
	var tick_count := 0
	for f in split_frames:
		phys_split += float(f["physics_split"])
		frame_split += float(f["frame_split"])
		render_cpu += float(f["render_cpu"])
		render_gpu += float(f["render_gpu"])
		tick_count += int(f["steps"])
	print("FRAMES split: frame %.2f ms = physics %.2f ms (%.2f ms per tick, %.2f ticks) + rest %.2f ms; viewport render cpu %.2f ms, gpu %.2f ms" % [
		frame_split / split_count, phys_split / split_count, phys_split / maxf(float(tick_count), 1.0),
		float(tick_count) / split_count, (frame_split - phys_split) / split_count, render_cpu / split_count,
		render_gpu / split_count])
	if _car_ticks > 0:
		print("FRAMES the cars (player, police, rivals) %.3f ms of physics per tick" % (_car_usec / float(_car_ticks) / 1000.0))
	if _ticks > 0:
		var parts := ""
		for key in _traffic_sum:
			parts += " %s %.2f" % [key, float(_traffic_sum[key]) / float(_ticks)]
		print("FRAMES traffic per physics tick (ms):%s; peak tick %.2f ms; %.1f cars on average, %.1f near" % [parts, _traffic_peak,
			float(_car_count) / float(_ticks), float(_near_count) / float(_ticks)])
	print("FRAMES synthesizers %.2f ms per frame (both, the average they report)" % (_synth_sum / float(count)))
	hitches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	for h in hitches.slice(0, 12):
		print("FRAMES hitch %.1f ms: %d steps, process %.1f ms, physics %.1f ms, draws %d at %s" % [float(h["ms"]), int(h["steps"]),
			float(h["process_ms"]), float(h["physics_ms"]), int(h["draws"]), str((h["pos"] as Vector3).snapped(Vector3.ONE))])

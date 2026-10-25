extends Node
## The frame probe: the whole game, the player car driven along the lanes of the city by a simple lane follower (throttle held,
## the wheel turned towards a point 25 m ahead on its lane), and every frame written down: its time, the physics steps it ran,
## the time of the process and of the physics callbacks, the draw calls. A diagnostic tool, not a test: it shows how even the
## frames are (a frame that runs three physics steps moves the car three times as far as one that runs one).
##
##   python tools/gd.py shot --scene=res://tools/frame_probe.tscn --out=fp --stub=menu --times=75 [--vsync=0] [--seconds=45]
##
## The car is driven in the physics tick and the lanes it takes are drawn from a seeded source: with --seed=N (the traffic and the
## police take it too) two runs are the same drive.
##
## Options: seconds (45) the drive; warm (0) seconds of driving before the record starts; heat (none) a pursuit at this heat
## from the start of the record; park (0) 1 = the car stands (the A/B
## turns are 2 s then: the same place for both); vsync (1) 0 = vsync off (the headroom of
## the machine); start=x,z (the Bund) where it starts; ab=<switch>: a paired comparison in one drive, the switch is off (A) and on
## (B) in turns of 4 s and the frames of the two are reported apart. Switches: traffic (the traffic thinks every tick / every second
## tick), police (the police dispatcher thinks every tick / every second tick), rate (the physics at 120 Hz / 60 Hz), occlusion (the occlusion culling on / off), hud (the HUD shown / hidden), shadows (the shadow of the sun on / off), probes
## (the wheel probes of the cars cast on their own as well / only when the car casts them), steps (up to 4 / 8 physics ticks a
## frame).
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
## The synthesizers (the players that report `cpu_ms`), looked up once: walking the tree of the city every frame cost the probe
## itself 20-30 ms a frame.
var _synths: Array[Node] = []
## The A/B turn of the frame (0 = A, 1 = B).
var _ab_turn := 0
## The physics profile: the units of the game (Main's children), their slot in the physics order and the time they took.
const SLOT_STEP := 1000
var _units: Array[Node] = []
var _unit_usec: PackedFloat64Array = PackedFloat64Array()
var _marks: PackedInt64Array = PackedInt64Array()
var _tick_end := 0
var _engine_usec := 0.0
var _engine_ticks := 0
var _scripts_usec := 0.0
var _scripts_ticks := 0
var _police_sum := 0
var _police_modules: Dictionary = {}
var _police_tick := 0.0
var _process_usec: PackedFloat64Array = PackedFloat64Array()
var _process_marks: PackedInt64Array = PackedInt64Array()
var _process_frames := 0
var _process_total := 0.0
var _car_ticks := 0
var _driving := false
## The car follows its lanes (the warm-up and the record).
var _steering := false
var _car: ArcadeCar = null
var _route := RandomNumberGenerator.new()
## The phases of a frame (usec): the start of the process step (the probe runs first in it), the start and the end of the draw of
## the rendering server; per frame the time of the process step, of the draw, and after the draw (the present, the wait).
var _proc_start := 0
var _draw_start := 0
var _draw_end := 0
var _phase_proc := 0.0
var _phase_draw := 0.0
var _phase_after := 0.0
var _phase_frames := 0
## The time of the probe's own physics callback (usec), and the wait before its driver looks for a lane again (s).
var _self_usec := 0.0
## The events of the drive: "<s> <what>" (the time from the start of the record).
var _events: Array[String] = []
var _record_start := 0


## Writes down an event of the drive with its time.
func _event(what: String) -> void:
	if _driving:
		_events.append("%.2f s %s" % [float(Time.get_ticks_usec() - _record_start) / 1000000.0, what])


## The phases of the last whole frame (ms): the process step, the draw, after the draw.
var _last_phases: Array = [0.0, 0.0, 0.0]
## The totals at the end of the last frame (usec): a hitch reports what its own ticks spent.
var _unit_prev: PackedFloat64Array = PackedFloat64Array()
var _engine_prev := 0.0
var _self_prev := 0.0
var _cars_prev := 0.0
var _traffic_integrate_prev := 0.0
var _pick_wait := 0.0
## --park=1: the car stands where it starts, the traffic drives round it.
var _parked := false
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


## A marker in the physics order: it writes down the time when the callbacks before it are done.
class Marker:
	extends Node
	var probe: Node = null
	var slot: int = 0

	func _physics_process(_delta: float) -> void:
		probe.call(&"_mark", slot, Time.get_ticks_usec())

	func _process(_delta: float) -> void:
		probe.call(&"_process_mark", slot, Time.get_ticks_usec())


func _ready() -> void:
	# the probe runs first in the process step: the time from the first tick of the frame to here is the physics of the frame
	process_priority = -1000000
	# its own physics callback runs after the last slot of the profile (its time is taken out of the engine part)
	process_physics_priority = 100000000
	var clock := TickClock.new()
	clock.probe = self
	add_child(clock)
	_run.call_deferred()


func _tick_started(usec: int) -> void:
	# the engine part of the last tick: from the end of its scene callbacks to the start of this one (the Jolt step, the force
	# integration of the bodies); only between two ticks of the same frame
	if _driving and _tick_end > 0 and not _tick_starts.is_empty():
		_engine_usec += float(usec - _tick_end)
		_engine_ticks += 1
	_tick_starts.append(usec)
	_marks.fill(usec)


## A marker of the process step: the units before `slot` are done with their _process.
func _process_mark(slot: int, usec: int) -> void:
	if slot == 0:
		_process_marks.fill(usec)
	elif slot <= _units.size() and _driving:
		_process_usec[slot - 1] += float(usec - _process_marks[slot - 1])
	_process_marks[slot] = usec
	if slot == _units.size() + 1 and _driving:
		_process_frames += 1
		_process_total += float(usec - _process_marks[0])


## A marker: the units before `slot` are done.
func _mark(slot: int, usec: int) -> void:
	if slot > 0 and slot <= _units.size() and _driving:
		_unit_usec[slot - 1] += float(usec - _marks[slot - 1])
	_marks[slot] = usec
	if slot == _units.size() + 1:
		_tick_end = usec
		if _driving and not _tick_starts.is_empty():
			_scripts_usec += float(usec - _tick_starts[_tick_starts.size() - 1])
			_scripts_ticks += 1


## Every unit's subtree gets its own physics priority, with a marker after it. The order of the callbacks within a tick changes,
## nothing else (the bodies move in the step after all of them).
func _set_priorities(main: Node) -> void:
	if _units.is_empty():
		for child in main.get_children():
			_units.append(child)
		_unit_usec.resize(_units.size())
		_unit_usec.fill(0.0)
		_process_usec.resize(_units.size())
		_process_usec.fill(0.0)
		_process_marks.resize(_units.size() + 2)
		_marks.resize(_units.size() + 2)
		for slot in _units.size() + 2:
			var marker := Marker.new()
			marker.probe = self
			marker.slot = slot
			marker.process_physics_priority = slot * SLOT_STEP + SLOT_STEP / 2 if slot > 0 else -SLOT_STEP * 10
			marker.process_priority = marker.process_physics_priority
			add_child(marker)
	for i in _units.size():
		if is_instance_valid(_units[i]):
			_prioritise(_units[i], (i + 1) * SLOT_STEP - SLOT_STEP / 4)
	# the nodes that join later (police units, debris, effects) get the slot of their unit as they come
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## A node joined the tree: it gets the slot of the unit it is under (a walk up its parents, not a pass over the tree).
func _on_node_added(node: Node) -> void:
	var up := node
	while up != null and up.get_parent() != null:
		var index := _units.find(up)
		if index >= 0:
			node.process_physics_priority = (index + 1) * SLOT_STEP - SLOT_STEP / 4
			node.process_priority = node.process_physics_priority
			return
		up = up.get_parent()


func _prioritise(node: Node, priority: int) -> void:
	node.process_physics_priority = priority
	node.process_priority = priority
	for child in node.get_children():
		_prioritise(child, priority)


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
	_car = car
	_route.seed = int(Game.option("seed", "1"))
	_parked = Game.option("park", "0") == "1"
	var start := String(Game.option("start", "-60,-300")).split(",")
	var at := Vector3(float(start[0]), 0.0, float(start[1]))
	car.freeze = false
	car.reset_to(Game.world.respawn_transform(at, Vector3.FORWARD))
	await get_tree().physics_frame
	_pick_lane(car)
	_last_physics = Engine.get_physics_frames()
	for synth in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if synth.get("cpu_ms") != null:
			_synths.append(synth)
	_set_priorities(main)
	Events.vehicle_wrecked.connect(func(vehicle: VehicleBase, _source: Node3D) -> void:
		_event("wrecked %s%s" % [vehicle.name, " (the player)" if vehicle == Game.player else ""]))
	Events.player_respawned.connect(func() -> void: _event("the player respawned"))
	Events.pursuit_state_changed.connect(func(state: StringName) -> void: _event("pursuit %s" % state))
	RenderingServer.frame_pre_draw.connect(func() -> void: _draw_start = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _draw_end = Time.get_ticks_usec())
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	TrafficCar.measure_cost = true
	var traffic_script: Script = load("res://ai/traffic/traffic_car.gd")
	for key in ["t_plan", "t_speed", "t_lane", "t_think", "t_move", "t_lamp"]:
		traffic_script.set(key, 0.0)
	traffic_script.set("t_calls", 0)
	var rigs := load("res://fx/fx_car_rig.gd")
	rigs.set("tier_changes", 0)
	rigs.set("tier_usec", 0.0)
	_tick_starts.clear()
	_last_process_usec = Time.get_ticks_usec()
	_driving = true
	var seconds := float(Game.option("seconds", "45"))
	# the warm-up: the car drives, nothing is recorded (the traffic fills its ring, the shaders of the route compile)
	var warm := float(Game.option("warm", "0"))
	_steering = true
	if warm > 0.0:
		_driving = false
		var warm_ticks := int(warm * float(Engine.physics_ticks_per_second))
		var warm_from := Engine.get_physics_frames()
		while Engine.get_physics_frames() - warm_from < warm_ticks:
			await get_tree().process_frame
		_driving = true
		_tick_starts.clear()
		_last_process_usec = Time.get_ticks_usec()
		_last_physics = Engine.get_physics_frames()
	# --heat=N: a pursuit at heat N runs from the start of the record (the police are on the road for the whole drive)
	if Game.has_option("heat"):
		var dispatcher := get_tree().get_first_node_in_group(&"police_director")
		if dispatcher != null:
			dispatcher.call(&"start_pursuit", int(Game.option("heat")))
	var started := Time.get_ticks_msec()
	_record_start = Time.get_ticks_usec()
	var ab := String(Game.option("ab", ""))
	var director := get_tree().get_first_node_in_group(&"traffic_director")
	while float(Time.get_ticks_msec() - started) / 1000.0 < seconds:
		await get_tree().process_frame
		if ab != "":
			var turn := int(float(Time.get_ticks_msec() - started) / (2000.0 if _parked else 4000.0)) % 2
			if turn != _ab_turn:
				_ab_switch(ab, turn == 1, director)
			_ab_turn = turn
	if ab != "":
		_ab_switch(ab, false, director)
	_driving = false
	_steering = false
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	_report()
	_report_profile()
	report_ab()
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	var self_start := Time.get_ticks_usec()
	_physics_body()
	if _driving:
		_self_usec += float(Time.get_ticks_usec() - self_start)


## The work of the probe in a tick (it runs after the last slot of the profile, and its time is taken out of the engine part).
func _physics_body() -> void:
	if _steering and _car != null and is_instance_valid(_car):
		_drive(_car)
	if not _driving:
		return
	var director := get_tree().get_first_node_in_group(&"traffic_director")
	if director == null:
		return
	_ticks += 1
	_car_count += (director.get("cars") as Array).size()
	# the loops over the vehicles every 4th tick (a sample of the ticks), whether the traffic thought in it or not
	if _ticks % 4 == 0:
		_sample_vehicles(director)
	if not bool(director.get("ran_this_tick")):
		return
	_traffic_sum["tick"] += float(director.get("tick_last_ms"))
	_traffic_sum["integrate"] += float(director.get("physics_last_ms"))
	for key in ["index", "modes", "cars", "events", "ring"]:
		_traffic_sum[key] += float(director.get("cost_%s_ms" % key))
	_traffic_peak = maxf(_traffic_peak, float(director.get("tick_last_ms")))


## The police units, the police dispatcher, the physics of the cars and the near traffic cars of this tick.
func _sample_vehicles(director: Node) -> void:
	var cars: Array = director.get("cars")
	_police_sum += get_tree().get_nodes_in_group(&"police").size()
	var police := get_tree().get_first_node_in_group(&"police_director")
	if police != null:
		var modules: Dictionary = police.get("module_ms")
		for key in modules:
			_police_modules[key] = float(_police_modules.get(key, 0.0)) + float(modules[key])
		_police_tick += float(police.get("tick_ms"))
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
	if _proc_start > 0 and _draw_start > _proc_start and _draw_end > _draw_start:
		# the last frame: its process step ran from _proc_start to the draw, the draw to _draw_end, then the present and the
		# wait until the physics of this frame started (or this process step, when it ran no tick)
		var next_start: int = _tick_starts[0] if not _tick_starts.is_empty() else now
		_phase_proc += float(_draw_start - _proc_start)
		_phase_draw += float(_draw_end - _draw_start)
		_phase_after += float(maxi(next_start - _draw_end, 0))
		_phase_frames += 1
		_last_phases = [float(_draw_start - _proc_start) / 1000.0, float(_draw_end - _draw_start) / 1000.0,
			float(maxi(next_start - _draw_end, 0)) / 1000.0]
	_proc_start = now
	var frame_usec := now - _last_process_usec
	_last_process_usec = now
	_tick_starts.clear()
	var vp := get_viewport().get_viewport_rid()
	for synth in _synths:
		if is_instance_valid(synth):
			_synth_sum += float(synth.get("cpu_ms"))
	var physics := Engine.get_physics_frames()
	var spent := _frame_spending(now) if frame_usec > int(HITCH_MS * 1000.0) else {}
	_unit_prev = _unit_usec.duplicate()
	_engine_prev = _engine_usec
	_self_prev = _self_usec
	_cars_prev = ArcadeCar.cpu_total_usec
	_traffic_integrate_prev = float(_traffic_sum["integrate"])
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
		"setup": RenderingServer.get_frame_setup_time_cpu(),
		"phases": _last_phases.duplicate(),
		"at": float(Time.get_ticks_usec() - _record_start) / 1000000.0,
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"ab": _ab_turn,
		"pos": Game.player.global_position if Game.player != null else Vector3.ZERO,
		"spent": spent,
	})
	_last_physics = physics


## What the ticks of the frame that ends `now` spent (ms): the callbacks of every unit that took 0.5 ms or more, the engine part
## (the Jolt steps and the force integration: the probe's own callback is taken out), the physics of the player, police and rival
## cars (their _integrate_forces, a part of the engine part) and of the near traffic cars; what was on the road at its end.
func _frame_spending(now: int) -> Dictionary:
	var spent := {}
	for i in mini(_units.size(), _unit_prev.size()):
		var ms := (_unit_usec[i] - _unit_prev[i]) / 1000.0
		if ms >= 0.5 and is_instance_valid(_units[i]):
			spent[String(_units[i].name)] = snappedf(ms, 0.1)
	var engine := _engine_usec - _engine_prev - (_self_usec - _self_prev)
	# the engine part of the last tick of the frame: from the end of its callbacks to this process step
	if _tick_end > 0 and not _tick_starts.is_empty() and _tick_end > _tick_starts[_tick_starts.size() - 1]:
		engine += float(now - _tick_end)
	spent["engine"] = snappedf(engine / 1000.0, 0.1)
	spent["cars"] = snappedf((ArcadeCar.cpu_total_usec - _cars_prev) / 1000.0, 0.1)
	spent["near traffic"] = snappedf(float(_traffic_sum["integrate"]) - _traffic_integrate_prev, 0.1)
	spent["police units"] = get_tree().get_nodes_in_group(&"police").size()
	var director := get_tree().get_first_node_in_group(&"traffic_director")
	if director != null:
		var near := 0
		for car in director.get("cars") as Array:
			if int(car.get("mode")) == 1:
				near += 1
		spent["near cars"] = near
	for unit in _units:
		if is_instance_valid(unit) and unit.has_method(&"debris_count"):
			spent["debris"] = int(unit.call(&"debris_count"))
	return spent


## The lane follower: aims at a point AIM_AHEAD along its lane, takes the next lane at the end, starts again after a wreck.
func _drive(car: ArcadeCar) -> void:
	if _parked:
		# --park=1: the car stands (an A/B of the render compares the same place: a drive moves through the city between turns)
		Input.action_release(&"accelerate")
		return
	if car.is_wrecked:
		# the crash cam and the respawn: nothing to steer (a lane search in every tick of a wreck walked the 11,724 lanes and cost
		# the drive tens of ms a tick)
		Input.action_release(&"accelerate")
		_lane = null
		return
	if _lane == null:
		_pick_wait -= 1.0 / float(Engine.physics_ticks_per_second)
		if _pick_wait > 0.0:
			return
		_pick_wait = 0.5
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
			# a dead end: the throttled search finds a lane again (it walks every lane of the city)
			_lane = null
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
	var pick := _lane.next_lanes[_route.randi() % _lane.next_lanes.size()]
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
	var setup := 0.0
	var objects := 0.0
	var primitives := 0.0
	for f in split_frames:
		setup += float(f["setup"])
		objects += float(f["objects"])
		primitives += float(f["primitives"])
	# the nodes with a physics callback that sit in no slot of the profile (they joined since the last pass), by script
	var strays := {}
	for node in get_tree().root.find_children("*", "", true, false):
		if node.is_physics_processing() and node.process_physics_priority == 0:
			var script := node.get_script() as Script
			var parent_name := String(node.get_parent().name) if node.get_parent() != null else "?"
			var key := (script.resource_path.get_file() if script != null else node.get_class()) + " under " + parent_name
			strays[key] = int(strays.get(key, 0)) + 1
	print("FRAMES physics callbacks outside the slots: %s" % str(strays))
	# the particle systems and the lights of the scene at the end of the drive
	var particles := get_tree().root.find_children("*", "GPUParticles3D", true, false)
	var emitting := 0
	for node in particles:
		if (node as GPUParticles3D).emitting:
			emitting += 1
	var lights := get_tree().root.find_children("*", "Light3D", true, false)
	var shadowed := 0
	var lit := 0
	for node in lights:
		var light := node as Light3D
		if light.is_visible_in_tree():
			lit += 1
			if light.shadow_enabled:
				shadowed += 1
	var decals := get_tree().root.find_children("*", "Decal", true, false)
	var decals_on := 0
	for node in decals:
		if (node as Decal).is_visible_in_tree():
			decals_on += 1
	print("FRAMES at the end: %d particle systems (%d emitting), %d lights shown (%d with shadows) of %d, %d decals shown of %d" % [
		particles.size(), emitting, lit, shadowed, lights.size(), decals_on, decals.size()])
	if _phase_frames > 0:
		print("FRAMES phases: the process step %.2f ms, the draw %.2f ms, after the draw %.2f ms (a frame)" % [
			_phase_proc / float(_phase_frames) / 1000.0, _phase_draw / float(_phase_frames) / 1000.0,
			_phase_after / float(_phase_frames) / 1000.0])
	print("FRAMES render setup %.2f ms, %.0f objects, %.0f primitives a frame; thread model %s" % [setup / split_count,
		objects / split_count, primitives / split_count, str(ProjectSettings.get_setting("rendering/driver/threads/thread_model"))])
	if _ticks > 0:
		var parts := ""
		for key in _traffic_sum:
			parts += " %s %.2f" % [key, float(_traffic_sum[key]) / float(_ticks)]
		print("FRAMES traffic per physics tick (ms):%s; peak tick %.2f ms; %.1f cars on average, %.1f near" % [parts, _traffic_peak,
			float(_car_count) / float(_ticks), float(_near_count) / float(_ticks)])
	print("FRAMES synthesizers %.2f ms per frame (both, the average they report)" % (_synth_sum / float(count)))
	hitches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	for h in hitches.slice(0, 12):
		# the physics of this frame, and the process step, the draw and the after-draw of the frame before it (that frame's
		# length decided how many ticks this one ran)
		var ph: Array = h.get("phases", [0.0, 0.0, 0.0])
		print("FRAMES hitch at %.2f s, %.1f ms: %d steps, physics %.1f ms; the frame before: process %.1f, draw %.1f, after %.1f ms; at %s" % [
			float(h.get("at", 0.0)), float(h["frame_split"]), int(h["steps"]), float(h["physics_split"]), float(ph[0]), float(ph[1]),
			float(ph[2]), str((h["pos"] as Vector3).snapped(Vector3.ONE))])
		print("FRAMES   its ticks spent (ms) %s" % str(h.get("spent", {})))
	for event_line in _events:
		print("FRAMES event ", event_line)


## The physics profile: the scene callbacks of every unit per tick, the engine part of a tick, the police on the road.
func _report_profile() -> void:
	if _scripts_ticks == 0:
		return
	var parts: Array[String] = []
	var order: Array[int] = []
	for i in _units.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _unit_usec[a] > _unit_usec[b])
	for i in order:
		parts.append("%s %.3f" % [_units[i].name if is_instance_valid(_units[i]) else "?", _unit_usec[i] / float(_scripts_ticks) / 1000.0])
	print("PROFILE scene callbacks %.3f ms per tick: %s" % [_scripts_usec / float(_scripts_ticks) / 1000.0, ", ".join(parts)])
	# the probe's own physics callback runs after the last slot: its time is in the engine part, it is taken out
	print("PROFILE engine part of a tick (step + force integration) %.3f ms over %d ticks; the probe itself %.3f ms a tick" % [
		maxf(_engine_usec - _self_usec, 0.0) / maxf(float(_engine_ticks), 1.0) / 1000.0, _engine_ticks,
		_self_usec / maxf(float(_ticks), 1.0) / 1000.0])
	print("PROFILE %.1f police units on average" % (float(_police_sum) / maxf(float(_car_ticks), 1.0)))
	var rig_script := load("res://fx/fx_car_rig.gd")
	var seconds := float(_ticks) / float(Engine.physics_ticks_per_second)
	print("PROFILE FX tiers: %.1f changes a second, %.3f ms a second in the changes" % [
		float(rig_script.get("tier_changes")) / maxf(seconds, 0.001), float(rig_script.get("tier_usec")) / 1000.0 / maxf(seconds, 0.001)])
	# the think of the traffic cars (traffic_car.gd keeps the sums: usec)
	var think_parts: Array[String] = []
	var traffic_script: Script = load("res://ai/traffic/traffic_car.gd")
	var calls := float(traffic_script.get("t_calls"))
	for key in ["t_plan", "t_speed", "t_lane", "t_think", "t_move", "t_lamp"]:
		think_parts.append("%s %.1f" % [key.trim_prefix("t_"), float(traffic_script.get(key)) / maxf(calls, 1.0)])
	print("PROFILE traffic cars that thought: %.1f a tick, us per car: %s" % [calls / maxf(float(_ticks), 1.0), ", ".join(think_parts)])
	var police_parts: Array[String] = []
	for key in _police_modules:
		police_parts.append("%s %.3f" % [key, float(_police_modules[key]) / maxf(float(_car_ticks), 1.0)])
	# sampled every 4th tick (_sample_vehicles)
	print("PROFILE police dispatcher %.3f ms per tick: %s" % [_police_tick / maxf(float(_car_ticks), 1.0), ", ".join(police_parts)])
	if _process_frames > 0:
		var proc_order: Array[int] = []
		for i in _units.size():
			proc_order.append(i)
		proc_order.sort_custom(func(a: int, b: int) -> bool: return _process_usec[a] > _process_usec[b])
		var proc_parts: Array[String] = []
		for i in proc_order:
			proc_parts.append("%s %.3f" % [_units[i].name if is_instance_valid(_units[i]) else "?",
				_process_usec[i] / float(_process_frames) / 1000.0])
		print("PROFILE process callbacks %.3f ms per frame: %s" % [_process_total / float(_process_frames) / 1000.0,
			", ".join(proc_parts)])


## Puts the switch of an A/B drive in its B state (`on`) or back.
func _ab_switch(ab: String, on: bool, director: Node) -> void:
	match ab:
		"traffic":
			if director != null:
				director.set("tick_period", 1 if not on else 2)
		"occlusion":
			get_viewport().use_occlusion_culling = not on
		"hud":
			for node in get_tree().root.find_children("Hud", "", true, false):
				if node is CanvasLayer:
					(node as CanvasLayer).visible = not on
				node.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		"shadows":
			for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				(node as DirectionalLight3D).shadow_enabled = not on
		"steps":
			# A: up to 4 physics ticks a frame (the project), B: up to 8 (the cap before 2026-10-25)
			Engine.max_physics_steps_per_frame = 8 if on else 4
		"police":
			# A: the police dispatcher thinks every tick, B: every second tick (the game)
			var dispatcher := get_tree().get_first_node_in_group(&"police_director")
			if dispatcher != null:
				dispatcher.set("tick_period", 2 if on else 1)
		"rate":
			# A: the physics at 120 Hz, B: at 60 Hz (the project since 2026-10-25); the traffic and the police think at 60 Hz in
			# both (every second tick of A, every tick of B)
			Engine.physics_ticks_per_second = 60 if on else 120
			if director != null:
				director.set("tick_period", 1 if on else 2)
			var dispatcher := get_tree().get_first_node_in_group(&"police_director")
			if dispatcher != null:
				dispatcher.set("tick_period", 1 if on else 2)
		"probes":
			# A: the wheel probes cast on their own as well (as before vehicle/modules/wheel.gd turned that off), B: they do not
			for vehicle in get_tree().get_nodes_in_group(&"vehicles"):
				for child in (vehicle as Node).get_children():
					if child is ShapeCast3D:
						(child as ShapeCast3D).enabled = not on
		_ when ab.begins_with("hudpart:"):
			# one part of the HUD, by the file of its script (hudpart:minimap_panel.gd): shown / hidden
			var file := ab.trim_prefix("hudpart:")
			for hud in get_tree().root.find_children("Hud", "", true, false):
				for node in hud.find_children("*", "Control", true, false):
					var script := node.get_script() as Script
					if script != null and script.resource_path.get_file() == file:
						(node as Control).visible = not on
		_ when ab.begins_with("hide:"):
			# the nodes of a group (hide:traffic = the traffic cars): shown / hidden
			for node in get_tree().get_nodes_in_group(StringName(ab.trim_prefix("hide:"))):
				if node is Node3D:
					(node as Node3D).visible = not on
		"trafficfx":
			# the particle systems of the traffic cars (the smoke, the spray of the wet road): shown / hidden
			for car in get_tree().get_nodes_in_group(&"traffic"):
				for node in (car as Node).find_children("*", "GPUParticles3D", true, false):
					(node as GPUParticles3D).visible = not on
		"trafficdecal":
			# the blob shadows of the traffic cars: shown / hidden
			for car in get_tree().get_nodes_in_group(&"traffic"):
				for node in (car as Node).find_children("*", "Decal", true, false):
					(node as Decal).visible = not on
		"trafficshadow":
			# the shadows of the traffic cars: cast / not cast
			for car in get_tree().get_nodes_in_group(&"traffic"):
				for mesh in (car as Node).find_children("*", "MeshInstance3D", true, false):
					(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on \
							else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"dialstatic", "dialdynamic":
			# one layer of the speed dial of the HUD (the static face, the dynamic arc): shown / hidden
			for hud in get_tree().root.find_children("Hud", "", true, false):
				for node in hud.find_children("*", "Control", true, false):
					var script := node.get_script() as Script
					if script != null and script.resource_path.get_file() == "speed_dial.gd":
						var layer := node.get("_static" if ab == "dialstatic" else "_dynamic") as Control
						if layer != null:
							layer.visible = not on


## The frames of the two turns of an A/B drive, apart: the mean frame, the physics per tick, the ticks per frame, the rest.
func report_ab() -> void:
	for turn in 2:
		var frames := _frames.slice(5).filter(func(f: Dictionary) -> bool: return int(f["ab"]) == turn)
		if frames.is_empty():
			continue
		var frame_sum := 0.0
		var physics_sum := 0.0
		var ticks := 0
		var times: Array[float] = []
		for f in frames:
			frame_sum += float(f["frame_split"])
			physics_sum += float(f["physics_split"])
			ticks += int(f["steps"])
			times.append(float(f["frame_split"]))
		times.sort()
		var n := float(frames.size())
		print("AB %s: %d frames, frame mean %.2f ms median %.2f p95 %.2f; physics %.2f ms per tick x %.2f; rest %.2f ms" % [
			"A (switch off)" if turn == 0 else "B (switch on)", frames.size(), frame_sum / n,
			times[times.size() / 2], times[int(float(times.size()) * 0.95)], physics_sum / maxf(float(ticks), 1.0),
			float(ticks) / n, (frame_sum - physics_sum) / n])

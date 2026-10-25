extends Node
## The sky lane flights of the city, flown hands-off: the car drives onto the launch pad of every lane at 160 km/h with a full
## tank, and every tick of the flight is written down: the turn of the heading, the pitch and the bank (in the world: a banked
## turn is a turn, not a pitch), the sideways, the vertical and the forward g the car takes, where along the lane the worst of
## them are, and how the flight ends (how far the car flies past the end of the lane). A diagnostic tool, not a test: the feel
## of a flight on rails is the shape of its path.
##   python tools/gd.py test res://tools/flight_probe.gd -- --timeout=600 --stub=audio,menu,hud,traffic,police,rivals [--lane=id]
## [--trace=FROM --trace_length=M] prints every tick of M metres from the offset FROM; run windowed (Godot without --headless,
## -s res://tools/test_host.gd -- --test=res://tools/flight_probe.gd ...) with --shots=300,345 --outdir=ABS it saves a
## screenshot when the car passes each offset.

const MAIN := "res://main.tscn"
const RUN_UP := 70.0
const ENTRY_KMH := 160.0
const MAX_SECONDS := 45.0
const G := 9.81

var _car: ArcadeCar = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	_car = Game.player as ArcadeCar
	_car.freeze = false
	var only := String(Game.option("lane", ""))
	var lanes: Array[SkyLane] = []
	_collect(Game.world, lanes)
	for lane: SkyLane in lanes:
		if only != "" and not String(lane.name).contains(only):
			continue
		await _fly(lane)
	get_tree().quit(0)


func _fly(lane: SkyLane) -> void:
	# behind the pad, facing along the start of the lane
	var start := lane.frame_at(0.0)
	var fwd := -start.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := start.origin - fwd * RUN_UP
	at.y = start.origin.y + 0.5
	_car.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), at))
	await get_tree().physics_frame
	_car.boost.n2 = 200.0
	_car.linear_velocity = fwd * (ENTRY_KMH / 3.6)
	Input.action_press(&"accelerate")
	var hz := Engine.physics_ticks_per_second
	var took_off := -1.0
	for i in hz * 4:
		await get_tree().physics_frame
		if _car.sky.flying:
			took_off = float(i) / hz
			break
	Input.action_release(&"accelerate")
	if took_off < 0.0:
		print("FLIGHT %s: no take-off (speed %.0f km/h at the pad, n2 %.0f)" % [lane.name, _car.telemetry.speed_kmh, _car.boost.n2])
		return
	var dt := 1.0 / hz
	var trace_from := float(Game.option("trace", "-1"))
	# --shots=300,345 --outdir=ABS: a screenshot when the car passes these offsets (a windowed run only)
	var shots: PackedFloat64Array = []
	for at_text in String(Game.option("shots", "")).split(",", false):
		shots.append(float(at_text))
	var outdir := String(Game.option("outdir", ""))
	var next_shot := 0
	var trace_length := float(Game.option("trace_length", "100"))
	var prev := _attitude(_car.global_transform.basis)
	var prev_velocity := _car.linear_velocity
	var keys := ["heading", "pitch", "bank", "roll", "side_g", "vert_g", "surge_g"]
	var peaks := {}
	for key: String in keys:
		peaks[key] = [0.0, 0.0]
	var seconds := 0.0
	var snaps := 0
	var ended := ""
	var top_speed := 0.0
	var low_speed := INF
	var past_end := -1.0
	var end_point := Vector3.ZERO
	for i in int(MAX_SECONDS * hz):
		await get_tree().physics_frame
		seconds += dt
		var basis := _car.global_transform.basis
		var velocity := _car.linear_velocity
		var now := _attitude(basis)
		var heading_rate := wrapf(now.x - prev.x, -180.0, 180.0) / dt
		var pitch_rate := (now.y - prev.y) / dt
		var roll_rate := (now.z - prev.z) / dt
		var accel := (velocity - prev_velocity) / dt
		var ahead := -basis.z
		var flat := Vector3(ahead.x, 0.0, ahead.z).normalized()
		var right := flat.cross(Vector3.UP)
		var values := {"heading": heading_rate, "pitch": pitch_rate, "bank": now.z, "roll": roll_rate,
			"side_g": accel.dot(right) / G, "vert_g": accel.y / G, "surge_g": accel.dot(ahead) / G}
		var offset: float = _car.sky.offset
		for key: String in keys:
			if absf(float(values[key])) > absf(float(peaks[key][0])):
				peaks[key] = [values[key], offset]
		if absf(heading_rate) > 90.0 or absf(pitch_rate) > 60.0 or absf(roll_rate) > 180.0:
			snaps += 1
		var kmh := velocity.length() * 3.6
		top_speed = maxf(top_speed, kmh)
		if not _car.sky.transitioning:
			low_speed = minf(low_speed, kmh)
		if past_end < 0.0 and _car.sky.offset >= lane.length():
			past_end = seconds
			end_point = _car.global_position
		prev = now
		prev_velocity = velocity
		if next_shot < shots.size() and offset >= shots[next_shot]:
			if outdir != "" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var image := get_viewport().get_texture().get_image()
				image.save_jpg("%s/flight_%s_%04d.jpg" % [outdir, String(lane.name).trim_prefix("SkyLane_"), int(shots[next_shot])], 0.85)
			next_shot += 1
		if trace_from >= 0.0 and offset >= trace_from and offset <= trace_from + trace_length:
			print("TRACE %6.1f m %5.1f m/s heading %6.1f deg/s bank %5.1f lateral %5.2f vertical %6.2f ground %7.2f car %s frame y %7.2f exiting %s gliding %s n2 %.0f" % [
				offset, _car.sky.speed, heading_rate, now.z, _car.sky.lateral, _car.sky.vertical, _car.readout.ground_y,
				str(_car.global_position.snapped(Vector3.ONE * 0.1)), _car.sky._frame_at(offset).origin.y, _car.sky.exiting,
				_car.sky.gliding, _car.boost.n2])
		if not _car.sky.flying:
			var beyond := 0.0 if past_end < 0.0 else _car.global_position.distance_to(end_point)
			ended = "landed after %.1f s at %s, %.2f s and %.0f m past the end of the lane" % [seconds,
				str(_car.global_position.snapped(Vector3.ONE)), 0.0 if past_end < 0.0 else seconds - past_end, beyond]
			break
	if ended == "":
		ended = "still flying after %.0f s (offset %.0f of %.0f m)" % [MAX_SECONDS, _car.sky.offset, lane.length()]
	print("FLIGHT %s (%.0f m): took off %.2f s after the run-up; %s; speed %.0f..%.0f km/h" % [lane.name, lane.length(), took_off,
		ended, low_speed, top_speed])
	print("FLIGHT   peaks: heading %.0f deg/s at %.0f m, pitch %.0f deg/s at %.0f m, bank %.0f deg at %.0f m, roll %.0f deg/s at %.0f m, side %.1f g at %.0f m, vertical %.1f g at %.0f m, surge %.1f g at %.0f m; ticks of a snap (heading > 90, pitch > 60 or roll > 180 deg/s): %d" % [
		peaks["heading"][0], peaks["heading"][1], peaks["pitch"][0], peaks["pitch"][1], peaks["bank"][0], peaks["bank"][1],
		peaks["roll"][0], peaks["roll"][1], peaks["side_g"][0], peaks["side_g"][1], peaks["vert_g"][0], peaks["vert_g"][1],
		peaks["surge_g"][0], peaks["surge_g"][1], snaps])
	await get_tree().create_timer(0.5).timeout


## The attitude of the car in the world (deg): the heading of its nose (clockwise from -Z), the pitch of its nose over the
## horizon and its bank (the right side down is positive).
func _attitude(basis: Basis) -> Vector3:
	var ahead := -basis.z
	var heading := rad_to_deg(atan2(ahead.x, -ahead.z))
	var pitch := rad_to_deg(asin(clampf(ahead.y, -1.0, 1.0)))
	var bank := rad_to_deg(asin(clampf(-basis.x.y, -1.0, 1.0)))
	return Vector3(heading, pitch, bank)


## Every SkyLane under a node (the world builds them under its SkyLanes group).
func _collect(node: Node, out: Array[SkyLane]) -> void:
	if node is SkyLane:
		out.append(node as SkyLane)
	for child in node.get_children():
		_collect(child, out)

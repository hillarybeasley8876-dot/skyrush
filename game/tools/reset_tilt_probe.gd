extends Node
## The reset (the R key) and the respawn after a wreck in the city, as the player meets them: the car is put in a state (driving
## fast, drifting, on two wheels, on its side, on its roof, in the air, with the nitro, a wreck that knocks a wheel off), R is
## pressed (the wreck respawns by itself), then the throttle is held and the nitro fired, and for 3 s every tick the roll of the
## body (a pitch on a ramp is not counted) and the lean of the drawn car against its body are written down. A diagnostic tool,
## not a test (damage/tests/test_respawn.gd checks the drawn car after a lost wheel).
##   python tools/gd.py test res://tools/reset_tilt_probe.gd -- --timeout=600 --stub=audio,menu,hud --seed=3 --places=6

const MAIN := "res://main.tscn"
## A tilt over this many degrees for longer than TILT_TIME after the reset is a car that does not stand on its wheels.
const TILT_DEG := 20.0
const TILT_TIME := 0.2
const AFTER := 3.0

var _car: ArcadeCar = null
var _rng := RandomNumberGenerator.new()
var _bad := 0
var _runs := 0
var _respawns := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	_car = Game.player as ArcadeCar
	_car.freeze = false
	_rng.seed = int(Game.option("seed", "3"))
	var places := int(Game.option("places", "6"))
	var placer: Object = Game.world.get("_placer")
	var lanes: Array[LanePath] = []
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve != null and lane.curve.get_baked_length() > 120.0 and not bool(lane.get_meta(&"connector", false)):
			lanes.append(lane)
	var scenarios := ["driving", "drift", "two_wheels", "side", "roof", "air", "nitro", "wreck"]
	Events.player_respawned.connect(func() -> void: _respawns += 1)
	for p in places:
		var lane: LanePath = lanes[_rng.randi() % lanes.size()]
		var start: Transform3D = placer.call("lane_transform", _car, lane, lane.curve.get_baked_length() * 0.3)
		for scenario: String in scenarios:
			await _one(scenario, start)
	print("RESET %d of %d resets left the car rolled over %.0f deg for more than %.1f s or drawn off its body" % [_bad, _runs, TILT_DEG,
		TILT_TIME])
	_release_all()
	get_tree().quit(0)


## Puts the car in the state of `scenario` at `start`, presses R, drives 3 s and reports the tilt.
func _one(scenario: String, start: Transform3D) -> void:
	_release_all()
	var fwd := -start.basis.z
	var xform := start
	xform.origin += Vector3.UP * 0.1
	match scenario:
		"two_wheels":
			xform = Transform3D(Basis(fwd, deg_to_rad(40.0)) * start.basis, start.origin + Vector3.UP * 0.6)
		"side":
			xform = Transform3D(Basis(fwd, deg_to_rad(90.0)) * start.basis, start.origin + Vector3.UP * 1.0)
		"roof":
			xform = Transform3D(Basis(fwd, deg_to_rad(180.0)) * start.basis, start.origin + Vector3.UP * 1.5)
	_car.reset_to(xform)
	await get_tree().physics_frame
	match scenario:
		"driving", "nitro":
			_car.linear_velocity = fwd * (150.0 / 3.6)
			Input.action_press(&"accelerate")
			if scenario == "nitro":
				_car.boost.n2 = 200.0
				await _tap(&"nitro")
			await _ticks(0.8)
		"drift":
			_car.linear_velocity = fwd * (120.0 / 3.6)
			Input.action_press(&"accelerate")
			Input.action_press(&"steer_right")
			Input.action_press(&"drift")
			await _ticks(1.0)
		"two_wheels":
			_car.linear_velocity = fwd * (60.0 / 3.6)
			await _ticks(0.25)
		"side", "roof":
			await _ticks(1.0)
		"air":
			_car.linear_velocity = fwd * (100.0 / 3.6)
			_car.boost.n2 = 200.0
			Input.action_press(&"hop")
			await _ticks(0.4)
			Input.action_release(&"hop")
			await _ticks(0.3)
	var before_up := _car.global_transform.basis.y
	var before_tilt := rad_to_deg(acos(clampf(before_up.dot(Vector3.UP), -1.0, 1.0)))
	_release_all()
	if scenario == "wreck":
		# a head-on into a wall of a hurt car: the wreck flow (the crash cam, the slow motion) respawns it by itself
		var wall := StaticBody3D.new()
		add_child(wall)
		wall.global_position = _car.global_position + fwd * 12.0
		_car.health = 30.0
		_car.linear_velocity = fwd * 40.0
		# the damage unit takes the speed of the car before the step of the hit: two ticks at speed first
		await get_tree().physics_frame
		await get_tree().physics_frame
		var seen := _respawns
		Events.vehicle_collided.emit(_car, wall, 1900.0 * 40.0, _car.global_position + fwd * 2.2 + Vector3.UP * 0.6, -fwd)
		await _ticks(0.1)
		var visual_lean := rad_to_deg(acos(clampf(_car.get_visual_root().global_transform.basis.y.dot(_car.global_transform.basis.y), -1.0, 1.0)))
		print("RESET wreck: wrecked %s, the visual leans %.1f deg on the body before the respawn" % [str(_car.is_wrecked), visual_lean])
		var waited := 0.0
		while _respawns == seen and waited < 8.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		wall.queue_free()
	else:
		# R, as the player presses it: the car reads it in its tick
		await _tap(&"reset_car")
	var reset_up := _car.global_transform.basis.y
	var first_spin := _car.angular_velocity
	# then the throttle, and the nitro after half a second (the screenshot of the player: NITRO BOOST after a reset)
	Input.action_press(&"accelerate")
	_car.boost.n2 = 200.0
	var hz := Engine.physics_ticks_per_second
	var worst := 0.0
	var over := 0.0
	var longest_over := 0.0
	var off_wheels := 0.0
	var worst_at := Vector3.ZERO
	var spin_peak := 0.0
	var visual_peak := 0.0
	for i in int(AFTER * hz):
		if i == hz / 2:
			Input.action_press(&"nitro")
		elif i == hz / 2 + 1:
			Input.action_release(&"nitro")
		await get_tree().physics_frame
		# the roll: how far the right axis of the car leans out of the horizontal (a ramp pitches the car, it does not roll it)
		var tilt := rad_to_deg(absf(asin(clampf(_car.global_transform.basis.x.y, -1.0, 1.0))))
		spin_peak = maxf(spin_peak, Vector2(_car.angular_velocity.x, _car.angular_velocity.z).length())
		# the drawn car against its body (a lean of the visual that the body does not have)
		# (a wrecked car leans on the hub of a lost wheel on purpose, until its respawn)
		if not _car.is_wrecked:
			var visual_up := _car.get_visual_root().global_transform.basis.y
			visual_peak = maxf(visual_peak, rad_to_deg(acos(clampf(visual_up.dot(_car.global_transform.basis.y), -1.0, 1.0))))
		if float(i) / hz < 0.2:
			continue
		if tilt > worst:
			worst = tilt
			worst_at = _car.global_position
		if tilt > TILT_DEG:
			over += 1.0 / hz
			longest_over = maxf(longest_over, over)
		else:
			over = 0.0
		if _car.telemetry.grounded_wheels < 3:
			off_wheels += 1.0 / hz
	_runs += 1
	var bad := longest_over > TILT_TIME or visual_peak > 2.0
	if bad:
		_bad += 1
	print("RESET %-10s %s before %.0f deg | after the reset: up %s, roll/pitch spin %.2f rad/s | 3 s: worst roll %.1f deg at %s, over %.0f deg for %.2f s, fewer than 3 wheels %.2f s, roll/pitch spin peak %.2f rad/s, the drawn car off its body %.1f deg, wrecked %s" % [
		scenario, "BAD " if bad else "ok  ", before_tilt, str(reset_up.snapped(Vector3.ONE * 0.01)),
		Vector2(first_spin.x, first_spin.z).length(), worst, str(worst_at.snapped(Vector3.ONE)), TILT_DEG, longest_over, off_wheels,
		spin_peak, visual_peak, str(_car.is_wrecked)])
	_release_all()
	await _ticks(0.2)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _ticks(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _release_all() -> void:
	for action: StringName in [&"accelerate", &"brake", &"steer_left", &"steer_right", &"drift", &"nitro", &"hop", &"reset_car"]:
		Input.action_release(action)

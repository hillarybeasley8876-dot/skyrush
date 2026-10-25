extends Node
## The camera unit's scene tests: the follow, the wall pull-in, the drift rate, the flight
## bank, the look-at point, the player swap, the shake and the momentum.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const CameraPresets := preload("res://vehicle/camera/camera_presets.gd")
const Report := preload("res://vehicle/camera/tests/camera_test_report.gd")
const Helpers := preload("res://vehicle/camera/tests/camera_test_helpers.gd")

const CHASE_SPEED := 20.0        ## m/s, the speed the follow test drives at
const TOP_SPEED := 69.44         ## m/s, 250 km/h

var _report: Report = null
var _helpers := Helpers.new()


func run(host: Node, report: Report) -> void:
	_report = report
	await _test_follow(host)
	await _test_reverse(host)
	await _test_walls(host)
	await _test_drift(host)
	await _test_bank(host)
	await _test_look_at(host)
	await _test_player_swap(host)
	await _test_shake(host)
	await _test_momentum(host)


## The camera's heading, in degrees.
func _heading(cam: Camera3D) -> float:
	var forward := -cam.global_transform.basis.z
	return rad_to_deg(atan2(-forward.x, -forward.z))


## The camera's elevation, in degrees.
func _elevation(cam: Camera3D) -> float:
	var forward := -cam.global_transform.basis.z
	return rad_to_deg(atan2(forward.y, Vector2(forward.x, forward.z).length()))


## The camera's internal state (see the camera's get_debug_state).
func _state() -> Dictionary:
	return _helpers.cam_root.call("get_debug_state") as Dictionary


func _test_follow(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, 2)
	var car := _helpers.car
	for i in Engine.physics_ticks_per_second * 2:
		car.global_position += Vector3(0, 0, -CHASE_SPEED) / Engine.physics_ticks_per_second
		car.linear_velocity = Vector3(0, 0, -CHASE_SPEED)
		car.telemetry.speed_kmh = CHASE_SPEED * 3.6
		await host.get_tree().physics_frame
	var cam_pos := _helpers.cam.global_position
	var car_pos := car.global_position
	_report.check("the camera is behind the car", cam_pos.z > car_pos.z, str(cam_pos))
	var expected := CameraMath.DIST_REST + CameraMath.DIST_TOP_BONUS * (72.0 / CameraMath.TOP_SPEED_KMH)
	_report.near("the camera keeps the dossier distance",
			_helpers.flat_distance(cam_pos, car_pos), expected, 0.4)
	_report.near("the camera height", cam_pos.y - car_pos.y, CameraMath.HEIGHT_REST, 0.4)
	_report.near("the fov ramp", _helpers.cam.fov, CameraMath.FOV_BASE + CameraMath.FOV_PER_MPS * CHASE_SPEED, 0.2)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


## A reversing car is followed from behind its nose. The camera looked along the velocity, so it swung round in front of a
## reversing car, and a straight reverse sat on the 180 degree seam of the nose bias: every touch of the steering threw the
## target from one side of the car to the other (126 degrees, about 7 degrees a tick).
func _test_reverse(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	var car := _helpers.car
	var reverse_speed := 8.0
	var in_front := 0
	var worst_step := 0.0
	var previous := _heading(_helpers.cam)
	for i in Engine.physics_ticks_per_second * 3:
		# a straight reverse with the wobble of a hand on the wheel: the velocity swings 1.5 degrees to either side of the tail
		var wobble := deg_to_rad(1.5) * sin(float(i) * 0.4)
		var velocity := Vector3(sin(wobble), 0.0, cos(wobble)) * reverse_speed
		car.global_position += velocity / Engine.physics_ticks_per_second
		car.linear_velocity = velocity
		car.telemetry.speed_kmh = reverse_speed * 3.6
		car.telemetry.forward_speed_kmh = -reverse_speed * 3.6
		await host.get_tree().physics_frame
		var heading := _heading(_helpers.cam)
		worst_step = maxf(worst_step, absf(wrapf(heading - previous, -180.0, 180.0)))
		previous = heading
		if _helpers.cam.global_position.z <= car.global_position.z:
			in_front += 1
	_report.check("reverse: the camera stays behind the car", in_front == 0, "%d ticks in front of the car" % in_front)
	_report.check("reverse: the camera does not swing", worst_step < 1.0, "largest step %.2f degrees a tick" % worst_step)
	_report.near("reverse: the camera looks along the nose", _heading(_helpers.cam), 0.0, 3.0)
	car.linear_velocity = Vector3.ZERO
	car.telemetry.speed_kmh = 0.0
	car.telemetry.forward_speed_kmh = 0.0
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_walls(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	# A: the car spins out with a wall 2.25 m in front of it.
	var wall := _helpers.box(host, Vector3(30, 6, 0.5), Vector3(0, 3, -2.5))
	await _helpers.tick(host, 2)
	_helpers.car.rotation.y = PI
	var inside := 0
	var worst := INF
	for i in Engine.physics_ticks_per_second * 3 / 2:
		await host.get_tree().physics_frame
		var clearance := _helpers.cam.global_position.z + 2.25
		worst = minf(worst, clearance)
		if clearance < 0.25:
			inside += 1
	_report.check("spin out: the camera never enters the wall", inside == 0,
			"%d ticks inside, worst clearance %.3f" % [inside, worst])
	wall.queue_free()
	# B: the car respawns with its back to a wall.
	_helpers.car.rotation.y = 0
	_helpers.car.global_position = Vector3(0, 0, 100)
	await _helpers.tick(host, Engine.physics_ticks_per_second * 2)
	var back_wall := _helpers.box(host, Vector3(30, 6, 0.5), Vector3(0, 3, 102.5))
	Events.player_respawned.emit()
	var behind := 0
	var depth := -INF
	for i in Engine.physics_ticks_per_second / 3:
		await host.get_tree().physics_frame
		var d := _helpers.cam.global_position.z - 102.25
		depth = maxf(depth, d)
		if d > -0.25:
			behind += 1
	_report.check("respawn: the camera is in front of the wall from the first tick", behind == 0,
			"%d ticks behind, worst depth %.3f" % [behind, depth])
	back_wall.queue_free()
	await _helpers.tick(host, Engine.physics_ticks_per_second * 2)
	# C: a wall behind the car pulls the camera in.
	var close_wall := _helpers.box(host, Vector3(30, 6, 0.5), Vector3(0, 3, 2.0))
	_helpers.car.global_position = Vector3.ZERO
	_helpers.car.linear_velocity = Vector3.ZERO
	_helpers.car.telemetry.speed_kmh = 0
	await _helpers.tick(host, Engine.physics_ticks_per_second * 3 / 2)
	_report.check("a wall behind the car pulls the camera in",
			_helpers.cam.global_position.z < 1.75 - 0.25, str(_helpers.cam.global_position))
	close_wall.queue_free()
	await host.get_tree().physics_frame
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_drift(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	_helpers.car.telemetry.slip_angle_deg = -30.0
	_helpers.car.telemetry.drift_state = &"grip"
	var worst_step := 0.0
	var previous := float(_state()["yaw_lambda"])
	for i in Engine.physics_ticks_per_second * 3 / 4:
		await host.get_tree().physics_frame
		var current := float(_state()["yaw_lambda"])
		worst_step = maxf(worst_step, absf(current - previous))
		previous = current
	_report.near("a left slide reaches the drift yaw rate", previous, CameraMath.YAW_LAMBDA_DRIFT, 0.1)
	_report.check("the yaw rate never jumps", worst_step <= 0.2, "max step %.4f" % worst_step)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_bank(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	_helpers.car.telemetry.flying = true
	var previous := 0.0
	var worst_step := 0.0
	for i in Engine.physics_ticks_per_second * 7 / 10:
		_helpers.car.telemetry.roll_deg = 360.0 * float(i) / 84.0
		await host.get_tree().physics_frame
		var bank := float(_state()["bank"])
		worst_step = maxf(worst_step, absf(bank - previous))
		previous = bank
	_report.check("the flight bank never jumps", worst_step <= 1.0, "max step %.3f deg" % worst_step)
	_helpers.car.telemetry.flying = false
	_helpers.car.telemetry.roll_deg = 0.0
	await _helpers.tick(host, 2)
	var after_exit := float(_state()["bank"])
	_report.check("the bank fades out when the flight ends", absf(after_exit - previous) < 1.0,
			"bank %.3f" % after_exit)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_look_at(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	_helpers.car.linear_velocity = Vector3(-10, 0, -17.3)
	_helpers.car.telemetry.speed_kmh = 60.0
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	var look := _state()["look_point"] as Vector3
	var to_look := (look - _helpers.cam.global_position).normalized()
	var forward := -_helpers.cam.global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_look))
	_report.check("the camera aims at the look-at point", angle <= 0.1, "%.4f deg" % angle)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_player_swap(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	var second := _helpers.new_car(host, Vector3(0, 0, 400), Vector3.ZERO)
	Game.player = second
	Events.player_respawned.emit()
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	var distance := _helpers.cam.global_position.distance_to(second.global_position)
	_report.check("the camera follows a new player car", distance <= 8.0, "%.1f m" % distance)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_shake(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	var previous := _helpers.cam.global_position
	var moves: Array[float] = []
	Events.camera_shake.emit(0.15, 0.25)
	for i in Engine.physics_ticks_per_second / 3:
		await host.get_tree().physics_frame
		moves.append(_helpers.cam.global_position.distance_to(previous))
		previous = _helpers.cam.global_position
	var tail := 0.0
	for i in range(moves.size() - 3, moves.size()):
		tail = maxf(tail, moves[i])
	_report.check("the shake fades out without a pop", tail <= 0.01, "last move %.4f m" % tail)
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	var rest := _elevation(_helpers.cam)
	var rest_yaw := _heading(_helpers.cam)
	Events.camera_shake.emit(0.15, 0.25)
	for i in Engine.physics_ticks_per_second / 6:
		await host.get_tree().physics_frame
		pitch = maxf(pitch, absf(_elevation(_helpers.cam) - rest))
		yaw = maxf(yaw, absf(_heading(_helpers.cam) - rest_yaw))
		roll = maxf(roll, absf(_helpers.cam.global_transform.basis.x.y))
	_report.check("the shake tilts the camera", pitch >= 0.5, "%.4f deg" % pitch)
	_report.check("the shake turns the camera", yaw >= 0.3, "%.4f deg" % yaw)
	_report.check("the shake never rolls the camera", roll <= 0.0001, "%.6f" % roll)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_momentum(host: Node) -> void:
	_helpers.setup(host)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	var car := _helpers.car
	car.linear_velocity = Vector3(0, 0, -TOP_SPEED)
	car.telemetry.speed_kmh = 250.0
	await _helpers.tick(host, Engine.physics_ticks_per_second * 2)
	var before := _helpers.flat_distance(_helpers.cam.global_position, car.global_position)
	car.linear_velocity = Vector3.ZERO
	car.telemetry.speed_kmh = 0
	var closest := before
	for i in Engine.physics_ticks_per_second * 3 / 10:
		await host.get_tree().physics_frame
		closest = minf(closest, _helpers.flat_distance(_helpers.cam.global_position, car.global_position))
	_report.check("an instant stop pulls the camera in", before - closest >= 1.0,
			"%.3f m" % (before - closest))
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	var after := _helpers.flat_distance(_helpers.cam.global_position, car.global_position)
	_report.near("the camera returns to the dossier distance", after, CameraMath.DIST_REST, 0.4)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame

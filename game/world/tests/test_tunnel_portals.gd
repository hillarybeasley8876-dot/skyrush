extends Node
## The ramps of the Yan'an tunnel are open (world/build/tunnel_trench.gd). The ground lay over both of them: from Pudong a car drove
## over the portal on the flat ground (it never went down), and a car that came up the Puxi ramp stopped dead at the edge of the
## ground (tools/tunnel_probe.gd). Checks: the road of the ramp is under the ground no more; a car drives down into the tunnel from
## both ends and comes up out of it without stopping; a car that drives at the tube from the side meets its wall and does not fall
## into the ramp.
## Run: python tools/gd.py test res://world/tests/test_tunnel_portals.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
## The four lanes of the tunnel: the westbound ones go down in Pudong and come up in Puxi, the eastbound ones the other way.
const WEST_LANE := "yanan_tunnel"
## A car that is in the tunnel is this far under the ground (m).
const DOWN := -4.0
## A car that drives keeps at least this speed (m/s, 25 km/h) after its first seconds.
const MIN_SPEED := 7.0
## m/s (90 km/h): the speed the follower keeps.
const DRIVE_SPEED := 25.0

var _failures: int = 0
var _car: ArcadeCar = null
var _lane: LanePath = null


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _run() -> void:
	# the title menu holds the car (frozen, the input locked) when it is not stubbed (the suite runs every unit): the test starts
	# the game as --skip-menu does
	Game.options["skip-menu"] = "true"
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	_car = Game.player as ArcadeCar
	_car.freeze = false
	# the test drives the ramps, not the traffic: the suite runs every unit, and a traffic car in a lane of the tunnel or a police
	# unit that chased the car stopped a drive now and then
	_quiet_the_roads()
	var space := get_viewport().get_world_3d().direct_space_state
	var lanes: Array = Game.world.get_lane_paths()
	var tunnel_lanes: Array[LanePath] = []
	for lane: LanePath in lanes:
		if String(lane.road_id) == WEST_LANE and not bool(lane.get_meta(&"connector", false)) and lane.curve != null \
				and lane.curve.get_baked_length() > 1000.0:
			tunnel_lanes.append(lane)
	_check(tunnel_lanes.size() == 4, "the tunnel has its four lanes", "(%d)" % tunnel_lanes.size())
	if tunnel_lanes.is_empty():
		_finish()
		return
	# the ground of the city is cut over the ramps: a ray from 3 m over a lane point 1-5 m under the ground does not meet the
	# ground first (a road tile that lies over a ramp is the roads unit's: it is reported, not checked)
	var covered: Array[String] = []
	var roads_over: Array[String] = []
	var tried := 0
	for lane in tunnel_lanes:
		var length := lane.curve.get_baked_length()
		var d := 0.0
		while d < length:
			var p := lane.curve.sample_baked(d, true)
			d += 5.0
			if p.y > -1.0 or p.y < -5.0:
				continue
			tried += 1
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 1.0, 1))
			if hit.is_empty() or absf((hit["position"] as Vector3).y - p.y) <= 0.4:
				continue
			var label := "(%.0f, %.1f, %.0f) y %.2f %s" % [p.x, p.y, p.z, (hit["position"] as Vector3).y,
				(hit["collider"] as Node).name]
			if String((hit["collider"] as Node).name) == "GroundBody":
				covered.append(label)
			else:
				roads_over.append(label)
	_check(tried > 100 and covered.is_empty(), "the ground is cut over the ramps",
			"(%d of %d covered: %s)" % [covered.size(), tried, ", ".join(covered.slice(0, 4))])
	if not roads_over.is_empty():
		print("INFO %d ramp points lie under a road surface of a tile (the roads unit): %s" % [roads_over.size(),
			", ".join(roads_over.slice(0, 3))])
	# down into the tunnel from both ends, and up out of it
	for lane in tunnel_lanes:
		var start := _lane_start(lane)
		var deepest := await _drive(lane, start, 12.0)
		_check(deepest[0] < DOWN, "a car drives down into the tunnel from (%.0f, %.0f)" % [start.origin.x, start.origin.z],
				"(deepest y %.1f, slowest after 2 s %.1f m/s)" % [deepest[0], deepest[1]])
		_check(deepest[1] > MIN_SPEED, "it does not stop on the way down", "(%.1f m/s)" % deepest[1])
	for lane in tunnel_lanes:
		var start := _lane_inside(lane)
		var run := await _drive(lane, start, 10.0)
		_check(_car.global_position.y > -0.6, "a car comes up out of the tunnel near (%.0f, %.0f)" % [
			_car.global_position.x, _car.global_position.z], "(y %.1f)" % _car.global_position.y)
		_check(run[1] > MIN_SPEED, "it does not stop on the way up", "(slowest after 2 s %.1f m/s)" % run[1])
	# from the side: a car at 50 km/h across the line of the tube, where the tube stands 3-5 m out of the ground
	var lane := tunnel_lanes[0]
	var side_at := _point_at_height(lane, -1.5)
	var dir := _direction(lane, side_at[1])
	var across := Vector3(-dir.z, 0.0, dir.x)
	var from: Vector3 = side_at[0] + across * 14.0
	from.y = 0.6
	Input.action_release(&"accelerate")
	_car.reset_to(Transform3D(Basis.looking_at(-across, Vector3.UP), from))
	_car.linear_velocity = -across * 13.9
	var lowest := 99.0
	for i in Engine.physics_ticks_per_second * 3:
		await get_tree().physics_frame
		lowest = minf(lowest, _car.global_position.y)
	_check(lowest > -0.5, "a car that drives at the tube from the side does not fall into the ramp", "(lowest y %.2f)" % lowest)
	_finish()


## No traffic, no police, no rivals on the roads of the test.
func _quiet_the_roads() -> void:
	var traffic := get_tree().get_first_node_in_group(&"traffic_director")
	if traffic != null:
		traffic.set("density_override", 0)
		traffic.call("_clear_cars")
	var police := get_tree().get_first_node_in_group(&"police_director")
	if police != null:
		if police.has_method(&"remove_all_units"):
			police.call("remove_all_units")
		police.process_mode = Node.PROCESS_MODE_DISABLED
	for rivals in get_tree().root.find_children("RivalDirector", "", true, false):
		rivals.process_mode = Node.PROCESS_MODE_DISABLED


func _finish() -> void:
	Input.action_release(&"accelerate")
	print("TUNNEL TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## The start of a lane, 10 m in (it starts on the street).
func _lane_start(lane: LanePath) -> Transform3D:
	return _xform(lane, 10.0)


## A place in the tunnel 120 m before the end of the lane (it comes up then).
func _lane_inside(lane: LanePath) -> Transform3D:
	return _xform(lane, lane.curve.get_baked_length() - 220.0)


func _xform(lane: LanePath, offset: float) -> Transform3D:
	var p := lane.curve.sample_baked(offset, true)
	var q := lane.curve.sample_baked(offset + 2.0, true)
	return Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6).looking_at(Vector3(q.x, p.y + 0.6, q.z), Vector3.UP)


## Drives the lane from `start` for `seconds`: [the lowest y, the lowest speed after the first 2 s].
func _drive(lane: LanePath, start: Transform3D, seconds: float) -> Array:
	_lane = lane
	_car.reset_to(start)
	_car.linear_velocity = -start.basis.z * 14.0
	var lowest := 99.0
	var slowest := 99.0
	for i in int(seconds * Engine.physics_ticks_per_second):
		_steer()
		await get_tree().physics_frame
		lowest = minf(lowest, _car.global_position.y)
		if i > 240:
			slowest = minf(slowest, _car.linear_velocity.length())
	Input.action_release(&"accelerate")
	return [lowest, slowest]


## A lane keeper that drives like a careful player (the player car reads the input actions): the heading of the lane a little
## ahead and the distance of the car from the lane, at DRIVE_SPEED. A pure pursuit 17 m ahead cut the curves of the ramps by 1 m and
## scraped the walls of the bores (7.5 m apart), a follower that ran up to 145 km/h swung into them: tests of the follower, not of
## the ramps.
func _steer() -> void:
	var speed := _car.linear_velocity.length()
	var length := _lane.curve.get_baked_length()
	var offset := _lane.curve.get_closest_offset(_car.global_position)
	var p0 := _lane.curve.sample_baked(offset, true)
	var p1 := _lane.curve.sample_baked(minf(offset + 4.0 + speed * 0.15, length), true)
	var tangent := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var forward := -_car.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var right := _car.global_transform.basis.x
	right = Vector3(right.x, 0.0, right.z).normalized()
	# the lane turns right of the car: + ; the lane is right of the car: +
	var heading := atan2(tangent.dot(right), tangent.dot(forward))
	var cross := Vector3(p0.x - _car.global_position.x, 0.0, p0.z - _car.global_position.z).dot(right)
	var steer := clampf(heading * 1.6 + atan2(cross * 1.2, speed + 3.0) * 1.6, -1.0, 1.0)
	Input.action_press(&"accelerate", 0.6 if speed < DRIVE_SPEED else 0.0)
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	if steer > 0.05:
		Input.action_press(&"steer_right", steer)
	elif steer < -0.05:
		Input.action_press(&"steer_left", -steer)


## The first point of a lane at `height` (m): [point, offset].
func _point_at_height(lane: LanePath, height: float) -> Array:
	var length := lane.curve.get_baked_length()
	var d := 0.0
	while d < length:
		var p := lane.curve.sample_baked(d, true)
		if p.y <= height:
			return [p, d]
		d += 2.0
	return [lane.curve.sample_baked(0.0, true), 0.0]


func _direction(lane: LanePath, offset: float) -> Vector3:
	var a := lane.curve.sample_baked(offset, true)
	var b := lane.curve.sample_baked(offset + 2.0, true)
	return Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()

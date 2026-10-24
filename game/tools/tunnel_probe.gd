extends Node
## The tunnel probe: the player car drives the lanes of the Yan'an tunnel (world/build/tunnel_trench.gd opens its ramps). Every lane
## is driven from 220 m before its end (it comes up out of the tunnel then); the probe writes down the height, the speed and what
## the car touches every 0.25 s (a prop is named by its shape). A diagnostic tool, not a test (world/tests/test_tunnel_portals.gd).
##
##   python tools/gd.py test res://tools/tunnel_probe.gd -- --timeout=600 --stub=audio,menu,hud,rivals,traffic,police [--lane=N]

const MAIN := "res://main.tscn"
const SECONDS := 10.0
const AIM_AHEAD := 15.0

var _lane: LanePath = null
var _car: ArcadeCar = null
var _touch: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(2.0).timeout
	_car = Game.player as ArcadeCar
	_car.freeze = false
	var lanes: Array[LanePath] = []
	for lane: LanePath in Game.world.get_lane_paths():
		if String(lane.road_id) == "yanan_tunnel" and not bool(lane.get_meta(&"connector", false)) and lane.curve != null \
				and lane.curve.get_baked_length() > 1000.0:
			lanes.append(lane)
	var only := int(Game.option("lane", "-1"))
	for k in lanes.size():
		if only >= 0 and k != only:
			continue
		_lane = lanes[k]
		# --down=1: from the start of the lane, down into the tunnel (else from 220 m before its end, up out of it)
		var offset := 10.0 if Game.option("down", "0") == "1" else _lane.curve.get_baked_length() - 220.0
		var p := _lane.curve.sample_baked(offset, true)
		var q := _lane.curve.sample_baked(offset + 2.0, true)
		_car.reset_to(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6).looking_at(Vector3(q.x, p.y + 0.6, q.z), Vector3.UP))
		_car.linear_velocity = (q - p).normalized() * 14.0
		print("TUNNEL lane %d: %.0f m long, start at %s" % [k, _lane.curve.get_baked_length(), str(p.snapped(Vector3.ONE * 0.1))])
		var t := 0.0
		var next := 0.0
		while t < SECONDS:
			_drive()
			await get_tree().physics_frame
			t += 1.0 / 120.0
			# every tick of the crash on the Pudong ramp
			if _car.global_position.x > 696.0 and _car.global_position.x < 706.0 and t < SECONDS and _car.global_position.y < 0.0:
				var v := _car.linear_velocity
				var fwd := -_car.global_transform.basis.z
				print("TICK t %.3f pos %s v %s (%.1f km/h) yaw-vs-v %.1f deg steer %.2f wheels %d %s" % [t,
					str(_car.global_position.snapped(Vector3.ONE * 0.01)), str(v.snapped(Vector3.ONE * 0.1)), v.length() * 3.6,
					rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(v.x, v.z))), float(_car.get("_in_steer")),
					_car.telemetry.grounded_wheels, str(_touch)])
				_touch.clear()
			if t >= next:
				next += 0.25
				var at := _lane.curve.get_closest_offset(_car.global_position)
				var lane_point := _lane.curve.sample_baked(at, true)
				print("TUNNEL  t %.2f pos %s lane-y %.2f off-lane %.2f speed %.1f km/h wheels %d touches %s" % [t,
					str(_car.global_position.snapped(Vector3.ONE * 0.1)), lane_point.y,
					Vector2(_car.global_position.x - lane_point.x, _car.global_position.z - lane_point.z).length(),
					_car.linear_velocity.length() * 3.6, _car.telemetry.grounded_wheels, str(_touch)])
				_touch.clear()
		Input.action_release(&"accelerate")
	get_tree().quit(0)


## The lane follower of tools/frame_probe.gd, with the input actions (the player car reads them).
func _drive() -> void:
	var speed := _car.linear_velocity.length()
	var steer := lane_steer(_car, _lane)
	Input.action_press(&"accelerate", 0.6 if speed < 25.0 else 0.0)
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	if steer > 0.05:
		Input.action_press(&"steer_right", steer)
	elif steer < -0.05:
		Input.action_press(&"steer_left", -steer)


func _physics_process(_delta: float) -> void:
	if _car == null:
		return
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	if state == null:
		return
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as Node
		if other == null:
			continue
		var label := String(other.name)
		# the road and the ground under the car are not news; a surface met from the side or from below is
		if (label == "GroundBody" or label.ends_with("_surface")) and state.get_contact_local_normal(i).y > 0.7:
			continue
		if label == "TunnelTubes":
			var shape := state.get_contact_collider_shape(i)
			label += ":%d" % shape
		if label.ends_with("_concrete") or label == "TunnelTubes" or label.ends_with("_surface") or label == "GroundBody":
			# where the car meets it: the point (world), the normal, the point in the frame of the car
			var point := state.get_contact_collider_position(i)
			label += "@%s n%s local%s" % [str(point.snapped(Vector3.ONE * 0.01)),
				str(state.get_contact_local_normal(i).snapped(Vector3.ONE * 0.01)),
				str((_car.global_transform.affine_inverse() * point).snapped(Vector3.ONE * 0.01))]
		if not _touch.has(label):
			_touch.append(label)


## A lane keeper that does not cut the corners (a pure pursuit 17 m ahead cut a curve of the ramp by 1 m and scraped the inner
## wall): the heading of the lane a little ahead, and the distance of the car from the lane.
static func lane_steer(car: VehicleBase, lane: LanePath) -> float:
	var speed := car.linear_velocity.length()
	var length := lane.curve.get_baked_length()
	var offset := lane.curve.get_closest_offset(car.global_position)
	var p0 := lane.curve.sample_baked(offset, true)
	var p1 := lane.curve.sample_baked(minf(offset + 4.0 + speed * 0.15, length), true)
	var tangent := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var forward := -car.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var right := car.global_transform.basis.x
	right = Vector3(right.x, 0.0, right.z).normalized()
	# the lane turns right of the car: + ; the lane is right of the car: +
	var heading := atan2(tangent.dot(right), tangent.dot(forward))
	var cross := Vector3(p0.x - car.global_position.x, 0.0, p0.z - car.global_position.z).dot(right)
	return clampf(heading * 1.6 + atan2(cross * 1.2, speed + 3.0) * 1.6, -1.0, 1.0)

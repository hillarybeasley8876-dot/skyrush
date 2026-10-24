extends Node
## The tunnel probe: the player car is driven down the lanes that go into the river tunnel (the Puxi portal near (-410, 200), the
## Pudong portal near (709, -470)). The spawn clearance probe found the ground (World/Terrain/GroundBody) at y 0 over these
## ramps, 2-4 m above the lane. The probe follows the lane from 50 m before the portal and writes down the height, the speed and
## what the car touches every 0.25 s (a prop is named by its shape). A diagnostic tool, not a test.
##
##   python tools/gd.py test res://tools/tunnel_probe.gd -- --timeout=600 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
## A point of each ramp (from tools/spawn_height_probe.gd): the run follows the lane through it.
const RAMPS := [
	{"name": "puxi portal", "point": Vector3(-410.2, -0.55, 198.7)},
	{"name": "pudong portal", "point": Vector3(708.9, -0.57, -470.1)},
]
const LEAD_IN := 50.0
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
	for ramp: Dictionary in RAMPS:
		_lane = _lane_through(ramp["point"])
		if _lane == null:
			print("TUNNEL %s: no lane" % ramp["name"])
			continue
		var at := _lane.curve.get_closest_offset(ramp["point"])
		var start := maxf(at - LEAD_IN, 0.0)
		var p := _lane.curve.sample_baked(start, true)
		var q := _lane.curve.sample_baked(start + 2.0, true)
		_car.reset_to(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6).looking_at(q + Vector3.UP * 0.6, Vector3.UP))
		_car.linear_velocity = (q - p).normalized() * 14.0
		print("TUNNEL %s: lane %s, %.0f m long, the ramp point at %.0f m, start at %s" % [ramp["name"], _lane.road_id,
			_lane.curve.get_baked_length(), at, str(p.snapped(Vector3.ONE * 0.1))])
		var t := 0.0
		var next := 0.0
		while t < SECONDS:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			_drive()
			if t >= next:
				next += 0.25
				var lane_point := _lane.curve.sample_baked(_lane.curve.get_closest_offset(_car.global_position), true)
				print("TUNNEL  t %.2f pos %s lane-y %.2f speed %.1f km/h wheels %d tilt %.0f touches %s" % [t,
					str(_car.global_position.snapped(Vector3.ONE * 0.1)), lane_point.y, _car.linear_velocity.length() * 3.6,
					_car.telemetry.grounded_wheels, rad_to_deg(acos(clampf(_car.global_transform.basis.y.y, -1.0, 1.0))),
					str(_touch)])
				_touch.clear()
		Input.action_release(&"accelerate")
	get_tree().quit(0)


## The lane that passes closest to `point`.
func _lane_through(point: Vector3) -> LanePath:
	var best: LanePath = null
	var best_d := INF
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null:
			continue
		var d := lane.curve.sample_baked(lane.curve.get_closest_offset(point), true).distance_to(point)
		if d < best_d:
			best_d = d
			best = lane
	return best


## The lane follower of tools/frame_probe.gd, with the input actions (the player car reads them).
func _drive() -> void:
	var offset := _lane.curve.get_closest_offset(_car.global_position)
	var length := _lane.curve.get_baked_length()
	if offset + AIM_AHEAD > length and not _lane.next_lanes.is_empty():
		var lanes: Array = Game.world.get_lane_paths()
		_lane = lanes[_lane.next_lanes[0]] as LanePath
		offset = _lane.curve.get_closest_offset(_car.global_position)
	var target := _lane.curve.sample_baked(minf(offset + AIM_AHEAD, _lane.curve.get_baked_length()), true)
	var to := target - _car.global_position
	var angle := atan2(to.dot(_car.global_transform.basis.x), to.dot(-_car.global_transform.basis.z))
	var steer := clampf(angle * 2.5, -1.0, 1.0)
	Input.action_press(&"accelerate", 0.5)
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
		if label.begins_with("PropCollision"):
			var shape := PhysicsServer3D.body_get_shape(state.get_contact_collider(i), state.get_contact_collider_shape(i))
			label += ":" + _shape_label(other, shape)
		elif label == "GroundBody" or label.ends_with("_surface"):
			continue
		if not _touch.has(label):
			_touch.append(label)


## The kind of a prop shape: the shared shape of the body that has this RID.
func _shape_label(body: Node, rid: RID) -> String:
	for s: Shape3D in body.get_meta(&"shapes", []):
		if s.get_rid() == rid:
			if s is CylinderShape3D:
				return "cylinder r %.2f h %.1f" % [(s as CylinderShape3D).radius, (s as CylinderShape3D).height]
			if s is BoxShape3D:
				return "box %s" % str((s as BoxShape3D).size)
	return "?"

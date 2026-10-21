extends SceneTree
# Tunnelling test: car-sized and debris-sized RigidBody3D at 100 m/s vs trimesh (ConcavePolygonShape3D).
# Engine is picked by override.cfg ([physics] 3d/physics_engine="Jolt Physics"), tick by --hz.
# Run: godot --headless --path . --fixed-fps 120 --script res://scripts/phys_tunnel.gd -- --hz=120
# Prints one TUNNEL line per lane: scenario, ccd, outcome (OK / TUNNEL), key coordinate.

const SPACING := 200.0
const SIM_SECONDS := 1.5
const CAR := Vector3(1.9, 1.2, 4.6)      # Roadster-sized box (est.)
const DEBRIS := Vector3(0.3, 0.3, 0.3)

var hz := 120
var lanes: Array[Dictionary] = []
var probe_fast: RigidBody3D
var step := 0
var max_steps := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hz="): hz = a.substr(5).to_int()
	Engine.physics_ticks_per_second = hz
	max_steps = int(SIM_SECONDS * hz)
	var scenarios := ["drop100", "skim100", "wall100", "wall100_debris", "wall100_backface", "wall100_backface_bfc", "wall100_debris_off", "rail30_100"]
	var lane := 0
	for sc in scenarios:
		for ccd in [false, true]:
			_make_lane(sc, ccd, lane * SPACING)
			lane += 1
	probe_fast = _body(Vector3(-500, 500, 0), CAR, false)   # engine fingerprint: Jolt clamps |v| to 500
	probe_fast.gravity_scale = 0.0
	probe_fast.linear_velocity = Vector3(1000, 0, 0)

func _static_from_plane(size: Vector2, orient: int, xf: Transform3D, subdiv := Vector2i.ZERO, two_sided := false) -> StaticBody3D:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.orientation = orient
	pm.subdivide_width = subdiv.x
	pm.subdivide_depth = subdiv.y
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := pm.create_trimesh_shape()     # same path the importer uses for -col meshes
	shape.backface_collision = two_sided
	cs.shape = shape
	sb.add_child(cs)
	sb.transform = xf
	get_root().add_child(sb)
	return sb

func _body(pos: Vector3, size: Vector3, ccd: bool) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	rb.add_child(cs)
	rb.mass = 1800.0 if size == CAR else 20.0
	rb.continuous_cd = ccd
	rb.can_sleep = false
	rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rb.linear_damp = 0.0
	rb.position = pos
	get_root().add_child(rb)
	return rb

func _make_lane(sc: String, ccd: bool, x: float) -> void:
	var d := {"sc": sc, "ccd": ccd, "x": x, "min_y": 1e9}
	# road: 20 m x 620 m trimesh, 2 m quads (seams every 2 m), top surface at y=0
	_static_from_plane(Vector2(20, 620), PlaneMesh.FACE_Y, Transform3D(Basis(), Vector3(x, 0, -290)), Vector2i(9, 309))
	match sc:
		"drop100":
			d.body = _body(Vector3(x, 5, 0), CAR, ccd)
			d.body.linear_velocity = Vector3(0, -100, 0)
		"skim100":
			d.body = _body(Vector3(x, 0.62, 0), CAR, ccd)
			d.body.linear_velocity = Vector3(0, -3, -100)
		"wall100", "wall100_debris", "wall100_debris_off":   # _off: wall at -30.37 so steps never land on it
			var wz := -30.37 if sc.ends_with("_off") else -30.0
			_static_from_plane(Vector2(40, 10), PlaneMesh.FACE_Z, Transform3D(Basis(), Vector3(x, 5, wz)))
			d.wall_z = wz
			d.body = _body(Vector3(x, 1.0, 0), CAR if sc == "wall100" else DEBRIS, ccd)
			d.body.linear_velocity = Vector3(0, 0, -100)
		"wall100_backface", "wall100_backface_bfc":   # wall faces -Z, car arrives from +Z => hits the BACK face
			_static_from_plane(Vector2(40, 10), PlaneMesh.FACE_Z, Transform3D(Basis(Vector3.UP, PI), Vector3(x, 5, -30)), Vector2i.ZERO, sc.ends_with("_bfc"))
			d.wall_z = -30.0
			d.body = _body(Vector3(x, 1.0, 0), CAR, ccd)
			d.body.linear_velocity = Vector3(0, 0, -100)
		"rail30_100":           # 1 m guard rail along the road edge, faces -X; car hits it at 30 deg
			_static_from_plane(Vector2(620, 1.0), PlaneMesh.FACE_X, Transform3D(Basis(Vector3.UP, PI), Vector3(x + 8, 0.5, -290)))
			d.rail_x = x + 8.0
			d.body = _body(Vector3(x, 0.62, 0), CAR, ccd)
			d.body.linear_velocity = Vector3(sin(deg_to_rad(30.0)), 0, -cos(deg_to_rad(30.0))) * 100.0
	lanes.append(d)

func _physics_process(_delta: float) -> bool:
	step += 1
	if step == 3:
		print("ENGINE_FINGERPRINT speed_after_set_1000=%.1f (500.0 => Jolt clamp, 1000.0 => GodotPhysics3D)" % probe_fast.linear_velocity.length())
	for d in lanes:
		d.min_y = minf(d.min_y, d.body.position.y)
	if step < max_steps:
		return false
	print("ENGINE_SETTING ", ProjectSettings.get_setting("physics/3d/physics_engine"), " hz=", hz)
	for d in lanes:
		var p: Vector3 = d.body.position
		var verdict := "OK"
		var info := ""
		match d.sc:
			"drop100", "skim100":
				verdict = "TUNNEL" if p.y < -1.0 else "OK"
				info = "final_y=%.2f min_y=%.2f" % [p.y, d.min_y]
			"wall100", "wall100_debris", "wall100_debris_off", "wall100_backface", "wall100_backface_bfc":
				verdict = "TUNNEL" if p.z < d.wall_z - 1.0 else "OK"
				info = "final_z=%.2f (wall at %.1f) v=%.1f" % [p.z, d.wall_z, d.body.linear_velocity.length()]
			"rail30_100":
				verdict = "TUNNEL" if p.x > d.rail_x + 1.0 else "OK"
				info = "final_dx_from_rail=%.2f v=%.1f" % [p.x - d.rail_x, d.body.linear_velocity.length()]
		print("TUNNEL %-18s ccd=%-5s %-6s %s" % [d.sc, str(d.ccd), verdict, info])
	return true

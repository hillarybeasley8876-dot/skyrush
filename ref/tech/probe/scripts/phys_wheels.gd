extends SceneTree
# Wheel-probe test: RaycastWheelCar (RAY vs SPHERE probes) at 100 m/s over a trimesh road with
# 2 m seams + 5 cm bumps (wavelength 20 m), then a 2 m kicker ramp at z=-300 and the landing.
# Run: godot --headless --path . --fixed-fps 120 --script res://scripts/phys_wheels.gd -- --hz=120
const Car := preload("res://scripts/raycast_wheel_car.gd")
const SIM_S := 7.0
var hz := 120
var lanes: Array[Dictionary] = []
var step := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hz="): hz = a.substr(5).to_int()
	Engine.physics_ticks_per_second = hz
	for mode in [Car.Probe.RAY, Car.Probe.SPHERE]:
		var x: float = 100.0 * mode
		_road(x)
		_kicker(x)
		var car: RigidBody3D = Car.new()
		car.probe_mode = mode
		car.mass = 1800.0
		car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		car.center_of_mass = Vector3(0, -0.1, 0)
		car.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		car.linear_damp = 0.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.9, 0.8, 4.4)
		cs.shape = bs
		cs.position = Vector3(0, 0.05, 0)
		car.add_child(cs)
		car.position = Vector3(x, 0.62, 0)
		car.linear_velocity = Vector3(0, 0, -100)
		get_root().add_child(car)
		lanes.append({"name": "RAY" if mode == Car.Probe.RAY else "SPHERE", "car": car, "x": x,
			"air_wheel_steps": 0, "bottom": 0, "max_comp": 0.0, "max_tilt": 0.0, "min_y": 99.0,
			"takeoff_t": -1.0, "land_t": -1.0, "land_max_comp": 0.0, "land_bottom": 0, "land_min_y": 99.0})

func _road(x: float) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 1200)
	pm.subdivide_width = 1
	pm.subdivide_depth = 599                     # 2 m quads => a seam every 2 m
	var arr := pm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y = 0.05 * sin(TAU * verts[i].z / 20.0)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_static(am.create_trimesh_shape(), Transform3D(Basis(), Vector3(x, 0, -580)))

func _kicker(x: float) -> void:
	var a := atan(2.0 / 20.0)                     # 2 m rise over 20 m
	var b := Basis(Vector3.RIGHT, a)
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 1, 20.1)
	_static(bm.create_trimesh_shape(), Transform3D(b, Vector3(x, 1.0, -300) - b.y * 0.5))

func _static(shape: Shape3D, xf: Transform3D) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.transform = xf
	get_root().add_child(sb)

func _physics_process(_d: float) -> bool:
	step += 1
	var t := step / float(hz)
	for L in lanes:
		var car = L.car
		var speed: float = car.linear_velocity.length()
		car.throttle = clampf((100.0 - speed) / 5.0, 0.0, 1.0)
		var grounded: bool = car.is_grounded()
		var comp: float = car.compression.max()
		var tilt := rad_to_deg(car.global_basis.y.angle_to(Vector3.UP))
		if t > 0.5 and t < 2.8:                          # bump section
			L.air_wheel_steps += car.contact.count(false)
			L.max_comp = maxf(L.max_comp, comp)
			L.bottom += int(comp >= car.rest_length - 0.001)
			L.max_tilt = maxf(L.max_tilt, tilt)
			L.min_y = minf(L.min_y, car.position.y)
		if L.takeoff_t < 0 and t > 2.8 and not grounded:
			L.takeoff_t = t
		if L.takeoff_t > 0 and L.land_t < 0 and grounded and t > L.takeoff_t + 0.3:
			L.land_t = t
		if L.land_t > 0 and t < L.land_t + 0.6:
			L.land_max_comp = maxf(L.land_max_comp, comp)
			L.land_bottom += int(comp >= car.rest_length - 0.001)
			L.land_min_y = minf(L.land_min_y, car.position.y)
	if t < SIM_S:
		return false
	for L in lanes:
		var c = L.car
		print("WHEELS hz=%d %-6s bumps: air_wheel_steps=%d max_comp=%.3f bottom_outs=%d max_tilt=%.2fdeg min_y=%.3f | jump: takeoff=%.2fs land=%.2fs airtime=%.2fs land_max_comp=%.3f land_bottom=%d land_min_y=%.3f | final y=%.3f z=%.1f x_drift=%.3f speed=%.1f tilt=%.2f" % [
			hz, L.name, L.air_wheel_steps, L.max_comp, L.bottom, L.max_tilt, L.min_y, L.takeoff_t, L.land_t,
			L.land_t - L.takeoff_t, L.land_max_comp, L.land_bottom, L.land_min_y, c.position.y, c.position.z,
			c.position.x - L.x, c.linear_velocity.length(), rad_to_deg(c.global_basis.y.angle_to(Vector3.UP))])
	return true

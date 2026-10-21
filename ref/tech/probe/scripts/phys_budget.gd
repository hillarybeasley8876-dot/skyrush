extends SceneTree
# Physics CPU budget for a city racer tick (headless):
#   2025 static building boxes + 1.2 km x 1.2 km road trimesh (~29k tris) + N RaycastWheelCars
#   (4 ShapeCast3D each) + M debris boxes with CCD, all awake. Prints avg / p95 / max physics frame ms.
# Frame-to-frame wall time is used (Performance.TIME_PHYSICS_PROCESS read 0.000 under Jolt here).
# Run: godot --headless --path . --fixed-fps 120 --script res://scripts/phys_budget.gd -- --cars=31 --debris=300
const Car := preload("res://scripts/raycast_wheel_car.gd")
var cars := 31
var debris := 300
var samples: PackedFloat32Array = []
var step := 0
var car_nodes: Array = []
var last_us := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cars="): cars = a.substr(7).to_int()
		if a.begins_with("--debris="): debris = a.substr(9).to_int()
	Engine.physics_ticks_per_second = 120
	_world()
	for i in cars:
		var c: RigidBody3D = Car.new()
		c.mass = 1800.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.9, 0.8, 4.4)
		cs.shape = bs
		c.add_child(cs)
		c.position = Vector3(-600 + 15 + (i % 8) * 4.0, 0.7, 500 - (i / 8) * 12.0)
		c.linear_velocity = Vector3(0, 0, -30)
		get_root().add_child(c)
		car_nodes.append(c)
	for i in debris:
		var rb := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.4, 0.3, 0.6)
		cs.shape = bs
		rb.add_child(cs)
		rb.mass = 15.0
		rb.continuous_cd = true
		rb.position = Vector3(-560 + (i % 20) * 1.0, 1.0 + (i / 20) * 0.5, 480)
		rb.linear_velocity = Vector3(randf_range(-20, 20), randf_range(5, 25), randf_range(-40, 0))
		get_root().add_child(rb)

func _world() -> void:
	var sb := StaticBody3D.new()                # ONE static body, many box shapes (cheaper than 2025 bodies)
	for ix in 45:
		for iz in 45:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var h := 12.0 + float((ix * 7 + iz * 13) % 78)
			bs.size = Vector3(20, h, 20)
			cs.shape = bs
			cs.position = Vector3(ix * 30.0 - 660.0 + 30.0, h * 0.5, iz * 30.0 - 660.0)
			sb.add_child(cs)
	get_root().add_child(sb)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	pm.subdivide_width = 119
	pm.subdivide_depth = 119                     # 10 m grid -> 28.8k triangles
	var road := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	rcs.shape = pm.create_trimesh_shape()
	road.add_child(rcs)
	get_root().add_child(road)

func _physics_process(_d: float) -> bool:
	step += 1
	for c in car_nodes:
		c.throttle = 0.3
	var now := Time.get_ticks_usec()   # headless + --fixed-fps: one tick per frame, frame time = CPU cost
	if step > 60:   # skip the spawn second
		samples.append((now - last_us) / 1000.0)
	last_us = now
	if step < 60 + 600:
		return false
	var arr := Array(samples)
	arr.sort()
	var avg := 0.0
	for v in arr: avg += v
	avg /= arr.size()
	print("PHYS_BUDGET engine=%s cars=%d debris=%d tick=120Hz avg=%.3f ms p95=%.3f ms max=%.3f ms active=%d" % [
		ProjectSettings.get_setting("physics/3d/physics_engine"), cars, debris, avg, arr[int(arr.size() * 0.95)], arr[-1],
		PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)])
	return true

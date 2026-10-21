extends RefCounted
## Geometry builders for the core sandbox (sandbox.gd). Everything is primitive meshes with
## colliders; no imported assets so the sandbox works before any art exists.

const GRID_SHADER := preload("res://core/sandbox/grid.gdshader")
const RAMP_ANGLE_DEG := 6.0

var root: Node3D
var _mats: Dictionary = {}


func _init(parent: Node3D) -> void:
	root = parent


func ground(size: float) -> void:
	var body := _static_box(Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size), null)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = 0.5
	body.add_child(mi)


func road_loop(half: Vector2, corner_r: float, width: float) -> void:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	var c := [Vector2(half.x - corner_r, -half.y + corner_r), Vector2(half.x - corner_r, half.y - corner_r),
		Vector2(-half.x + corner_r, half.y - corner_r), Vector2(-half.x + corner_r, -half.y + corner_r)]
	for i in 4:
		for s in 13:
			var a := -PI * 0.5 + PI * 0.5 * (float(i) + float(s) / 12.0)
			curve.add_point(Vector3(c[i].x + cos(a) * corner_r, 0.0, c[i].y + sin(a) * corner_r))
	curve.add_point(curve.get_point_position(0))
	var mi := MeshInstance3D.new()
	mi.mesh = _ribbon(curve, width, 0.03, _mat(&"asphalt", Color(0.05, 0.05, 0.06), 0.55, 0.0))
	root.add_child(mi)
	for side in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		line.mesh = _ribbon(_offset_curve(curve, side * (width * 0.5 - 0.6)), 0.25, 0.04,
				_mat(&"line", Color(0.9, 0.9, 0.85), 0.4, 0.4))
		root.add_child(line)


func ramp(pos: Vector3, width: float, height: float, length: float) -> void:
	var angle := atan2(height, length)
	var slab := Vector3(width, 0.6, length / cos(angle))
	var body := _static_box(pos + Vector3(0.0, height * 0.5 - 0.3, 0.0), slab, _mat(&"ramp", Color(0.85, 0.3, 0.1), 0.6, 0.6))
	body.rotation.x = angle  # rises toward -Z (approach from +Z)


func elevated_deck(center: Vector3, length: float, height: float, width: float) -> void:
	var concrete := _mat(&"concrete", Color(0.42, 0.42, 0.44), 0.85, 0.0)
	_static_box(center + Vector3(0.0, height - 0.5, 0.0), Vector3(length, 1.0, width), concrete)
	for side in [-1.0, 1.0]:
		_static_box(center + Vector3(0.0, height + 0.55, side * (width * 0.5 - 0.2)), Vector3(length, 1.1, 0.4),
				_mat(&"parapet", Color(0.75, 0.75, 0.78), 0.7, 0.0))
	var n := int(length / 30.0)
	for i in n + 1:
		var x := center.x - length * 0.5 + length * float(i) / float(n)
		_static_box(Vector3(x, height * 0.5 - 0.5, center.z), Vector3(2.0, height - 1.0, 2.0), concrete)
	var run := height / tan(deg_to_rad(RAMP_ANGLE_DEG))
	for side in [-1.0, 1.0]:
		var slope := _static_box(Vector3(center.x + side * (length * 0.5 + run * 0.5), height * 0.5 - 0.5, center.z),
				Vector3(run / cos(deg_to_rad(RAMP_ANGLE_DEG)) + 0.5, 1.0, width), concrete)
		slope.rotation.z = -side * deg_to_rad(RAMP_ANGLE_DEG)


func gas_station(pos: Vector3) -> void:
	var white := _mat(&"canopy", Color(0.92, 0.92, 0.94), 0.5, 0.0)
	_static_box(pos + Vector3(0.0, 6.5, 0.0), Vector3(32.0, 1.2, 20.0), white)
	var stripe := _mat(&"stripe", Color(1.0, 0.25, 0.2), 0.4, 3.0)
	for side in [-1.0, 1.0]:
		_static_box(pos + Vector3(0.0, 6.5, side * 10.05), Vector3(32.0, 0.6, 0.1), stripe)
	for x in [-11.0, 11.0]:
		for z in [-6.0, 6.0]:
			_static_box(pos + Vector3(x, 3.0, z), Vector3(0.8, 6.0, 0.8), white)
	for x in [-6.0, 0.0, 6.0]:
		_static_box(pos + Vector3(x, 0.9, 0.0), Vector3(1.2, 1.8, 0.8), _mat(&"pump", Color(0.2, 0.6, 0.3), 0.5, 0.2))
	var gate := StuntGate.new()
	gate.kind = &"fly_over_gas"
	gate.label = "飞跃加油站!"
	gate.points = 800
	_area(gate, pos + Vector3(0.0, 18.0, 0.0), Vector3(36.0, 22.0, 24.0))


## Straight launch pad + a gently rising and falling sky lane along -X (west) from `start`.
func sky_lane(start: Vector3, length: float, height: float) -> void:
	var lane := SkyLane.new()
	lane.name = "SkyLane"
	lane.curve = Curve3D.new()
	lane.curve.bake_interval = 1.0
	var n := 12
	for i in n + 1:
		var t := float(i) / float(n)
		lane.curve.add_point(start + Vector3(-length * t, 2.0 + height * sin(PI * t), 0.0))
	lane.n2_ring_offsets = PackedFloat32Array([length * 0.33, length * 0.66])
	var pad := Area3D.new()
	pad.name = "LaunchPad"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 4.0, 14.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = start + Vector3(15.0, 2.0, 0.0)
	lane.add_child(pad)
	root.add_child(lane)
	_static_box(start + Vector3(15.0, 0.02, 0.0), Vector3(30.0, 0.04, 14.0), _mat(&"pad", Color(0.0, 0.9, 1.0), 0.3, 1.5))


func charge_lane(pos: Vector3) -> void:
	var cyan := _mat(&"charge", Color(0.1, 0.9, 1.0), 0.3, 4.0)
	for x in [-7.0, 7.0]:
		for z in [-3.5, 3.5]:
			_static_box(pos + Vector3(x, 2.5, z), Vector3(0.4, 5.0, 0.4), _mat(&"post", Color(0.15, 0.16, 0.2), 0.4, 0.0))
	_static_box(pos + Vector3(0.0, 5.2, 0.0), Vector3(15.0, 0.4, 7.6), cyan)
	_area(ChargeStation.new(), pos + Vector3(0.0, 2.0, 0.0), Vector3(14.0, 4.0, 6.0))


func parked_row(pos: Vector3, count: int) -> void:
	for i in count:
		var car := RigidBody3D.new()
		car.mass = 1500.0
		car.collision_layer = 1 << 2
		car.collision_mask = 0b111
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.6, 1.5, 2.0)
		shape.shape = box
		car.add_child(shape)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box.size
		mesh.material = _mat(StringName("parked%d" % (i % 3)), Color.from_hsv(0.55 + 0.12 * float(i % 3), 0.5, 0.7), 0.35, 0.0)
		mi.mesh = mesh
		car.add_child(mi)
		car.position = pos + Vector3(float(i) * 2.6, 0.76, 0.0)
		root.add_child(car)
	var gate := StuntGate.new()
	gate.kind = &"fly_over_cars"
	gate.label = "飞跃车阵!"
	gate.points = 600
	_area(gate, pos + Vector3(float(count - 1) * 1.3, 12.0, 0.0), Vector3(float(count) * 2.6 + 8.0, 20.0, 8.0))


func _static_box(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if mat != null:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		mi.mesh = mesh
		body.add_child(mi)
	root.add_child(body)
	return body


func _area(area: Area3D, center: Vector3, size: Vector3) -> void:
	area.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	root.add_child(area)


func _mat(key: StringName, color: Color, roughness: float, emission: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	_mats[key] = mat
	return mat


func _offset_curve(curve: Curve3D, offset: float) -> Curve3D:
	var out := Curve3D.new()
	out.bake_interval = curve.bake_interval
	var pts := curve.get_baked_points()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side := (b - a).cross(Vector3.UP).normalized()
		out.add_point(pts[i] + side * offset)
	return out


## Flat ribbon mesh along a curve (y = curve y + lift), UV.x across, UV.y = metres along.
func _ribbon(curve: Curve3D, width: float, lift: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := curve.get_baked_points()
	var dist := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(Vector3.UP).normalized() * width * 0.5
		var seg := a.distance_to(b)
		var quad := [a - side, a + side, b + side, b - side]
		var uvs := [Vector2(0, dist), Vector2(1, dist), Vector2(1, dist + seg), Vector2(0, dist + seg)]
		for k in [0, 2, 1, 0, 3, 2]:  # clockwise seen from above (Godot front face)
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			st.add_vertex(quad[k] + Vector3.UP * lift)
		dist += seg
	st.set_material(mat)
	return st.commit()

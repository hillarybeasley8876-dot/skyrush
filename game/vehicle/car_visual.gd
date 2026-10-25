extends Node3D
## Binds the car mesh to the physics: instances the glb (or a tidy placeholder), applies the
## shared material library, spins and steers the wheels with the suspension, follows the
## brake calipers, poses the active wing and lights the brake bar.
##
## The wing poses come from the glb (the "extras" meta of the Wing node); the CarSpec only has
## the fallback values. The pose change takes at most 0.25 s and a new pose waits 0.25 s, so the
## wing does not chatter around the speed thresholds.

const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")
const LightsMod := preload("res://vehicle/modules/car_lights.gd")

## The wheel nodes found in the visual, in the order FL, FR, RL, RR.
var wheels: Array[Node3D] = []
## The brake calipers, in the same order.
var calipers: Array[Node3D] = []
## The active wing node, if the mesh has one.
var wing: Node3D = null
## The brake lights of this car (the rear bar, the brake box and the NPC brake lamp).
var lights: LightsMod = LightsMod.new()

var _spec: CarSpec = null
var _wheel_base: Array[Transform3D] = []
var _caliper_base: Array[Transform3D] = []
## The spin axis of every wheel in world space (the glTF contract says X).
var _spin_axis: Array[Vector3] = []
var _wing_base: Vector3 = Vector3.ZERO
## The pose the wing is easing towards and the one it is easing from.
var _pose_name: StringName = &"stowed"
var _pose_angle: float = 0.0
var _pose_from: float = 0.0
var _pose_to: float = 0.0
var _pose_time: float = VisualTuning.WING_POSE_TIME
var _pose_hold: float = 0.0
## The instance id of the model, to notice when it is replaced at runtime.
var _model_id: int = 0
## The headlight of the player car (a shadowless spot) and the red lamp at the rear.
var _headlight: SpotLight3D = null
var _tail_lamp: OmniLight3D = null


## Instances the visual for a spec. Call once, after the car is in the tree.
## player: the player car gets a headlight and a tail lamp.
func setup(spec: CarSpec, player: bool = false) -> void:
	_spec = spec
	var packed: PackedScene = spec.load_visual()
	if packed != null:
		var instance: Node3D = packed.instantiate() as Node3D
		if instance != null:
			instance.name = "Model"
			add_child(instance)
			MaterialLibrary.apply(instance)
	else:
		_build_placeholder()
	_find_nodes()
	if player:
		_build_lights()


## Finds the wheels, the calipers, the wing and the brake light by the contract names.
func _find_nodes() -> void:
	wheels.clear()
	calipers.clear()
	var model: Node3D = get_node_or_null(^"Model") as Node3D
	_model_id = model.get_instance_id() if model != null else 0
	for i in 4:
		var names: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
		var caliper_names: Array[String] = ["Caliper_FL", "Caliper_FR", "Caliper_RL", "Caliper_RR"]
		wheels.append(model.find_child(names[i], true, false) as Node3D if model != null else null)
		calipers.append(model.find_child(caliper_names[i], true, false) as Node3D if model != null else null)
	wing = model.find_child("Wing", true, false) as Node3D if model != null else null
	# The wheels, the calipers and the wing move every drawn frame: they are left out of the physics
	# interpolation (their own motion shows at once) and still follow the interpolated body.
	for node: Node3D in wheels + calipers + [wing]:
		if node != null:
			node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cache_bases()
	lights.bind(model)


## Caches the rest transforms of the wheels and the calipers.
func _cache_bases() -> void:
	_wheel_base.clear()
	_caliper_base.clear()
	_spin_axis.clear()
	for w: Node3D in wheels:
		if w == null:
			_wheel_base.append(Transform3D.IDENTITY)
			_spin_axis.append(Vector3.RIGHT)
			continue
		_wheel_base.append(w.transform)
		# The glTF contract puts the spin axis on X; the placeholder wheels are built the same way.
		_spin_axis.append(w.transform.basis.x.normalized())
	for c: Node3D in calipers:
		_caliper_base.append(c.transform if c != null else Transform3D.IDENTITY)
	if wing != null:
		_wing_base = wing.rotation


## The lights of the player car: a shadowless spot at Light_Front (it lights the wet road in
## front of the car) and a small red lamp at Light_Rear that follows the brake level.
func _build_lights() -> void:
	var model: Node3D = get_node_or_null(^"Model") as Node3D
	if model == null:
		return
	var front: Node3D = model.find_child("Light_Front", true, false) as Node3D
	if front != null:
		var spot := SpotLight3D.new()
		spot.name = "Headlight"
		spot.light_color = VisualTuning.HEADLIGHT_COLOUR
		spot.light_energy = VisualTuning.HEADLIGHT_ENERGY
		spot.spot_range = VisualTuning.HEADLIGHT_RANGE
		spot.spot_angle = VisualTuning.HEADLIGHT_ANGLE
		spot.shadow_enabled = false
		front.add_child(spot)
		_headlight = spot
	var rear: Node3D = model.find_child("Light_Rear", true, false) as Node3D
	if rear != null:
		var lamp := OmniLight3D.new()
		lamp.name = "TailLamp"
		lamp.light_color = VisualTuning.TAIL_LAMP_COLOUR
		lamp.light_energy = 0.0
		lamp.omni_range = VisualTuning.TAIL_LAMP_RANGE
		lamp.shadow_enabled = false
		rear.add_child(lamp)
		_tail_lamp = lamp


## Updates the wheels, the wing and the brake light.
## centres: the local centre of every wheel, in the car order. spins: the spin angles.
## steer: the front wheel steer angle in radians. counter: the drift counter steer in radians.
func update(delta: float, centres: PackedVector3Array, spins: PackedFloat32Array, steer: float,
		speed_kmh: float, cornering: float, braking: bool, counter: float) -> void:
	_check_model()
	_update_wheels(centres, spins, steer, counter)
	_update_wing(delta, speed_kmh, cornering, braking)
	lights.set_braking(braking)
	_update_lamps(braking)


## The red lamp at the rear follows the brake level.
func _update_lamps(braking: bool) -> void:
	if _tail_lamp == null:
		return
	var energy: float = VisualTuning.TAIL_LAMP_ENERGY if braking else 0.0
	if is_equal_approx(_tail_lamp.light_energy, energy):
		return
	_tail_lamp.light_energy = energy


## Re-finds the nodes when the model was replaced at runtime (the damage unit detaches parts).
func _check_model() -> void:
	var model: Node3D = get_node_or_null(^"Model") as Node3D
	if model == null:
		return
	if model.get_instance_id() != _model_id:
		_find_nodes()


## Places the visual wheels at the suspension height and spins them. The calipers follow the
## wheel centre and the steer, but they do not spin.
func _update_wheels(centres: PackedVector3Array, spins: PackedFloat32Array, steer: float,
		counter: float) -> void:
	for i in mini(wheels.size(), centres.size()):
		var w: Node3D = wheels[i]
		if w == null or not is_instance_valid(w):
			continue
		var centre: Vector3 = centres[i]
		var spin: float = spins[i]
		var base: Transform3D = _wheel_base[i]
		var axis: Vector3 = _spin_axis[i]
		# A positive steer turns the wheels to the right: the rotation is about -Y.
		var angle: float = steer if i < 2 else 0.0
		if i < 2:
			angle += counter
		var basis: Basis = Basis(Quaternion(Vector3.UP, -angle)) \
				* Basis(Quaternion(axis, spin)) * base.basis
		w.transform = Transform3D(basis, centre)
		var caliper: Node3D = calipers[i]
		if caliper != null and is_instance_valid(caliper):
			var caliper_basis: Basis = Basis(Quaternion(Vector3.UP, -angle)) \
					* _caliper_base[i].basis
			caliper.transform = Transform3D(caliper_basis, centre)


## Chooses and eases the wing pose. The angle change takes at most 0.25 s and a new pose waits
## 0.25 s, so the wing does not chatter around the speed thresholds.
func _update_wing(delta: float, speed_kmh: float, cornering: float, braking: bool) -> void:
	if wing == null or not is_instance_valid(wing):
		return
	var wanted: StringName = _wanted_pose(speed_kmh, cornering, braking)
	# The dwell is counted from the last change: a pose the wing has held for a while is
	# replaced at once, a pose that just changed waits for the wing to settle.
	_pose_hold = maxf(_pose_hold - delta, 0.0)
	if wanted != _pose_name and _pose_hold <= 0.0:
		_pose_name = wanted
		_pose_from = _pose_angle
		_pose_to = _pose_target(wanted)
		_pose_time = 0.0
	if _pose_time < VisualTuning.WING_POSE_TIME:
		_pose_time = minf(_pose_time + delta, VisualTuning.WING_POSE_TIME)
		var t: float = _pose_time / VisualTuning.WING_POSE_TIME
		_pose_angle = lerpf(_pose_from, _pose_to, smoothstep(0.0, 1.0, t))
		if _pose_time >= VisualTuning.WING_POSE_TIME:
			_pose_hold = VisualTuning.WING_POSE_HOLD
	# The trailing edge goes up with a positive pitch: the rotation is the other way round.
	wing.rotation = _wing_base + Vector3(-deg_to_rad(_pose_angle), 0.0, 0.0)


## The pose for the current state (dossier 8.2 and the glb metadata).
func _wanted_pose(speed_kmh: float, cornering: float, braking: bool) -> StringName:
	# The air brake latches: it stays out while the brake is held and only folds back in below
	# the release speed. Without the hysteresis the wing chatters around 150 km/h.
	if _pose_name == &"air_brake" and braking and speed_kmh >= VisualTuning.WING_AIRBRAKE_RELEASE_KMH:
		return &"air_brake"
	if speed_kmh >= VisualTuning.WING_AIRBRAKE_KMH and braking:
		return &"air_brake"
	if cornering > VisualTuning.WING_CORNERING:
		return &"high_downforce"
	if speed_kmh >= VisualTuning.WING_LOWDRAG_KMH:
		return &"low_drag"
	return &"stowed"


## The angle of a pose in degrees: the glb metadata first, the spec as the fallback.
func _pose_target(name: StringName) -> float:
	if wing != null and wing.has_meta("extras"):
		var extras: Dictionary = wing.get_meta("extras")
		var poses: Dictionary = extras.get("poses", {}) as Dictionary
		if poses.has(name):
			return float(poses[name])
	if _spec != null:
		return float(_spec.pose(name).get("angle", 0.0))
	return 0.0


## Builds a tidy placeholder when the glb is missing: the body of the spec, a glass cabin and
## four wheels, with the shared materials of the library (the same paint as the real car).
func _build_placeholder() -> void:
	var size: Vector3 = _spec.body_size
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _wedge_mesh(size)
	body.mesh.surface_set_material(0, _library_material(&"SH_car_paint", VisualTuning.PLACEHOLDER_PAINT))
	body.position = Vector3(0.0, _spec.body_center_y, 0.0)
	add_child(body)
	var cabin: MeshInstance3D = MeshInstance3D.new()
	cabin.name = "Glass"
	var glass: BoxMesh = BoxMesh.new()
	glass.size = size * VisualTuning.PLACEHOLDER_CABIN_SCALE
	glass.material = _library_material(&"SH_glass_tinted", VisualTuning.PLACEHOLDER_GLASS)
	cabin.mesh = glass
	cabin.position = Vector3(0.0, _spec.body_center_y + VisualTuning.PLACEHOLDER_CABIN_Y,
			VisualTuning.PLACEHOLDER_CABIN_Z)
	add_child(cabin)
	for i in 4:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"][i]
		var radius: float = _spec.wheel_radii[i] if i < _spec.wheel_radii.size() \
			else VisualTuning.PLACEHOLDER_WHEEL_R
		mesh.mesh = _wheel_mesh(radius, radius * VisualTuning.PLACEHOLDER_WHEEL_SCALE)
		add_child(mesh)


## A material of the shared library (the core owns the library), or a plain one with the given
## colour when it is missing. The library material is copied: the library hands out a cached
## resource, and the car must not change it for everybody.
func _library_material(name: StringName, fallback: Color) -> Material:
	var material: Material = MaterialLibrary.lookup(String(name))
	if material != null:
		return material.duplicate() as Material
	var plain: StandardMaterial3D = StandardMaterial3D.new()
	plain.albedo_color = fallback
	plain.roughness = VisualTuning.PLACEHOLDER_ROUGHNESS
	plain.metallic = VisualTuning.PLACEHOLDER_METALLIC
	return plain


## The tyre of the placeholder: the plastic texture of the library with the tyre colour, so the
## wheel is not a flat untextured disc (ART 5).
func _tyre_material() -> StandardMaterial3D:
	var tyre: StandardMaterial3D = StandardMaterial3D.new()
	tyre.albedo_color = VisualTuning.PLACEHOLDER_TYRE
	tyre.roughness = VisualTuning.PLACEHOLDER_TYRE_ROUGHNESS
	var albedo: Texture2D = _texture(VisualTuning.TYRE_TEXTURE_DIR, "Plastic006_diff")
	var normal: Texture2D = _texture(VisualTuning.TYRE_TEXTURE_DIR, "Plastic006_nor_gl")
	var rough: Texture2D = _texture(VisualTuning.TYRE_TEXTURE_DIR, "Plastic006_rough")
	if albedo != null:
		tyre.albedo_texture = albedo
	if normal != null:
		tyre.normal_enabled = true
		tyre.normal_texture = normal
		tyre.normal_scale = VisualTuning.PLACEHOLDER_TYRE_NORMAL
	if rough != null:
		tyre.roughness_texture = rough
	return tyre


## A texture of the shared texture library, or null when it is missing.
func _texture(folder: String, name: String) -> Texture2D:
	var path: String = "res://assets/textures/%s/%s.jpg" % [folder, name]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## A wedge: a box whose top is narrower than its bottom, so the placeholder reads as a car.
## The mesh has flat normals and box UVs, so the paint material shows its flake and the car
## is not a black faceted blob.
func _wedge_mesh(size: Vector3) -> ArrayMesh:
	var half: Vector3 = size * 0.5
	# The top of the wedge is narrower than the bottom (the taper is a share of the half width).
	var top: float = half.x * VisualTuning.PLACEHOLDER_TAPER
	var verts: PackedVector3Array = PackedVector3Array([
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z),
		Vector3(-top, half.y, -half.z * VisualTuning.PLACEHOLDER_TAPER_Z),
		Vector3(top, half.y, -half.z * VisualTuning.PLACEHOLDER_TAPER_Z),
		Vector3(top, half.y, half.z * VisualTuning.PLACEHOLDER_TAPER_Z),
		Vector3(-top, half.y, half.z * VisualTuning.PLACEHOLDER_TAPER_Z),
	])
	var indices: PackedInt32Array = PackedInt32Array([
		0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
		0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
		2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0,
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, indices.size(), 3):
		var a: Vector3 = verts[indices[i]]
		var b: Vector3 = verts[indices[i + 1]]
		var c: Vector3 = verts[indices[i + 2]]
		var normal: Vector3 = (b - a).cross(c - a)
		# The body is centred on the origin, so an outward normal points away from it.
		if normal.dot(a) > 0.0:
			normal = -normal
		normal = normal.normalized()
		for p: Vector3 in [a, b, c]:
			st.set_normal(normal)
			st.set_uv(_box_uv(p, size, normal))
			st.add_vertex(p)
	return st.commit()


## A box projection of the point on the surface: the UV of the dominant axis of the normal.
func _box_uv(p: Vector3, size: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > VisualTuning.PLACEHOLDER_UV_DOMINANT:
		return Vector2(p.x / size.x + 0.5, p.z / size.z + 0.5)
	if absf(normal.x) > VisualTuning.PLACEHOLDER_UV_DOMINANT:
		return Vector2(p.z / size.z + 0.5, p.y / size.y + 0.5)
	return Vector2(p.x / size.x + 0.5, p.y / size.y + 0.5)


## A cylinder whose axis lies on X, so the placeholder wheels spin like the glTF ones.
func _wheel_mesh(radius: float, width: float) -> ArrayMesh:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = width
	var arrays: Array = cylinder.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = Vector3(verts[i].y, -verts[i].x, verts[i].z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size():
		normals[i] = Vector3(normals[i].y, -normals[i].x, normals[i].z)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out: ArrayMesh = ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, _tyre_material())
	return out

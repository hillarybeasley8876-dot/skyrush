extends RefCounted
## Builds the sky lanes (飞行航道) from the city.json sky_lanes: the SkyLane contract node with
## its curve, the launch pad, the hologram ring gates every `ring_spacing` metres, the obstacles
## of the lane (drones, billboards, crane arms) and the overhead gantry 300 m before the pad.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const MeshMerger := preload("res://world/build/mesh_merger.gd")
const PropLibrary := preload("res://world/loader/prop_library.gd")
const SkyObstacles := preload("res://world/build/sky_obstacles.gd")
const Spline := preload("res://world/api/spline_util.gd")
const Heading := preload("res://world/api/heading.gd")

const PAD_GLB := "res://assets/props/sites/sky_lane_pad.glb"
const GATE_GLB := "res://assets/props/sites/sky_lane_gate.glb"
const GANTRY_GLB := "res://assets/props/sites/sky_lane_gantry.glb"

const RING_SPACING := 40.0
const RING_INNER := 6.4
const RING_OUTER := 7.0
const PAD_LENGTH := 30.0
const GANTRY_OFFSET := 300.0


func build(parent: Node3D, specs: Array) -> Array[SkyLane]:
	var out: Array[SkyLane] = []
	for spec in specs:
		if spec is Dictionary:
			var lane := _build_lane(spec as Dictionary, parent)
			if lane != null:
				out.append(lane)
	return out


func _build_lane(spec: Dictionary, parent: Node3D) -> SkyLane:
	var points := _points(spec.get("points", []))
	if points.size() < 2:
		return null
	var lane := SkyLane.new()
	lane.name = "SkyLane_" + str(spec.get("id", "lane"))
	lane.label = str(spec.get("label", "飞行航道"))
	lane.ring_spacing = RING_SPACING
	lane.curve = Spline.make_curve(points)
	for offset in _ring_offsets(spec.get("n2_rings_m", [])):
		lane.n2_ring_offsets.append(offset)
	var pad := _build_pad(spec, lane)
	lane.add_child(pad)
	parent.add_child(lane)
	_build_rings(lane, points)
	SkyObstacles.new().build(lane)
	_build_gantry(lane, spec, points, parent)
	return lane


## The glowing launch ramp; touching it emits Events.sky_lane_launch.
func _build_pad(spec: Dictionary, lane: SkyLane) -> Area3D:
	var pad := Area3D.new()
	pad.name = "LaunchPad"
	var data: Dictionary = spec.get("pad", {})
	var position := Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	var yaw := Heading.yaw_from_heading(float(data.get("heading_deg", 0.0)))
	pad.position = position
	pad.rotation.y = yaw
	var model := _instance(PAD_GLB)
	if model != null:
		pad.add_child(model)
	else:
		var ramp := MeshInstance3D.new()
		ramp.name = "Ramp"
		ramp.mesh = ProcMeshes.box(Vector3(PAD_LENGTH, 0.3, 12.0))
		ramp.material_override = ProcMeshes.glow(Color("00e5ff"), 0.8)
		ramp.position = Vector3(0, 0.15, 0)
		pad.add_child(ramp)
		for i in 5:
			var chevron := MeshInstance3D.new()
			chevron.name = "Chevron_%d" % i
			chevron.mesh = ProcMeshes.box(Vector3(2.2, 0.12, 10.0))
			chevron.material_override = ProcMeshes.glow(Color("ff2bd6"), 1.6)
			chevron.position = Vector3(-PAD_LENGTH * 0.4 + float(i) * 5.2, 0.34, 0)
			pad.add_child(chevron)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PAD_LENGTH, 3.0, 12.0)
	shape.shape = box
	shape.position = Vector3(0, 1.5, 0)
	pad.add_child(shape)
	return pad


## Hologram ring gates every `ring_spacing` metres along the lane. The gates of one lane are
## one MultiMesh: a thousand gate nodes cost a thousand draw calls.
func _build_rings(lane: SkyLane, points: PackedVector3Array) -> void:
	var length := Spline.total_length(points)
	var count := int(length / RING_SPACING)
	if count <= 0:
		return
	var transforms: Array[Transform3D] = []
	for i in range(1, count + 1):
		var distance := float(i) * RING_SPACING
		if distance > length - 10.0:
			break
		var position := _point_at(points, distance)
		var tangent := _tangent_at(points, distance)
		var xform := Transform3D(Basis.looking_at(tangent, Vector3.UP), position)
		transforms.append(xform)
	var model := _instance(GATE_GLB)
	if model != null:
		var instances: Array[MeshInstance3D] = []
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi != null and mi.mesh != null:
				instances.append(mi)
		var merged := MeshMerger.merge(instances)
		model.free()
		_add_rings(lane, merged, transforms, null)
		return
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 24
	torus.ring_segments = 10
	var baked: Array[Transform3D] = []
	for xform in transforms:
		# The torus lies in the XZ plane: turn it up, the glb gate is already upright.
		baked.append(xform * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	_add_rings(lane, torus, baked, ProcMeshes.glow(Color("00e5ff"), 2.4))


## The MultiMesh of the ring gates of one lane.
func _add_rings(lane: SkyLane, mesh: Mesh, transforms: Array[Transform3D],
		material: Material) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RingGates"
	mmi.multimesh = multimesh
	if material != null:
		mmi.material_override = material
	lane.add_child(mmi)
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])


## The overhead gantry that announces the lane 300 m before the pad.
func _build_gantry(lane: SkyLane, spec: Dictionary, points: PackedVector3Array,
		parent: Node3D) -> void:
	var data: Dictionary = spec.get("pad", {})
	var position := Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	var yaw := float(data.get("heading_deg", 0.0))
	var backward := -Heading.forward_from_heading(float(data.get("heading_deg", 0.0)))
	var gantry := Node3D.new()
	gantry.name = "SkyLaneGantry"
	gantry.position = position + backward * GANTRY_OFFSET
	gantry.rotation.y = yaw
	parent.add_child(gantry)
	var model := _instance(GANTRY_GLB)
	if model != null:
		gantry.add_child(model)
		return
	var props := PropLibrary.new()
	var def := props.get_prop("gantry")
	for part in def.get("parts", []):
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		mi.material_override = part["material"]
		mi.transform = part["transform"]
		gantry.add_child(mi)
	var sign := MeshInstance3D.new()
	sign.name = "Sign"
	sign.mesh = ProcMeshes.box(Vector3(9.0, 2.0, 0.2))
	sign.material_override = ProcMeshes.glow(Color("0a1a2a"), 0.4)
	sign.position = Vector3(0, 6.4, 0.25)
	gantry.add_child(sign)


## Instantiates a glb of the props unit (null when it does not exist).
static func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	MaterialLibrary.apply(node)
	return node


static func _ring_offsets(raw: Variant) -> Array[float]:
	var out: Array[float] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		out.append(float(entry))
	return out


static func _points(raw: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out


static func _point_at(points: PackedVector3Array, distance: float) -> Vector3:
	var travelled := 0.0
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if travelled + seg >= distance:
			return points[i].lerp(points[i + 1], (distance - travelled) / maxf(seg, 0.001))
		travelled += seg
	return points[points.size() - 1]


static func _tangent_at(points: PackedVector3Array, distance: float) -> Vector3:
	var travelled := 0.0
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if travelled + seg >= distance:
			return (points[i + 1] - points[i]).normalized()
		travelled += seg
	return Vector3.FORWARD

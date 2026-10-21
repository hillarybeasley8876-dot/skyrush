extends Node3D
## Toll plaza (收费站, ref/shanghai/SHANGHAI_DOSSIER.md §7.2). The plaza of the props unit is
## used when it is there: its barrier arms (`Barrier_<n>`) become frozen RigidBody3D that break
## off when they are hit, its lane signals (`LaneSignal_<n>`) show green on the ETC lanes and
## red on the closed ones, and the ETC lanes lift their arms automatically. Driving a closed
## lane or flying over the plaza raises the "toll_evaded" infraction.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")
const Layers := preload("res://world/api/layers.gd")
const PLAZA_GLB := "res://assets/props/sites/toll_plaza.glb"

const LANE_WIDTH := 3.2
const LANE_COUNT := 6
const CANOPY_CLEARANCE := 5.5
const CANOPY_DEPTH := 20.0
const FASCIA_H := 2.4
const ARM_LENGTH := 3.0
const ARM_HEIGHT := 1.05
const ETC_WIDTH := 5.5
## The impulse (N s) a broken barrier arm gets.
const BREAK_IMPULSE := 120.0
## The angle of the arm of an ETC lane when it lifts.
const ETC_ARM_ANGLE := -78.0

var _arms: Array[RigidBody3D] = []
var _arm_lanes: Array[int] = []
var _lane_open: Array[bool] = []
var _lane_z: Array[float] = []
var _lane_meshes: Array[MeshInstance3D] = []
var _area: Area3D
var _centre: Vector3
var _yaw := 0.0
var _half_width := 10.0
## A car may run the toll plaza again after this many seconds.
const REPORT_COOLDOWN := 5.0
var _reported: Dictionary = {}


## Builds the plaza at a city.json POI: {"x","y","z","heading_deg","size":[w,d]}.
func setup(poi: Dictionary) -> void:
	_centre = Vector3(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)), float(poi.get("z", 0.0)))
	_yaw = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0)))
	position = _centre
	rotation.y = _yaw
	if not _build_from_glb():
		_build_procedural()
	_build_area()


# --- the plaza of the props unit -------------------------------------------------------------------

func _build_from_glb() -> bool:
	if not ResourceLoader.exists(PLAZA_GLB):
		return false
	var packed := load(PLAZA_GLB) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	MaterialLibrary.apply(model)
	add_child(model)
	_collect_lanes(model)
	if _lane_z.is_empty():
		return false
	_half_width = maxf(absf(_lane_z[0]), absf(_lane_z[_lane_z.size() - 1])) + 2.0
	_collect_etc(model)
	_collect_arms(model)
	_paint_lane_signals()
	return true


## The lanes of the plaza, sorted from one side to the other (the local z of the plaza).
func _collect_lanes(model: Node3D) -> void:
	var found: Array[MeshInstance3D] = []
	for child in model.find_children("LaneSignal_*", "MeshInstance3D", true, false):
		found.append(child as MeshInstance3D)
	found.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return a.position.z < b.position.z)
	for mesh in found:
		_lane_meshes.append(mesh)
		_lane_z.append(mesh.position.z)


## The ETC lanes are the ones with the ETC road markings (the EtcStrip strips of the plaza);
## without them the outermost lane on each side is the ETC lane.
func _collect_etc(model: Node3D) -> void:
	var strips: Array[float] = []
	for child in model.find_children("EtcStrip*", "Node3D", true, false):
		strips.append((child as Node3D).position.z)
	for i in _lane_z.size():
		var etc := false
		if strips.is_empty():
			etc = i == 0 or i == _lane_z.size() - 1
		else:
			for strip in strips:
				if absf(_lane_z[i] - strip) <= ETC_WIDTH:
					etc = true
		_lane_open.append(etc)


## The barrier arms: frozen bodies that break off, or lifted arms on the ETC lanes.
func _collect_arms(model: Node3D) -> void:
	for i in _lane_z.size():
		var arm := model.find_child("Barrier_%d" % (i + 1), true, false) as Node3D
		if arm == null:
			continue
		if i < _lane_open.size() and _lane_open[i]:
			_lift(arm)
			continue
		var body := _make_breakable(arm)
		_arms.append(body)
		_arm_lanes.append(i)


## Green on the open lanes, red on the closed ones.
func _paint_lane_signals() -> void:
	for i in _lane_meshes.size():
		var mesh := _lane_meshes[i]
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		mat = mat.duplicate() as StandardMaterial3D
		mesh.material_override = mat
		var open_lane := i < _lane_open.size() and _lane_open[i]
		var color := Color("20e070") if open_lane else Color("ff2a3a")
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
		mat.albedo_color = color


## Turns the arm into a frozen RigidBody3D that turns into debris when it is hit.
func _make_breakable(arm: Node3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = arm.name + "_Body"
	body.transform = arm.transform
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.collision_layer = 1
	body.collision_mask = 0
	body.mass = 12.0
	var mesh := arm as MeshInstance3D
	if mesh != null:
		var copy := MeshInstance3D.new()
		copy.name = "Mesh"
		copy.mesh = mesh.mesh
		copy.material_override = mesh.get_active_material(0)
		body.add_child(copy)
	else:
		for child in arm.get_children():
			child.reparent(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _mesh_size(arm)
	shape.shape = box
	body.add_child(shape)
	arm.get_parent().add_child(body)
	arm.queue_free()
	return body


## Raises the arm of an ETC lane (it opens automatically).
func _lift(arm: Node3D) -> void:
	arm.rotation_degrees.x = ETC_ARM_ANGLE


static func _mesh_size(node: Node3D) -> Vector3:
	var result := Vector3.ONE
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.get_aabb()
		if first:
			result = box.size
			first = false
		else:
			result = result.max(box.size)
	return result


# --- the procedural fallback -----------------------------------------------------------------------

func _build_procedural() -> void:
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	add_child(canopy)
	canopy.position = _centre
	canopy.rotation.y = _yaw
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	slab.mesh = ProcMeshes.box(Vector3(CANOPY_DEPTH, 0.5, _half_width * 2.0))
	slab.material_override = ProcMeshes.material("metal")
	slab.position = Vector3(0, CANOPY_CLEARANCE, 0)
	canopy.add_child(slab)
	var fascia := MeshInstance3D.new()
	fascia.name = "Fascia"
	fascia.mesh = ProcMeshes.box(Vector3(0.6, FASCIA_H, _half_width * 2.0))
	fascia.material_override = ProcMeshes.material("metal")
	fascia.position = Vector3(CANOPY_DEPTH * 0.5, CANOPY_CLEARANCE + FASCIA_H * 0.5, 0)
	canopy.add_child(fascia)
	var sign := MeshInstance3D.new()
	sign.name = "Sign"
	sign.mesh = ProcMeshes.box(Vector3(0.2, 1.4, 18.0))
	sign.material_override = ProcMeshes.glow(Color("00704a"), 1.2)
	sign.position = Vector3(CANOPY_DEPTH * 0.5 + 0.35, CANOPY_CLEARANCE + 1.2, 0)
	canopy.add_child(sign)
	var troffers := MeshInstance3D.new()
	troffers.name = "Troffers"
	troffers.mesh = ProcMeshes.box(Vector3(CANOPY_DEPTH * 0.8, 0.08, _half_width * 1.9))
	troffers.material_override = ProcMeshes.glow(Color("f2f2f2"), 2.4)
	troffers.position = Vector3(0, CANOPY_CLEARANCE - 0.28, 0)
	canopy.add_child(troffers)
	_lane_z.clear()
	for i in LANE_COUNT:
		var z := (float(i) - float(LANE_COUNT - 1) * 0.5) * (LANE_WIDTH + 1.8)
		_lane_z.append(z)
		_lane_open.append(i == 0 or i == LANE_COUNT - 1)
		var etc := i == 0 or i == LANE_COUNT - 1
		var box := MeshInstance3D.new()
		box.name = "LaneSignal_%d" % (i + 1)
		box.mesh = ProcMeshes.box(Vector3(0.5, 0.5, 0.5))
		box.material_override = ProcMeshes.glow(Color("20e070") if etc else Color("ff2a3a"), 5.0)
		box.position = Vector3(CANOPY_DEPTH * 0.5 - 0.8, CANOPY_CLEARANCE - 0.9, z)
		canopy.add_child(box)
		_add_arm(canopy, z, etc, i)
	_half_width = maxf(absf(_lane_z[0]), absf(_lane_z[_lane_z.size() - 1])) + 2.0


func _add_arm(parent: Node3D, z: float, etc: bool, index: int) -> void:
	var pivot := Node3D.new()
	pivot.name = "ArmPivot_%d" % index
	pivot.position = Vector3(-CANOPY_DEPTH * 0.1, ARM_HEIGHT, z)
	parent.add_child(pivot)
	var arm := RigidBody3D.new()
	arm.name = "BarrierArm_%d" % index
	arm.freeze = true
	arm.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	arm.collision_layer = 1
	arm.collision_mask = 0
	arm.mass = 12.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, 0.12, ARM_LENGTH)
	shape.shape = box
	shape.position = Vector3(0, 0, ARM_LENGTH * 0.5)
	arm.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = ProcMeshes.box(Vector3(0.12, 0.12, ARM_LENGTH))
	mesh.material_override = ProcMeshes.material("metal")
	arm.add_child(mesh)
	pivot.add_child(arm)
	_arms.append(arm)
	_arm_lanes.append(index)
	if etc:
		_lift(arm)


# --- the trigger and the infraction -----------------------------------------------------------------

func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "TollArea"
	add_child(_area)
	# The area is a child of the plaza, so it sits at the plaza's origin.
	_area.position = Vector3.ZERO
	_area.collision_layer = 1 << 3
	_area.collision_mask = 1 << 1
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CANOPY_DEPTH + 6.0, 14.0, _half_width * 2.0)
	shape.shape = box
	shape.position = Vector3(0, 3.0, 0)
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	_arm_sensors()


## A sensor in front of every closed arm: hitting it breaks the arm off.
func _arm_sensors() -> void:
	for i in _arms.size():
		var lane := _arm_lanes[i]
		if lane < _lane_open.size() and _lane_open[lane]:
			continue
		var arm := _arms[i]
		var sensor := Area3D.new()
		sensor.name = "ArmSensor"
		sensor.collision_layer = 0
		sensor.collision_mask = 1 << 1
		sensor.monitorable = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.5, 3.0, ARM_LENGTH)
		shape.shape = box
		shape.position = Vector3(-3.0, 1.2, ARM_LENGTH * 0.5)
		sensor.add_child(shape)
		sensor.body_entered.connect(_on_arm_hit.bind(lane))
		arm.add_child(sensor)


## Lane index for a world position, or -1 when the position is outside the plaza.
func lane_at(world_position: Vector3) -> int:
	var local := (world_position - _centre).rotated(Vector3.UP, -_yaw)
	var best := -1
	var best_distance := 8.0
	for i in _lane_z.size():
		var distance := absf(local.z - _lane_z[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null:
		return
	if vehicle.is_airborne():
		_report(vehicle)
		return
	var lane := lane_at(vehicle.global_position)
	if lane < 0 or lane >= _lane_open.size():
		return
	if _lane_open[lane]:
		return  # the ETC lane opened its arm
	_report(vehicle)


## A vehicle that hits a closed arm hard enough breaks it off; the lane is then unpaid.
func _on_arm_hit(body: Node3D, lane: int) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null:
		return
	if lane < _lane_open.size() and _lane_open[lane]:
		return
	if vehicle.get_speed_kmh() < 20.0:
		return
	break_arm(lane, vehicle.linear_velocity)
	_report(vehicle)


## A closed lane that is hit: the arm breaks off and becomes debris.
func break_arm(lane: int, direction: Vector3 = Vector3.ZERO) -> void:
	for i in _arms.size():
		if _arm_lanes[i] != lane:
			continue
		var arm := _arms[i]
		arm.freeze = false
		# The debris layer (bit 4), not the world and the props: the cars drive on the mask
		# 0b111, so a broken arm must not stop them.
		arm.collision_layer = Layers.DEBRIS
		arm.collision_mask = Layers.WORLD
		var push := direction.normalized() * BREAK_IMPULSE if direction.length_squared() > 0.01 \
			else Vector3(BREAK_IMPULSE * 0.5, BREAK_IMPULSE * 0.2, 0.0)
		arm.apply_central_impulse(push)


func _report(vehicle: VehicleBase) -> void:
	if vehicle.team != VehicleBase.Team.PLAYER:
		return
	var id := vehicle.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_reported.get(id, -1000.0)) < REPORT_COOLDOWN:
		return
	_reported[id] = now
	Events.infraction.emit(vehicle, &"toll_evaded")

extends Node3D
## Toll plaza (收费站, ref/shanghai/SHANGHAI_DOSSIER.md §7.2). The plaza of the props unit is
## used when it is there: the 3+3 lane plaza of the G50 (`toll_plaza_road.glb`, its lanes on the
## lanes of the road) or the dossier's 10+10 lane one (`toll_plaza.glb`). Its barrier arms
## (`Barrier_<n>`, the lane in their extras) become frozen bodies that break off when they are
## hit, its lane signals (`LaneSignal_<n>_Red` / `_Green`) show green on the ETC lanes and red on
## the closed ones, and the ETC lanes lift their arms. A closed lane opens for the cars that pay:
## the traffic and the police (their ETC tag) and the player under PAY_KMH (the booth takes the
## toll). Driving a closed lane or flying over the plaza raises the "toll_evaded" infraction.
##
## The plazas of the props unit are built for traffic along their x axis (the eastbound lanes on
## +z): the heading of the POI is the heading of the road, a road that runs east turns them by
## nothing (MODEL_YAW).

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")
const Layers := preload("res://world/api/layers.gd")
const PLAZA_GLB := "res://assets/props/sites/toll_plaza.glb"
const ROAD_PLAZA_GLB := "res://assets/props/sites/toll_plaza_road.glb"
const MODEL_YAW := PI * 0.5

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
## The angle of the arm of an open lane.
const ETC_ARM_ANGLE := -78.0
## A closed lane opens for a paying car: the player pays under this speed (km/h).
const PAY_KMH := 30.0
## The sensor of a closed lane reaches this far upstream of its arm (m); the lane stays open this
## long after the last paying car entered it (s); the arm swings up in this time (s).
const SENSOR_LENGTH := 26.0
## The spot lights of the markers of the plaza (the values of the props preview) and the distance
## from which they fade out.
const LIGHT_ENERGY := 9.0
const LIGHT_RANGE := 34.0
const LIGHT_ANGLE := 78.0
const LIGHT_COLOUR := Color(1.0, 0.94, 0.84)
const LIGHT_FADE := 320.0
const OPEN_TIME := 6.0
const LIFT_TIME := 0.45

var _arms: Array[RigidBody3D] = []
var _arm_lanes: Array[int] = []
var _arm_rest: Array[Vector3] = []
var _lane_open: Array[bool] = []
var _lane_z: Array[float] = []
var _lane_meshes: Array[MeshInstance3D] = []
## The two states of the signal of every lane (the plazas of the props unit ship both).
var _signal_red: Array[MeshInstance3D] = []
var _signal_green: Array[MeshInstance3D] = []
## Until when a closed lane is open for the car that paid (s, engine clock).
var _open_until: Array[float] = []
var _broken: Array[bool] = []
var _area: Area3D
var _centre: Vector3
var _yaw := 0.0
var _half_width := 10.0
## A car may run the toll plaza again after this many seconds.
const REPORT_COOLDOWN := 5.0
var _reported: Dictionary = {}


## Builds the plaza at a city.json POI: {"x","y","z","heading_deg","size":[w,d],"asset"}.
func setup(poi: Dictionary) -> void:
	_centre = Vector3(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)), float(poi.get("z", 0.0)))
	_yaw = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0))) + MODEL_YAW
	position = _centre
	rotation.y = _yaw
	var glb := ROAD_PLAZA_GLB if str(poi.get("asset", "")) == "toll_plaza_road" else PLAZA_GLB
	if not _build_from_glb(glb):
		_build_procedural()
	_build_area()


func _physics_process(_delta: float) -> void:
	# A lane that a paying car opened closes again when its time is up.
	var now := _now()
	for i in _open_until.size():
		if _open_until[i] > 0.0 and now >= _open_until[i]:
			_open_until[i] = 0.0
			_set_lane_arm(i, false)


# --- the plaza of the props unit -------------------------------------------------------------------

func _build_from_glb(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	MaterialLibrary.apply(model)
	add_child(model)
	_add_marker_lights(model)
	_collect_lanes(model)
	if _lane_z.is_empty():
		return false
	_half_width = maxf(absf(_lane_z[0]), absf(_lane_z[_lane_z.size() - 1])) + 2.0
	_collect_etc(model)
	_collect_arms(model)
	_paint_lane_signals()
	return true


## The `Light` / `Light_<n>` markers of the plaza become spot lights (the values of the props
## preview, CONTRACTS.md §2): without them the plaza was black under its canopy at night.
func _add_marker_lights(model: Node3D) -> void:
	for child in model.find_children("Light*", "Node3D", true, false):
		var marker := child as Node3D
		var marker_name := String(marker.name)
		if not (marker_name == "Light" or marker_name.begins_with("Light_")):
			continue
		var spot := SpotLight3D.new()
		spot.name = "%s_Spot" % marker_name
		spot.light_energy = LIGHT_ENERGY
		spot.light_color = LIGHT_COLOUR
		spot.spot_range = LIGHT_RANGE
		spot.spot_angle = LIGHT_ANGLE
		spot.spot_angle_attenuation = 0.5
		spot.shadow_enabled = false
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = LIGHT_FADE
		spot.distance_fade_length = 60.0
		marker.add_child(spot)


## The lanes of the plaza, sorted from one side to the other (the local z of the plaza): one per
## `LaneSignal_<n>_Red` (each lane ships a red and a green state), or one per signal mesh.
func _collect_lanes(model: Node3D) -> void:
	var reds: Array[MeshInstance3D] = []
	var all: Array[MeshInstance3D] = []
	for child in model.find_children("LaneSignal_*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		all.append(mesh)
		if String(mesh.name).ends_with("_Red"):
			reds.append(mesh)
	var lanes := reds if not reds.is_empty() else all
	lanes.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return _local(a).z < _local(b).z)
	for mesh in lanes:
		_lane_meshes.append(mesh)
		_lane_z.append(_local(mesh).z)
		_signal_red.append(mesh if not reds.is_empty() else null)
		var green: MeshInstance3D = null
		if not reds.is_empty():
			var name := String(mesh.name).trim_suffix("_Red") + "_Green"
			green = model.find_child(name, true, false) as MeshInstance3D
		_signal_green.append(green)
		_open_until.append(0.0)


## The ETC lanes: the lane of every arm whose extras say "etc"; without them the lanes under the
## ETC road markings (the EtcStrip strips of the plaza), and without those the outermost lanes.
func _collect_etc(model: Node3D) -> void:
	for i in _lane_z.size():
		_lane_open.append(false)
	var tagged := false
	for child in model.find_children("Barrier_*", "Node3D", true, false):
		var extras: Dictionary = (child as Node3D).get_meta("extras", {})
		if not extras.has("etc"):
			continue
		tagged = true
		var lane := _lane_of(child as Node3D)
		if lane >= 0 and int(extras["etc"]) != 0:
			_lane_open[lane] = true
	if tagged:
		return
	var strips: Array[float] = []
	for child in model.find_children("EtcStrip*", "Node3D", true, false):
		strips.append(_local(child as Node3D).z)
	if strips.is_empty():
		_lane_open[0] = true
		_lane_open[_lane_z.size() - 1] = true
		return
	for strip in strips:
		var best := -1
		for i in _lane_z.size():
			if best < 0 or absf(_lane_z[i] - strip) < absf(_lane_z[best] - strip):
				best = i
		if best >= 0 and absf(_lane_z[best] - strip) <= ETC_WIDTH:
			_lane_open[best] = true


## The barrier arms: lifted on the ETC lanes, frozen bodies that break off (and lift for a paying
## car) on the closed ones. Every arm finds its lane by the lane in its extras (the hinge stands on
## the island next to the lane, closer to the next lane than to its own one on a slim island).
func _collect_arms(model: Node3D) -> void:
	for child in model.find_children("Barrier_*", "Node3D", true, false):
		var arm := child as Node3D
		if String(arm.name).ends_with("_Body"):
			continue
		var lane := _lane_of(arm)
		if lane < 0:
			continue
		if _lane_open[lane]:
			_lift(arm)
			continue
		var body := _make_breakable(arm)
		_arms.append(body)
		_arm_lanes.append(lane)
		_arm_rest.append(body.rotation_degrees)
		_broken.append(false)


## The lane of an arm: its "lane_y" extra (Blender, so the local z is -lane_y), or the nearest lane.
func _lane_of(node: Node3D) -> int:
	var extras: Dictionary = node.get_meta("extras", {})
	var z := _local(node).z
	if extras.has("lane_y"):
		z = -float(extras["lane_y"])
	var best := -1
	var best_distance := 4.0
	for i in _lane_z.size():
		var distance := absf(z - _lane_z[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## The position of a node of the model in the plaza's own space.
func _local(node: Node3D) -> Vector3:
	var at := Vector3.ZERO
	var current: Node = node
	var xform := Transform3D.IDENTITY
	while current != null and current != self:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform * at


## Green on the open lanes, red on the closed ones: the plaza shows one of the two states, or it
## paints its one signal mesh.
func _paint_lane_signals() -> void:
	for i in _lane_meshes.size():
		_show_signal(i, i < _lane_open.size() and _lane_open[i])


func _show_signal(lane: int, green: bool) -> void:
	if lane >= _lane_meshes.size():
		return
	var red_mesh := _signal_red[lane]
	var green_mesh := _signal_green[lane]
	if red_mesh != null and green_mesh != null:
		red_mesh.visible = not green
		green_mesh.visible = green
		return
	var mesh := _lane_meshes[lane]
	var mat := mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat = mat.duplicate() as StandardMaterial3D
	mesh.material_override = mat
	var color := Color("20e070") if green else Color("ff2a3a")
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
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
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
	shape.position = _mesh_centre(arm)
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
	for child in [node] + node.find_children("*", "MeshInstance3D", true, false):
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


static func _mesh_centre(node: Node3D) -> Vector3:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return Vector3.ZERO
	var box := mi.get_aabb()
	return box.position + box.size * 0.5


# --- the procedural fallback -----------------------------------------------------------------------

func _build_procedural() -> void:
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	add_child(canopy)
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
		_open_until.append(0.0)
		var etc := i == 0 or i == LANE_COUNT - 1
		_lane_open.append(etc)
		var box := MeshInstance3D.new()
		box.name = "LaneSignal_%d" % (i + 1)
		box.mesh = ProcMeshes.box(Vector3(0.5, 0.5, 0.5))
		box.material_override = ProcMeshes.glow(Color("20e070") if etc else Color("ff2a3a"), 5.0)
		box.position = Vector3(CANOPY_DEPTH * 0.5 - 0.8, CANOPY_CLEARANCE - 0.9, z)
		canopy.add_child(box)
		_lane_meshes.append(box)
		_signal_red.append(null)
		_signal_green.append(null)
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
	arm.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
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
	if etc:
		_lift(arm)
		return
	_arms.append(arm)
	_arm_lanes.append(index)
	_arm_rest.append(arm.rotation_degrees)
	_broken.append(false)


# --- the trigger, the paying cars and the infraction -------------------------------------------------

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
	_pay_sensors()


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


## A sensor upstream of every closed lane: a car that pays there opens the lane before it reaches
## the arm. The eastbound lanes (local +z) run along +x, the westbound ones along -x.
func _pay_sensors() -> void:
	for lane in _lane_z.size():
		if _lane_open[lane]:
			continue
		var direction := 1.0 if _lane_z[lane] > 0.0 else -1.0
		var sensor := Area3D.new()
		sensor.name = "PaySensor_%d" % lane
		sensor.collision_layer = 0
		sensor.collision_mask = 1 << 1
		sensor.monitorable = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(SENSOR_LENGTH, 3.0, 2.8)
		shape.shape = box
		shape.position = Vector3(-direction * (SENSOR_LENGTH * 0.5 + 1.0), 1.5, _lane_z[lane])
		sensor.add_child(shape)
		sensor.body_entered.connect(_on_paying.bind(lane))
		add_child(sensor)


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


## True while the lane lets a car through without the toll: an ETC lane, or a closed lane that a
## paying car opened.
func lane_is_open(lane: int) -> bool:
	if lane < 0 or lane >= _lane_open.size():
		return false
	return _lane_open[lane] or _open_until[lane] > 0.0


## A car pays: the traffic and the police always (their ETC tag), the player under PAY_KMH.
func _on_paying(body: Node3D, lane: int) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null:
		return
	if vehicle.team == VehicleBase.Team.PLAYER and vehicle.get_speed_kmh() >= PAY_KMH:
		return
	_open_until[lane] = _now() + OPEN_TIME
	_set_lane_arm(lane, true)


## Swings the arm of a closed lane up (open) or down (closed); its collision follows it.
func _set_lane_arm(lane: int, open: bool) -> void:
	for i in _arms.size():
		if _arm_lanes[i] != lane or _broken[i]:
			continue
		var arm := _arms[i]
		var rest := _arm_rest[i]
		var target := Vector3(ETC_ARM_ANGLE, rest.y, rest.z) if open else rest
		var tween := arm.create_tween()
		tween.tween_property(arm, "rotation_degrees", target, LIFT_TIME)
	_show_signal(lane, open or _lane_open[lane])


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
	if lane_is_open(lane):
		return  # the ETC lane, or the lane the car paid for
	_report(vehicle)


## A vehicle that hits a closed arm hard enough breaks it off; the lane is then unpaid.
func _on_arm_hit(body: Node3D, lane: int) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null:
		return
	if lane_is_open(lane):
		return
	# A car that pays at the arm itself (the traffic, or a player who crept up to it) opens it.
	if vehicle.team != VehicleBase.Team.PLAYER or vehicle.get_speed_kmh() < PAY_KMH:
		_on_paying(body, lane)
		return
	break_arm(lane, vehicle.linear_velocity)
	_report(vehicle)


## A closed lane that is hit: the arm breaks off and becomes debris.
func break_arm(lane: int, direction: Vector3 = Vector3.ZERO) -> void:
	for i in _arms.size():
		if _arm_lanes[i] != lane or _broken[i]:
			continue
		_broken[i] = true
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
	var now := _now()
	if now - float(_reported.get(id, -1000.0)) < REPORT_COOLDOWN:
		return
	_reported[id] = now
	Events.infraction.emit(vehicle, &"toll_evaded")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

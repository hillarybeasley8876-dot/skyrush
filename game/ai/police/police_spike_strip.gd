class_name PoliceSpikeStrip
extends Node3D
## A spike strip (ref/gameplay/DOSSIER.md §3.1 and §6.3).
##
## The strip is the model of the props unit (game/assets/props/street/spike_strip.glb): a four
## metre case with a row of spikes in it. Two cases end to end make the seven metre strip of the
## dossier (§6.3: 7 m x 0.6 m across two lanes), and the case lies ACROSS the road, not along
## it. The strip unrolls in 0.35 s: the length grows from the lamp end and the spikes come out
## of the case. A car that drives over it gets punctured tyres (the grip and the top speed drop
## for eight seconds). The police cars are not affected (dossier §3.1: "Cop cars are not
## affected by spikes").

## The model of the props unit.
const SCENE := preload("res://assets/props/street/spike_strip.glb")
## The length of the whole strip (m) and the length of one case (m).
const STRIP_LENGTH := 7.0
const CASE_LENGTH := 4.0
## The number of cases that make the strip.
const CASE_COUNT := 2
## The depth of the strip (m).
const STRIP_DEPTH := 0.6
## The seconds the strip needs to deploy.
const DEPLOY_TIME := 0.35
## The scale the case has while it is rolled up.
const ROLLED_SCALE := 0.05
## The colour of the warning lamp.
const LAMP_COLOR := Color("ff2030")
## The blink of the lamp (Hz).
const LAMP_BLINK := 2.0
## The height of the trigger volume (m).
const TRIGGER_HEIGHT := 0.8
## The seconds the strip needs to fall onto the road.
const FALL_TIME := 0.6
## The height the strip falls from (m).
const FALL_HEIGHT := 6.0
## The size of the housing of the lamp (m).
const LAMP_HOUSING := Vector3(0.16, 0.10, 0.12)
## The radius of the lens of the lamp (m).
const LAMP_LENS := 0.045
## The energy of the lens of the lamp.
const LAMP_EMISSION := 6.0
## The distance of the lamp from the end of the strip (m).
const LAMP_OFFSET := 0.12
## The radius of the housing of the lamp (m).
const LAMP_RADIUS := 0.05
## The height of the housing of the lamp (m).
const LAMP_HEIGHT := 0.08
## The texture scale of the housing: the metal atlas reads at 512 px/m on it.
const LAMP_UV_SCALE := 0.25
## The colour of the housing.
const LAMP_HOUSING_COLOR := Color(0.18, 0.18, 0.20)

var _deployed: float = 0.0
var _fall: float = 0.0
var _fall_offset: float = 0.0
var _area: Area3D = null
var _lamp: MeshInstance3D = null
var _lens: MeshInstance3D = null
var _cases: Array[Node3D] = []
var _spikes: Array[Node3D] = []
## The clock of the lamp: the blink runs on its own time, not on the deploy.
var _lamp_time: float = 0.0


## Builds the strip: the two cases, the trigger volume and the warning lamp.
##
## The local X axis of the strip is its length; the caller turns it across the road.
func setup(across: Vector3) -> void:
	aim(across)
	_build_cases()
	_build_area()
	_build_lamp()
	reset_strip()


## Turns the strip across the road (the length of the strip is its local X axis).
func aim(across: Vector3) -> void:
	var a := across.normalized() if across.length_squared() > 0.01 else Vector3.RIGHT
	rotation.y = atan2(-a.z, a.x)


## Puts the strip back into its rolled up state (the pool uses it for the next block).
func reset_strip() -> void:
	_deployed = 0.0
	_fall = 0.0
	_fall_offset = 0.0
	_lamp_time = 0.0
	_apply_deploy()
	if _lens != null:
		_lens.visible = true


## Switches the strip on and off: a strip that waits in the pool must not watch for cars.
func set_active(active: bool) -> void:
	visible = active
	if _area != null:
		_area.monitoring = active


## The strip falls from the drone: it starts FALL_HEIGHT above the road.
func drop_from_height() -> void:
	_fall = FALL_TIME
	_fall_offset = FALL_HEIGHT
	position.y = FALL_HEIGHT


## The two cases that make the strip.
func _build_cases() -> void:
	for i in CASE_COUNT:
		var node := SCENE.instantiate() as Node3D
		if node == null:
			continue
		add_child(node)
		MaterialLibrary.apply(node)
		_cases.append(node)
		var spikes := node.find_child("Spikes", true, false) as Node3D
		if spikes != null:
			_spikes.append(spikes)


## The trigger volume over the strip.
func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "Trigger"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(STRIP_LENGTH, TRIGGER_HEIGHT, STRIP_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, TRIGGER_HEIGHT * 0.5, 0.0)
	_area.add_child(shape)
	_area.collision_layer = 0
	_area.collision_mask = 1 << 1
	_area.monitoring = true
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


## The warning lamp at the end of the strip: a dark housing with a red lens, so it reads as a
## lamp and not as a floating ball (ART.md §5: no flat untextured surfaces).
func _build_lamp() -> void:
	_lamp = MeshInstance3D.new()
	_lamp.name = "Lamp"
	var housing := CylinderMesh.new()
	housing.top_radius = LAMP_RADIUS
	housing.bottom_radius = LAMP_RADIUS
	housing.height = LAMP_HEIGHT
	housing.radial_segments = 12
	_lamp.mesh = housing
	_lamp.material_override = _housing_material()
	_lamp.position = Vector3(STRIP_LENGTH * 0.5 + LAMP_OFFSET, LAMP_HEIGHT * 0.5, 0.0)
	add_child(_lamp)
	_lens = MeshInstance3D.new()
	_lens.name = "LampLens"
	var lens := SphereMesh.new()
	lens.radius = LAMP_LENS
	lens.height = LAMP_LENS * 2.0
	_lens.mesh = lens
	var material := StandardMaterial3D.new()
	material.albedo_color = LAMP_COLOR
	material.emission_enabled = true
	material.emission = LAMP_COLOR
	material.emission_energy_multiplier = LAMP_EMISSION
	_lens.material_override = material
	_lens.position = _lamp.position + Vector3(0.0, LAMP_HEIGHT * 0.5 + LAMP_LENS * 0.6, 0.0)
	add_child(_lens)


## The material of the housing: the texture of the case, darkened.
##
## The texture scale is lowered so the metal atlas reads at the density of ART.md §5
## (512 px/m) on a housing that is only eight centimetres high.
func _housing_material() -> Material:
	if _cases.is_empty():
		return null
	for child in _cases[0].get_children():
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var source := mesh.get_active_material(0)
		if source == null:
			continue
		var copy := source.duplicate() as Material
		var base := copy as BaseMaterial3D
		if base != null:
			base.albedo_color = LAMP_HOUSING_COLOR
			base.uv1_scale = Vector3.ONE * LAMP_UV_SCALE
		return copy
	return null


## The deploy: the strip unrolls from the lamp end and the spikes come out of the case.
func tick(dt: float) -> void:
	if _fall > 0.0:
		# The strip falls out of the drone.
		_fall = maxf(_fall - dt, 0.0)
		position.y = _fall_offset * (_fall / FALL_TIME)
		return
	if _deployed < 1.0:
		_deployed = minf(_deployed + dt / DEPLOY_TIME, 1.0)
		_apply_deploy()
	_lamp_time += dt
	if _lens != null:
		var half := 0.5 / LAMP_BLINK
		_lens.visible = fmod(_lamp_time, 1.0 / LAMP_BLINK) < half


## Moves the cases and the spikes to the state of the deploy.
##
## The strip is centred on the node: the cases run from -3.5 m to +3.5 m, and they unroll
## from the lamp end (+3.5 m) towards the other end. The trigger volume is centred too, so a
## car that drives over the spikes is punctured.
func _apply_deploy() -> void:
	var segment := STRIP_LENGTH / float(CASE_COUNT)
	var full := segment / CASE_LENGTH
	var x := STRIP_LENGTH * 0.5
	for i in _cases.size():
		var grown := clampf(_deployed * float(CASE_COUNT) - float(i), 0.0, 1.0)
		var length := maxf(full * grown, full * ROLLED_SCALE)
		var basis := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0),
				Vector3(1.0, 0.0, 0.0) * length)
		var centre := x - segment * grown * 0.5
		_cases[i].transform = Transform3D(basis, Vector3(centre, 0.0, 0.0))
		x -= segment * grown
	for spikes in _spikes:
		spikes.scale = Vector3(1.0, maxf(0.02, _deployed), 1.0)


## The extent of the cases along the local X axis of the strip (m).
##
## The strip is centred on the node: the cases run from -3.5 m to +3.5 m, so the trigger
## volume and the spikes are on the same place.
func case_extent() -> Vector2:
	var out := Vector2(INF, -INF)
	for node in _cases:
		# The case lies along its own Z axis: that is the axis the strip scales.
		var half := node.transform.basis.get_scale().z * CASE_LENGTH * 0.5
		var centre := node.transform.origin.x
		out.x = minf(out.x, centre - half)
		out.y = maxf(out.y, centre + half)
	return out


## The place of the warning lamp along the local X axis (m).
func lamp_position() -> Vector3:
	return _lamp.position if _lamp != null else Vector3.ZERO


## A car drove over the strip: its tyres are punctured.
func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null or vehicle.is_wrecked:
		return
	if vehicle.team == VehicleBase.Team.POLICE:
		# The police cars drive over their own spikes (dossier §3.1).
		return
	var director := get_tree().get_first_node_in_group(&"police_director") as PoliceDirector
	if director != null:
		director.debuff.puncture(vehicle)

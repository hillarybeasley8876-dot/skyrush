extends VehicleBase
## Stand-in Roadster body for the fx_thrusters demo.
##
## The real hero car (game/assets/cars/roadster/roadster.glb) is built by the car_model unit; this
## stand-in carries the same ten `Nozzle_*` markers at the dossier positions (ref/roadster/DOSSIER.md
## §5) so the plume system can be developed and reviewed before the glTF exists.

const NozzleTable := preload("res://fx/thrusters/lib/nozzle_table.gd")

const BODY_LENGTH := 4.38
const BODY_WIDTH := 1.98
const WHEELBASE := 2.825
const FRONT_TRACK := 1.56
const REAR_TRACK := 1.63
const TYRE_RADIUS := 0.35

var _visual: Node3D
## When the real glTF is available the demo shows that model instead of the stand-in body, but
## still needs a VehicleBase wrapper (the plume system attaches to vehicles).
var build_body: bool = true
var build_markers: bool = true


func _ready() -> void:
	super._ready()
	mass = 1900.0
	collision_layer = 1 << 1
	collision_mask = 0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if build_body:
		_build_body()
	if build_markers:
		_build_markers()


## Where a real glTF instance should be parented (the Visual root).
func get_visual_root() -> Node3D:
	return _visual


func _build_body() -> void:
	_add_box("Sill", Vector3(1.9, 0.24, 4.2), Vector3(0, 0.24, 0), _black())
	_add_box("Body", Vector3(BODY_WIDTH, 0.44, BODY_LENGTH), Vector3(0, 0.56, 0), _white())
	_add_box("Cabin", Vector3(1.42, 0.32, 2.0), Vector3(0, 0.92, -0.18), _glass())
	_add_box("Deck", Vector3(1.7, 0.07, 0.36), Vector3(0, 0.79, 2.05), _white())
	_add_box("LightBar", Vector3(1.62, 0.055, 0.05), Vector3(0, 0.72, 2.19), _red_bar())
	for side in [-1.0, 1.0]:
		_add_wheel("Wheel", Vector3(side * FRONT_TRACK * 0.5, TYRE_RADIUS, -WHEELBASE * 0.5))
		_add_wheel("Wheel", Vector3(side * REAR_TRACK * 0.5, TYRE_RADIUS, WHEELBASE * 0.5))
	for i in 4:
		var x: float = -0.36 + 0.24 * float(i)
		_add_box("NozzleBezel", Vector3(0.08, 0.08, 0.02), Vector3(x, 0.5, 2.2), _metal())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BODY_WIDTH, 1.0, BODY_LENGTH)
	shape.shape = box
	shape.position = Vector3(0, 0.55, 0)
	add_child(shape)


func _add_box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	_visual.add_child(mi)


func _add_wheel(node_name: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = TYRE_RADIUS
	cyl.bottom_radius = TYRE_RADIUS
	cyl.height = 0.3
	cyl.radial_segments = 20
	mi.mesh = cyl
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 90)
	mi.material_override = _rubber()
	_visual.add_child(mi)


## The ten jet markers. -Z points along the jet, exactly like the glTF empties.
func _build_markers() -> void:
	for nozzle_name in NozzleTable.NAMES:
		var cfg: Dictionary = NozzleTable.get_nozzle(nozzle_name)
		var marker := Marker3D.new()
		marker.name = String(nozzle_name)
		var dir: Vector3 = cfg["dir"]
		var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
		marker.transform = Transform3D(Basis.looking_at(dir, up), cfg["pos"])
		_visual.add_child(marker)


func _white() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.925, 0.929, 0.937)
	m.metallic = 0.25
	m.roughness = 0.28
	return m


func _black() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.075)
	m.metallic = 0.1
	m.roughness = 0.45
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.09, 0.05, 0.85)
	m.metallic = 0.6
	m.roughness = 0.08
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.61, 0.58, 0.55)
	m.metallic = 0.9
	m.roughness = 0.22
	return m


func _rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.16, 0.16)
	m.roughness = 0.85
	return m


func _red_bar() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.02, 0.03)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.1, 0.18)
	m.emission_energy_multiplier = 4.0
	return m

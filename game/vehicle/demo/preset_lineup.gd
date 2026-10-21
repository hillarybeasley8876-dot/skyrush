extends Node3D
## The evidence sheet of the NPC presets: every car of the game parks in a row, so the sheet
## shows that each preset loads its own glb (no white placeholders) and that the wheels sit in
## their arches.
##
## Run: tools/godot.sh shot --scene=res://vehicle/demo/preset_lineup.tscn --out=veh_presets \
##           --cams="lineup:0,4,-22:0,1,4:60" --warm=120

const CarScene := preload("res://vehicle/player_car.tscn")
const DebugOverlay := preload("res://core/debug_overlay.gd")

## The presets of the sheet, in the order of the row.
const PRESETS: Array[String] = ["roadster", "sedan", "hatch_ev", "suv", "taxi", "van", "truck",
		"bus", "robotaxi", "patrol", "interceptor", "heavy_suv"]
## The gap between two cars (m).
const GAP := 1.6
## The row is centred on the origin.
const COLUMNS := 4
## The cars are frozen after they have settled on the ground (seconds).
const SETTLE_TIME := 1.5

## The cars of the sheet.
var _cars: Array[ArcadeCar] = []
var _settled: float = 0.0


func _ready() -> void:
	var specs: Array[CarSpec] = []
	for id: String in PRESETS:
		var spec: CarSpec = load("res://vehicle/specs/%s.tres" % id) as CarSpec
		if spec == null:
			push_error("preset_lineup: no preset %s" % id)
			continue
		specs.append(spec)
	# The rows: four cars per row, the slot of a car follows its own size, so the bus and the
	# truck do not stand in their neighbours.
	var z: float = 0.0
	for row_start in range(0, specs.size(), COLUMNS):
		var row: Array[CarSpec] = specs.slice(row_start, mini(row_start + COLUMNS, specs.size()))
		var width: float = 0.0
		var longest: float = 0.0
		for spec in row:
			width += spec.body_size.x + GAP
			longest = maxf(longest, spec.body_size.z)
		width -= GAP
		var x: float = -width * 0.5
		for spec in row:
			_spawn(spec, Vector3(x + spec.body_size.x * 0.5, 0.05, z))
			x += spec.body_size.x + GAP
		z += longest + GAP
	_build_lights()
	if Game.option("debug") != "":
		add_child(DebugOverlay.new())


## Spawns a car and lets it settle on the ground.
func _spawn(spec: CarSpec, place: Vector3) -> void:
	var car: ArcadeCar = CarScene.instantiate() as ArcadeCar
	car.spec = spec
	car.player_controlled = false
	add_child(car)
	car.reset_to(Transform3D(Basis(Vector3.UP, PI), place))
	_cars.append(car)


## The cars settle on the ground and are then frozen for the shot.
func _physics_process(delta: float) -> void:
	if _cars.is_empty():
		return
	_settled += delta
	if _settled < SETTLE_TIME:
		return
	for car in _cars:
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true


## The night sky of the environment unit, a soft key light and the ground of the sheet.
func _build_lights() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(70.0, 0.2, 50.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.09)
	mat.roughness = 0.85
	box.material = mat
	# The ground of the sheet is a real body: the cars have to settle on it.
	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = Vector3(0.0, -0.1, 12.0)
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = box.size
	shape.shape = collision
	shape.position = mesh.position
	ground.add_child(shape)
	add_child(ground)
	var env := preload("res://world/env/environment.tscn").instantiate()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.8
	sun.light_color = Color(0.8, 0.88, 1.0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.6, 0.7, 1.0)
	add_child(fill)

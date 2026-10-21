class_name GatePylon
extends RefCounted
## One pylon of a race gate: a chamfered galvanised column with corner trims, a base flange
## with its bolts, a cable duct up to the beam and an LED channel with its mounting brackets.
##
## The parts are separate meshes so the gate reads as a built object and not as a pale box: a
## pylon is the biggest surface of a gate and it must not be the brightest thing in the frame
## (ART.md 2: the car is the brightest object).

const COLUMN := Vector3(0.62, 7.5, 0.62)  ## m: the column of the pylon
const TRIM := 0.13        ## m: the corner trims that chamfer the column
const FLANGE := Vector3(1.06, 0.025, 1.06)  ## m: the base flange
const BOLT_RADIUS := 0.02  ## m
const BOLT_HEIGHT := 0.03  ## m
const BOLT_RING := 0.42    ## m: the radius of the ring of bolts around the column
const BOLT_COUNT := 8
const LED_HEIGHT := 6.6    ## m: the height of the LED strip
const LED_CHANNEL := Vector3(0.24, 6.9, 0.18)  ## m: the dark channel the strip sits in
const LED_STRIP := Vector3(0.11, 6.5, 0.05)   ## m: the LED strip itself
const LED_OFFSET := 0.30   ## m: the strip stands this far off the face of the column
const DUCT := Vector3(0.17, 6.2, 0.11)  ## m: the cable duct up to the beam
const DUCT_OFFSET := 0.30  ## m
const BRACKET_COUNT := 4
const BRACKET := Vector3(0.3, 0.06, 0.1)  ## m: the brackets of the LED channel


## Builds one pylon at `x` (the side of the road it stands on).
static func build(parent: Node3D, x: float, steel: Material, dark: Material, led: Material) -> void:
	var side := 1.0 if x >= 0.0 else -1.0
	var column := _box(parent, "Column", COLUMN, Vector3(x, COLUMN.y * 0.5, 0.0), steel)
	column.name = "Column"
	_add_trims(parent, x, steel)
	_add_flange(parent, x, steel)
	_add_bolts(parent, x, steel)
	_add_duct(parent, x, side, dark)
	_add_led_channel(parent, x, side, dark, led)


## A box mesh with a material.
static func _box(parent: Node3D, node_name: String, size: Vector3, position: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = position
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


## The four corner trims: they chamfer the column, the way a real pylon is folded from sheet.
static func _add_trims(parent: Node3D, x: float, steel: Material) -> void:
	var half := COLUMN.x * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var trim := _box(parent, "Trim", Vector3(TRIM, COLUMN.y, TRIM),
				Vector3(x + sx * half * 0.82, COLUMN.y * 0.5, sz * half * 0.82), steel)
			trim.rotation.y = PI * 0.25


## The base flange: the pylon is bolted to the ground through it.
static func _add_flange(parent: Node3D, x: float, steel: Material) -> void:
	_box(parent, "Flange", FLANGE, Vector3(x, FLANGE.y * 0.5, 0.0), steel)


## The eight bolts of the flange.
static func _add_bolts(parent: Node3D, x: float, steel: Material) -> void:
	for i in BOLT_COUNT:
		var angle := TAU * float(i) / float(BOLT_COUNT)
		var cylinder := MeshInstance3D.new()
		cylinder.name = "Bolt%d" % i
		var shape := CylinderMesh.new()
		shape.top_radius = BOLT_RADIUS
		shape.bottom_radius = BOLT_RADIUS
		shape.height = BOLT_HEIGHT
		shape.radial_segments = 6
		cylinder.mesh = shape
		cylinder.position = Vector3(x + cos(angle) * BOLT_RING, FLANGE.y + BOLT_HEIGHT * 0.5,
			sin(angle) * BOLT_RING)
		cylinder.material_override = steel
		parent.add_child(cylinder)


## The cable duct that runs up the inner face of the pylon to the beam.
static func _add_duct(parent: Node3D, x: float, side: float, dark: Material) -> void:
	_box(parent, "Duct", DUCT, Vector3(x - side * DUCT_OFFSET, DUCT.y * 0.5, 0.0), dark)


## The LED channel: a dark backing with the light strip in it and the brackets that hold it.
static func _add_led_channel(parent: Node3D, x: float, side: float, dark: Material,
		led: Material) -> void:
	var channel_x := x - side * LED_OFFSET
	_box(parent, "LedChannel", LED_CHANNEL, Vector3(channel_x, LED_HEIGHT * 0.5 + 0.35, 0.0), dark)
	_box(parent, "LedStrip", LED_STRIP, Vector3(channel_x - side * 0.04,
		LED_HEIGHT * 0.5 + 0.35, 0.0), led)
	for i in BRACKET_COUNT:
		var y := 0.9 + float(i) * 1.9
		_box(parent, "Bracket%d" % i, BRACKET,
			Vector3(channel_x, y, 0.0), dark)

class_name RaceGate
extends Area3D
## A checkpoint gate of a race: two galvanised pylons with a hazard plinth, an LED board on
## the top beam, a hologram curtain across the opening and chevrons on the tarmac.
##
## The gate is the trigger of a checkpoint: it watches the vehicles (physics layer 2) and
## reports every car that passes it. The first gate of a route is the start (amber), the
## others are checkpoints (cyan) and the last gate of a sprint is the finish (red).

const GATE_SHADER := preload("res://modes/race_gate.gdshader")
const PYLON_INSET := 0.5                        ## m from the edge of the opening
const BEAM_HEIGHT := 1.5                        ## m: the height of the top beam
const BEAM_DEPTH := 0.45                        ## m
const PANEL_WIDTH := 9.0                        ## m: the width of the sign panel
const PANEL_HEIGHT := 1.15                      ## m
const CURTAIN_HEIGHT := 6.5                     ## m
const CURTAIN_DROP := 1.9                       ## m above the road
const TRIGGER_DEPTH := 3.0                      ## m: how deep the trigger box is
const TRIGGER_HEIGHT := 14.0                    ## m: the gate is high enough for a sky lane
## The heights that are on the level of the gate: a car that drives on the deck above the
## gate is inside the trigger box, but on another level, and must not score the checkpoint.
## A grounded car is never more than about a metre above its road, the closest deck on the map
## is 9.6 m above a gate (the surface road over the Bund tunnel gate at y = -9.6), so 6 m keeps a
## margin to both sides. A car in the air (a sky lane) counts at any height of the box.
const GROUND_PASS_HEIGHT := 6.0                 ## m above the gate origin
const GROUND_PASS_BELOW := 2.0                  ## m below the gate origin
const LED_ENERGY := 4.5                         ## the energy of the LED strips
const CURTAIN_ENERGY := 3.5                     ## the energy of the hologram curtain
const GATE_FADE := 0.35                         ## the alpha of the curtain in the middle
const STEEL_TILE := 0.5                         ## 1/m: the galvanised texture repeats every 2 m
const DETAIL_UV_1 := 0        ## the detail layer uses the UV1 of the material (the world UV)
const DETAIL_BLEND_MIX := 0   ## the grime is mixed into the galvanising
const GALV_DIFF := "res://modes/textures/gate_steel_diff.jpg"
const GALV_NOR := "res://modes/textures/gate_steel_nor.png"
const GRIME := "res://modes/textures/gate_grime_diff.jpg"

## A car passed the gate.
signal passed(vehicle: VehicleBase, index: int)

## The index of the checkpoint in the route.
var index: int = 0
## The number of checkpoints of the route.
var total: int = 1
## The kind of the gate: &"start", &"checkpoint", &"finish" or &"start_finish".
var kind: StringName = &"checkpoint"
## The tint of the gate (the start is amber, the checkpoints are cyan).
var tint: Color = Color("19e6ff")
## The energy of the gate (the next gate of the player burns brighter).
var energy: float = LED_ENERGY
## The hologram material of the curtain.
var curtain_material: ShaderMaterial = null
## The mesh of the curtain (the tint and the energy are instance uniforms).
var curtain: MeshInstance3D = null

var _fade: float = 1.0
var _led_material: StandardMaterial3D = null
var _steel_material: StandardMaterial3D = null
var _dark_material: StandardMaterial3D = null


## The fade of the gate (1 = full, 0 = gone). A tween can drive it.
var fade: float:
	get:
		return _fade
	set(value):
		_fade = clampf(value, 0.0, 1.0)
		_apply_fade(_fade)


## Builds the gate at a checkpoint transform.
func build(gate_index: int, xform: Transform3D, width: float, gate_tint: Color,
		gate_total: int, gate_kind: StringName = &"checkpoint") -> void:
	index = gate_index
	total = maxi(1, gate_total)
	kind = gate_kind
	tint = gate_tint
	energy = LED_ENERGY
	global_transform = xform
	reset_physics_interpolation()
	collision_layer = 1 << 3      # the trigger layer
	collision_mask = 1 << 1       # the vehicles
	monitoring = true
	_steel_material = _steel()
	_dark_material = _dark()
	_led_material = _led()
	_add_shape(width)
	_add_pylons(width)
	_add_beam(width)
	_add_panels(width)
	_add_curtain(width)
	_add_ground(width)
	body_entered.connect(_on_body_entered)


## The trigger box: as wide as the gate and as deep as a fast car needs.
func _add_shape(width: float) -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(width, TRIGGER_HEIGHT, TRIGGER_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, TRIGGER_HEIGHT * 0.5, 0.0)
	add_child(shape)


## The two pylons with their flanges, their bolts and their LED channels.
func _add_pylons(width: float) -> void:
	var half := width * 0.5 - PYLON_INSET
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var tag := "L" if side < 0.0 else "R"
		var pylon := Node3D.new()
		pylon.name = "Pylon%s" % tag
		add_child(pylon)
		GatePylon.build(pylon, side * half, _steel_material, _dark_material, _led_material)
		var plinth := MeshInstance3D.new()
		plinth.name = "Plinth%s" % tag
		var plinth_box := BoxMesh.new()
		plinth_box.size = GatePylon.FLANGE
		plinth.mesh = plinth_box
		plinth.position = Vector3(side * half, GatePylon.FLANGE.y * 0.5, 0.0)
		plinth.material_override = _plinth_material()
		add_child(plinth)


## The top beam: a galvanised box across the road.
func _add_beam(width: float) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var box := BoxMesh.new()
	box.size = Vector3(width, BEAM_HEIGHT, BEAM_DEPTH)
	beam.mesh = box
	beam.position = Vector3(0.0, GatePylon.COLUMN.y - BEAM_HEIGHT * 0.5, 0.0)
	beam.material_override = _steel_material
	add_child(beam)


## The sign panel of the beam: the text of the gate as LED dots, on the approach face and
## mirrored on the exit face.
func _add_panels(width: float) -> void:
	var texture := GateTextures.board_texture(kind, index, total)
	if texture == null:
		return
	var y := GatePylon.COLUMN.y - BEAM_HEIGHT * 0.5
	var front := MeshInstance3D.new()
	front.name = "PanelFront"
	front.mesh = _panel_mesh()
	front.position = Vector3(0.0, y, BEAM_DEPTH * 0.5 + 0.012)
	front.material_override = _panel_material(texture, false)
	add_child(front)
	var back := MeshInstance3D.new()
	back.name = "PanelBack"
	back.mesh = _panel_mesh()
	back.position = Vector3(0.0, y, -BEAM_DEPTH * 0.5 - 0.012)
	back.rotation.y = PI
	back.material_override = _panel_material(texture, true)
	add_child(back)


## The mesh of a sign panel.
func _panel_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	return quad


## The hologram curtain across the opening.
func _add_curtain(width: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Curtain"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width - 1.0, CURTAIN_HEIGHT)
	mesh.mesh = plane
	mesh.position = Vector3(0.0, CURTAIN_DROP + CURTAIN_HEIGHT * 0.5, 0.0)
	# The plane of a PlaneMesh lies flat: it has to stand up across the road.
	mesh.rotation_degrees.x = -90.0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain_material = ShaderMaterial.new()
	curtain_material.shader = GATE_SHADER
	curtain_material.set_shader_parameter("world_height", CURTAIN_HEIGHT)
	curtain_material.set_shader_parameter("max_alpha", GATE_FADE)
	mesh.material_override = curtain_material
	add_child(mesh)
	curtain = mesh
	curtain.set_instance_shader_parameter("tint", tint)
	curtain.set_instance_shader_parameter("energy", CURTAIN_ENERGY)


## The chevrons on the tarmac and the band of a start/finish line.
func _add_ground(width: float) -> void:
	var decal := Decal.new()
	decal.name = "Ground"
	decal.texture_albedo = GateTextures.ground_texture()
	decal.size = Vector3(width - 1.0, 2.0, 4.0)
	decal.modulate = Color(1.0, 1.0, 1.0, 0.6)
	decal.position = Vector3(0.0, 0.02, 0.0)
	add_child(decal)
	if kind != &"start_finish":
		return
	# The start/finish line of a circuit: a black/white checker band on the tarmac.
	var band := MeshInstance3D.new()
	band.name = "CheckerBand"
	var quad := QuadMesh.new()
	quad.size = Vector2(width - 1.0, 0.3)
	band.mesh = quad
	band.position = Vector3(0.0, 0.03, 0.0)
	band.rotation_degrees.x = -90.0
	band.material_override = _checker_material()
	add_child(band)


## The galvanised steel of the pylons (the texture is projected on the world, so the faces
## of the pylon are not stretched by the atlas of a box).
func _steel() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# The pylon is dark galvanised steel: the car is the brightest object of a frame (ART.md 2).
	material.albedo_color = Color("6e737a")
	material.roughness = 0.55
	material.metallic = 0.7
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(STEEL_TILE, STEEL_TILE, STEEL_TILE)
	_apply_texture(material, "albedo_texture", GALV_DIFF)
	_apply_texture(material, "normal_enabled", GALV_NOR)
	_apply_detail(material)
	return material


## The grime of the steel: the streaks of the library texture on top of the galvanising.
func _apply_detail(material: StandardMaterial3D) -> void:
	if not ResourceLoader.exists(GRIME):
		return
	var grime := load(GRIME) as Texture2D
	if grime == null:
		return
	material.detail_enabled = true
	material.detail_albedo = grime
	material.detail_uv_layer = DETAIL_UV_1
	material.detail_blend_mode = DETAIL_BLEND_MIX


## The dark painted metal of the cable duct and the LED channel.
func _dark() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1a1d24")
	material.roughness = 0.42
	material.metallic = 0.6
	return material


## The hazard plinth of the pylon.
func _plinth_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = GateTextures.hazard_texture()
	material.roughness = 0.6
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.6, 0.6, 0.6)
	return material


## The LED edge strips of the pylons: a dark strip that lights up in the tint of the gate.
##
## The emission is lit per pixel (Godot does not apply the emission of an unshaded material),
## so the strip glows and the bloom of the night catches it (ART.md 4).
func _led() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("111113")
	material.roughness = 0.3
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material


## The sign panel of the beam: the LED texture is the albedo and the emission mask.
func _panel_material(texture: Texture2D, mirrored: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color("0a0f1e")
	material.roughness = 0.35
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission_texture = texture
	material.emission = Color.WHITE
	# The panel is a dark board with LED dots: the emission must not blow the letters out.
	material.emission_energy_multiplier = 0.5
	if mirrored:
		# The panel of the exit face is turned around: the texture has to be mirrored with it.
		material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	return material


## The checker band of a start/finish line.
func _checker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = GateTextures.checker_texture()
	material.roughness = 0.7
	material.uv1_scale = Vector3(4.8, 0.5, 1.0)
	return material


## Loads a texture of the library (null when it is missing).
func _apply_texture(material: StandardMaterial3D, property: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("[modes] the gate texture is missing: %s" % path)
		return
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("[modes] the gate texture could not be loaded: %s" % path)
		return
	if property == "normal_enabled":
		material.normal_enabled = true
		material.normal_texture = texture
	elif property == "roughness_texture":
		material.roughness_texture = texture
	else:
		material.albedo_texture = texture


## Sets the brightness of the gate (the next gate of the player burns brighter).
func set_energy(value: float) -> void:
	energy = value
	if _led_material != null:
		_led_material.emission_energy_multiplier = value
	if curtain != null:
		curtain.set_instance_shader_parameter("energy", CURTAIN_ENERGY * value / LED_ENERGY)


## Fades the gate out (the racer has passed it): 1 = full, 0 = gone.
func _apply_fade(value: float) -> void:
	set_energy(LED_ENERGY * value)
	if curtain != null:
		curtain.visible = value > 0.01
	if value <= 0.0:
		collision_layer = 0


## Reports the car that passed.
func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null:
		return
	# A car that drives on the deck above the gate is inside the box, but on another
	# level: it must not score the checkpoint. A car in the air (a sky lane) does.
	if not vehicle.is_airborne() and not _is_on_gate_level(vehicle):
		return
	passed.emit(vehicle, index)


## True when a grounded car is on the level of the gate (not on a deck above it and
## not in a tunnel below it).
func _is_on_gate_level(vehicle: VehicleBase) -> bool:
	var dy := vehicle.global_position.y - global_position.y
	return dy <= GROUND_PASS_HEIGHT and dy >= -GROUND_PASS_BELOW

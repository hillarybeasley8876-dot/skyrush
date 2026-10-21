extends Node3D
## The wheel arch glow of a boosting car (brief §7).
##
## A small cyan light plus an additive card per rear wheel. The light and the card sit at the
## wheel marker of the car, 10 cm outwards and 15 cm above the road, so the glow is on the tyre
## and not in the middle of the car (review §9).

const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")
const TEXTURES := preload("res://fx/fx_textures.gd")
const ADD_SHADER := preload("res://fx/fx_add.gdshader")

const CARD_SIZE := Vector2(0.45, 0.25)

var _light_l: OmniLight3D
var _light_r: OmniLight3D
var _card_l: MeshInstance3D
var _card_r: MeshInstance3D
var _mat_l: ShaderMaterial
var _mat_r: ShaderMaterial
var _vehicle: VehicleBase = null


func _ready() -> void:
	_light_l = _make_light("ArchLightL")
	_light_r = _make_light("ArchLightR")
	_card_l = _make_card()
	_card_r = _make_card()
	_mat_l = _card_l.material_override as ShaderMaterial
	_mat_r = _card_r.material_override as ShaderMaterial
	add_child(_light_l)
	add_child(_light_r)
	add_child(_card_l)
	add_child(_card_r)
	set_glow(0.0)


## The car the glow belongs to: the lights and the cards are placed at its rear wheels.
func set_vehicle(vehicle: VehicleBase) -> void:
	_vehicle = vehicle
	_place()


## Places the lights and the cards at the rear wheel markers of the car.
func _place() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return
	for i in 2:
		var marker := _vehicle.get_marker(&"Wheel_RL" if i == 0 else &"Wheel_RR")
		if marker == null:
			continue
		var local := _vehicle.to_local(marker.global_position)
		var side := -1.0 if i == 0 else 1.0
		var offset := Vector3(side * TUNE.ARCH_LIGHT_OUT, TUNE.ARCH_LIGHT_UP, 0.0)
		var light := _light_l if i == 0 else _light_r
		var card := _card_l if i == 0 else _card_r
		light.position = local + offset
		card.position = local + offset
		# The card faces outwards, so the glow is seen from the side of the car.
		card.rotation_degrees = Vector3(0.0, 90.0, 0.0)


## Sets the glow strength (0..1). The caller ramps it, so the fade is frame rate independent.
func set_glow(value: float) -> void:
	var glow := clampf(value, 0.0, 1.0)
	_light_l.light_energy = glow * TUNE.ARCH_LIGHT_ENERGY
	_light_r.light_energy = glow * TUNE.ARCH_LIGHT_ENERGY
	_card_l.visible = glow > 0.02
	_card_r.visible = glow > 0.02
	if _mat_l != null:
		_mat_l.set_shader_parameter(&"alpha_scale", glow)
	if _mat_r != null:
		_mat_r.set_shader_parameter(&"alpha_scale", glow)


func _make_light(node_name: String) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_color = PALETTE.CHARGE
	light.light_energy = 0.0
	light.omni_range = TUNE.ARCH_LIGHT_RANGE
	light.shadow_enabled = false
	return light


func _make_card() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = CARD_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = ADD_SHADER
	mat.set_shader_parameter(&"albedo_tex", TEXTURES.glow())
	mat.set_shader_parameter(&"use_texture", true)
	mat.set_shader_parameter(&"tint", PALETTE.CHARGE)
	mat.set_shader_parameter(&"energy", 2.0)
	quad.material = mat
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

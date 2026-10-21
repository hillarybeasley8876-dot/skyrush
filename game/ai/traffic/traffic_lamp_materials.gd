class_name TrafficLampMaterials
extends RefCounted
## The lamp materials of one traffic car model.
##
## The npc models ship real lamp lenses: the rear lamp mesh (`Lamp_R`) has a tail lens
## (`NPC_lamp_rear`), a brake lens (`NPC_lamp_brake`) and a reversing lens (`NPC_lamp_front`),
## the front lamp mesh (`Lamp_F`) the head lens and the black housing. Every lens is a surface
## of its own mesh, so the lamp state is a per-surface material swap - the lens texture of the
## model stays and the whole housing does not turn red.
##
## The materials are the model's OWN textures and colours, duplicated once per model and per
## state and then shared by every car of that model. They carry no instance uniform: the
## instance buffer of the city is full and every car would need a slot for every lamp.
##
## The lens material is the shader `traffic_lens.gdshader`: it lights only the faces that look
## out of the car (the shell of a lamp has an inner face, and the body panels are one sided,
## so the far lamp used to shine through the cabin) and it multiplies the emission with the
## strip of the model's own atlas, so the lamp reads as segments and not as a neon tube.

const LENS_SHADER := preload("res://ai/traffic/traffic_lens.gdshader")

const TAIL_TINT := Color("ff1a2e")    ## the red of the tail lamps
const BRAKE_TINT := Color("ff1a2e")   ## the red of the brake lamps
const HEAD_TINT := Color("f4f7ff")    ## the cold white of the head lamps
const REVERSE_TINT := Color("dfe6ff") ## the white of the reversing lens
## The energy of each state, as a factor of the energy the model was imported with. The
## emission is multiplied with the strip of the atlas, so it needs more energy than the
## uniform glow of the old material.
const TAIL_FACTOR := 6.0
## The brake lens of a model without a brake lens of its own (a bus): it has to blaze when the
## car brakes, so the brake reads from the back of the car.
const TAIL_BRAKE_FACTOR := 25.0
const BRAKE_OFF_FACTOR := 0.0
const BRAKE_ON_FACTOR := 12.0
const HEAD_FACTOR := 6.0
const REVERSE_FACTOR := 0.02
## A lit lens: the colour of the model, a little rough.
const LIT_ALBEDO := 1.0
const LIT_ROUGHNESS := 0.15
const LIT_METALLIC := 0.0
## An unlit lens: clear glass over a chrome reflector, not a white sticker.
const UNLIT_ALBEDO := 0.3
const UNLIT_ROUGHNESS := 0.08
const UNLIT_METALLIC := 0.6
## The material names the npc models use for the lenses.
const MAT_REAR := "NPC_lamp_rear"
const MAT_BRAKE := "NPC_lamp_brake"
const MAT_FRONT := "NPC_lamp_front"
## The direction the rear and the front lens look at, in the space of the car (-Z = forward).
const REAR_AXIS := Vector3(0.0, 0.0, 1.0)
const FRONT_AXIS := Vector3(0.0, 0.0, -1.0)


## The lamp materials of one model.
class Set extends RefCounted:
	## The tail lens while cruising.
	var tail: Material = null
	## The tail lens while braking (used when the model has no brake lens of its own).
	var tail_brake: Material = null
	## The brake lens while the car is not braking.
	var brake_off: Material = null
	## The brake lens while the car is braking.
	var brake_on: Material = null
	## The head lens.
	var head: Material = null
	## The reversing lens (dim, it is only lit in reverse).
	var reverse: Material = null
	## True when the model has a brake lens of its own.
	var has_brake_lens: bool = false


static var _sets: Dictionary = {}


## The lamp materials of `model_id`, built from the lamp meshes of `visual` the first time the
## model is used and shared by every car of that model afterwards.
static func set_for(model_id: StringName, visual: Node3D) -> Set:
	if _sets.has(model_id):
		return _sets[model_id] as Set
	var result := Set.new()
	var base_tail: StandardMaterial3D = null
	var base_brake: StandardMaterial3D = null
	var base_head: StandardMaterial3D = null
	var base_reverse: StandardMaterial3D = null
	var mesh_tail: MeshInstance3D = null
	var mesh_brake: MeshInstance3D = null
	var mesh_head: MeshInstance3D = null
	var mesh_reverse: MeshInstance3D = null
	for node in visual.find_children("Lamp_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null:
				continue
			match source.resource_name:
				MAT_REAR:
					if base_tail == null:
						base_tail = source
						mesh_tail = mesh
				MAT_BRAKE:
					if base_brake == null:
						base_brake = source
						mesh_brake = mesh
				MAT_FRONT:
					if mesh.name == "Lamp_F":
						if base_head == null:
							base_head = source
							mesh_head = mesh
					elif base_reverse == null:
						base_reverse = source
						mesh_reverse = mesh
	if base_tail != null:
		result.tail = _lens(base_tail, mesh_tail, visual, REAR_AXIS, TAIL_TINT, TAIL_FACTOR, true)
		result.tail_brake = _lens(base_tail, mesh_tail, visual, REAR_AXIS, BRAKE_TINT,
				TAIL_BRAKE_FACTOR, true)
	if base_brake != null:
		result.has_brake_lens = true
		result.brake_off = _lens(base_brake, mesh_brake, visual, REAR_AXIS, BRAKE_TINT,
				BRAKE_OFF_FACTOR, false)
		result.brake_on = _lens(base_brake, mesh_brake, visual, REAR_AXIS, BRAKE_TINT,
				BRAKE_ON_FACTOR, true)
	if base_head != null:
		result.head = _lens(base_head, mesh_head, visual, FRONT_AXIS, HEAD_TINT, HEAD_FACTOR, true)
	if base_reverse != null:
		result.reverse = _lens(base_reverse, mesh_reverse, visual, REAR_AXIS, REVERSE_TINT,
				REVERSE_FACTOR, false)
	_sets[model_id] = result
	return result


## A lens material of the model: its own textures and colour, with the energy of the state.
##
## `axis` is the direction the lens looks at, in the space of the car. It is transformed into
## the space of the mesh, because the shader compares it with the normal of the mesh.
static func _lens(source: StandardMaterial3D, mesh: MeshInstance3D, visual: Node3D,
		axis: Vector3, tint: Color, factor: float, lit: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LENS_SHADER
	mat.resource_name = source.resource_name + "_traffic"
	mat.set_shader_parameter(&"lamp_color", tint)
	mat.set_shader_parameter(&"energy", source.emission_energy_multiplier * factor)
	mat.set_shader_parameter(&"lamp_axis", _axis_of(mesh, visual, axis))
	mat.set_shader_parameter(&"lens_tint", source.albedo_color)
	mat.set_shader_parameter(&"albedo_scale", LIT_ALBEDO if lit else UNLIT_ALBEDO)
	mat.set_shader_parameter(&"roughness", LIT_ROUGHNESS if lit else UNLIT_ROUGHNESS)
	mat.set_shader_parameter(&"metallic", LIT_METALLIC if lit else UNLIT_METALLIC)
	if source.albedo_texture != null:
		mat.set_shader_parameter(&"albedo_texture", source.albedo_texture)
		mat.set_shader_parameter(&"use_albedo_texture", true)
	if source.emission_texture != null:
		mat.set_shader_parameter(&"emission_texture", source.emission_texture)
		mat.set_shader_parameter(&"use_emission_texture", true)
	mat.set_shader_parameter(&"uv_scale", source.uv1_scale)
	mat.set_shader_parameter(&"uv_offset", source.uv1_offset)
	return mat


## The direction the lens looks at, in the model space of the mesh it belongs to.
static func _axis_of(mesh: MeshInstance3D, visual: Node3D, axis: Vector3) -> Vector3:
	if mesh == null or visual == null:
		return axis
	var relative := visual.global_transform.affine_inverse() * mesh.global_transform
	var local := relative.basis.inverse() * axis
	if local.length_squared() < 0.0001:
		return axis
	return local.normalized()

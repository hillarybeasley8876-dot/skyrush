extends RefCounted
## The brake lights of one car: the rear light bar (the glb's LightBar_Rear), the brake light
## box (the glb's Brake_Light) and the brake lamp of an NPC car (the NPC_lamp_brake surface).
##
## The materials are copied per car, so every car on the road drives its own lights. Every lit
## surface behaves the same way: the idle level is the strength the glb was authored with (the
## roadster's bar and box are authored at 3.2) and the braking level is that strength times
## BRAKE_LIGHT_RATIO. The colour is never written: the glb authors the emission texture (the
## red core inside the lens, ART 2), so only the energy is touched.
##
## The energy is written only when it changes: toggling the emission feature would recompile
## a shader variant and every car would hitch on its first brake.

const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")

## The shader uniforms the emission energy can live in (the first one the shader has wins).
const ENERGY_UNIFORMS: Array[StringName] = [
	&"emission_energy_multiplier",
	&"emission_energy",
]


## One lit surface: the mesh, the surface index and the per-car copy of the material.
class Slot extends RefCounted:
	var mesh: MeshInstance3D = null
	var surface: int = 0
	var material: Material = null
	## The emission energy the material was authored with.
	var idle: float = 1.0
	## The emission energy of the last update.
	var energy: float = 0.0


## The rear light bar.
var bar: Slot = Slot.new()
## The brake light box.
var box: Slot = Slot.new()
## The brake lamp of an NPC car.
var lamp: Slot = Slot.new()


## Finds the lights of the model and copies their materials.
func bind(model: Node3D) -> void:
	bar = Slot.new()
	box = Slot.new()
	lamp = Slot.new()
	if model == null:
		return
	bar = _bind_node(model.find_child("LightBar_Rear", true, false) as MeshInstance3D, 0)
	box = _bind_node(model.find_child("Brake_Light", true, false) as MeshInstance3D, 0)
	lamp = _bind_lamp(model)


## Lights the brake: every lit surface flares up to BRAKE_LIGHT_RATIO times its idle level.
func set_braking(braking: bool) -> void:
	var ratio: float = VisualTuning.BRAKE_LIGHT_RATIO if braking else 1.0
	_set_slot(bar, ratio)
	_set_slot(box, ratio)
	_set_slot(lamp, ratio)


## The emission energy of the rear bar (0 when the car has no bar).
func bar_energy() -> float:
	return bar.energy


## The emission energy of the brake box.
func box_energy() -> float:
	return box.energy


## The emission energy of the NPC brake lamp.
func lamp_energy() -> float:
	return lamp.energy


## Lights (or darkens) one slot. The energy is written only when it changes.
func _set_slot(slot: Slot, ratio: float) -> void:
	if slot.material == null:
		return
	var level: float = slot.idle * ratio
	if is_equal_approx(slot.energy, level):
		return
	slot.energy = level
	_apply(slot, level)


## Writes the emission energy into a material. The colour stays the one the glb authored.
func _apply(slot: Slot, level: float) -> void:
	var material: Material = slot.material
	if material is BaseMaterial3D:
		var base: BaseMaterial3D = material as BaseMaterial3D
		# The feature stays on: toggling it would recompile the shader variant.
		base.emission_enabled = true
		base.emission_energy_multiplier = level
		return
	if material is ShaderMaterial:
		var shader: ShaderMaterial = material as ShaderMaterial
		if shader.shader == null:
			return
		var uniforms: Array[StringName] = []
		for u: Dictionary in shader.shader.get_shader_uniform_list():
			uniforms.append(StringName(u["name"]))
		for name: StringName in ENERGY_UNIFORMS:
			if uniforms.has(name):
				shader.set_shader_parameter(name, level)
				return


## Copies the material of a mesh (surface 0) and reads the authored strength.
func _bind_node(mesh: MeshInstance3D, surface: int) -> Slot:
	var slot := Slot.new()
	slot.mesh = mesh
	slot.surface = surface
	if mesh == null or mesh.mesh == null:
		return slot
	var source: Material = mesh.get_active_material(surface)
	if source == null:
		return slot
	slot.material = source.duplicate() as Material
	mesh.set_surface_override_material(surface, slot.material)
	slot.idle = _authored_energy(slot.material)
	slot.energy = slot.idle
	return slot


## The brake lamp of an NPC car: the surface (or the material) is called NPC_lamp_brake.
func _bind_lamp(model: Node3D) -> Slot:
	var slot := Slot.new()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.mesh.surface_get_material(i)
			var surface_name: String = ""
			if mesh.mesh.has_method("get_surface_name"):
				surface_name = mesh.mesh.get_surface_name(i)
			var named: bool = surface_name.findn("NPC_lamp_brake") >= 0 \
				or (material != null and material.resource_name.findn("NPC_lamp_brake") >= 0)
			if not named:
				continue
			slot.mesh = mesh
			slot.surface = i
			if material != null:
				slot.material = material.duplicate() as Material
				mesh.set_surface_override_material(i, slot.material)
				slot.idle = _authored_energy(slot.material)
				slot.energy = slot.idle
			return slot
	return slot


## The emission energy the material was authored with.
func _authored_energy(material: Material) -> float:
	if material is BaseMaterial3D:
		var base: BaseMaterial3D = material as BaseMaterial3D
		if base.emission_energy_multiplier > 0.0:
			return base.emission_energy_multiplier
	return VisualTuning.BRAKE_LIGHT_IDLE

extends RefCounted
## The head lamp of a hurt car (dossier §7.4): it flickers, with irregular dropouts.
##
## The material of the lamp is copied, so the other cars are not touched, and the
## brightness is driven by the emission energy of that copy. The unit never writes the
## instance uniforms of another unit: a lamp whose material is a shader (the traffic lamps)
## is left alone, and the traffic unit is asked to flicker it.

## The darkest the lamp goes (a share of its own brightness).
const DIM := 0.12
## The head lamp: irregular dropouts (the lamp is on for 0.05 to 0.25 s).
const LAMP_ON_MIN := 0.05
const LAMP_ON_MAX := 0.25
## The names of the head lamps of the cars.
const LAMP_NAMES: Array[String] = ["Lamp_FL", "Lamp_F", "HeadlampPanel_L", "Lamp_F.001"]

var _lamp: MeshInstance3D = null
## The copy of the material of the lamp.
var _material: BaseMaterial3D = null
## The brightness of the lamp before the damage unit touched it.
var _original: float = 1.0
var _timer: float = 0.0
var _on: bool = true
var _rng := RandomNumberGenerator.new()


## Finds the head lamp of the car and copies its material.
func setup(car: VehicleBase) -> void:
	if _material != null:
		return
	_rng.randomize()
	_lamp = _find_lamp(car)
	if _lamp == null or _lamp.mesh == null:
		return
	_material = _copy_material(_lamp)
	if _material == null:
		_lamp = null
		return
	_original = _material.emission_energy_multiplier


## The lamp flickers while the car is hurt.
func tick(delta: float) -> void:
	if _material == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(LAMP_ON_MIN, LAMP_ON_MAX)
	_on = not _on
	_set_brightness(_on)


## The car is whole again: the lamp gets its own brightness back.
func reset() -> void:
	_on = true
	_set_brightness(true)


## The brightness of the lamp, as a share of the one it had.
func _set_brightness(on: bool) -> void:
	if _material == null:
		return
	_material.emission_energy_multiplier = _original * (1.0 if on else DIM)


## The head lamp of the car. The tree is walked once: a search per name costs four times
## as much, and the car has a hundred meshes.
func _find_lamp(car: VehicleBase) -> MeshInstance3D:
	var visual := car.get_visual_root()
	if visual == null:
		return null
	var found: Dictionary = {}
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var name := String(mesh.name)
		if LAMP_NAMES.has(name) and not found.has(name):
			found[name] = mesh
	# The names have a priority: the left lamp is the one of the list.
	for name: String in LAMP_NAMES:
		if found.has(name):
			return found[name] as MeshInstance3D
	return null


## A copy of the material of the lamp, so the brightness can be driven per car. A lamp whose
## material is a shader belongs to another unit: it is not touched.
func _copy_material(lamp: MeshInstance3D) -> BaseMaterial3D:
	for i in lamp.mesh.get_surface_count():
		var material := lamp.get_active_material(i)
		if material is BaseMaterial3D:
			var copy := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			if copy == null:
				continue
			lamp.set_surface_override_material(i, copy)
			return copy
	return null

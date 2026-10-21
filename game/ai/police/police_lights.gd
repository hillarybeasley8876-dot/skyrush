class_name PoliceLights
extends RefCounted
## The police light bar (ref/art/DOSSIER.md §4.8).
##
## Two emissive halves, red and blue, with the strobe pattern of the dossier: a 0.75 s loop with
## red on 0-70 ms and 130-200 ms, blue on 375-445 ms and 505-575 ms. The emission energy is 12
## and every half drives one OmniLight3D (range 16 m, energy 6, volumetric fog 2.0, no shadow).
##
## The glb materials are plain StandardMaterial3D, so the emission is driven through a per-car
## duplicate of the material instead of an instance shader parameter.

const LOOP := 0.75             ## s: the length of the strobe pattern
const EMISSION := 12.0         ## the emission energy of a lit half (dossier 4.8)
const LIGHT_RANGE := 16.0      ## m: the range of the omni light
const LIGHT_ENERGY := 6.0      ## the energy of the omni light
const VOL_FOG := 2.0           ## the volumetric fog energy of the omni light
## The police colours of ART.md §3: red #FF2030 and blue #2A5CFF.
const RED := Color("ff2030")
const BLUE := Color("2a5cff")
## The emission the unlit lens keeps, so the bar is not dead grey in the loop.
const IDLE_EMISSION := 0.3
## The lateral offset of the two omni lights (m): the pools alternate left and right.
const LIGHT_OFFSET := 0.45
## The height of the omni lights above the road (m).
const LIGHT_HEIGHT := 1.3

## The lit windows of the pattern, in seconds inside the loop.
const RED_WINDOWS: Array[Vector2] = [Vector2(0.0, 0.070), Vector2(0.130, 0.200)]
const BLUE_WINDOWS: Array[Vector2] = [Vector2(0.375, 0.445), Vector2(0.505, 0.575)]


## The pattern state at `phase` seconds inside the loop: x = red (0..1), y = blue (0..1).
static func phase_state(phase: float) -> Vector2:
	var t := fposmod(phase, LOOP)
	var red := 1.0 if _in_window(t, RED_WINDOWS) else 0.0
	var blue := 1.0 if _in_window(t, BLUE_WINDOWS) else 0.0
	return Vector2(red, blue)


## True when the time falls inside one of the windows.
static func _in_window(t: float, windows: Array[Vector2]) -> bool:
	for w in windows:
		if t >= w.x and t <= w.y:
			return true
	return false


## Finds the two light bar halves of a police model and gives each of them its own material
## copy, so one car can flash without touching the others.
##
## `prefix` is the node name prefix: the cars use "LightBar_Red"/"LightBar_Blue", the drone uses
## "Strobe_Red"/"Strobe_Blue".
##
## Returns {"red": MeshInstance3D, "blue": MeshInstance3D, "red_mat": Material, ...}; a missing
## half is a null and is simply skipped.
static func prepare_bar(model: Node, prefix: String = "LightBar_") -> Dictionary:
	var out := {"red": null, "blue": null, "red_mat": null, "blue_mat": null}
	if model == null:
		return out
	for half: String in ["red", "blue"]:
		var mesh := model.find_child(prefix + half.capitalize(), true, false) as MeshInstance3D
		if mesh == null:
			continue
		var material := _own_material(mesh)
		if material == null:
			continue
		PoliceLightBarTexture.apply(material, half)
		out[half] = mesh
		out[half + "_mat"] = material
	return out


## A private copy of the mesh material, so the emission can be driven per car.
static func _own_material(mesh: MeshInstance3D) -> Material:
	if mesh.mesh == null:
		return null
	var source := mesh.get_active_material(0)
	if source == null:
		return null
	var copy := source.duplicate() as Material
	mesh.set_surface_override_material(0, copy)
	return copy


## Writes the emission of a light bar half. `on` is 0..1.
static func set_emission(material: Material, on: float) -> void:
	if material == null:
		return
	var base := material as BaseMaterial3D
	if base == null:
		return
	base.emission_energy_multiplier = EMISSION * clampf(on, 0.0, 1.0) + IDLE_EMISSION


## Builds the omni light of one half of the bar.
static func make_light(colour: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = colour
	light.omni_range = LIGHT_RANGE
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = VOL_FOG
	return light

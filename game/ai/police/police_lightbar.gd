class_name PoliceLightBar
extends RefCounted
## The light bar of a police unit (ref/art/DOSSIER.md §4.8).
##
## The pattern and the numbers live in PoliceLights; this class drives the strobe of one unit
## and the omni lights of its two halves. The omni lights are only switched on for the three
## nearest units.

var phase: float = 0.0

var _red_mat: Material = null
var _blue_mat: Material = null
var _omni_red: OmniLight3D = null
var _omni_blue: OmniLight3D = null
var _enabled: bool = false
var _last_red: float = -1.0
var _last_blue: float = -1.0


## Builds the bar: the two halves of the model and the two omni lights.
##
## `prefix` is the node name prefix: the cars use "LightBar_Red"/"LightBar_Blue", the drone uses
## "Strobe_Red"/"Strobe_Blue". The drone has a search light of its own, so it is built without
## the omni lights.
func build(host: Node3D, model: Node, prefix: String = "LightBar_",
		with_omni: bool = true) -> void:
	if model == null:
		return
	var bar := PoliceLights.prepare_bar(model, prefix)
	_red_mat = bar.get("red_mat") as Material
	_blue_mat = bar.get("blue_mat") as Material
	if not with_omni:
		return
	_omni_red = PoliceLights.make_light(PoliceLights.RED)
	_omni_red.name = "LightRed"
	_omni_red.position = Vector3(-PoliceLights.LIGHT_OFFSET, PoliceLights.LIGHT_HEIGHT, 0.0)
	_omni_red.visible = false
	host.add_child(_omni_red)
	_omni_blue = PoliceLights.make_light(PoliceLights.BLUE)
	_omni_blue.name = "LightBlue"
	_omni_blue.position = Vector3(PoliceLights.LIGHT_OFFSET, PoliceLights.LIGHT_HEIGHT, 0.0)
	_omni_blue.visible = false
	host.add_child(_omni_blue)


## Advances the strobe.
func update(dt: float) -> void:
	phase = fposmod(phase + dt, PoliceLights.LOOP)
	var strobe := PoliceLights.phase_state(phase)
	# The lights are only written when the pattern changes: the energy of a light is a
	# property of the renderer, and writing it every tick costs every tick.
	if not is_equal_approx(strobe.x, _last_red):
		_last_red = strobe.x
		PoliceLights.set_emission(_red_mat, strobe.x)
		if _omni_red != null:
			_omni_red.light_energy = PoliceLights.LIGHT_ENERGY * strobe.x
	if not is_equal_approx(strobe.y, _last_blue):
		_last_blue = strobe.y
		PoliceLights.set_emission(_blue_mat, strobe.y)
		if _omni_blue != null:
			_omni_blue.light_energy = PoliceLights.LIGHT_ENERGY * strobe.y


## Switches the omni lights on (only the three nearest units get them).
func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if _omni_red != null:
		_omni_red.visible = enabled
	if _omni_blue != null:
		_omni_blue.visible = enabled

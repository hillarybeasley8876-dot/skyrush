extends Node
## The LED dot skin of the Oriental Pearl (L-NIGHT2).
##
## The spheres carry a separate dot shell 0.6 m off the glass. This script
## puts a ShaderMaterial on it (the dot grid and the chasing wave are in
## opt_dots.gdshader) and cycles the colour pink -> violet -> blue over 40 s.
##
## NOTE for the world unit: led_cycle.gd casts the material to
## StandardMaterial3D, so a ShaderMaterial is SKIPPED by it - the colour
## cycle of the spheres is driven from here, not from led_cycle.gd.

const BIG_ENERGY := 4.0
const SMALL_ENERGY := 5.0
const CYCLE := 40.0
const PINK := Color("#FF3FA4")
const VIOLET := Color("#8A3CFF")
const BLUE := Color("#2E7BFF")

@export var dots_shader: Shader

var _mats: Array[ShaderMaterial] = []
var _t: float = 0.0


func _ready() -> void:
	if dots_shader == null:
		push_error("opt_led: no shader assigned")
		return
	var mat_big := _make(BIG_ENERGY)
	var mat_small := _make(SMALL_ENERGY)
	for child in _root().find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not mi.name.begins_with("LED_Sphere_"):
			continue
		var mat := mat_small if mi.name.contains("Small") else mat_big
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	set_process(true)


func _make(energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = dots_shader
	mat.set_shader_parameter("led_color", PINK)
	mat.set_shader_parameter("energy", energy)
	_mats.append(mat)
	return mat


func _process(delta: float) -> void:
	_t = fposmod(_t + delta, CYCLE)
	var c := _color_at(_t / CYCLE)
	for mat in _mats:
		mat.set_shader_parameter("led_color", c)


func _color_at(t: float) -> Color:
	# three stops, each a third of the cycle
	var f := t * 3.0
	if f < 1.0:
		return PINK.lerp(VIOLET, f)
	if f < 2.0:
		return VIOLET.lerp(BLUE, f - 1.0)
	return BLUE.lerp(PINK, f - 2.0)


## The scripts hang off the wrapper's ROOT node, so the meshes live under the
## root's children, not under this node.
func _root() -> Node:
	var parent := get_parent()
	return parent if parent != null else self

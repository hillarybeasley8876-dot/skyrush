extends Node3D
## Pooled point lights for short impact flashes (a big crash) and the wreck fire. A light is
## borrowed from the pool, peaks at its energy and decays to zero over its lifetime.

const COUNT := 4
const TUNE := preload("res://fx/fx_tuning.gd")

var _lights: Array[OmniLight3D] = []
var _peak: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _max_life: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0


func _ready() -> void:
	for i in COUNT:
		var light := OmniLight3D.new()
		light.name = "Flash%d" % i
		light.shadow_enabled = false
		light.light_energy = 0.0
		add_child(light)
		_lights.append(light)
	_peak.resize(COUNT)
	_life.resize(COUNT)
	_max_life.resize(COUNT)


## Flashes a light at `position`. `time` is how long it takes to decay to nothing.
func flash(position: Vector3, color: Color, energy: float, range_m: float, time: float) -> void:
	var i := _next
	_next = (_next + 1) % COUNT
	var light := _lights[i]
	light.global_position = position
	light.light_color = color
	light.omni_range = range_m
	_peak[i] = energy
	_life[i] = time
	_max_life[i] = maxf(time, 0.001)
	light.light_energy = energy


## A light that keeps flickering (the wreck fire).
func set_flicker(index: int, color: Color, energy: float, range_m: float) -> void:
	var light := _lights[index]
	light.light_color = color
	light.omni_range = range_m
	light.light_energy = energy


func clear_light(index: int) -> void:
	_lights[index].light_energy = 0.0


func _process(delta: float) -> void:
	for i in COUNT:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		var k := clampf(_life[i] / _max_life[i], 0.0, 1.0)
		_lights[i].light_energy = _peak[i] * k * k
		if _life[i] <= 0.0:
			_lights[i].light_energy = 0.0

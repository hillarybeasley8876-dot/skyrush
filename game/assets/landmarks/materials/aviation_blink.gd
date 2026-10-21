extends Node
## The aviation beacons (ART.md 11: red aviation beacons blinking 1 Hz on
## every roof above 100 m).
##
## Every beacon mesh (LED_Aviation_*) has its OWN material, so each tower can
## carry its own phase and the roofline does not blink in lockstep. The
## beacon is on for 0.25 s of every 1 s.

const PERIOD := 1.0
const ON_TIME := 0.25

var _mats: Array[StandardMaterial3D] = []
var _phase: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_collect()
	set_process(true)


func _collect() -> void:
	var seen: Dictionary = {}
	for child in _root().find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and mat.resource_name.begins_with("LED_Aviation"):
				var key := mat.get_rid()
				if seen.has(key):
					continue
				seen[key] = true
				_mats.append(mat)
				_phase.append(_phase_of(mat.resource_name))


func _phase_of(mat_name: String) -> float:
	var h: int = 0
	for i in mat_name.length():
		h = (h * 31 + mat_name.unicode_at(i)) & 0xffff
	return float(h) / 65535.0


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	for i in _mats.size():
		var t := fposmod(now + _phase[i], PERIOD)
		_mats[i].emission_energy_multiplier = 1.0 if t < ON_TIME else 0.0


## The scripts hang off the wrapper's ROOT node, so the meshes live under the
## root's children, not under this node.
func _root() -> Node:
	var parent := get_parent()
	return parent if parent != null else self

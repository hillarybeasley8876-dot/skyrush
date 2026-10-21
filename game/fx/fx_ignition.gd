extends Node3D
## The cold vapour of a nitro ignition (brief §7, dossier §5.5): a few soft white puffs and a
## white shock ring at the nozzles. Never orange, never fire: nitrogen is cold gas.
##
## The node frees itself when the effect is over.

const EMITTERS := preload("res://fx/fx_emitters.gd")
const RING_SHADER := preload("res://fx/fx_ring.gdshader")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

## The nozzles that get a shock ring.
const NOZZLES := [&"Nozzle_R1", &"Nozzle_R2", &"Nozzle_R3", &"Nozzle_R4"]

var _puffs: GPUParticles3D
var _rings: Array[MeshInstance3D] = []
var _t: float = 0.0
var _running: bool = false


## Starts the ignition on a car: the puffs at the tail, the rings at the nozzles.
func play(vehicle: VehicleBase, quality: float) -> void:
	_running = true
	_t = 0.0
	_puffs = EMITTERS.ignition_puff(quality)
	_puffs.name = "IgnitionPuffs"
	_puffs.one_shot = true
	_puffs.explosiveness = 1.0
	add_child(_puffs)
	var back := vehicle.global_position - vehicle.get_forward() * 1.8 + Vector3.UP * 0.4
	_puffs.global_position = back
	_puffs.emitting = true
	for i in NOZZLES.size():
		var marker := vehicle.get_marker(NOZZLES[i])
		var ring := _make_ring()
		add_child(ring)
		if marker != null:
			# The ring lies across the axis of the nozzle: the gas leaves along the -Z of the
			# marker, so the shock ring is perpendicular to it.
			ring.global_transform = Transform3D(_basis_with_y(-marker.global_transform.basis.z),
					marker.global_position)
		else:
			ring.global_position = back
		_rings.append(ring)


func _make_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "ShockRing"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter(&"tint", PALETTE.VAPOUR)
	mat.set_shader_parameter(&"energy", 3.0)
	mat.set_shader_parameter(&"thickness", 0.12)
	plane.material = mat
	ring.mesh = plane
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


## A basis whose Y axis points along `up` (the ring lies flat on a ramp too).
static func _basis_with_y(up: Vector3) -> Basis:
	var y := up.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	var k := clampf(_t / TUNE.IGNITION_RING_TIME, 0.0, 1.0)
	for ring in _rings:
		ring.scale = Vector3.ONE * lerpf(TUNE.IGNITION_SCALE_MIN, TUNE.IGNITION_SCALE_MAX, sqrt(k))
		ring.material_override.set_shader_parameter(&"progress", k)
		ring.material_override.set_shader_parameter(&"energy", 3.0 * (1.0 - k))
	if _t >= TUNE.IGNITION_LIFETIME:
		_running = false
		queue_free()

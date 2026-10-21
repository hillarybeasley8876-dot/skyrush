extends Node3D
## Look-dev scene for SmokeFX presets (core): `tools/godot.sh shot --scene=res://core/fx/smoke_demo.tscn
## --cams=...`. A jet firing down onto wet asphalt (vapour + ground cloud), tyre smoke, dust and wreck
## smoke side by side under two neon lights and a street lamp.

const ENV := preload("res://core/stubs/stub_environment.tscn")
const GROUND := preload("res://shaders/materials/SH_wet_asphalt.tres")


func _ready() -> void:
	add_child(ENV.instantiate())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	plane.material = GROUND
	ground.mesh = plane
	add_child(ground)
	_light(Vector3(-6.0, 2.5, -2.0), Color(0.1, 0.9, 1.0), 6.0)
	_light(Vector3(6.0, 2.5, -4.0), Color(1.0, 0.17, 0.84), 6.0)
	_light(Vector3(0.0, 7.0, 3.0), Color(1.0, 0.71, 0.42), 10.0)
	var jet := _emitter(&"jet_vapour", Vector3(0.0, 3.0, 0.0))
	jet.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # -Z (the jet direction) points down
	_emitter(&"ground_cloud", Vector3(0.0, 0.05, 0.0))
	_emitter(&"tyre_smoke", Vector3(-9.0, 0.3, 0.0))
	_emitter(&"dust", Vector3(9.0, 0.2, 0.0))
	_emitter(&"wreck_smoke", Vector3(15.0, 1.0, -4.0))


func _emitter(kind: StringName, at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	SmokeFX.setup(p, SmokeFX.preset(kind))
	p.position = at
	add_child(p)
	return p


func _light(at: Vector3, color: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 12.0
	add_child(l)

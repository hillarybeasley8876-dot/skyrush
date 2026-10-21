extends Node3D
## The impact sparks of the damage unit: a short shower of hot streaks at the point of a
## hard hit. The fx unit has a spark pool of its own, but the damage unit must show the
## spark of its own hits even when the fx unit is not running.
##
## The bursts are pooled: at most MAX_BURSTS of them are alive at the same time.

const FxAssets := preload("res://damage/fx_assets.gd")

const MAX_BURSTS := 6
const SPARK_COUNT := 28
const LIFETIME := 0.35
const SPARK_COLOR := Color(1.0, 0.75, 0.35)
## The streaks of the sparks: a thin, long, additive quad.
const STREAK_WIDTH := 0.015
const STREAK_LENGTH := 0.18
const SPARK_ENERGY := 6.0
## A hit below this speed only throws dust, not sparks.
const MIN_SPEED := 7.0

var _bursts: Array[GPUParticles3D] = []
var _next: int = 0


func _ready() -> void:
	for i in MAX_BURSTS:
		var burst := _make_burst()
		add_child(burst)
		_bursts.append(burst)


## Throws a shower of sparks at a point. `direction` is the way the sparks fly.
func burst(point: Vector3, direction: Vector3, speed: float) -> void:
	if speed < MIN_SPEED:
		return
	# The fx unit sparks every contact on its own: two showers would double the light.
	if Modules.loaded.get(&"fx", "stub") == "real":
		return
	var particles := _bursts[_next]
	_next = (_next + 1) % _bursts.size()
	particles.global_position = point
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction.normalized() if direction.length() > 0.01 else Vector3.UP
	process.initial_velocity_min = clampf(speed * 0.10, 1.5, 4.0)
	process.initial_velocity_max = clampf(speed * 0.22, 3.0, 7.5)
	particles.restart()
	particles.emitting = true


func _make_burst() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = SPARK_COUNT
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 9.0
	process.gravity = Vector3(0.0, -16.0, 0.0)
	process.particle_flag_align_y = true
	process.damping_min = 1.0
	process.damping_max = 3.0
	process.scale_min = 1.0
	process.scale_max = 1.0
	process.color = SPARK_COLOR
	particles.process_material = process
	particles.draw_pass_1 = _make_quad()
	return particles


## A hot streak: a thin, long, additive quad that turns with the velocity.
func _make_quad() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(STREAK_WIDTH, STREAK_LENGTH)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_color = SPARK_COLOR
	material.albedo_texture = FxAssets.spark_texture()
	material.emission_enabled = true
	material.emission = SPARK_COLOR
	material.emission_energy_multiplier = SPARK_ENERGY
	material.disable_receive_shadows = true
	quad.material = material
	return quad

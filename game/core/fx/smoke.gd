class_name SmokeFX
extends RefCounted
## Shared smoke / vapour particles (core-owned, lead). One look for every unit: thruster vapour and
## ground clouds (fx_thrusters), tyre smoke, dust, wreck smoke and steam (fx).
##
##   var p := GPUParticles3D.new()
##   SmokeFX.setup(p, SmokeFX.preset(&"ground_cloud"))     # or tweak the dictionary first
##
## Sprites: res://assets/textures/fx/smoke_billow.png (4 x 4 soft billows, tools/textures/gen_smoke.py)
## + its normal map. Every particle takes ONE RANDOM frame (no flipbook animation), a random angle and
## a slow spin, grows through `scale_curve` and fades in/out through `color_ramp`. The material is LIT
## (scene lights and neon tint the vapour; backlight lets lamps glow through it) with soft-particle
## proximity fade, so sprites never show a hard edge where they meet the ground or the car.

const ATLAS := preload("res://assets/textures/fx/smoke_billow.png")
const ATLAS_N := preload("res://assets/textures/fx/smoke_billow_n.png")
const FRAMES := 4

## Presets. Units copy one and change what they need (amount, sizes, speeds, colours).
const PRESETS: Dictionary = {
	# Cold-gas jet vapour along a plume: a dense, continuous stream that blooms as it slows.
	&"jet_vapour": {"amount": 360, "lifetime": 0.7, "speed": Vector2(18.0, 26.0), "spread": 5.0,
		"damping": Vector2(40.0, 60.0), "size": Vector2(0.2, 0.3), "grow": 6.0, "gravity": 0.0,
		"color": Color(0.95, 0.97, 1.0, 0.5), "flat": 0.0, "spin": 40.0},
	# Ground cloud where a down-firing jet hits the ground: radial, low, big, dense, slow to die.
	&"ground_cloud": {"amount": 220, "lifetime": 3.0, "speed": Vector2(3.0, 9.0), "spread": 180.0,
		"damping": Vector2(4.0, 6.0), "size": Vector2(2.0, 3.2), "grow": 2.4, "gravity": 0.4,
		"color": Color(0.90, 0.92, 0.95, 0.6), "flat": 1.0, "spin": 15.0},
	# Tyre smoke while drifting / burning out: rolls behind the wheel, rises slowly.
	&"tyre_smoke": {"amount": 90, "lifetime": 2.2, "speed": Vector2(1.0, 3.0), "spread": 35.0,
		"damping": Vector2(1.5, 2.5), "size": Vector2(0.7, 1.1), "grow": 3.5, "gravity": 0.35,
		"color": Color(0.78, 0.80, 0.84, 0.4), "flat": 0.0, "spin": 25.0},
	# Dust / debris puff on impacts and off-road.
	&"dust": {"amount": 50, "lifetime": 1.6, "speed": Vector2(2.0, 5.0), "spread": 60.0,
		"damping": Vector2(3.0, 4.0), "size": Vector2(0.5, 0.9), "grow": 3.0, "gravity": -0.4,
		"color": Color(0.55, 0.52, 0.48, 0.45), "flat": 0.0, "spin": 30.0},
	# Dark smoke from a wrecked car: thick, rising, long.
	&"wreck_smoke": {"amount": 80, "lifetime": 4.0, "speed": Vector2(0.8, 1.6), "spread": 15.0,
		"damping": Vector2(0.5, 1.0), "size": Vector2(0.8, 1.2), "grow": 5.0, "gravity": 1.2,
		"color": Color(0.16, 0.16, 0.17, 0.6), "flat": 0.0, "spin": 20.0},
}


static func preset(name: StringName) -> Dictionary:
	return (PRESETS[name] as Dictionary).duplicate()


## Configures `particles` (world-space, lit soft billboards) from a preset dictionary.
static func setup(particles: GPUParticles3D, spec: Dictionary) -> void:
	particles.amount = int(spec["amount"])
	particles.lifetime = float(spec["lifetime"])
	particles.local_coords = false
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.process_material = process_material(spec)
	var quad := QuadMesh.new()
	quad.material = material(spec)
	particles.draw_pass_1 = quad
	var reach := float((spec["speed"] as Vector2).y) * float(spec["lifetime"]) * 0.5
	var size := float((spec["size"] as Vector2).y) * float(spec["grow"])
	particles.visibility_aabb = AABB(Vector3.ONE * -(reach + size), Vector3.ONE * 2.0 * (reach + size))


static func process_material(spec: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	var speed: Vector2 = spec["speed"]
	var damping: Vector2 = spec["damping"]
	var size: Vector2 = spec["size"]
	var flat := float(spec["flat"]) > 0.5
	m.direction = Vector3(1.0, 0.0, 0.0) if flat else Vector3(0.0, 0.0, -1.0)
	if flat:  # ground clouds start half a sprite above the ground, or the soft fade eats them
		m.emission_shape_offset = Vector3(0.0, size.x * 0.45, 0.0)
	m.spread = float(spec["spread"])
	m.flatness = float(spec["flat"])
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.damping_min = damping.x
	m.damping_max = damping.y
	m.gravity = Vector3(0.0, float(spec["gravity"]), 0.0)
	m.scale_min = size.x
	m.scale_max = size.y
	m.scale_curve = _grow_curve(float(spec["grow"]))
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -float(spec["spin"])
	m.angular_velocity_max = float(spec["spin"])
	m.anim_offset_min = 0.0          # one random frame per particle ...
	m.anim_offset_max = 1.0
	m.anim_speed_min = 0.0           # ... that never changes
	m.anim_speed_max = 0.0
	m.color = spec["color"]
	m.color_ramp = _fade_ramp()
	# Gentle curl only: the influence is a per-step blend towards the noise velocity, so anything
	# above ~0.02 eats the launch speed and the cloud never spreads.
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 4.0
	m.turbulence_influence_min = 0.004
	m.turbulence_influence_max = 0.012
	return m


static func material(spec: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true    # without it the billboard drops the particle scale (size/growth)
	m.particles_anim_h_frames = FRAMES
	m.particles_anim_v_frames = FRAMES
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ATLAS
	m.normal_enabled = true
	m.normal_texture = ATLAS_N
	m.normal_scale = 0.8
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.58, 0.62)
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## Fast growth early, slow later (vapour expands, then drifts).
static func _grow_curve(grow: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = grow
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.25, 1.0 + (grow - 1.0) * 0.6))
	c.add_point(Vector2(1.0, grow))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Alpha: quick fade-in (no popping), long soft fade-out.
static func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

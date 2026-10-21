extends RefCounted
## Factory for the GPUParticles3D emitters used by game/fx/. Building them in code (instead of
## hand-written .tscn sub-resources) keeps every effect tunable in one place and makes the
## quality scaling automatic: `quality` is Settings.feature("particles") (0.4 low .. 1.3 ultra).
##
## Every emitter starts with emitting = false: a rig only switches an emitter on when its effect
## is actually wanted, so an idle car runs no particle system at all.
##
## The smoke, the spray, the vapour and the wreck column use the shared core smoke
## (core/fx/smoke.gd, SmokeFX): one look for every unit, a soft billow atlas and lit soft
## billboards. The hot effects (the sparks, the fire, the droplets) use the additive material
## of the fx unit.

const ADD_SHADER := preload("res://fx/fx_add.gdshader")
const TEXTURES := preload("res://fx/fx_textures.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

const BOUNDS := AABB(Vector3(-10.0, -6.0, -10.0), Vector3(20.0, 14.0, 20.0))
## The life ramp of a puff: the alpha fades in quickly, holds and fades out.
const FADE_IN := 0.12
## The number of cells of the flame atlas.
const FLAME_CELLS := 4


## Tyre smoke: lit, wispy puffs that rise and drift back (brief §2). Grey-blue, alpha <= 0.35.
##
## The emitter runs at the rate of the frame (fixed_fps = 0), so the plume is a continuous roll
## of puffs and not a dotted line of clumps.
static func tyre_smoke(quality: float) -> GPUParticles3D:
	var spec := SmokeFX.preset(&"tyre_smoke")
	spec["amount"] = TUNE.SMOKE_AMOUNT
	spec["lifetime"] = TUNE.SMOKE_LIFETIME
	spec["speed"] = Vector2(TUNE.SMOKE_SPEED_MIN, TUNE.SMOKE_SPEED_MAX)
	spec["spread"] = TUNE.SMOKE_SPREAD_DEG
	spec["damping"] = Vector2(0.7, 1.4)
	spec["size"] = Vector2(TUNE.SMOKE_SIZE_MIN, TUNE.SMOKE_SIZE_MAX)
	spec["grow"] = TUNE.SMOKE_GROW
	spec["gravity"] = TUNE.SMOKE_RISE
	# The lead's own tyre smoke preset uses this grey-blue: it is the colour that still reads
	# under a street lamp at night.
	spec["color"] = Color(PALETTE.SMOKE.r, PALETTE.SMOKE.g, PALETTE.SMOKE.b, TUNE.SMOKE_ALPHA)
	var p := _soft_particles(spec, quality)
	# The puffs come out of the contact patch and drift back behind the car.
	_emit_from(p, Vector3(0.2, 0.04, 0.1), Vector3(0.0, 1.0, 0.45))
	var mat := p.process_material as ParticleProcessMaterial
	mat.inherit_velocity_ratio = TUNE.SMOKE_INHERIT
	_ambient_floor(p, TUNE.SMOKE_AMBIENT, TUNE.SMOKE_AMBIENT_ENERGY)
	return p


## The ambient floor of a soft effect: the puffs keep a dim glow of their own, so they read on
## an unlit road instead of rendering black. The shared material of the core is lit only.
static func _ambient_floor(p: GPUParticles3D, color: Color, energy: float) -> void:
	var quad := p.draw_pass_1 as QuadMesh
	if quad == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy


## Wet-road spray: a low, wide fan of cold mist thrown backwards (brief §5). One emitter per
## tyre, so the spray comes out of the contact patch and not from under the axle.
static func spray_mist(quality: float) -> GPUParticles3D:
	var spec := SmokeFX.preset(&"tyre_smoke")
	spec["amount"] = TUNE.SPRAY_AMOUNT
	spec["lifetime"] = TUNE.SPRAY_LIFETIME
	spec["speed"] = Vector2(TUNE.SPRAY_SPEED_MIN, TUNE.SPRAY_SPEED_MAX)
	spec["spread"] = TUNE.SPRAY_FAN_DEG
	spec["damping"] = Vector2(1.2, 2.4)
	spec["size"] = Vector2(TUNE.SPRAY_SIZE_MIN, TUNE.SPRAY_SIZE_MAX)
	spec["grow"] = TUNE.SPRAY_GROW
	spec["gravity"] = -TUNE.SPRAY_GRAVITY * 0.35
	spec["color"] = Color(PALETTE.SPRAY_MIST.r, PALETTE.SPRAY_MIST.g, PALETTE.SPRAY_MIST.b,
			TUNE.SPRAY_ALPHA)
	var p := _soft_particles(spec, quality)
	_emit_from(p, Vector3(0.12, 0.02, 0.08), Vector3(0.0, tan(deg_to_rad(TUNE.SPRAY_TILT_DEG)), 1.0))
	var mat := p.process_material as ParticleProcessMaterial
	mat.inherit_velocity_ratio = TUNE.SPRAY_INHERIT
	# The mist is stretched along its own velocity, so it reads as a fan and not as bubbles.
	mat.particle_flag_align_y = true
	mat.scale_over_velocity_min = TUNE.SPRAY_SPEED_FACTOR * 0.5
	mat.scale_over_velocity_max = TUNE.SPRAY_SPEED_FACTOR
	_ambient_floor(p, TUNE.SMOKE_AMBIENT, TUNE.SMOKE_AMBIENT_ENERGY * 0.15)
	return p


## N2 boost vapour: a cold blue-white trail behind the car (brief §7).
static func vapour(quality: float) -> GPUParticles3D:
	var spec := SmokeFX.preset(&"jet_vapour")
	spec["amount"] = TUNE.VAPOUR_AMOUNT
	spec["lifetime"] = TUNE.VAPOUR_LIFETIME
	spec["speed"] = Vector2(TUNE.VAPOUR_SPEED_MIN, TUNE.VAPOUR_SPEED_MAX)
	spec["damping"] = Vector2(1.6, 3.0)
	spec["size"] = Vector2(TUNE.VAPOUR_WIDTH * 0.35, TUNE.VAPOUR_WIDTH * 0.5)
	spec["grow"] = 2.6
	spec["gravity"] = 0.5
	spec["color"] = Color(PALETTE.VAPOUR.r, PALETTE.VAPOUR.g, PALETTE.VAPOUR.b, 0.3)
	var p := _soft_particles(spec, quality)
	_emit_from(p, Vector3(TUNE.VAPOUR_WIDTH * 0.5, 0.05, 0.1), Vector3(0.0, 0.08, 1.0))
	return p


## The cold puffs of a nitro ignition: white, soft, no fire (dossier §5.5).
static func ignition_puff(quality: float) -> GPUParticles3D:
	var spec := SmokeFX.preset(&"jet_vapour")
	spec["amount"] = TUNE.IGNITION_PUFFS
	spec["lifetime"] = TUNE.IGNITION_LIFETIME
	spec["speed"] = Vector2(2.0, 5.0)
	spec["damping"] = Vector2(1.5, 3.0)
	spec["size"] = Vector2(0.3, 0.5)
	spec["grow"] = 2.8
	spec["gravity"] = 0.6
	spec["color"] = Color(PALETTE.VAPOUR.r, PALETTE.VAPOUR.g, PALETTE.VAPOUR.b,
			TUNE.IGNITION_ALPHA)
	var p := _soft_particles(spec, quality)
	_emit_from(p, Vector3(0.3, 0.3, 0.3), Vector3(0.0, 0.5, 1.0))
	return p


## Wreck smoke column: dark grey #2A2A2E (ICE) or cold white (EV), rising from the engine bay
## and widening from 0.8 m to 4.5 m over its life.
static func wreck_smoke(quality: float, color: Color, lit_from_below: bool) -> GPUParticles3D:
	var spec := SmokeFX.preset(&"wreck_smoke")
	spec["amount"] = TUNE.WRECK_SMOKE_AMOUNT
	spec["lifetime"] = TUNE.WRECK_SMOKE_LIFETIME
	spec["speed"] = Vector2(TUNE.WRECK_SMOKE_RISE_MIN, TUNE.WRECK_SMOKE_RISE_MAX)
	spec["spread"] = TUNE.WRECK_SMOKE_SPREAD
	spec["damping"] = Vector2(0.05, 0.15)
	spec["size"] = Vector2(0.8, 1.2)
	spec["grow"] = TUNE.WRECK_SMOKE_SCALE
	spec["gravity"] = TUNE.WRECK_SMOKE_BUOYANCY
	spec["color"] = Color(color.r, color.g, color.b, TUNE.WRECK_SMOKE_ALPHA)
	var p := _soft_particles(spec, quality)
	_emit_from(p, Vector3(0.4, 0.4, 0.4), Vector3(0.0, 1.0, 0.0))
	var mat := p.process_material as ParticleProcessMaterial
	# The column leans with the wind, but only a little: it has to stand up.
	mat.gravity = Vector3(TUNE.WRECK_SMOKE_WIND, TUNE.WRECK_SMOKE_BUOYANCY, 0.0)
	if lit_from_below:
		# The first puffs of the column are lit by the fire of the wreck.
		mat.color_ramp = _wreck_ramp(color)
	_ambient_floor(p, TUNE.SMOKE_AMBIENT, TUNE.SMOKE_AMBIENT_ENERGY * 0.7)
	return p


## A soft particle system from the shared core smoke (the lead's SmokeFX).
static func _soft_particles(spec: Dictionary, quality: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spec["amount"] = maxi(int(float(spec["amount"]) * clampf(quality, 0.2, 1.3)), 4)
	SmokeFX.setup(p, spec)
	# The puffs are emitted per frame, not in 30 Hz clumps, and the frame in between is
	# interpolated: a plume has to be continuous.
	p.fixed_fps = 0
	p.interpolate = true
	# The shared material of the core has a 0.35 m proximity fade: the puff melts into the road
	# a little before it touches it.
	var mat := p.draw_pass_1 as QuadMesh
	if mat != null and mat.material is StandardMaterial3D:
		(mat.material as StandardMaterial3D).proximity_fade_distance = TUNE.SMOKE_SOFT_DISTANCE
	return p


## Where the puffs come from and which way they go.
static func _emit_from(p: GPUParticles3D, box: Vector3, direction: Vector3) -> void:
	var mat := p.process_material as ParticleProcessMaterial
	if mat == null:
		return
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = box
	mat.direction = direction


## Water droplets thrown off the tyre: bright streaks along their own velocity.
static func droplets(quality: float) -> GPUParticles3D:
	var p := _base(0.55)
	p.amount = maxi(int(TUNE.DROPLET_AMOUNT * quality), 4)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.5, 0.02, 0.08)
	mat.direction = Vector3(0.0, 0.5, 1.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0.0, -TUNE.DROPLET_GRAVITY, 0.0)
	mat.inherit_velocity_ratio = 0.35
	# The particle is aligned with its velocity, so the streak points along the flight.
	mat.particle_flag_align_y = true
	mat.scale_min = TUNE.DROPLET_LENGTH * 0.4
	mat.scale_max = TUNE.DROPLET_LENGTH
	mat.scale_over_velocity_min = TUNE.DROPLET_STREAK
	mat.scale_over_velocity_max = TUNE.DROPLET_STREAK * 4.0
	mat.color_ramp = _fade_ramp(0.8)
	mat.color_initial_ramp = _white()
	p.process_material = mat
	p.draw_pass_1 = _add_quad(TEXTURES.rain_streak(), PALETTE.DROPLET, 1.6, 0.0)
	return p


## Fire licks at the engine bay of a wrecked ICE car: additive, hot core, E3-E4. The quads stand
## up (they turn around the world Y only), so the fire is upright from every side.
static func wreck_fire(quality: float) -> GPUParticles3D:
	var p := _base(TUNE.WRECK_FIRE_LIFETIME)
	p.amount = maxi(int(TUNE.WRECK_FIRE_AMOUNT * quality), 6)
	# The licks live in the space of the car: a wreck that is still sliding does not leave a
	# trail of cards behind it.
	p.local_coords = true
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 14.0
	mat.initial_velocity_min = TUNE.WRECK_FIRE_RISE_MIN
	mat.initial_velocity_max = TUNE.WRECK_FIRE_RISE_MAX
	mat.gravity = Vector3.ZERO
	mat.damping_min = 1.0
	mat.damping_max = 2.2
	# The flame grows to its size and shrinks away again.
	mat.scale_min = 1.0
	mat.scale_max = 1.0
	mat.scale_curve = _scale_curve([[0.0, TUNE.WRECK_FIRE_SIZE_MIN], [0.3, TUNE.WRECK_FIRE_SIZE],
			[1.0, TUNE.WRECK_FIRE_SIZE_END]])
	mat.color_ramp = _fire_ramp()
	# A fixed random angle: the shader picks the cell of the flame atlas from it, so the shape
	# of a lick is fixed for its life and never pops. The angle is read in degrees.
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.color_initial_ramp = _white()
	p.process_material = mat
	p.draw_pass_1 = _add_quad(TEXTURES.flame_atlas(), Color(1.0, 1.0, 1.0), TUNE.WRECK_FIRE_ENERGY,
			float(FLAME_CELLS), 2.0)
	return p


## Shared setup: a billboard particle system that starts switched off.
static func _base(lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	# A soft particle would cast a square shadow: no shadows from particles.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.lifetime = lifetime
	p.randomness = 0.6
	p.local_coords = false
	p.visibility_aabb = BOUNDS
	return p


## Additive billboard (flames, flashes, droplets).
static func _add_quad(atlas: Texture2D, tint: Color, energy: float, cells: float,
		billboard_mode: float = 0.0) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = ADD_SHADER
	mat.set_shader_parameter(&"albedo_tex", atlas)
	mat.set_shader_parameter(&"use_texture", true)
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"energy", energy)
	mat.set_shader_parameter(&"atlas_cells", cells)
	mat.set_shader_parameter(&"billboard_mode", billboard_mode)
	quad.material = mat
	return quad


## A fade ramp for the additive materials: the RGB stays white (the tint of the effect is a
## uniform of the shader) and the alpha carries the fade.
static func _fade_ramp(alpha: float) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, FADE_IN, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, alpha),
		Color(1.0, 1.0, 1.0, alpha * 0.7),
		Color(1.0, 1.0, 1.0, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## The colour ramp of a flame: amber, then orange, then the cold tip. The white-hot core lives
## in the texture, not in the HDR, or the licks tonemap to cream white.
static func _fire_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.06, 0.35, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(PALETTE.FIRE_RAMP_0.r, PALETTE.FIRE_RAMP_0.g, PALETTE.FIRE_RAMP_0.b, 0.0),
		Color(PALETTE.FIRE_RAMP_0.r, PALETTE.FIRE_RAMP_0.g, PALETTE.FIRE_RAMP_0.b, 1.0),
		Color(PALETTE.FIRE_RAMP_1.r, PALETTE.FIRE_RAMP_1.g, PALETTE.FIRE_RAMP_1.b, 0.9),
		Color(PALETTE.FIRE_RAMP_2.r, PALETTE.FIRE_RAMP_2.g, PALETTE.FIRE_RAMP_2.b, 0.6),
		Color(PALETTE.FIRE_RAMP_3.r, PALETTE.FIRE_RAMP_3.g, PALETTE.FIRE_RAMP_3.b, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## The colour ramp of the column of an ICE wreck: the first puffs are lit by the fire below.
static func _wreck_ramp(color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.05, 0.15, 0.45, 1.0])
	var hot := PALETTE.FIRE_RAMP_1
	grad.colors = PackedColorArray([
		Color(hot.r, hot.g, hot.b, 0.0),
		Color(hot.r, hot.g, hot.b, 0.9),
		Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 1.0),
		Color(color.r, color.g, color.b, 0.7),
		Color(color.r, color.g, color.b, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## A white initial ramp (for the effects whose colour comes from their own life ramp).
static func _white() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## Scale over lifetime: pairs of (position, value) on a curve normalised to 0..1.
static func _scale_curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.0
	for pair: Array in points:
		curve.add_point(Vector2(float(pair[0]), float(pair[1])))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

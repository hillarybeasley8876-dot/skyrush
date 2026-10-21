extends RefCounted
## Shared materials and textures for the thruster plumes.
##
## The vapour sprites are the lead's shared smoke atlas (core/fx/smoke.gd, SmokeFX): one look
## for every unit, and the puff shape is already right (soft billows, no hard edges).
##
## The billboards are drawn with the cheap per-vertex variant of that atlas. The plumes are made
## of big soft sprites (0.4-3.6 m), so the per-pixel lighting of the shared preset would cost
## about five times the fill rate for no visible gain (the perf budget is 1.2 ms per 1080p
## view).

## The landing ring decal is this unit's own texture.
const RING_PATH := "res://fx/thrusters/textures/ring_decal.png"
## The lead's shared smoke atlas.
const SMOKE_ATLAS := preload("res://assets/textures/fx/smoke_billow.png")
## The seamless fbm the vapour column scrolls (textures/gen_textures.py).
const NOISE_PATH := "res://fx/thrusters/textures/vapour_noise.png"

## Proximity fade: the billboards must not cut the road in a straight line.
const VAPOUR_FADE := 0.35
## The billboards fade out when the camera is inside them. The chase camera sits in the rear
## trail, and a 7 m sprite one metre from the lens covers the whole screen: without this the
## trail alone costs more than the whole perf budget.
const NEAR_FADE_MIN := 1.0
const NEAR_FADE_MAX := 2.5
## How much the jet vapour lights itself.
const VAPOUR_EMISSION := 0.3
## The ground cloud gets a little: it has to read as a bank on a dark road, and it has to stay
## translucent, so the scene's neon tints it as well.
const CLOUD_EMISSION := 0.35

## Vapour body colour (dossier §6.1): white condensation, never fire. It is thin enough that
## the shock diamonds of the core stay readable through it (review MUST-FIX 4).
const VAPOUR_BIRTH := Color(0.949, 0.965, 0.980, 0.65)
## Ground cloud: white, and thin enough that the road shows through it.
const CLOUD_BIRTH := Color(0.902, 0.918, 0.933, 0.7)
## The rear launch trail (photo 29): white, a bit more transparent than the cloud.
const TRAIL_BIRTH := Color(0.902, 0.918, 0.933, 0.5)

static var _ring_tex: Texture2D = null
static var _cloud_mat: StandardMaterial3D = null
static var _vapour_mat: StandardMaterial3D = null


static func ring_texture() -> Texture2D:
	if _ring_tex == null:
		_ring_tex = load(RING_PATH) as Texture2D
	return _ring_tex


## The scrolling noise of the vapour column.
static func noise_texture() -> Texture2D:
	return load(NOISE_PATH) as Texture2D


## The cheap variant of the shared smoke billboard, for the big ground-cloud sprites.
##
## It keeps everything that shows: the lead's atlas and its 4 x 4 frames, the vertex colour, the
## soft-particle proximity fade and the lit tint from the scene lights. What it drops is the
## per-pixel lighting, the normal map and the backlight - the sprites are metres across, so the
## per-pixel version cost five times the fill for a difference nobody can see.
##
## The cloud is lit, not emissive: the scene's neon tints it and the bank stays translucent
## instead of turning into a white wall (the lead's look-dev target).
static func cloud_material() -> StandardMaterial3D:
	if _cloud_mat == null:
		_cloud_mat = _make_billboard(CLOUD_EMISSION)
	return _cloud_mat


## The jet vapour: the same cheap billboard, but with a little self-illumination. The plume is
## the brightest accent in the frame (ART §2.4), and a single young sprite lit only by the scene
## reads as a dark speck against the dark road.
static func vapour_material() -> StandardMaterial3D:
	if _vapour_mat == null:
		_vapour_mat = _make_billboard(VAPOUR_EMISSION)
	return _vapour_mat


static func _make_billboard(emission_energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without it the billboard drops the particle scale (the size curve is ignored).
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 4
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = SMOKE_ATLAS
	m.albedo_color = Color(1, 1, 1, 1)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = VAPOUR_FADE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	# The chase camera can end up inside a cloud: fade the sprite out instead of letting it
	# cover the whole screen.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = NEAR_FADE_MIN
	m.distance_fade_max_distance = NEAR_FADE_MAX
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = VAPOUR_BIRTH
		m.emission_energy_multiplier = emission_energy
	return m


## Emissive disc sitting in the nozzle throat (the lit throat, not a glowing flame).
static func throat_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 1)
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.emission_enabled = true
	m.emission = Color(0.624, 0.847, 1.0)
	m.emission_energy_multiplier = 0.0
	return m


## Repairs the shared preset's growth curve.
##
## SmokeFX builds the size curve with `curve.max_value = grow`, and a CurveTexture stores its
## points normalised into 0..1 of that range, so a curve of 1.0 - 2.4 never reaches the
## particle shader as a multiplier. Measured: the ground cloud stayed a scatter of 1.2 m
## chips instead of a bank of soft puffs (review MUST-FIX 1).
##
## The curve cannot be repaired from here (the CurveTexture of Godot 4.7 stores the points
## clamped), so the growth is dropped and the sprite size is set directly instead: the sprites
## are the size this unit asks for, from the first frame. The fix belongs in
## core/fx/smoke.gd (see the request in the status file).
static func uncap_growth(particles: GPUParticles3D, _grow: float) -> void:
	var pm := particles.process_material as ParticleProcessMaterial
	if pm == null:
		return
	pm.scale_curve = null


## Drops the cached resources. The engine's leak detector counts them at exit, so the owner
## calls this once the last rig is gone.
static func release() -> void:
	_ring_tex = null
	_cloud_mat = null
	_vapour_mat = null

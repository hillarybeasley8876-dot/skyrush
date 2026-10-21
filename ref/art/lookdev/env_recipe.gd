## SKYRUSH look-dev: the night-city Environment recipe (Godot 4.7, Forward+).
## Every number here is the DOSSIER section 3 recipe. Copy this file into the game unchanged and call
## EnvRecipe.make_world_environment(); tweak only through the exported constants below.
class_name EnvRecipe
extends RefCounted

const SKY_SHADER := "res://shaders/sky_night_city.gdshader"
const HDRI_PATH := "res://tex/shanghai_bund_2k.hdr"   # Poly Haven CC0, 2K is enough for radiance

static func make_cloud_noise() -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.004
	fnl.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = fnl
	return tex

static func make_sky() -> Sky:
	var mat := ShaderMaterial.new()
	mat.shader = load(SKY_SHADER)
	mat.set_shader_parameter("cloud_noise", make_cloud_noise())
	if ResourceLoader.exists(HDRI_PATH):
		mat.set_shader_parameter("radiance_hdri", load(HDRI_PATH))
	var sky := Sky.new()
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	return sky

static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Tonemap: AgX keeps neon hue while the core goes white; supports HDR output (Filmic does not).
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_agx_white = 10.0
	env.tonemap_agx_contrast = 1.3
	# Glow: only emission above ~1.2 blooms (neon, lamps, headlights). Windows stay below it.
	env.glow_enabled = true
	env.glow_normalized = false
	env.set_glow_level(0, 0.0)  # level 1
	env.set_glow_level(1, 0.5)  # level 2: tight halo around tubes
	env.set_glow_level(2, 0.7)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.15)  # level 5: wide wet-air bloom
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.2
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	# Distance haze (cheap, everywhere) - purple-grey city air.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("2a2638")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.35
	env.fog_height = 6.0
	env.fog_height_density = 0.015
	env.fog_aerial_perspective = 0.0
	# Volumetric fog: light shafts from headlights / lamps / police bars. Keep length short for quality.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color("9aa0b8")
	env.volumetric_fog_emission = Color("000000")
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.15
	# Screen-space effects.
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_light_affect = 0.0
	env.ssil_enabled = false          # "High" preset only: on, intensity 1.0, radius 5 (neon bounce on walls)
	env.sdfgi_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	return env

static func make_world_environment() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.environment = make_environment()
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = false
	we.camera_attributes = cam_attr
	return we

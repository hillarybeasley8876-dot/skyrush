extends RefCounted
## SKYRUSH night-city Environment recipe.
## Ported from ref/art/lookdev/env_recipe.gd [V] and extended with quality-preset scaling
## (DOSSIER 3.1, tech dossier section 5). Every number below is the verified recipe; the preset
## only switches the expensive screen-space features off on low/medium.

const SKY_SHADER := "res://shaders/sky_night_city.gdshader"
## The distance-fog density of the default district (DOSSIER 3.1).
const FOG_DENSITY := 0.0035
## The volumetric density of the default district. The zone table is the only place it is written
## (a quality change must not reset the active zone back to the default density).
const VOLUMETRIC_DENSITY := 0.0035
## The environment values every zone starts from, and the per-zone overrides (DOSSIER 3.1).
const ZONE_DEFAULTS: Dictionary = {
	"volumetric_fog_density": VOLUMETRIC_DENSITY,
	"fog_density": FOG_DENSITY,
	"fog_aerial_perspective": 0.0,
}
const ZONE_OVERRIDES: Dictionary = {
	&"nanjing": {"volumetric_fog_density": 0.009},
	&"underdeck": {"volumetric_fog_density": 0.008},
	&"flight": {"fog_density": 0.0015, "fog_aerial_perspective": 0.5},
}


## The environment values of a district: the defaults with the zone's overrides merged in.
static func zone_values(zone: StringName) -> Dictionary:
	var values := ZONE_DEFAULTS.duplicate()
	if ZONE_OVERRIDES.has(zone):
		values.merge(ZONE_OVERRIDES[zone] as Dictionary, true)
	return values
const HDRI_PATH := "res://assets/hdri/shanghai_bund.hdr"   # Poly Haven CC0, 2K is enough for radiance
const RAIN_HDRI_PATH := "res://assets/hdri/vignaioli_night.hdr"  # the overcast night the rain brings


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
		mat.set_shader_parameter("radiance_energy", 0.18)  # >0.3 makes puddles look like gold foil
	if ResourceLoader.exists(RAIN_HDRI_PATH):
		mat.set_shader_parameter("rain_hdri", load(RAIN_HDRI_PATH))
		mat.set_shader_parameter("rain_hdri_energy", 0.18)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	return sky


## Builds the full recipe. `features` is Settings.PRESETS[preset] (see core/settings.gd).
static func make_environment(features: Dictionary) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# The ambient is a cool fill, not the key: 1.0 is the verified recipe (DOSSIER 3.1). A higher
	# value lifts the whole game 40 % above the recipe and washes the night out.
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
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.35
	env.fog_height = 6.0
	env.fog_height_density = 0.015
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.volumetric_fog_density = VOLUMETRIC_DENSITY
	apply_features(env, features)
	return env


## Screen-space features that the quality preset scales. Called again whenever Settings.changed fires.
static func apply_features(env: Environment, features: Dictionary) -> void:
	var volumetric := bool(features.get("volumetric_fog", true))
	env.volumetric_fog_enabled = volumetric
	if volumetric:
		# Light shafts from headlights / lamps / police bars. Keep length short for quality.
		# NOTE: the density is NOT written here - the zone table owns it (a quality change must
		# not reset the active zone's density back to the default).
		env.volumetric_fog_albedo = Color("9aa0b8")
		# A cool violet emission is the base of the haze: without it the street volume is lit only
		# by the warm lamps and reads brown (lead note 1).
		env.volumetric_fog_emission = Color("14122a")
		# The cool base of the haze (DOSSIER 3.1). It only washed the street out while the light
		# pools were standing vertically across it as tan walls; those are gone.
		env.volumetric_fog_emission_energy = 0.6
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_length = 64.0   # a shorter volume is cheaper and looks the same on a street
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_ambient_inject = 0.03
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_sky_affect = 0.15
	env.ssr_enabled = bool(features.get("ssr", true))
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.ssao_enabled = bool(features.get("ssao", true))
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_light_affect = 0.0
	env.ssil_enabled = false          # "High" preset only: on, intensity 1.0, radius 5 (neon bounce on walls)
	env.sdfgi_enabled = false

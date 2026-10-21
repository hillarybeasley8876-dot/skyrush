## SKYRUSH look-dev: material factory (reference implementation of DOSSIER section 4 recipes).
class_name LookdevMaterials
extends RefCounted

const SH := "res://shaders/"
const TEX := "res://tex/"

static func noise_tex(freq: float, seed: int, as_normal := false, size := 512) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = freq
	fnl.seed = seed
	fnl.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = as_normal
	t.bump_strength = 6.0
	t.noise = fnl
	return t

static func shader_mat(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH + file)
	return m

static func road_wet(wetness := 0.85, puddles := 0.2) -> ShaderMaterial:
	var m := shader_mat("road_wet.gdshader")
	m.set_shader_parameter("albedo_tex", load(TEX + "asphalt_02_diff_2k.jpg"))
	m.set_shader_parameter("normal_tex", load(TEX + "asphalt_02_nor_gl_2k.jpg"))
	m.set_shader_parameter("rough_tex", load(TEX + "asphalt_02_rough_2k.jpg"))
	m.set_shader_parameter("tile_m", 3.0)
	m.set_shader_parameter("albedo_mul", 0.55)   # asphalt_02 mean #5B5955 -> dry ~#424240
	m.set_shader_parameter("macro_tex", noise_tex(0.01, 7))
	m.set_shader_parameter("puddle_noise", noise_tex(0.012, 11))
	m.set_shader_parameter("ripple_normal", noise_tex(0.08, 3, true, 256))
	m.set_shader_parameter("wetness", wetness)
	m.set_shader_parameter("puddle_amount", puddles)
	m.set_shader_parameter("puddle_m", 14.0)
	return m

static func road_marking(color: Color, wetness := 0.85) -> ShaderMaterial:
	var m := shader_mat("road_marking.gdshader")
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("wear_noise", noise_tex(0.05, 21, false, 256))
	m.set_shader_parameter("wetness", wetness)
	return m

static func facade(floor_h := 3.8, lit := 0.38) -> ShaderMaterial:
	var m := shader_mat("facade_windows.gdshader")
	m.set_shader_parameter("floor_h", floor_h)
	m.set_shader_parameter("lit_ratio", lit)
	return m

static func neon() -> ShaderMaterial:
	return shader_mat("neon_tube.gdshader")

static func hologram(content: Texture2D) -> ShaderMaterial:
	var m := shader_mat("hologram_billboard.gdshader")
	m.set_shader_parameter("content", content)
	return m

static func car_paint() -> ShaderMaterial:
	var m := shader_mat("car_paint.gdshader")
	m.set_shader_parameter("flake_normal", noise_tex(0.9, 5, true, 256))
	return m

static func granite_bund() -> StandardMaterial3D:
	# Bund facade: NEUTRAL warm-grey stone. The gold comes from 2500 K uplights, never from albedo.
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "granite_bund_diff_2k.jpg")  # conditioned copy, mean sRGB ~#ABAAA3
	m.albedo_color = Color("ffffff")
	m.normal_enabled = true
	m.normal_texture = load(TEX + "granite_tile_03_nor_gl_2k.jpg")
	m.normal_scale = 0.5   # full-strength stone grain sparkles/aliases beyond ~15 m
	m.orm_texture = load(TEX + "granite_tile_03_arm_2k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 1.8   # granite_tile_03 real size 1.8 m
	return m

static func chrome() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c4c5c5")
	m.metallic = 1.0
	m.roughness = 0.08
	return m

static func tyre_rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a2a2a")
	m.roughness = 0.86
	return m

static func tinted_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.039, 0.055, 0.071, 0.55)   # #0A0E12 @ 55 %
	m.roughness = 0.03
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m

static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.8)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

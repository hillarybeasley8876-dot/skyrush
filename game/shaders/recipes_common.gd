extends RefCounted
## Shared helpers for the material recipes (the driver and the three recipe files).
## The recipes build the SH_*.tres; see material_factory.gd.

const SHADER_DIR := "res://shaders/"
const TEX_DIR := "res://assets/textures/"

## The measured mean of every albedo scan we use, in LINEAR space. The shaders divide the scan by
## this value, so the material keeps its intended colour instead of the scan's warm cast
## (DOSSIER 5.4; the piers rendered near-black without it).
const MEANS: Dictionary = {
	"asphalt_02": Vector3(0.1046, 0.0999, 0.0908),
	"concrete": Vector3(0.1714, 0.1413, 0.1046),
	"concrete_wall_008": Vector3(0.2664, 0.2346, 0.1651),
	"concrete_pavement": Vector3(0.2159, 0.1746, 0.1356),
	"granite_bund": Vector3(0.4072, 0.4020, 0.3663),
	"granite_tile_03": Vector3(0.1336, 0.1084, 0.0883),
	"PavingStones144": Vector3(0.3372, 0.3231, 0.2747),
	"clean_asphalt": Vector3(0.0595, 0.0595, 0.0630),
	"Concrete046": Vector3(0.6172, 0.6105, 0.4910),
	"TactilePaving003": Vector3(0.4125, 0.3564, 0.0015),
}


## The textures a recipe asked for but could not find. A missing texture is FATAL: the material
## would silently fall back to a black or white sampler and the detail layer would be a no-op.
static var _missing: PackedStringArray = PackedStringArray()


static func tex(id: String, map: String) -> Texture2D:
	var path := TEX_DIR + id + "/" + id + "_" + map + ".jpg"
	if not ResourceLoader.exists(path):
		push_error("material_factory: missing texture " + path)
		_missing.append(path)
		return null
	return load(path) as Texture2D


## The textures the recipes asked for but could not find (the factory fails on these).
static func missing_textures() -> PackedStringArray:
	return _missing


static func mean(id: String) -> Vector3:
	return MEANS.get(id, Vector3(0.1714, 0.1413, 0.1046)) as Vector3


static func noise(freq: float, seed_value: int, size: int = 512, as_normal: bool = false) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = freq
	fnl.seed = seed_value
	fnl.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.as_normal_map = as_normal
	tex.bump_strength = 2.0
	tex.noise = fnl
	return tex


## A 128 x 1024 stretched noise, the mask of the concrete detail layer (DOSSIER 4.3).
static func detail_mask() -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.03
	fnl.seed = 71
	fnl.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 1024
	tex.noise = fnl
	return tex


static func mat(shader_file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + shader_file)
	return m


static func apply(m: ShaderMaterial, params: Dictionary) -> void:
	for key: String in params:
		m.set_shader_parameter(key, params[key])

extends RefCounted
## The street recipes: the wet asphalt, the lane paint and the concrete family (piers, barriers,
## granite, pavement, kerb, tactile strip).

const C := preload("res://shaders/recipes_common.gd")


## Wet asphalt for streets, elevated decks and ramps.
static func wet_asphalt() -> ShaderMaterial:
	var m := C.mat("road_wet.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex("asphalt_02", "diff"),
		"normal_texture": C.tex("asphalt_02", "nor_gl"),
		"roughness_texture": C.tex("asphalt_02", "rough"),
		"ao_texture": C.tex("asphalt_02", "ao"),
		"tile_m": 3.0,
		"macro_tex": C.tex("aerial_asphalt_01", "diff"),
		"macro_m": 30.0,
		"macro_strength": 0.35,
		"albedo_mul": 0.50,
		"tint": Color(1, 1, 1),
		"wetness_bias": 0.0,
		"rain_bias": 0.0,
		"detail_strength": 0.5,
		"detail_fade_m": 26.0,
		"puddle_amount": 0.24,
		"puddle_m": 14.0,
		"puddle_noise": C.noise(0.012, 11, 512),
		"ripple_normal": C.noise(0.08, 3, 256, true),
	})
	return m


## Lane paint. `paint` is the sRGB colour, `wear` how worn the line is.
static func road_marking(paint: Color, wear: float) -> ShaderMaterial:
	var m := C.mat("road_marking.gdshader")
	C.apply(m, {
		"paint_color": paint,
		"use_mask": false,
		"wear": wear,
		"wear_noise": C.noise(0.05, 21, 256),
		"wetness_bias": 0.0,
		"retro_strength": 0.35,
		"retro_near_m": 6.0,
		"retro_far_m": 70.0,
	})
	return m


## Stained concrete. `id` picks the library texture, `size_m` its real-world size.
## `drip` is the strength of the water stains from the Leaking* maps.
static func concrete(id: String, size_m: float, streak: float, splash_h: float, drip: float) -> ShaderMaterial:
	var m := C.mat("concrete_stained.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex(id, "diff"),
		"normal_texture": C.tex(id, "nor_gl"),
		"roughness_texture": C.tex(id, "rough"),
		"ao_texture": C.tex(id, "ao"),
		"detail_texture": C.tex(id, "diff"),
		"drip_texture": C.tex("Leaking004", "opacity"),
		"detail_mask": C.detail_mask(),
		"uv_scale": 1.0 / size_m,
		"detail_scale": 3.0,
		"detail_amount": 0.35,
		"tex_mean": C.mean(id),
		"detail_mean": C.mean(id),
		"base_color": Color("7a7874"),
		"albedo_mul": 1.0,
		"concrete_tint": Color(1, 1, 1),
		"splash_factor": 1.0,
		"streak_noise": C.noise(0.06, 61, 512),
		"streak_amount": streak,
		"streak_scale": 0.3,
		"drip_amount": drip,
		"drip_lo_m": 1.8,
		"drip_hi_m": 6.0,
		"splash_height_m": splash_h,
		"splash_darken": 0.30,
		"wet_roughness": 0.55,
	})
	return m


## Bund granite: the conditioned Poly Haven scan (mean #ABAAA3), triplanar, neutral warm grey.
## The gold comes from the 2500 K uplights, never from the albedo (DOSSIER 1.4 / 4.9).
static func granite() -> ShaderMaterial:
	var m := C.mat("concrete_stained.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex("granite_bund", "diff"),
		"normal_texture": C.tex("granite_tile_03", "nor_gl"),
		"roughness_texture": C.tex("granite_tile_03", "rough"),
		"ao_texture": C.tex("granite_tile_03", "ao"),
		"detail_texture": C.tex("granite_tile_03", "diff"),
		"drip_texture": C.tex("Leaking004", "opacity"),
		"detail_mask": C.detail_mask(),
		"uv_scale": 1.0 / 1.8,
		"detail_scale": 3.0,
		"detail_amount": 0.30,
		"tex_mean": C.mean("granite_bund"),
		"detail_mean": C.mean("granite_tile_03"),
		"base_color": Color("9c9b95"),
		"albedo_mul": 1.0,
		"concrete_tint": Color(1, 1, 1),
		"splash_factor": 0.4,
		"streak_noise": C.noise(0.06, 61, 512),
		"streak_amount": 0.12,
		"streak_scale": 0.3,
		"drip_amount": 0.0,
		"splash_height_m": 0.4,
		"splash_darken": 0.20,
		"wet_roughness": 0.5,
		# DOSSIER 4.9: the granite's normal at half strength (full strength sparkles past 15 m),
		# and the stone is laid in courses, not in the 1.8 m square grid of the scan.
		"normal_scale": 0.5,
		"course_height_m": 0.42,
		"course_width_m": 1.8,
		"course_joint": 0.5,
	})
	return m


## The pavement: paving stones with the joints, wet-darkened, and no splash zone (it is flat).
static func sidewalk() -> ShaderMaterial:
	var m := C.mat("concrete_stained.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex("PavingStones144", "diff"),
		"normal_texture": C.tex("PavingStones144", "nor_gl"),
		"roughness_texture": C.tex("PavingStones144", "rough"),
		"ao_texture": C.tex("PavingStones144", "ao"),
		"detail_texture": C.tex("PavingStones144", "diff"),
		"drip_texture": C.tex("Leaking004", "opacity"),
		"detail_mask": C.detail_mask(),
		"uv_scale": 1.0 / 1.4,
		"detail_scale": 3.0,
		"detail_amount": 0.40,
		"tex_mean": C.mean("PavingStones144"),
		"detail_mean": C.mean("PavingStones144"),
		"base_color": Color("6e6c68"),
		"albedo_mul": 1.0,
		"concrete_tint": Color(1, 1, 1),
		"splash_factor": 0.0,
		"streak_noise": C.noise(0.06, 61, 512),
		"streak_amount": 0.10,
		"streak_scale": 0.3,
		"drip_amount": 0.0,
		"splash_height_m": 0.05,
		"splash_darken": 0.15,
		"wet_roughness": 0.45,
	})
	return m


## The kerb: the Bund granite, darkened to #8E8C86 (DOSSIER 4.9).
static func kerb() -> ShaderMaterial:
	var m := C.mat("concrete_stained.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex("granite_bund", "diff"),
		"normal_texture": C.tex("granite_tile_03", "nor_gl"),
		"roughness_texture": C.tex("granite_tile_03", "rough"),
		"ao_texture": C.tex("granite_tile_03", "ao"),
		"detail_texture": C.tex("granite_tile_03", "diff"),
		"drip_texture": C.tex("Leaking004", "opacity"),
		"detail_mask": C.detail_mask(),
		"uv_scale": 1.0 / 1.8,
		"detail_scale": 3.0,
		"detail_amount": 0.35,
		"tex_mean": C.mean("granite_bund"),
		"detail_mean": C.mean("granite_tile_03"),
		"base_color": Color("8e8c86"),
		"albedo_mul": 1.0,
		"concrete_tint": Color(1, 1, 1),
		"splash_factor": 0.6,
		"streak_noise": C.noise(0.06, 61, 512),
		"streak_amount": 0.18,
		"streak_scale": 0.3,
		"drip_amount": 0.0,
		"splash_height_m": 0.18,
		"splash_darken": 0.25,
		"wet_roughness": 0.4,
		"normal_scale": 0.5,
		"course_height_m": 0.42,
		"course_width_m": 1.8,
		"course_joint": 0.45,
	})
	return m


## The tactile strip (盲道): the 30 cm yellow band at the kerb edge (DOSSIER 4.9).
static func tactile() -> ShaderMaterial:
	var m := C.mat("concrete_stained.gdshader")
	C.apply(m, {
		"albedo_texture": C.tex("TactilePaving003", "diff"),
		"normal_texture": C.tex("TactilePaving003", "nor_gl"),
		"roughness_texture": C.tex("TactilePaving003", "rough"),
		"detail_texture": C.tex("TactilePaving003", "diff"),
		"drip_texture": C.tex("Leaking004", "opacity"),
		"detail_mask": C.detail_mask(),
		"uv_scale": 1.0 / 1.2,
		"detail_scale": 3.0,
		"detail_amount": 0.35,
		"tex_mean": C.mean("TactilePaving003"),
		"detail_mean": C.mean("TactilePaving003"),
		"base_color": Color("c9b43a"),
		"albedo_mul": 1.0,
		"concrete_tint": Color(1, 1, 1),
		"splash_factor": 0.0,
		"streak_noise": C.noise(0.06, 61, 512),
		"streak_amount": 0.15,
		"streak_scale": 0.3,
		"drip_amount": 0.0,
		"splash_height_m": 0.03,
		"splash_darken": 0.10,
		"wet_roughness": 0.4,
	})
	return m

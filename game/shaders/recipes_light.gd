extends RefCounted
## The light recipes: the neon, the hologram, the soffit, the water and the facades.

const C := preload("res://shaders/recipes_common.gd")


## Neon tubes and LED channel letters. The per-material colour/energy are plain uniforms, so a
## sign that exports `SH_neon` with its own emission colour keeps it; the instance uniforms are
## per-sign overrides.
static func neon() -> ShaderMaterial:
	var m := C.mat("neon_tube.gdshader")
	C.apply(m, {
		"emission_color": Color(1.0, 0.165, 0.541, 1.0),
		"emission_energy": 5.0,
		"core_whiten": 0.12,
		"dropout_rate": 0.015,
	})
	return m


## Floating hologram / giant LED screen. mode/energy/tint are instance uniforms (per screen).
static func hologram() -> ShaderMaterial:
	var grad := Gradient.new()
	grad.set_color(0, Color("0b1e3a"))
	grad.set_color(1, Color("19e6ff"))
	grad.set_color(2, Color("ff2bd6"))
	var content := GradientTexture2D.new()
	content.gradient = grad
	content.width = 512
	content.height = 512
	content.fill_from = Vector2(0, 0)
	content.fill_to = Vector2(1, 1)
	var m := C.mat("hologram_billboard.gdshader")
	C.apply(m, {
		"emission_texture": content,
		"scan_lines": 220.0,
		"scan_speed": 0.6,
		"chroma_px": 2.0,
		"glitch_rate": 0.08,
		"led_grid": Vector2(320, 180),
		"edge_fade": 0.04,
	})
	return m


## The underside of the elevated deck: the blue wash (E1) and the two edge LED strips (E3).
static func soffit_blue() -> ShaderMaterial:
	var m := C.mat("soffit_blue.gdshader")
	C.apply(m, {
		"wash_color": Color("2357f3"),
		"strip_color": Color("5a3dff"),
		"wash_energy": 0.9,          # E1 (DOSSIER 3.7 #2): the wash is the verified recipe value
		"strip_energy": 4.5,         # E3
		"wash_falloff": 0.45,        # 100 % at the outer edge, ~55 % toward the girder
		"soffit_width_m": 15.4,
		"strip_width_m": 0.05,
		"core_whiten": 0.3,
		"albedo_texture": C.tex("concrete", "diff"),
		"normal_texture": C.tex("concrete", "nor_gl"),
		"ao_texture": C.tex("concrete", "ao"),
		# The stain SHAPE is the opacity map; the colour map is the stain's own dark colour.
		"stain_texture": C.tex("Leaking004", "opacity"),
		"tex_mean": C.mean("concrete"),
		"base_color": Color("6e6c68"),
		"uv_scale": 1.0,
		"grime_noise": C.noise(0.09, 51, 512),
		"grime_amount": 0.4,
		"joint_spacing_m": 1.2,
		"joint_width_m": 0.07,
		"joint_v": 0.25,
		"joint_width_v": 0.002,
		"rib_light": 0.12,
		"stain_amount": 0.7,
	})
	return m


## The Huangpu: opaque, dark, two scrolling normals 40 deg apart.
static func water() -> ShaderMaterial:
	var m := C.mat("water_river.gdshader")
	C.apply(m, {
		"water_color": Color("0b1016"),
		"roughness_value": 0.08,
		"wave_strength": 0.38,
		"normal_a": C.noise(0.06, 41, 512, true),
		"normal_b": C.noise(0.11, 43, 512, true),
		"ripple_normal": C.noise(0.3, 47, 256, true),
		"tile_m": 6.0,
		"flow_a": Vector2(0.10, 0.0),
		"flow_b": Vector2(0.044, 0.037),
		"ripple_scale": 2.2,
		"ripple_speed": 1.6,
		"ripple_strength": 0.5,
	})
	return m


## Office and residential curtain wall. `residential` switches the whole preset.
## The lit area is kept at 6-7 % of the facade (ART.md 2 and 5: "2-8 % of a facade").
static func facade(residential: bool) -> ShaderMaterial:
	var m := C.mat("facade_windows.gdshader")
	var id := "concrete_wall_008" if residential else "concrete"
	C.apply(m, {
		"wall_color": Color("8e877c") if residential else Color("383a3e"),
		"wall_roughness": 0.7 if residential else 0.55,
		"glass_color": Color("0b0e13"),
		"glass_roughness": 0.06,
		"floor_h": 2.95 if residential else 3.9,
		"bay_w": 3.3 if residential else 1.5,
		"window_frac": Vector2(0.55, 0.55) if residential else Vector2(0.86, 0.62),
		"sill_frac": 0.3 if residential else 0.22,
		"ground_floors": 1.0 if residential else 2.0,
		"lit_ratio": 0.22 if residential else 0.15,
		"dark_floor_ratio": 0.05 if residential else 0.18,
		"tv_ratio": 0.05 if residential else 0.0,
		"window_energy": 1.0,
		"blinds_max": 0.9 if residential else 0.7,
		"ground_y": 0.0,
		"albedo_texture": C.tex(id, "diff"),
		"normal_texture": C.tex(id, "nor_gl"),
		"wall_uv_scale": 0.37 if residential else 0.25,
		"tex_mean": C.mean(id),
		"grime_noise": C.noise(0.07, 23, 512),
		"grime_amount": 0.35,
	})
	return m

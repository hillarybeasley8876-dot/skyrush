extends RefCounted
## The vehicle recipes: the car paint (hero, traffic, police, taxi) and the two glass shaders.

const C := preload("res://shaders/recipes_common.gd")


## Car paint. `kind`: "hero" (Ano White Roadster), "npc" (traffic), "police", "taxi".
## The paint colour is a plain uniform; a traffic car overrides it with base_color_override.
static func car_paint(kind: String) -> ShaderMaterial:
	var m := C.mat("car_paint.gdshader")
	var paint := Color("ecedef")
	var metallic := 0.0
	var rough := 0.12
	var flake := 0.06
	var grime := 0.15
	var coat := 1.0
	var coat_rough := 0.04
	var grime_h := 0.30
	match kind:
		"npc":
			paint = Color("e8e8e6")
			metallic = 0.3
			rough = 0.42
			flake = 0.2
			grime = 0.45
			coat = 0.8
			coat_rough = 0.08
			grime_h = 0.45
		"police":
			paint = Color("f2f4f5")   # POLICE_WHITE
			metallic = 0.0
			rough = 0.35
			flake = 0.0
			grime = 0.35
			coat = 1.0
			coat_rough = 0.06
			grime_h = 0.45
		"taxi":
			paint = Color("1e8c8a")   # the fictional teal taxi
			metallic = 0.2
			rough = 0.38
			flake = 0.15
			grime = 0.45
			coat = 0.9
			coat_rough = 0.07
			grime_h = 0.45
	C.apply(m, {
		"base_color": paint,
		"metallic_amount": metallic,
		"base_roughness": rough,
		"flake_strength": flake,
		"grime_amount": grime,
		"clearcoat_amount": coat,
		"clearcoat_rough": coat_rough,
		"grime_height_m": grime_h,
		"grime_color": Color("2e2a26"),
		"panel_normal_strength": 0.25,
		"peel_normal": C.noise(0.06, 5, 256, true),
		"peel_scale": 6.0,
		"peel_strength": 0.10,
		"flake_normal": C.noise(0.06, 9, 256, true),
		"flake_scale": 60.0,
		# The clear coat is broken up by the dust sheet (SurfaceImperfections001), sampled in
		# object space so the dust belongs to the car.
		"clearcoat_roughness_map": C.tex("SurfaceImperfections001", "opacity"),
		"clearcoat_detail_scale": 0.5,
		"clearcoat_breakup": 0.06,
		"use_livery": false,
	})
	return m


## Roadster canopy: dark bronze-gold, fresnel, metallic sheen, rain streaks.
static func glass_gold() -> ShaderMaterial:
	var m := C.mat("glass_gold.gdshader")
	C.apply(m, {
		"tint_color": Color("5a3f2a"),
		"sheen_color": Color(0.85, 0.68, 0.42),
		"interior_color": Color(0.30, 0.22, 0.16),
		"base_alpha": 0.68,
		"interior_amount": 0.35,
		"fresnel_power": 3.0,
		"fresnel_opacity": 0.85,
		"sheen_strength": 0.5,
		"roughness_value": 0.05,
		"rain_streaks": 1.0,
		"streak_noise": C.noise(0.05, 31, 512),
		"streak_scale": 3.0,
		"streak_speed": 0.35,
	})
	return m


## Dark tinted glass for traffic cars.
static func glass_tinted() -> ShaderMaterial:
	var m := C.mat("glass_tinted.gdshader")
	C.apply(m, {
		"tint_color": Color("0a0e12"),
		"base_alpha": 0.72,
		"fresnel_power": 3.0,
		"fresnel_opacity": 0.95,
		"roughness_value": 0.08,
		"grime_amount": 0.25,
		"grime_noise": C.noise(0.08, 33, 512),
	})
	return m

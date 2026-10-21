extends RefCounted
## Texture library for game/fx/. The particle textures are baked once by
## game/fx/tools/bake_textures.gd into game/fx/textures/ and loaded from disk; the small
## procedural helpers stay here for the few shapes that are cheaper to compute.

const DIR := "res://fx/textures/"

static var _cache: Dictionary = {}


## 32 x 256 streak: white-hot head, orange tail.
static func spark_streak() -> Texture2D:
	return _load(&"spark_streak", "spark_streak.png")


## Tyre track: 8 tread grooves, 256 px across the 24 cm track.
static func tyre_track() -> Texture2D:
	return _load(&"tyre_track", "tyre_track.png")


## Air streak: a soft white line (the displaced air of a near miss, the cold vapour).
static func air_streak() -> Texture2D:
	return _load(&"air_streak", "air_streak.png")


## Arc streak: a white-hot core with a cyan halo, fading at the ends.
static func arc_streak() -> Texture2D:
	return _load(&"arc_streak", "arc_streak.png")


## Rain streak line.
static func rain_streak() -> Texture2D:
	return _load(&"rain_streak", "rain_streak.png")


## Two concentric rings for the rain splashes.
static func ripple() -> Texture2D:
	return _load(&"ripple", "ripple.png")


## The energy ribbon of the 闪充 charge flash: chevron dashes with a bright leading edge.
static func energy_ribbon() -> Texture2D:
	return _load(&"energy_ribbon", "energy_ribbon.png")


## 4 x 4 atlas of 256 px flame licks.
static func flame_atlas() -> Texture2D:
	return _load(&"flame_atlas", "flame_atlas.png")


## The halo of the 闪充 charge flash: a hot core and a halo that falls off as exp(-8 d^2), with
## no visible rim. A wide quad with a rim whites out the frame from above.
static func charge_halo() -> Texture2D:
	if _cache.has(&"charge_halo"):
		return _cache[&"charge_halo"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var core := 1.0 - smoothstep(0.0, 0.20, d)
			var halo := exp(-8.0 * d * d) * 0.45
			var a := clampf(core + halo, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[&"charge_halo"] = tex
	return tex


## A soft round glow (procedural, used for the charge flash and the small lights).
static func glow() -> Texture2D:
	if _cache.has(&"glow"):
		return _cache[&"glow"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var core := 1.0 - smoothstep(0.0, 0.30, d)
			var halo := (1.0 - smoothstep(0.0, 1.0, d)) * 0.45
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(core + halo, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[&"glow"] = tex
	return tex


static func _load(key: StringName, file: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := DIR + file
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		push_warning("[fx] missing baked texture " + path)
		tex = glow()
	_cache[key] = tex
	return tex

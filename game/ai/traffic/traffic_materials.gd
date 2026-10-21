class_name TrafficMaterials
extends RefCounted
## The shared materials of the AI traffic.
##
## The body paint is the shared `SH_car_paint_npc` shader material: its `base_color` is an
## instance uniform, so every car gets its own colour from ONE material (art dossier 4.7). The
## lamps use `traffic_lights.gdshader`, whose `energy` is an instance uniform so a car can brake
## or blink its indicators without any material duplication.

const LIGHT_SHADER := preload("res://ai/traffic/traffic_lights.gdshader")
const PAINT_PATH := "res://shaders/materials/SH_car_paint_npc.tres"
const GLASS_PATH := "res://shaders/materials/SH_glass_tinted.tres"

const HEAD_COLOR := Color("f4f7ff")     ## cold white head lamp
## Tail lamp red. The green and the blue stay under 8 % of the red: with AgX a lamp that has
## any blue in it washes out to white when the brake lamps come on.
const TAIL_COLOR := Color("ff1414")
const HEAD_LAMP_ENERGY := 1.0           ## the head lamps
const TAIL_LAMP_ENERGY := 0.8           ## the tail lamps while cruising
const INDICATOR_COLOR := Color("ffb000")## amber indicator
const INDICATOR_ENERGY := 3.2           ## the blinking indicator

static var _paint: Material = null
static var _shadow: GradientTexture2D = null
static var _glass: Material = null
static var _rubber: StandardMaterial3D = null
static var _trim: StandardMaterial3D = null
static var _head: ShaderMaterial = null
static var _tail: ShaderMaterial = null
static var _indicator: ShaderMaterial = null
static var _indicator_on: ShaderMaterial = null


## The shared car paint. Set `base_color` per mesh instance.
static func paint() -> Material:
	if _paint == null:
		if ResourceLoader.exists(PAINT_PATH):
			_paint = load(PAINT_PATH) as Material
		else:
			var fallback := StandardMaterial3D.new()
			fallback.albedo_color = Color("e8e8e6")
			fallback.metallic = 0.3
			fallback.roughness = 0.42
			_paint = fallback
	return _paint


## The dark glass of the greenhouse.
static func glass() -> Material:
	if _glass == null:
		if ResourceLoader.exists(GLASS_PATH):
			_glass = load(GLASS_PATH) as Material
		else:
			var fallback := StandardMaterial3D.new()
			fallback.albedo_color = Color("0a0e12")
			fallback.metallic = 0.4
			fallback.roughness = 0.12
			_glass = fallback
	return _glass


## The soft round texture of the blob shadow under a car.
static func shadow_texture() -> GradientTexture2D:
	if _shadow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_shadow = GradientTexture2D.new()
		_shadow.gradient = gradient
		_shadow.fill = GradientTexture2D.FILL_RADIAL
		_shadow.fill_from = Vector2(0.5, 0.5)
		_shadow.fill_to = Vector2(1.0, 0.5)
		_shadow.width = 128
		_shadow.height = 128
	return _shadow


## Tyres: near black, rough, with a fine tread normal so they are not a flat blob.
static func rubber() -> StandardMaterial3D:
	if _rubber == null:
		_rubber = StandardMaterial3D.new()
		_rubber.albedo_color = Color(0.035, 0.036, 0.04)
		_rubber.roughness = 0.88
		_rubber.metallic = 0.0
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.35
		noise.seed = 17
		var tex := NoiseTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 2.0
		tex.noise = noise
		_rubber.normal_enabled = true
		_rubber.normal_texture = tex
	return _rubber


## Bumpers, sills, grille: dark satin plastic with a little metal.
static func trim() -> StandardMaterial3D:
	if _trim == null:
		_trim = StandardMaterial3D.new()
		_trim.albedo_color = Color(0.055, 0.057, 0.065)
		_trim.roughness = 0.55
		_trim.metallic = 0.35
	return _trim


static func head() -> ShaderMaterial:
	if _head == null:
		_head = _lamp(HEAD_COLOR, HEAD_LAMP_ENERGY)
	return _head


static func tail() -> ShaderMaterial:
	if _tail == null:
		_tail = _lamp(TAIL_COLOR, TAIL_LAMP_ENERGY)
	return _tail


static func indicator() -> ShaderMaterial:
	if _indicator == null:
		_indicator = _lamp(INDICATOR_COLOR, 0.0)
	return _indicator


## The amber indicator while it blinks.
static func indicator_on() -> ShaderMaterial:
	if _indicator_on == null:
		_indicator_on = _lamp(INDICATOR_COLOR, INDICATOR_ENERGY)
	return _indicator_on


## The amber indicator while it is off.
static func indicator_off() -> ShaderMaterial:
	return indicator()


static func _lamp(color: Color, energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_SHADER
	mat.set_shader_parameter("lamp_color", color)
	mat.set_shader_parameter("energy", energy)
	return mat

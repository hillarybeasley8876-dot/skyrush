extends Node3D
## Environment unit entry point (res://world/env/environment.tscn).
## Owns the WorldEnvironment, the moon light and the weather controller, and re-applies the quality
## preset whenever Settings.changed fires. The recipe itself lives in env_recipe.gd.

const EnvRecipe := preload("res://world/env/env_recipe.gd")

## Moon colour and energy (DOSSIER 3.3): the city lights the city, the moon only rims the towers.
const MOON_COLOR := Color("9fb4ff")
const MOON_ENERGY := 0.06
const MOON_ENERGY_FLIGHT := 0.12

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _moon: DirectionalLight3D = $Moon

var _features: Dictionary = {}
var _zone: StringName = &"default"
var _zone_from: Dictionary = {}
var _zone_to: Dictionary = {}
var _zone_blend: float = 1.0
const ZONE_BLEND_SECONDS := 2.0


func _ready() -> void:
	add_to_group("environment")
	_features = Settings.PRESETS.get(Settings.quality, Settings.PRESETS[&"high"]) as Dictionary
	_world_env.environment = EnvRecipe.make_environment(_features)
	_configure_moon()
	Settings.changed.connect(_on_settings_changed)
	var weather := get_node_or_null("Weather")
	if weather != null and weather.has_signal("rain_changed"):
		(weather as Node).connect("rain_changed", _on_rain_changed)
		# The weather node is ready before this one, so the --rain boot state is already set.
		if weather.has_method("is_raining"):
			_on_rain_changed(bool(weather.call("is_raining")))


## Switch to a district preset. The values blend in over 2 s so the change is not a cut.
func set_zone(zone: StringName) -> void:
	if not EnvRecipe.ZONE_OVERRIDES.has(zone) and zone != &"default":
		push_warning("environment: unknown zone %s" % zone)
		return
	_zone = zone
	_zone_to = EnvRecipe.zone_values(zone)
	# The blend starts from what the environment shows right now, so a zone switch never pops.
	_zone_from = {}
	var env := _world_env.environment
	for key: String in _zone_to:
		if env != null:
			_zone_from[key] = env.get(key)
	_zone_blend = 0.0


func _process(delta: float) -> void:
	if _zone_blend >= 1.0:
		return
	_zone_blend = minf(1.0, _zone_blend + delta / ZONE_BLEND_SECONDS)
	_apply_zone()


func _apply_zone() -> void:
	var env := _world_env.environment
	if env == null:
		return
	for key: String in _zone_to:
		var from := float(_zone_from.get(key, _zone_to[key]))
		var to := float(_zone_to[key])
		env.set(key, lerp(from, to, _zone_blend))


func _on_settings_changed() -> void:
	_features = Settings.PRESETS.get(Settings.quality, Settings.PRESETS[&"high"]) as Dictionary
	if _world_env.environment != null:
		EnvRecipe.apply_features(_world_env.environment, _features)
		_zone_from = {}
		var env := _world_env.environment
		for key: String in _zone_to:
			_zone_from[key] = env.get(key)
		_zone_blend = 0.0


## The flight layer is above 80 m: the moon gets a rim light and the shadows switch on.
func set_flight_mode(flight: bool) -> void:
	_moon.light_energy = MOON_ENERGY_FLIGHT if flight else MOON_ENERGY
	_moon.shadow_enabled = flight
	# One directional light, 4 splits, 200 m (tech dossier section 5).
	_moon.directional_shadow_max_distance = 200.0
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## The rain sky: the sky's radiance cross-fades to the overcast night while it rains, so the
## puddles stop mirroring a clear sky.
func _on_rain_changed(active: bool) -> void:
	var env := _world_env.environment
	if env == null or env.sky == null:
		return
	var mat := env.sky.sky_material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("rain_mix", 1.0 if active else 0.0)


func _configure_moon() -> void:
	_moon.light_color = MOON_COLOR
	_moon.light_energy = MOON_ENERGY
	_moon.shadow_enabled = false       # streets are lit by the city, not the moon
	_moon.rotation_degrees = Vector3(-38.0, 128.0, 0.0)

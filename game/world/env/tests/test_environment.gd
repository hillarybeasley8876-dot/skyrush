extends Node
## Environment unit test: the WorldEnvironment recipe, the quality-preset scaling and the weather
## controller (shader globals, smooth transitions).
##
##   tools/godot.sh test res://world/env/tests/test_environment.gd

const EnvRecipe := preload("res://world/env/env_recipe.gd")
const ENV_SCENE := "res://world/env/environment.tscn"

var _failed: int = 0


func _ready() -> void:
	_check_recipe_high()
	_check_presets()
	_check_scene()
	_check_weather()
	_check_rain_boot_snap()
	_check_zones()
	_check_globals_registered()
	print("TEST_ENVIRONMENT %d failed" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)


func _check_recipe_high() -> void:
	var env := EnvRecipe.make_environment(Settings.PRESETS[&"high"])
	if env == null:
		_fail("make_environment returned null")
		return
	if env.tonemap_mode != Environment.TONE_MAPPER_AGX:
		_fail("tonemap is not AgX")
		return
	if not is_equal_approx(env.tonemap_exposure, 1.0):
		_fail("tonemap exposure is %f" % env.tonemap_exposure)
		return
	if not is_equal_approx(env.tonemap_agx_contrast, 1.3):
		_fail("agx contrast is %f" % env.tonemap_agx_contrast)
		return
	if not env.glow_enabled or not is_equal_approx(env.glow_hdr_threshold, 1.2):
		_fail("glow is off or has the wrong threshold")
		return
	var levels := [0.0, 0.5, 0.7, 0.4, 0.15, 0.0, 0.0]
	for i in 7:
		if not is_equal_approx(env.get_glow_level(i), levels[i]):
			_fail("glow level %d is %f, expected %f" % [i, env.get_glow_level(i), levels[i]])
			return
	if not env.fog_enabled or not is_equal_approx(env.fog_density, EnvRecipe.FOG_DENSITY):
		_fail("distance fog is off or has the wrong density")
		return
	if env.fog_light_color != Color("2a2638"):
		_fail("fog colour is %s" % str(env.fog_light_color))
		return
	if not env.volumetric_fog_enabled or not is_equal_approx(env.volumetric_fog_density, 0.0035):
		_fail("volumetric fog is off or has the wrong density on high")
		return
	if not env.ssr_enabled or not env.ssao_enabled:
		_fail("SSR or SSAO is off on high")
		return
	if env.ssil_enabled or env.sdfgi_enabled:
		_fail("SSIL/SDFGI must stay off (tech dossier 5)")
		return
	if env.background_mode != Environment.BG_SKY or env.sky == null:
		_fail("the background is not the sky")
		return
	var sky_mat := env.sky.sky_material as ShaderMaterial
	if sky_mat == null or sky_mat.shader == null:
		_fail("the sky has no shader material")
		return
	if not is_equal_approx(float(sky_mat.get_shader_parameter("radiance_energy")), 0.18):
		_fail("the HDRI radiance energy is not 0.25")
		return
	_pass("the environment recipe matches the verified look-dev values")


func _check_presets() -> void:
	var expect := {
		&"low": [false, false, false],
		&"medium": [false, true, true],
		&"high": [true, true, true],
		&"ultra": [true, true, true],
	}
	for preset: StringName in expect:
		var features: Dictionary = Settings.PRESETS[preset]
		var env := EnvRecipe.make_environment(features)
		var want: Array = expect[preset]
		if env.volumetric_fog_enabled != bool(want[0]):
			_fail("%s: volumetric fog should be %s" % [preset, str(want[0])])
			return
		if env.ssr_enabled != bool(want[1]):
			_fail("%s: SSR should be %s" % [preset, str(want[1])])
			return
		if env.ssao_enabled != bool(want[2]):
			_fail("%s: SSAO should be %s" % [preset, str(want[2])])
			return
	_pass("the quality presets scale the screen-space features")


func _check_scene() -> void:
	var packed := load(ENV_SCENE) as PackedScene
	if packed == null:
		_fail("the environment scene does not load")
		return
	var node := packed.instantiate()
	add_child(node)
	var world_env := node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		_fail("the environment scene has no WorldEnvironment with an environment")
		return
	if world_env.environment.tonemap_mode != Environment.TONE_MAPPER_AGX:
		_fail("the scene environment is not the AgX recipe")
		return
	var moon := node.get_node_or_null("Moon") as DirectionalLight3D
	if moon == null:
		_fail("the environment scene has no moon")
		return
	if moon.light_energy > 0.1 or moon.shadow_enabled:
		_fail("the moon is %f with shadows %s (must be 0.06 and shadowless on the street)"
			% [moon.light_energy, str(moon.shadow_enabled)])
		return
	if node.get_node_or_null("Weather") == null:
		_fail("the environment scene has no weather controller")
		return
	_pass("the environment scene wires the recipe, the moon and the weather")
	node.queue_free()


func _check_weather() -> void:
	var packed := load(ENV_SCENE) as PackedScene
	# The rain is a feature of the medium/high presets: the persisted quality must not decide
	# whether this test can run.
	var saved_quality := Settings.quality
	Settings.quality = &"high"
	var node := packed.instantiate()
	add_child(node)
	var weather := node.get_node("Weather")
	if not weather.is_in_group("weather"):
		_fail("the weather controller is not in the 'weather' group")
		return
	if not is_equal_approx(weather.wetness(), 0.85):
		_fail("the default wetness is %f, expected 0.85" % weather.wetness())
		return
	if not is_equal_approx(weather.rain_amount(), 0.0):
		_fail("the default rain is %f, expected 0" % weather.rain_amount())
		return
	weather.set_rain(true)
	if not weather.is_raining():
		_fail("set_rain(true) did not start the rain")
		return
	# The transition is smooth: the rain amount must not jump on the same frame.
	if weather.rain_amount() > 0.01:
		_fail("the rain jumped to %f instead of transitioning" % weather.rain_amount())
		return
	for i in 40:
		weather._process(0.5)
	if not is_equal_approx(weather.rain_amount(), 0.6):
		_fail("the rain settled at %f, expected 0.6" % weather.rain_amount())
		return
	if not is_equal_approx(weather.wetness(), 1.0):
		_fail("the wetness settled at %f, expected 1.0 while it rains" % weather.wetness())
		return
	weather.set_rain(false)
	for i in 40:
		weather._process(0.5)
	if weather.rain_amount() > 0.01:
		_fail("the rain did not stop")
		return
	if not is_equal_approx(weather.wetness(), 0.85):
		_fail("the wetness after the rain is %f, expected 0.85" % weather.wetness())
		return
	_pass("the weather controller defaults to after-rain and transitions smoothly")
	node.queue_free()
	Settings.quality = saved_quality


## The --rain boot snap: the rain is already falling on the first frame, not ramping in.
func _check_rain_boot_snap() -> void:
	var packed := load(ENV_SCENE) as PackedScene
	var saved_quality := Settings.quality
	Settings.quality = &"high"
	var node := packed.instantiate()
	add_child(node)
	var weather := node.get_node("Weather")
	weather.set_rain(true)
	if weather.rain_amount() > 0.01:
		_fail("the rain jumped to %f instead of transitioning" % weather.rain_amount())
		return
	weather.apply_now()
	if not is_equal_approx(weather.rain_amount(), 0.6):
		_fail("the boot snap left the rain at %f, expected 0.6" % weather.rain_amount())
		return
	if not is_equal_approx(weather.wetness(), 1.0):
		_fail("the boot snap left the wetness at %f, expected 1.0" % weather.wetness())
		return
	_pass("the rain snaps to its target at boot")
	node.queue_free()
	Settings.quality = saved_quality


## The zone overrides: flight -> default restores the default values, and a zone switch never pops.
func _check_zones() -> void:
	var packed := load(ENV_SCENE) as PackedScene
	var node := packed.instantiate()
	add_child(node)
	var env := node.get_node("WorldEnvironment") as WorldEnvironment
	var controller := node as Node
	controller.set_zone(&"flight")
	for i in 60:
		controller._process(0.1)
	var flight_density := float(env.environment.get("fog_density"))
	var flight_aerial := float(env.environment.get("fog_aerial_perspective"))
	if not is_equal_approx(flight_density, 0.0015) or not is_equal_approx(flight_aerial, 0.5):
		_fail("the flight zone did not apply: density %f aerial %f" % [flight_density, flight_aerial])
		return
	controller.set_zone(&"default")
	for i in 30:
		controller._process(0.1)
	var back_density := float(env.environment.get("fog_density"))
	var back_aerial := float(env.environment.get("fog_aerial_perspective"))
	if not is_equal_approx(back_density, EnvRecipe.FOG_DENSITY) or not is_equal_approx(back_aerial, 0.0):
		_fail("the default zone did not restore: density %f aerial %f" % [back_density, back_aerial])
		return
	# A zone switch must not pop: the first frame is still the old value.
	controller.set_zone(&"nanjing")
	for i in 60:
		controller._process(0.1)
	var nanjing := float(env.environment.get("volumetric_fog_density"))
	controller.set_zone(&"underdeck")
	controller._process(0.001)
	var first := float(env.environment.get("volumetric_fog_density"))
	if absf(first - nanjing) > nanjing * 0.05:
		_fail("the zone switch popped: %f -> %f" % [nanjing, first])
		return
	# A quality change must NOT reset the active zone's density back to the default.
	controller.set_zone(&"nanjing")
	for i in 60:
		controller._process(0.1)
	var zone_density := float(env.environment.get("volumetric_fog_density"))
	controller._on_settings_changed()
	for i in 60:
		controller._process(0.1)
	var after_quality := float(env.environment.get("volumetric_fog_density"))
	if absf(after_quality - zone_density) > 0.0001:
		_fail("the quality change reset the zone density: %f -> %f" % [zone_density, after_quality])
		return
	_pass("the zone overrides blend and restore")
	node.queue_free()


func _check_globals_registered() -> void:
	for key: String in ["shader_globals/skyrush_wetness", "shader_globals/skyrush_rain"]:
		if not ProjectSettings.has_setting(key):
			_fail("%s is not registered in the project settings" % key)
			return
	_pass("the shader globals skyrush_wetness and skyrush_rain are registered")


func _pass(msg: String) -> void:
	print("PASS ", msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL ", msg)

extends Node
## Weather controller (environment unit). Owns the two shader globals every wet surface reads:
##   skyrush_wetness - 0 dry .. 1 soaked. Default 0.85: the look is "Shanghai, 1 a.m., just after rain".
##   skyrush_rain    - 0 dry .. 1 raining. Turned on by the --rain command-line option or by the menu.
## Transitions are smoothed so the road, the paint and the car glass never pop between states.
## Other units talk to it through the "weather" group:
##   get_tree().get_first_node_in_group("weather").set_rain(true)

signal rain_changed(active: bool)
signal wetness_changed(value: float)

## Road wetness right after the rain stops (the default look).
const DEFAULT_WETNESS := 0.85
## Rain intensity while it is raining.
const RAIN_AMOUNT := 0.6
## Seconds for a full 0..1 transition.
const TRANSITION_SECONDS := 8.0

@export var enabled: bool = true
@export var transition_seconds: float = TRANSITION_SECONDS

var _wetness: float = DEFAULT_WETNESS
var _rain: float = 0.0
var _target_wetness: float = DEFAULT_WETNESS
var _target_rain: float = 0.0
var _raining: bool = false
var _quality_allows_rain: bool = true


func _ready() -> void:
	add_to_group("weather")
	_read_quality()
	_wetness = _target_wetness
	_rain = _target_rain
	_push_globals()
	if Game.has_option("rain"):
		set_rain(true)
		# At boot the rain is already falling: snap to the target instead of ramping in over 5 s,
		# so a capture taken a second after start sees the rain (lead note 13).
		apply_now()
	Settings.changed.connect(_read_quality)


## Snap the current weather to the target at once and push the globals (used at boot).
func apply_now() -> void:
	_wetness = _target_wetness
	_rain = _target_rain
	_push_globals()


func _process(delta: float) -> void:
	if not enabled:
		return
	var step := delta / maxf(transition_seconds, 0.01)
	var wet := move_toward(_wetness, _target_wetness, step)
	var rain := move_toward(_rain, _target_rain, step)
	if is_equal_approx(wet, _wetness) and is_equal_approx(rain, _rain):
		return
	_wetness = wet
	_rain = rain
	_push_globals()
	wetness_changed.emit(_wetness)


## Turns the rain on (true) or off (false). The road stays wet after the rain stops.
func set_rain(active: bool) -> void:
	_raining = active and _quality_allows_rain
	_target_rain = RAIN_AMOUNT if _raining else 0.0
	_target_wetness = 1.0 if _raining else DEFAULT_WETNESS
	rain_changed.emit(_raining)


## Fully dry road (used by the "dry" look-dev preset and by the pit garage).
func set_dry() -> void:
	_raining = false
	_target_rain = 0.0
	_target_wetness = 0.0
	rain_changed.emit(false)


func is_raining() -> bool:
	return _raining


func wetness() -> float:
	return _wetness


## 0..1 rain amount, for the fx unit's rain particles.
func rain_amount() -> float:
	return _rain


func _read_quality() -> void:
	_quality_allows_rain = bool(Settings.feature("rain"))
	if not _quality_allows_rain and _raining:
		set_rain(false)


func _push_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"skyrush_wetness", _wetness)
	RenderingServer.global_shader_parameter_set(&"skyrush_rain", _rain)

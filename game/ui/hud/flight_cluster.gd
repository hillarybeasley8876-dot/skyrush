extends Control
## Flight cluster: the Roadster reveal livestream gauges (dossier §6.4).
##   left  — DOWNFORCE (kg) + car-attitude circle
##   right — PITCH (deg) + ALTITUDE (m)
## Gauge centres sit at y = 0.906 H, x = 0.091 / 0.19 / 0.815 / 0.910 W. The cluster slides in
## over 0.2 s when the car leaves the ground.

const UI := preload("res://ui/theme/skyrush_theme.gd")
const GaugeDial := preload("res://ui/hud/gauge_dial.gd")
const AttitudeIcon := preload("res://ui/hud/attitude_icon.gd")

## The gauge geometry of the dossier (§6.4): the DOWNFORCE, the attitude icon, the PITCH and the
## ALTITUDE rings sit at these x fractions of the width and at 0.906 H, 156 px wide.
const GAUGE_SIZE := 156.0
const GAUGE_X: Array[float] = [0.091, 0.19, 0.815, 0.910]
const GAUGE_Y_FRACTION := 0.906
const GAUGE_HALF := 78.0
## The speed cluster is anchored to the bottom right, so the flight shift grows with the height.
const SPEED_MARGIN := 84.0
## The N2 cluster keeps its own N2 visible in flight (the player spends it there), but it has to
## clear the DOWNFORCE ring.
const NITRO_CLEARANCE := 24.0
const HALF := GAUGE_SIZE * 0.5
const DOWNFORCE_MAX := 5000.0
const ALTITUDE_MAX := 100.0
const PITCH_MAX := 180.0
const SLIDE_TIME := 0.2

var _downforce: GaugeDial
var _attitude: AttitudeIcon
var _pitch: GaugeDial
var _altitude: GaugeDial
## The four gauges, so the slide does not build an array every frame.
var _gauges: Array[Control] = []


## How far the speed cluster moves up in flight, so it clears the flight gauges.
static func flight_speed_shift(viewport: Vector2) -> float:
	return (1.0 - GAUGE_Y_FRACTION) * viewport.y + SPEED_MARGIN


## The y the N2 cluster moves to in flight: its bottom edge sits NITRO_CLEARANCE above the
## DOWNFORCE gauge box (the gauge box starts at 0.906 H - 78 px).
static func flight_nitro_target(viewport: Vector2, cluster_height: float) -> float:
	return viewport.y * GAUGE_Y_FRACTION - GAUGE_HALF - NITRO_CLEARANCE - cluster_height

var _slide: float = -70.0:
	set(value):
		_slide = value
		_apply_slide()
var _tween: Tween
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	modulate.a = 0.0
	visible = false


func _build() -> void:
	_downforce = _add_gauge(GaugeDial.new(), GAUGE_X[0])
	_attitude = _add_gauge(AttitudeIcon.new(), GAUGE_X[1])
	_pitch = _add_gauge(GaugeDial.new(), GAUGE_X[2])
	_altitude = _add_gauge(GaugeDial.new(), GAUGE_X[3])
	_gauges = [_downforce, _attitude, _pitch, _altitude]

	var live := UI.outlined_label("SKYRUSH LIVE", 16, Color(1, 1, 1, 0.45), null,
		HORIZONTAL_ALIGNMENT_RIGHT)
	live.anchor_left = 1.0
	live.anchor_right = 1.0
	live.anchor_top = 1.0
	live.anchor_bottom = 1.0
	live.offset_left = -240.0
	live.offset_right = -16.0
	live.offset_top = -44.0
	live.offset_bottom = -22.0
	add_child(live)


func _add_gauge(node: Control, frac_x: float) -> Control:
	node.anchor_left = frac_x
	node.anchor_right = frac_x
	node.anchor_top = GAUGE_Y_FRACTION
	node.anchor_bottom = GAUGE_Y_FRACTION
	node.offset_left = -HALF
	node.offset_right = HALF
	node.offset_top = -HALF
	node.offset_bottom = HALF
	add_child(node)
	return node


## downforce_kg, pitch_deg, altitude_m, plumes (P1..P4 thruster levels).
func set_values(downforce_kg: float, pitch_deg: float, altitude_m: float,
		plumes: PackedFloat32Array) -> void:
	_downforce.set_values(downforce_kg, clampf(downforce_kg / DOWNFORCE_MAX, 0.0, 1.0),
		"DOWNFORCE", "KG", 0)
	_pitch.set_values(pitch_deg, clampf(absf(pitch_deg) / PITCH_MAX, 0.0, 1.0), "PITCH", "DEG", 0)
	_altitude.set_values(altitude_m, clampf(altitude_m / ALTITUDE_MAX, 0.0, 1.0), "ALTITUDE", "M", 1)
	_attitude.set_values(pitch_deg, plumes)


## active: show (slide in) or hide (slide out) the cluster.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	visible = true
	# Kill the previous tween so a quick hop in / hop out cannot leave the cluster half way.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.set_parallel(false)
	_tween.tween_property(self, "modulate:a", 1.0 if active else 0.0, SLIDE_TIME)
	_tween.parallel().tween_property(self, "_slide", 0.0 if active else -70.0, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not active:
		_tween.tween_callback(func() -> void: visible = false)


func _apply_slide() -> void:
	for node in _gauges:
		node.offset_top = -HALF + _slide
		node.offset_bottom = HALF + _slide

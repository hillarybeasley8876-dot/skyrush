extends Control
## Bottom-right speed cluster: the dial, the big italic speed number inside it, the km/h unit and
## the battery readout underneath. Anchored to the bottom-right corner so it survives 16:10 and 21:9.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const SpeedDial := preload("res://ui/hud/speed_dial.gd")

const DIAL_SIZE := Vector2(300, 340)
## The battery row sits BELOW the dial (the bezel ends at y 295), so it never crosses the ring.
const BATTERY_RECT := Rect2(150, 326, 140, 6)
const BATTERY_LOW := 0.15
const BATTERY_MID := 0.35

var _dial: SpeedDial
var _value: Label
var _unit: Label
var _battery_label: Label
var _last_speed: int = -1
var _last_battery_pct: int = -1
var _last_boost: bool = false
var _battery_shown: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DIAL_SIZE
	size = DIAL_SIZE
	_build()


func _build() -> void:
	_dial = SpeedDial.new()
	_dial.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dial)

	_value = UI.outlined_display_label("0", 96, Palette.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_value.size = Vector2(240, 110)
	_value.position = Vector2(30, 92)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_value)

	_unit = UI.outlined_label("km/h", 24, Palette.TEXT_DIM, null, HORIZONTAL_ALIGNMENT_CENTER)
	_unit.size = Vector2(240, 28)
	_unit.position = Vector2(30, 198)
	add_child(_unit)

	_battery_label = UI.outlined_label("电量 100%", 18, Palette.TEXT_DIM, null,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_battery_label.size = Vector2(140, 22)
	_battery_label.position = Vector2(150, 300)
	add_child(_battery_label)


## Hide the battery row (the flight layout hides it to clear the right-hand gauges).
func set_battery_visible(visible: bool) -> void:
	_battery_label.visible = visible
	_battery_shown = visible
	queue_redraw()


## speed_kmh: current speed; load: motor load 0..1; boosting: an N2 boost is burning;
## battery: 0..1.
func update_values(speed_kmh: float, load: float, boosting: bool, battery: float) -> void:
	_dial.set_values(speed_kmh, load, boosting)

	var rounded := int(round(speed_kmh))
	if rounded != _last_speed:
		_last_speed = rounded
		_value.text = str(rounded)
	if boosting != _last_boost:
		_last_boost = boosting
		_value.add_theme_color_override("font_color", Palette.MAGENTA if boosting else Palette.WHITE)

	# The battery is compared as a whole percent: a draining battery must not redraw the cluster
	# (and rewrite the label) every single frame.
	var pct := int(round(clampf(battery, 0.0, 1.0) * 100.0))
	if pct != _last_battery_pct:
		_last_battery_pct = pct
		_battery_label.text = "电量 %d%%" % pct
		_battery_label.add_theme_color_override("font_color",
			Palette.RED if pct < int(BATTERY_LOW * 100.0) else Palette.TEXT_DIM)
		# The battery bar is the only thing the cluster draws, so it is redrawn only when it changes.
		queue_redraw()


## The battery bar: a dark track with a 1 px border, so it reads over a bright background.
func _draw() -> void:
	if not _battery_shown:
		return
	draw_rect(BATTERY_RECT.grow(1.0), Color(0.02, 0.024, 0.059, 0.8))
	draw_rect(BATTERY_RECT, Color(1, 1, 1, 0.12))
	var b := float(_last_battery_pct) / 100.0
	var col := Palette.CYAN
	if b < BATTERY_LOW:
		col = Palette.RED
	elif b < BATTERY_MID:
		col = Palette.AMBER
	draw_rect(Rect2(BATTERY_RECT.position, Vector2(BATTERY_RECT.size.x * b, BATTERY_RECT.size.y)),
		col)


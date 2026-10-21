extends Control
## A 270° telemetry gauge (Roadster reveal livestream, dossier §6.4): a thin ring open at the bottom
## (gap from 4:30 to 7:30), the filled part white, the remainder dim grey, short inward end ticks,
## a wide tracked label, a big upright techno value (Oxanium's own slashed zero) and a unit.
##
## The gauge is split in two layers: the static one (the rest ring, the end ticks, the label, the
## unit) is redrawn only when the label changes, the dynamic one (the value arc and the value) when
## the value changes.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

const START_DEG := 135.0
const SWEEP_DEG := 270.0
const RING_RADIUS := 75.0
const RING_WIDTH := 2.5
const VALUE_SIZE := 42
const LABEL_SIZE := 14
const UNIT_SIZE := 12
const LABEL_TRACKING := 3.0
## The two end ticks of the ring, as a fraction of the sweep.
const END_TICK_ANGLES: Array[float] = [0.0, 1.0]
## The dark backing that makes the gauge readable over a white or a saturated magenta scene.
const BACKING_RADIUS := 92.0
const DISC_RADIUS := 70.0
const DISC_COLOR := Color(0.020, 0.027, 0.051, 0.45)
## The outline of the text and the under-stroke of the arcs.
const STROKE_COLOR := Color(0.020, 0.024, 0.059, 0.9)
const ARC_STROKE_COLOR := Color(0.020, 0.024, 0.059, 0.6)

var value: float = 0.0
var fill: float = 0.0
var caption: String = ""
var unit: String = ""
var decimals: int = 0

var _static: Control
var _dynamic: Control
var _text: String = ""
## The measured width of the value, so the draw does not measure the font.
var _text_width: float = 0.0
## The pre-measured x offset of every letter of the caption.
var _letter_offsets: PackedFloat32Array = PackedFloat32Array()
var _last_value: float = -1.0
var _last_fill: float = -1.0
var _last_caption: String = ""
var _last_unit: String = ""
var _last_decimals: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(156, 156)
	_static = Control.new()
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static.draw.connect(_draw_static)
	add_child(_static)
	_dynamic = Control.new()
	_dynamic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dynamic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dynamic.draw.connect(_draw_dynamic)
	add_child(_dynamic)
	resized.connect(_on_resized)


func _on_resized() -> void:
	_static.queue_redraw()


## display_value: the number to print. fill_fraction: 0..1 of the ring. caption: wide-tracked
## label. unit_text: "KG" / "DEG" / "M". decimals: 0 or 1.
func set_values(display_value: float, fill_fraction: float, caption_text: String,
		unit_text: String, decimal_count: int) -> void:
	var f := clampf(fill_fraction, 0.0, 1.0)
	if is_equal_approx(display_value, _last_value) and is_equal_approx(f, _last_fill) \
			and caption_text == _last_caption and unit_text == _last_unit \
			and decimal_count == _last_decimals:
		return
	var caption_changed := caption_text != _last_caption
	_last_value = display_value
	_last_fill = f
	_last_caption = caption_text
	_last_unit = unit_text
	_last_decimals = decimal_count
	value = display_value
	fill = f
	caption = caption_text
	unit = unit_text
	decimals = decimal_count
	var new_text := _format(display_value)
	if new_text != _text:
		_text = new_text
		# The width is measured once, not in the draw.
		_text_width = UI.Fonts.techno().get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			VALUE_SIZE).x
	if caption_changed:
		_measure_caption()
		_static.queue_redraw()
	_dynamic.queue_redraw()


## Pre-measure the letters of the caption so the draw does not measure the font.
func _measure_caption() -> void:
	_letter_offsets = PackedFloat32Array()
	var font := UI.Fonts.techno()
	var x := 0.0
	for i in caption.length():
		_letter_offsets.append(x)
		x += font.get_string_size(caption[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x + LABEL_TRACKING


## Everything that does not change with the value.
func _draw_static() -> void:
	var centre := _static.size * 0.5
	var r := RING_RADIUS
	if r <= 4.0:
		return
	_draw_backing(centre)
	var start := deg_to_rad(START_DEG)
	var full := deg_to_rad(SWEEP_DEG)
	# The dark under-stroke under the rest ring, so the ring reads over a bright scene.
	_static.draw_arc(centre, r, start, start + full, 48, ARC_STROKE_COLOR, RING_WIDTH + 2.0, true)
	_static.draw_arc(centre, r, start, start + full, 48, Palette.GAUGE_REST, RING_WIDTH, true)
	# Short ticks that point inward.
	for a in END_TICK_ANGLES:
		var ang := start + full * a
		var dir := Vector2(cos(ang), sin(ang))
		_static.draw_line(centre + dir * (r - 8.0), centre + dir * r, Palette.GAUGE_VALUE, 2.0, true)
	if not unit.is_empty():
		var font := UI.Fonts.techno()
		var us := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_SIZE)
		var pos := centre + Vector2(-us.x * 0.5, 30.0)
		_static.draw_string_outline(font, pos, unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_SIZE, 3,
			STROKE_COLOR)
		_static.draw_string(font, pos, unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_SIZE,
			Color(1, 1, 1, 0.65))
	_draw_caption(centre)


## The dark backing of the gauge: a soft vignette plus a solid disc, so the value and the label
## keep their contrast over a white or a saturated magenta scene.
func _draw_backing(centre: Vector2) -> void:
	_static.draw_texture_rect(UI.backing_texture(), Rect2(centre - Vector2(BACKING_RADIUS,
		BACKING_RADIUS), Vector2(BACKING_RADIUS * 2.0, BACKING_RADIUS * 2.0)), false)
	_static.draw_circle(centre, DISC_RADIUS, DISC_COLOR)


## The wide tracked label, drawn from the pre-measured offsets.
func _draw_caption(centre: Vector2) -> void:
	if caption.is_empty() or _letter_offsets.is_empty():
		return
	var font := UI.Fonts.techno()
	var total := _letter_offsets[_letter_offsets.size() - 1] - LABEL_TRACKING
	var x := centre.x - total * 0.5
	for i in caption.length():
		var pos := Vector2(x + _letter_offsets[i], centre.y - 32.0)
		_static.draw_string_outline(font, pos, caption[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_SIZE, 3, STROKE_COLOR)
		_static.draw_string(font, pos, caption[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			Color(1, 1, 1, 0.8))


## The value arc and the value.
func _draw_dynamic() -> void:
	var centre := _dynamic.size * 0.5
	var r := RING_RADIUS
	if r <= 4.0:
		return
	var start := deg_to_rad(START_DEG)
	var full := deg_to_rad(SWEEP_DEG)
	if fill > 0.002:
		# The dark under-stroke under the lit arc.
		_dynamic.draw_arc(centre, r, start, start + full * fill, 32, ARC_STROKE_COLOR,
			RING_WIDTH + 2.0, true)
		_dynamic.draw_arc(centre, r, start, start + full * fill, 32, Palette.GAUGE_VALUE,
			RING_WIDTH, true)
	var font := UI.Fonts.techno()
	var pos := centre + Vector2(-_text_width * 0.5, 10.0)
	_dynamic.draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE, 4,
		STROKE_COLOR)
	_dynamic.draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE,
		Palette.GAUGE_VALUE)


func _format(v: float) -> String:
	if decimals <= 0:
		return str(int(round(v)))
	return String.num(v, decimals)

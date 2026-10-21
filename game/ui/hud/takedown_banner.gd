extends Control
## Takedown banner (dossier §3.5): an amber skewed parallelogram with black text. It pops large in
## the centre at 160 % and shrinks into the top-left corner within 0.25 s.
## The whole timeline runs in REAL time (the takedown cam uses slow motion).
##
## The banner is laid out once (the font metrics are measured when it is shown) and then drawn in
## a fixed local space that is scaled as a whole, so no font is ever rasterised at a new size.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

const SKEW_DEG := 12.0    ## leans to the right (CSS skewX(-12°)); the bottom edge shifts left.
const MAIN_SIZE := 64
const SUB_SIZE := 36
const TEXT_GAP := 6.0
## The gap between the visible glyph boxes of the two lines.
const INK_GAP := 24.0
## The visible glyph box of a CJK ideograph, in em above / below the baseline.
const INK_ABOVE := 0.88
const INK_BELOW := 0.10
## The banner pops in at 160 % and settles at 100 %.
const POP_SCALE := 1.6
## The x the docked banner sits at (dossier §8.3: the top-left corner).
const DOCK_X := 60.0
const PAD_X := 32.0
const PAD_Y := 16.0
const HOLD := 2.2
const FADE := 0.30
const DOCK_TIME := 0.25
const POP_TIME := 0.10
const DOCK_Y := 340.0
## The plate's finish.
const PLATE_TOP := Color("ffc233")
const PLATE_BOTTOM := Color("ffa000")
const PLATE_HIGHLIGHT := Color("ffe08a")
const PLATE_SHADOW := Color(0, 0, 0, 0.35)
const HAZARD_COLOR := Color(0.039, 0.039, 0.039, 0.18)
const HAZARD_WIDTH := 48.0
const HAZARD_PITCH := 10.0
const TEXT_COLOR := Color(0.04, 0.04, 0.04, 1.0)

var _main: String = ""
var _en: String = ""
var _sub: String = ""
var _dock: float = 0.0
var _pop: float = 0.0
var _alpha: float = 0.0
var _active: bool = false
var _dock_y: float = DOCK_Y
var _tween: Tween
## The measured layout, computed when the banner is shown.
var _width: float = 0.0
var _height: float = 0.0
var _main_width: float = 0.0
var _latin_width: float = 0.0
var _sub_width: float = 0.0
var _main_baseline: float = 0.0
var _sub_baseline: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## zh: the Chinese line; en: the English line; sub: optional sub-line ("2-in-a-row", "RAMPAGE");
## dock_y: the y the banner docks to.
func show_banner(zh: String, en: String, sub: String = "", dock_y: float = DOCK_Y) -> void:
	_main = zh
	_en = en
	_sub = sub
	_dock_y = dock_y
	_active = true
	visible = true
	_set_pop(0.0)
	_set_dock(0.0)
	_set_alpha(1.0)
	_measure()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.set_parallel(false)
	_tween.tween_method(_set_pop, 0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_dock, 0.0, 1.0, DOCK_TIME).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD)
	_tween.tween_method(_set_alpha, 1.0, 0.0, FADE)
	_tween.tween_callback(_hide)


## Lay the banner out from the VISIBLE glyph box, not from the font's ascent: a CJK ideograph sits
## from 0.88 em above the baseline to 0.10 em below it. The padding above and below the text is
## therefore the same, whatever the font's line height is.
func _measure() -> void:
	var cjk_font := UI.Fonts.text_black()
	var latin_font := UI.Fonts.display()
	_main_width = cjk_font.get_string_size(_main, HORIZONTAL_ALIGNMENT_LEFT, -1, MAIN_SIZE).x
	_latin_width = 0.0
	if not _en.is_empty():
		_latin_width = latin_font.get_string_size(_en, HORIZONTAL_ALIGNMENT_LEFT, -1, MAIN_SIZE).x
	_sub_width = 0.0
	if not _sub.is_empty():
		_sub_width = cjk_font.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_SIZE).x
	var main_above := INK_ABOVE * MAIN_SIZE
	var main_below := INK_BELOW * MAIN_SIZE
	_main_baseline = PAD_Y + main_above
	var height := PAD_Y + main_above + main_below
	if not _sub.is_empty():
		_sub_baseline = _main_baseline + main_below + INK_GAP + INK_ABOVE * SUB_SIZE
		height = _sub_baseline + INK_BELOW * SUB_SIZE + PAD_Y
	_height = height
	var text_w := _main_width + (TEXT_GAP + _latin_width if not _en.is_empty() else 0.0)
	_width = maxf(text_w, _sub_width) + PAD_X * 2.0


func _set_pop(value: float) -> void:
	_pop = value
	queue_redraw()


func _set_dock(value: float) -> void:
	_dock = value
	queue_redraw()


func _set_alpha(value: float) -> void:
	_alpha = value
	queue_redraw()


func _hide() -> void:
	_active = false
	visible = false


func _draw() -> void:
	if not _active or _main.is_empty():
		return
	var s := lerpf(POP_SCALE, 1.0, _pop)
	# The centre of the screen at the start, the top-left corner at the end.
	var centre := (size * 0.5).lerp(Vector2(DOCK_X + _width * 0.5, _dock_y + _height * 0.5), _dock)
	var origin := centre - Vector2(_width, _height) * 0.5 * s
	draw_set_transform(origin, 0.0, Vector2(s, s))
	_draw_plate()
	_draw_text()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The amber plate: a gradient, a top highlight, hazard stripes on the right and a drop shadow.
func _draw_plate() -> void:
	var skew := tan(deg_to_rad(SKEW_DEG)) * _height
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(_width, 0), Vector2(_width - skew, _height), Vector2(-skew, _height)])
	# The drop shadow.
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 6.0))
	draw_colored_polygon(shadow, Color(PLATE_SHADOW.r, PLATE_SHADOW.g, PLATE_SHADOW.b,
		PLATE_SHADOW.a * _alpha))
	# The gradient plate.
	draw_polygon(pts, PackedColorArray([
		Color(PLATE_TOP.r, PLATE_TOP.g, PLATE_TOP.b, _alpha),
		Color(PLATE_TOP.r, PLATE_TOP.g, PLATE_TOP.b, _alpha),
		Color(PLATE_BOTTOM.r, PLATE_BOTTOM.g, PLATE_BOTTOM.b, _alpha),
		Color(PLATE_BOTTOM.r, PLATE_BOTTOM.g, PLATE_BOTTOM.b, _alpha)]))
	# The top highlight.
	draw_line(Vector2(0, 1.0), Vector2(_width, 1.0),
		Color(PLATE_HIGHLIGHT.r, PLATE_HIGHLIGHT.g, PLATE_HIGHLIGHT.b, _alpha), 2.0, true)
	# 45 degree hazard stripes on the right 48 px.
	var x := _width - HAZARD_WIDTH
	while x < _width + _height:
		draw_line(Vector2(x, 0.0), Vector2(x - _height, _height),
			Color(HAZARD_COLOR.r, HAZARD_COLOR.g, HAZARD_COLOR.b, HAZARD_COLOR.a * _alpha), 6.0, true)
		x += HAZARD_PITCH
	# The outline.
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(0, 0, 0, 0.30 * _alpha), 2.0, true)


## The Chinese line, the English line and the sub-line.
func _draw_text() -> void:
	var cjk_font := UI.Fonts.text_black()
	var latin_font := UI.Fonts.display()
	var text_w := _main_width + (TEXT_GAP + _latin_width if not _en.is_empty() else 0.0)
	var x := (_width - text_w) * 0.5
	draw_string(cjk_font, Vector2(x, _main_baseline), _main, HORIZONTAL_ALIGNMENT_LEFT, -1, MAIN_SIZE,
		Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, _alpha))
	if not _en.is_empty():
		draw_string(latin_font, Vector2(x + _main_width + TEXT_GAP, _main_baseline), _en,
			HORIZONTAL_ALIGNMENT_LEFT, -1, MAIN_SIZE,
			Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, _alpha))
	if not _sub.is_empty():
		var sub_x := (_width - _sub_width) * 0.5
		draw_string_outline(cjk_font, Vector2(sub_x, _sub_baseline), _sub, HORIZONTAL_ALIGNMENT_LEFT,
			-1, SUB_SIZE, 3, Color(0, 0, 0, _alpha))
		draw_string(cjk_font, Vector2(sub_x, _sub_baseline), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1,
			SUB_SIZE, Color(1, 1, 1, _alpha))

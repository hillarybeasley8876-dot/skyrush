extends Control
## Speedometer dial: a 240° arc (7 o'clock → 3 o'clock) with a tick ladder, a cyan→magenta value
## gradient, a red over-speed band, a value tip with a comet trail, a QQ-style dial face and a
## motor-load ring outside the numbers.
##
## The dial is split in two layers: the static one (face, bezel, ticks, labels, red band) is only
## redrawn when the size changes, the dynamic one (value arc, tip, trail, load ring) when the value
## changes. The value arc is ONE polyline with a per-vertex colour, so a redraw is a handful of
## draw calls and no allocation.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

const START_DEG := 120.0   ## 7 o'clock, measured clockwise from 3 o'clock.
const SWEEP_DEG := 240.0
const MAX_KMH := 330.0
const RADIUS := 100.0
const MAJOR_STEP := 50.0
const MINOR_STEP := 10.0
const MICRO_STEP := 2.0
const RED_FROM_KMH := 300.0
## The radius of the label anchors. The label box (at most 26 x 12 px) then stays between the
## major tick ends (r 106) and the motor ring (r 138) at every angle of the sweep.
const LABEL_RADIUS := 121.0
const LABEL_SIZE := 16
## The height of the visible digits of a label: the anchor is the centre of that box.
const LABEL_INK_HEIGHT := 12.0
const MOTOR_RADIUS := 138.0
const BEZEL_RADIUS := 145.0
## The value arc is one polyline of ARC_POINTS points with a colour per point.
const ARC_POINTS := 33
const TRAIL_POINTS := 8
const TRAIL_DEG := 18.0
## The bezel is lit from the upper left and dark at the lower right (Godot screen angles).
const BEZEL_LIT_DEG := 225.0
const BEZEL_POINTS := 64
const BEZEL_LIT := Color("6a7aa0")
const BEZEL_DARK := Color("141b2b")
## The 1 px specular arc on the bezel.
const SPECULAR_FROM := 200.0
const SPECULAR_TO := 250.0
const GLOSS_FROM := 200.0
const GLOSS_TO := 290.0

var speed_kmh: float = 0.0
var motor_load: float = 0.0
var boosting: bool = false

var _static: Control
var _dynamic: Control
var _last_speed: float = -1.0
var _last_load: float = -1.0
var _last_boost: bool = false
## The value arc, the glow under it and the comet trail: refilled, never reallocated.
var _arc_pts: PackedVector2Array = PackedVector2Array()
var _arc_cols: PackedColorArray = PackedColorArray()
var _glow_pts: PackedVector2Array = PackedVector2Array()
var _glow_cols: PackedColorArray = PackedColorArray()
var _trail_pts: PackedVector2Array = PackedVector2Array()
var _trail_cols: PackedColorArray = PackedColorArray()
## The measured label boxes, so the static draw does not measure the font.
var _label_anchor: PackedVector2Array = PackedVector2Array()
var _label_width: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 300)
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
	_on_resized()


func _on_resized() -> void:
	_measure_labels()
	_static.queue_redraw()


func set_values(speed: float, load: float, is_boosting: bool) -> void:
	speed_kmh = speed
	motor_load = load
	boosting = is_boosting
	if not is_equal_approx(speed, _last_speed) or not is_equal_approx(load, _last_load) \
			or is_boosting != _last_boost:
		_last_speed = speed
		_last_load = load
		_last_boost = is_boosting
		_dynamic.queue_redraw()


## The boxes of the major tick labels, in the dial's own space. The test uses them to prove that
## no label touches the tick ladder or the motor ring.
func label_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in _label_anchor.size():
		var w := _label_width[i]
		out.append(Rect2(_label_anchor[i] - Vector2(w * 0.5, LABEL_INK_HEIGHT * 0.5),
			Vector2(w, LABEL_INK_HEIGHT)))
	return out


## Measure the major tick labels once: the anchor (the centre of the digit box) and its width.
func _measure_labels() -> void:
	_label_anchor = PackedVector2Array()
	_label_width = PackedFloat32Array()
	var font := UI.Fonts.display()
	var centre := size * 0.5
	var start := deg_to_rad(START_DEG)
	var full := deg_to_rad(SWEEP_DEG)
	var value := 0.0
	while value < MAX_KMH:
		if is_equal_approx(fmod(value, MAJOR_STEP), 0.0):
			var a := start + full * (value / MAX_KMH)
			var dir := Vector2(cos(a), sin(a))
			var label := str(int(value))
			_label_anchor.append(centre + dir * LABEL_RADIUS)
			_label_width.append(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				LABEL_SIZE).x)
		value += MICRO_STEP


## Everything that does not change with the speed.
func _draw_static() -> void:
	var centre := size * 0.5
	# The soft backing and the dial face (a solid disc with the sunburst face on top, so the
	# texture never shows its square).
	_draw_backing(centre, BEZEL_RADIUS + 6.0)
	_static.draw_circle(centre, 92.0, Color(0.020, 0.027, 0.051, 0.92))
	_draw_backing(centre, 92.0, UI.dial_face_texture())
	_draw_bezel(centre)
	# The glossy highlight at the upper left.
	_draw_gloss(centre)
	# The track and the over-speed band.
	var start := deg_to_rad(START_DEG)
	var full := deg_to_rad(SWEEP_DEG)
	_static.draw_arc(centre, RADIUS, start, start + full, 48, Color(1, 1, 1, 0.14), 9.0, true)
	var red_from := start + full * (RED_FROM_KMH / MAX_KMH)
	_static.draw_arc(centre, RADIUS, red_from, start + full, 12,
		Color(Palette.RED.r, Palette.RED.g, Palette.RED.b, 0.75), 9.0, true)
	_draw_ticks(centre, start, full)
	_draw_labels(centre)


## A soft radial vignette under the dial (one smooth gradient, not stacked circles).
func _draw_backing(centre: Vector2, radius: float, texture: Texture2D = null) -> void:
	var tex := texture if texture != null else UI.backing_texture()
	_static.draw_texture_rect(tex, Rect2(centre - Vector2(radius, radius),
		Vector2(radius * 2.0, radius * 2.0)), false)


## The lit bezel: one polyline with a conic ramp (lit at the upper left, dark at the lower right)
## and a 1 px specular arc over it.
func _draw_bezel(centre: Vector2) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var lit := deg_to_rad(BEZEL_LIT_DEG)
	for i in BEZEL_POINTS + 1:
		var a := TAU * float(i) / float(BEZEL_POINTS)
		pts.append(centre + Vector2(cos(a), sin(a)) * BEZEL_RADIUS)
		# t = 0 at the lit angle, 1 at the opposite side.
		var t := 0.5 - 0.5 * cos(a - lit)
		cols.append(BEZEL_LIT.lerp(BEZEL_DARK, t))
	_static.draw_polyline_colors(pts, cols, 4.0, true)
	# A darker inner line, so the bezel reads as a ring with a lit edge.
	_static.draw_arc(centre, BEZEL_RADIUS - 4.0, 0.0, TAU, 64,
		Color(0.020, 0.027, 0.051, 0.9), 2.0, true)
	# The specular arc at the upper left.
	_static.draw_arc(centre, BEZEL_RADIUS - 1.0, deg_to_rad(SPECULAR_FROM),
		deg_to_rad(SPECULAR_TO), 24, Color(1, 1, 1, 0.25), 1.0, true)


## The glossy highlight arc at the upper left of the dial face.
func _draw_gloss(centre: Vector2) -> void:
	for i in 3:
		var t0 := float(i) / 3.0
		var a0 := deg_to_rad(lerpf(GLOSS_FROM, GLOSS_TO, t0))
		var a1 := deg_to_rad(lerpf(GLOSS_FROM, GLOSS_TO, t0 + 0.34))
		_static.draw_arc(centre, 88.0, a0, a1, 16, Color(1, 1, 1, 0.10 - 0.03 * t0), 10.0, true)


## The tick ladder: majors every 50 km/h, minors every 10, micros every 2.
func _draw_ticks(centre: Vector2, start: float, full: float) -> void:
	var value := 0.0
	while value <= MAX_KMH:
		var t := value / MAX_KMH
		var a := start + full * t
		var major := is_equal_approx(fmod(value, MAJOR_STEP), 0.0)
		var minor := is_equal_approx(fmod(value, MINOR_STEP), 0.0)
		var dir := Vector2(cos(a), sin(a))
		var col := Color(1, 1, 1, 0.75) if major else (Color(1, 1, 1, 0.30) if minor else Color(1, 1, 1, 0.12))
		var r0 := RADIUS - (14.0 if major else (8.0 if minor else 6.0))
		var r1 := RADIUS + 6.0 if (major or minor) else RADIUS
		var width := 2.0 if major else (1.0 if minor else 0.75)
		_static.draw_line(centre + dir * r0, centre + dir * r1, col, width, true)
		value += MICRO_STEP


## The major tick labels, centred on their anchor (the middle of the digit box).
func _draw_labels(centre: Vector2) -> void:
	var font := UI.Fonts.display()
	for i in _label_anchor.size():
		var label := str(int(i) * int(MAJOR_STEP))
		var anchor := _label_anchor[i]
		var pos := Vector2(anchor.x - _label_width[i] * 0.5, anchor.y - LABEL_INK_HEIGHT * 0.5)
		_static.draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, 48, LABEL_SIZE, 3,
			Color(0.02, 0.024, 0.059, 0.9))
		_static.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, 48, LABEL_SIZE,
			Color(1, 1, 1, 0.85))


## The value arc, the comet trail, the tip and the motor-load ring.
func _draw_dynamic() -> void:
	var centre := size * 0.5
	var frac := clampf(speed_kmh / MAX_KMH, 0.0, 1.0)
	var start := deg_to_rad(START_DEG)
	var full := deg_to_rad(SWEEP_DEG)
	if frac > 0.001:
		_fill_arc(centre, start, full, frac)
		_fill_trail(centre, start, full, frac)
		_draw_value_tip(centre, start + full * frac)
	_draw_motor_ring(centre, start, full)


## The value arc and the glow under it: one polyline each, with a colour per vertex.
func _fill_arc(centre: Vector2, start: float, full: float, frac: float) -> void:
	_arc_pts.resize(ARC_POINTS)
	_arc_cols.resize(ARC_POINTS)
	_glow_pts.resize(ARC_POINTS)
	_glow_cols.resize(ARC_POINTS)
	for i in ARC_POINTS:
		var t := frac * float(i) / float(ARC_POINTS - 1)
		var a := start + full * t
		var p := centre + Vector2(cos(a), sin(a)) * RADIUS
		var col := Palette.speed_ramp(t)
		if boosting:
			col = col.lerp(Palette.MAGENTA, 0.35)
		_arc_pts[i] = p
		_arc_cols[i] = col
		_glow_pts[i] = p
		_glow_cols[i] = Color(col.r, col.g, col.b, 0.18)
	_dynamic.draw_polyline_colors(_glow_pts, _glow_cols, 16.0, true)
	_dynamic.draw_polyline_colors(_arc_pts, _arc_cols, 9.0, true)


## The comet trail behind the tip: one polyline, the alpha fading towards the tail.
func _fill_trail(centre: Vector2, start: float, full: float, frac: float) -> void:
	_trail_pts.resize(TRAIL_POINTS)
	_trail_cols.resize(TRAIL_POINTS)
	var span := deg_to_rad(TRAIL_DEG) * frac
	for i in TRAIL_POINTS:
		var t0 := float(i) / float(TRAIL_POINTS - 1)
		var a := start + full * maxf(frac - span * (1.0 - t0), 0.0)
		_trail_pts[i] = centre + Vector2(cos(a), sin(a)) * RADIUS
		var col := Palette.speed_ramp(clampf(frac - (1.0 - t0) * 0.08, 0.0, 1.0))
		_trail_cols[i] = Color(col.r, col.g, col.b, 0.45 * t0)
	_dynamic.draw_polyline_colors(_trail_pts, _trail_cols, 9.0, true)


## The tip of the value arc: a white dot with a cyan glow.
func _draw_value_tip(centre: Vector2, angle: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	_dynamic.draw_circle(centre + dir * RADIUS, 12.0,
		Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.35))
	_dynamic.draw_circle(centre + dir * RADIUS, 3.0, Palette.WHITE)


## The motor-load ring: outside the labels (r 138) and inside the bezel (r 145).
func _draw_motor_ring(centre: Vector2, start: float, full: float) -> void:
	_dynamic.draw_arc(centre, MOTOR_RADIUS, start, start + full, 40, Color(1, 1, 1, 0.08), 2.0, true)
	var load := clampf(motor_load, 0.0, 1.0)
	if load > 0.005:
		var col := Color(Palette.AMBER.r, Palette.AMBER.g, Palette.AMBER.b, 0.75)
		_dynamic.draw_arc(centre, MOTOR_RADIUS, start, start + full * load, 20, col, 2.0, true)

extends Control
## Five police-light pips showing the heat level 1..5. Lit pips alternate red / blue at 2 Hz
## (dossier §3.2 police flash), unlit pips keep a dim red outline.
##
## The lens is a rounded polygon with a per-vertex gradient (the lit colour at the top, 70 % of it
## at the bottom), a 1 px highlight along the top and a soft three step glow.
##
## The blink is driven by a timer, not by the draw call: without it the pips would freeze on the
## first frame (the level rarely changes).

const Palette := preload("res://ui/theme/skyrush_palette.gd")

const BLINK_PERIOD := 0.25   ## 2 Hz
const PIPS := 5
const CORNER := 3
## The three glow steps: the rect is grown by 2, 4 and 6 px.
const GLOW_GROW: Array[float] = [2.0, 4.0, 6.0]
const GLOW_ALPHA: Array[float] = [0.10, 0.06, 0.03]
const ARC_SEGMENTS := 4

var level: int = 0
## The rounded lens of every pip and its two colour ramps (red and blue), built once: a redraw
## allocates nothing.
var _lenses: Array[PackedVector2Array] = []
var _lens_cols_red: Array[PackedColorArray] = []
var _lens_cols_blue: Array[PackedColorArray] = []
var _last: int = -1
var _phase: bool = false
var _accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 20)
	set_process(true)
	resized.connect(_build_lenses)
	_build_lenses()


## Build the rounded lens of every pip (they only change when the panel is resized).
func _build_lenses() -> void:
	_lenses = []
	_lens_cols_red = []
	_lens_cols_blue = []
	if size.x <= 0.0:
		return
	var gap := 6.0
	var w := (size.x - gap * float(PIPS - 1)) / float(PIPS)
	for i in PIPS:
		var rect := Rect2(Vector2(float(i) * (w + gap), 0.0), Vector2(w, size.y))
		var pts := _rounded_rect(rect, CORNER)
		_lenses.append(pts)
		_lens_cols_red.append(_ramp(pts, rect, Palette.RED))
		_lens_cols_blue.append(_ramp(pts, rect, Palette.POLICE_BLUE))


## The vertical colour ramp of a lens: the lit colour at the top, 70 % of it at the bottom.
static func _ramp(pts: PackedVector2Array, rect: Rect2, col: Color) -> PackedColorArray:
	var bottom := Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 1.0)
	var colors := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
		colors.append(col.lerp(bottom, t))
	return colors


func set_level(value: int) -> void:
	var v := clampi(value, 0, PIPS)
	if v == _last:
		return
	_last = v
	level = v
	queue_redraw()


## Flip the blink phase twice a second while there is heat to show.
func _process(delta: float) -> void:
	if level <= 0:
		return
	_accum += delta
	if _accum >= BLINK_PERIOD:
		_accum -= BLINK_PERIOD
		_phase = not _phase
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0:
		return
	var gap := 6.0
	var w := (size.x - gap * float(PIPS - 1)) / float(PIPS)
	var h := size.y
	for i in PIPS:
		var r := Rect2(Vector2(float(i) * (w + gap), 0.0), Vector2(w, h))
		if i < level:
			var col := Palette.RED if ((i + (0 if _phase else 1)) % 2 == 0) else Palette.POLICE_BLUE
			_draw_glow(r, col)
			_draw_lens(r, col, i)
		else:
			draw_rect(r, Color(1, 1, 1, 0.06))
			draw_rect(r, Color(Palette.RED.r, Palette.RED.g, Palette.RED.b, 0.25), false, 1.0)


## The soft glow: three rects, grown further and fainter every step.
func _draw_glow(r: Rect2, col: Color) -> void:
	for i in GLOW_GROW.size():
		draw_rect(r.grow(GLOW_GROW[i]), Color(col.r, col.g, col.b, GLOW_ALPHA[i]))


## The lens: a rounded polygon with a vertical gradient and a highlight along the top.
func _draw_lens(r: Rect2, col: Color, index: int) -> void:
	if index >= _lenses.size() or index >= _lens_cols_red.size():
		return
	var colors := _lens_cols_red[index] if col == Palette.RED else _lens_cols_blue[index]
	draw_polygon(_lenses[index], colors)
	# The 1 px highlight along the top edge.
	var hi := col.lightened(0.6)
	hi.a = 0.8
	draw_line(Vector2(r.position.x + CORNER, r.position.y + 0.5),
		Vector2(r.end.x - CORNER, r.position.y + 0.5), hi, 1.0, true)


## The rounded rectangle as a polygon (clockwise in screen space).
static func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var tl := rect.position + Vector2(r, r)
	var br := rect.end - Vector2(r, r)
	var corners: Array[Vector3] = [
		Vector3(tl.x, tl.y, PI),
		Vector3(br.x, tl.y, PI * 1.5),
		Vector3(br.x, br.y, 0.0),
		Vector3(tl.x, br.y, PI * 0.5),
	]
	var pts := PackedVector2Array()
	for c in corners:
		var centre := Vector2(c.x, c.y)
		for i in ARC_SEGMENTS + 1:
			var a := c.z + (PI * 0.5) * float(i) / float(ARC_SEGMENTS)
			pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts

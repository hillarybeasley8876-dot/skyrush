extends Control
## SKYRUSH glass panel: chamfered top corners, a vertical gradient, a tileable glass texture
## (scanlines, grain, a dot grid), an inner edge glow, an outer soft shadow, cyan L-brackets on
## the two square corners and an optional header (the panel's English sub-label: RACE / TIME / MAP
## / PURSUIT) on a filled chamfered tab.
## The base class of every HUD panel.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

const FILL_TOP := Color(0.043, 0.059, 0.102, 0.80)
const FILL_BOTTOM := Color(0.043, 0.059, 0.102, 0.62)
const EDGE_COLOR := Color(0.0, 0.898, 1.0, 0.55)
const INNER_GLOW := Color(0.0, 0.898, 1.0, 0.18)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const BRACKET_COLOR := Color(0.0, 0.898, 1.0, 0.9)
const BRACKET_LEN := 10.0
const BRACKET_WIDTH := 2.0
const HEADER_SIZE := 14
const HEADER_TRACKING := 3.0
const HEADER_TAB := Color(0.0, 0.898, 1.0, 0.10)
const HEADER_HEIGHT := 20.0
## The soft shadow: three stacked copies of the panel, offset further and fainter every step.
const SHADOW_OFFSETS: Array[float] = [2.0, 4.0, 8.0]
const SHADOW_ALPHAS: Array[float] = [0.18, 0.12, 0.06]
## The glass texture is a 128 px tile.
const GLASS_TILE := 128.0
## The two square (bottom) corners of the panel.
const BRACKET_CORNERS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]

@export var cut: float = 14.0
@export var fill_top: Color = FILL_TOP
@export var fill_bottom: Color = FILL_BOTTOM
@export var edge: Color = EDGE_COLOR
@export var edge_width: float = 1.0
## English sub-label drawn in the panel's header tab ("" = none).
@export var header: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var c := minf(cut, minf(w, h) * 0.5)
	# The top corners are chamfered, the bottom two stay square (they carry the brackets).
	var top := PackedVector2Array([
		Vector2(c, 0.0), Vector2(w - c, 0.0), Vector2(w, c), Vector2(w, h),
		Vector2(0.0, h), Vector2(0.0, c)])
	_draw_shadow(top)
	_draw_gradient(top)
	_draw_glass(top)
	_draw_inner_glow(top)
	if edge_width > 0.0:
		var closed := top.duplicate()
		closed.append(top[0])
		draw_polyline(closed, edge, edge_width, true)
	draw_line(Vector2(c, 1.0), Vector2(w - c, 1.0),
		Color(edge.r, edge.g, edge.b, edge.a * 0.35), 1.0, true)
	_draw_brackets(w, h)
	_draw_header(w, c)


## A soft shadow behind the panel: three copies, offset further and fainter every step.
func _draw_shadow(poly: PackedVector2Array) -> void:
	for i in SHADOW_OFFSETS.size():
		var shadow := PackedVector2Array()
		for p in poly:
			shadow.append(p + Vector2(0, SHADOW_OFFSETS[i]))
		draw_colored_polygon(shadow, Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b,
			SHADOW_COLOR.a * SHADOW_ALPHAS[i]))


## The panel fill: a vertical gradient (per-vertex colours, interpolated by the renderer).
func _draw_gradient(poly: PackedVector2Array) -> void:
	var colors := PackedColorArray()
	for p in poly:
		var t := clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0)
		colors.append(fill_top.lerp(fill_bottom, t))
	draw_polygon(poly, colors)


## The tileable glass texture over the panel body. It is drawn as a polygon, so it does not spill
## into the chamfered corners.
func _draw_glass(poly: PackedVector2Array) -> void:
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for p in poly:
		uvs.append(p / GLASS_TILE)
		colors.append(Color.WHITE)
	draw_polygon(poly, colors, uvs, UI.glass_texture())


## A 2 px cyan glow just inside the edge.
func _draw_inner_glow(poly: PackedVector2Array) -> void:
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(p + Vector2(0, 2.0) * (1.0 if p.y < size.y * 0.5 else -1.0))
	var closed_inner := inner.duplicate()
	closed_inner.append(inner[0])
	draw_polyline(closed_inner, INNER_GLOW, 2.0, true)


## Cyan L-brackets on the two square (bottom) corners.
func _draw_brackets(w: float, h: float) -> void:
	for corner in BRACKET_CORNERS:
		var c := Vector2(corner.x * w, h)
		var sx := 1.0 if c.x < w * 0.5 else -1.0
		draw_line(c, c + Vector2(BRACKET_LEN * sx, 0.0), BRACKET_COLOR, BRACKET_WIDTH, true)
		draw_line(c, c + Vector2(0.0, -BRACKET_LEN), BRACKET_COLOR, BRACKET_WIDTH, true)


## The English sub-label on a filled chamfered tab.
func _draw_header(w: float, c: float) -> void:
	if header.is_empty():
		return
	var tab := PackedVector2Array([
		Vector2(c, 0.0), Vector2(c + 96.0, 0.0), Vector2(c + 96.0 - 8.0, HEADER_HEIGHT),
		Vector2(c - 8.0, HEADER_HEIGHT)])
	draw_colored_polygon(tab, HEADER_TAB)
	var font := UI.Fonts.display()
	var x := c + 8.0
	var y := HEADER_HEIGHT - 6.0
	for i in header.length():
		draw_string(font, Vector2(x, y), header[i], HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_SIZE,
			Color(1, 1, 1, 0.7))
		x += font.get_string_size(header[i], HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_SIZE).x + HEADER_TRACKING

extends Control
## A key cap: the keyboard keys are rounded rectangles, the gamepad buttons are circles (A / B /
## X / Y in their Xbox colours) or pills (the shoulders, the triggers and the stick).
##
## The chips are drawn (no texture): a 6 px radius, a #1A2236 fill, a 1 px #3A4A6A border and
## #F2F6FF text. The Start button is drawn as three bars (the ☰ glyph is in none of the fonts).

const Fonts := preload("res://ui/theme/skyrush_fonts.gd")

enum Shape { KEY, ROUND, PILL, BARS }

const FILL := Color("1a2236")
const BORDER := Color("3a4a6a")
const TEXT := Color("f2f6ff")
const CORNER := 6.0
const BORDER_WIDTH := 1.0
const PAD_X := 11.0
const PAD_Y := 5.0
const FONT_SIZE := 15
## The colours of the Xbox buttons.
const BUTTON_COLOURS: Dictionary = {
	"A": Color("3bb54a"), "B": Color("e2322b"), "X": Color("2a7de1"), "Y": Color("f5c400"),
}

var text: String = ""
var shape: int = Shape.KEY

var _font: Font


func _init(caption: String = "", kind: int = Shape.KEY) -> void:
	text = caption
	shape = kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Fonts.text_bold()
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	custom_minimum_size = Vector2(width + PAD_X * 2.0, FONT_SIZE + PAD_Y * 2.0 + 8.0)


## The caption of a key (the arrows and "Esc" instead of the OS names).
static func caption_for(key: Key) -> String:
	match key:
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_ESCAPE:
			return "Esc"
		KEY_BACKSPACE:
			return "Bksp"
		KEY_SHIFT:
			return "Shift"
		KEY_CTRL:
			return "Ctrl"
		KEY_ALT:
			return "Alt"
		KEY_SPACE:
			return "Space"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
	return OS.get_keycode_string(key)


func set_caption(caption: String) -> void:
	text = caption
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	match shape:
		Shape.ROUND:
			var radius := minf(w, h) * 0.5 - 1.0
			var centre := Vector2(w * 0.5, h * 0.5)
			draw_circle(centre, radius, FILL)
			draw_arc(centre, radius, 0.0, TAU, 24, BUTTON_COLOURS.get(text, BORDER), BORDER_WIDTH + 1.0, true)
		Shape.PILL:
			var points := _rounded_rect(Rect2(0.0, 0.0, w, h), h * 0.5)
			draw_polygon(points, PackedColorArray([FILL]))
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, BORDER, BORDER_WIDTH, true)
		Shape.BARS:
			_draw_bars(w, h)
			return
		_:
			var points := _rounded_rect(Rect2(0.0, 0.0, w, h), CORNER)
			draw_polygon(points, PackedColorArray([FILL]))
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, BORDER, BORDER_WIDTH, true)
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(_font, Vector2((w - text_size.x) * 0.5, (h + text_size.y * 0.72) * 0.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)


## The Start button: three bars (the ☰ glyph is in none of the shipped fonts).
func _draw_bars(w: float, h: float) -> void:
	var points := _rounded_rect(Rect2(0.0, 0.0, w, h), CORNER)
	draw_polygon(points, PackedColorArray([FILL]))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, BORDER, BORDER_WIDTH, true)
	var bar_width := w * 0.42
	var bar_height := 2.0
	for i in 3:
		var y := h * 0.5 + (float(i) - 1.0) * 5.0
		draw_rect(Rect2((w - bar_width) * 0.5, y - bar_height * 0.5, bar_width, bar_height), TEXT)


## The points of a rounded rectangle.
func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var corners: Array = [
		[Vector2(rect.position.x + r, rect.position.y + r), PI, PI * 1.5],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5, TAU],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0, PI * 0.5],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5, PI],
	]
	for corner in corners:
		var centre: Vector2 = corner[0]
		for i in 7:
			var angle := lerpf(float(corner[1]), float(corner[2]), float(i) / 6.0)
			points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	return points

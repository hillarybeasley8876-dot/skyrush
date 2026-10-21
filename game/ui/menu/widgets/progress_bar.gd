extends Control
## A segmented progress bar with a cyan glow: the segments that are filled light up, the ones
## that are empty stay as a dim track. Used by the loading screen.

const Palette := preload("res://ui/theme/skyrush_palette.gd")

## How many segments the bar is made of.
const SEGMENTS := 32
const SEGMENT_GAP := 3.0

var _fraction: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 18)


func set_value(fraction: float) -> void:
	var clamped := clampf(fraction, 0.0, 1.0)
	if is_equal_approx(clamped, _fraction):
		return
	_fraction = clamped
	queue_redraw()


func get_value() -> float:
	return _fraction


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0:
		return
	var segment_width := (w - SEGMENT_GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	var lit := int(round(_fraction * float(SEGMENTS)))
	for i in SEGMENTS:
		var x := float(i) * (segment_width + SEGMENT_GAP)
		if i < lit:
			# The lit segment and its glow.
			draw_rect(Rect2(x - 1.0, -2.0, segment_width + 2.0, h + 4.0),
					Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.18))
			draw_rect(Rect2(x, 0.0, segment_width, h), Palette.CYAN)
			draw_rect(Rect2(x, 0.0, segment_width, 2.0), Color(1, 1, 1, 0.55))
		else:
			draw_rect(Rect2(x, h - 4.0, segment_width, 4.0), Color(1, 1, 1, 0.10))

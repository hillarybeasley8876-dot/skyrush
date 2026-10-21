extends Control
## Demo backdrop: a dark night gradient with a few deliberately bright areas (saturated magenta
## neon and a white wall) so the HUD can be judged for readability over a loud scene.

const Palette := preload("res://ui/theme/skyrush_palette.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# vertical night gradient
	var bands := 48
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := Color(0.02, 0.024, 0.06).lerp(Color(0.10, 0.06, 0.20), t)
		draw_rect(Rect2(0.0, h * float(i) / float(bands), w, h / float(bands) + 1.0), col)
	# horizon glow
	draw_rect(Rect2(0.0, h * 0.62, w, h * 0.12), Color(0.35, 0.12, 0.31, 0.35))
	# a saturated magenta neon slab (readability torture test)
	draw_rect(Rect2(w * 0.10, h * 0.18, w * 0.22, h * 0.34), Color(1.0, 0.17, 0.84, 0.85))
	draw_rect(Rect2(w * 0.10, h * 0.18, w * 0.22, h * 0.34), Color(1.0, 0.6, 0.95, 0.5), false, 6.0)
	# a white wall (bright background test)
	draw_rect(Rect2(w * 0.42, h * 0.52, w * 0.16, h * 0.26), Color(0.94, 0.95, 0.97, 0.92))
	# road with lane lines
	draw_rect(Rect2(0.0, h * 0.80, w, h * 0.20), Color(0.09, 0.10, 0.12))
	for i in 12:
		var x := w * (float(i) / 12.0)
		draw_rect(Rect2(x, h * 0.90, w * 0.04, 4.0), Color(0.9, 0.9, 0.85, 0.5))
	# cyan neon strip
	draw_rect(Rect2(0.0, h * 0.78, w, 3.0), Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.5))

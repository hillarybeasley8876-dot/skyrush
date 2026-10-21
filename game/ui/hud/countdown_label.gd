extends Control
## Race countdown: "3 · 2 · 1 · GO!" in the centre of the screen. The number pops in at 130 % and
## settles; "GO!" is cyan, the numbers are white.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

var _label: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_label = UI.display_label("", 160, Palette.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.38
	_label.anchor_bottom = 0.38
	_label.offset_bottom = 200.0
	_label.add_theme_color_override("font_outline_color", Palette.BLACK)
	_label.add_theme_constant_override("outline_size", 10)
	_label.visible = false
	add_child(_label)


## seconds_left: 3, 2, 1 ... 0 or less means GO.
func set_count(seconds_left: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.visible = true
	# The alpha is reset, or the second race of a session would show an invisible countdown.
	_label.modulate.a = 1.0
	if seconds_left > 0:
		_label.text = str(seconds_left)
		_label.add_theme_color_override("font_color", Palette.WHITE)
	else:
		_label.text = "GO!"
		_label.add_theme_color_override("font_color", Palette.CYAN)
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2(1.3, 1.3)
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	if seconds_left <= 0:
		_tween.tween_interval(0.7)
		_tween.tween_property(_label, "modulate:a", 0.0, 0.25)
		_tween.tween_callback(func() -> void: _label.visible = false)


func hide_count() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.visible = false
	_label.modulate.a = 1.0

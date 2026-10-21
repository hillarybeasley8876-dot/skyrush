extends "res://ui/menu/widgets/setting_row.gd"
## A settings row with a horizontal slider (the four volume buses).
##
## The slider is keyboard / gamepad friendly: left and right step it by 5 %, and the value is
## written straight through to `Settings.set_volume` through the `changed` signal.

signal changed(value: float)

var slider: HSlider
var _value: float = 0.9


func _init(title: String, subtitle: String, value: float) -> void:
	super(title, subtitle)
	_value = clampf(value, 0.0, 1.0)

	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _value
	slider.custom_minimum_size = Vector2(240, 24)
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.value_changed.connect(_on_slider_changed)
	slider.add_theme_stylebox_override("slider", _track_style())
	slider.add_theme_stylebox_override("grabber_area", _fill_style())
	slider.add_theme_stylebox_override("grabber_area_highlight", _fill_style())
	slider.add_theme_icon_override("grabber", _grabber_icon())
	slider.add_theme_icon_override("grabber_highlight", _grabber_icon())
	value_area.add_child(slider)

	set_value(_percent_text())
	value_label.add_theme_color_override("font_color", Palette.TEXT)


func current_value() -> float:
	return _value


func set_slider_value(value: float, notify: bool = false) -> void:
	_value = clampf(value, 0.0, 1.0)
	slider.set_value_no_signal(_value)
	set_value(_percent_text())
	if notify:
		changed.emit(_value)


func adjust(direction: int) -> bool:
	set_slider_value(_value + float(signi(direction)) * 0.05, true)
	return true


func _on_slider_changed(value: float) -> void:
	_value = value
	set_value(_percent_text())
	changed.emit(value)


func _percent_text() -> String:
	return "%d%%" % int(round(_value * 100.0))


func _track_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.10)
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb


## The grabber is a cyan tick, not the default round dot.
func _grabber_icon() -> ImageTexture:
	var image := Image.create(4, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.098, 0.898, 1.0, 0.95))
	return ImageTexture.create_from_image(image)


func _fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CYAN
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb

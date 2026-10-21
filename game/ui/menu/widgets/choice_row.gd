extends "res://ui/menu/widgets/setting_row.gd"
## A settings row that cycles through a fixed list of options (quality preset, rain on/off, ...).
##
## Left / right change the value, accept cycles forward. `changed` carries the new index so the
## screen can apply it (Settings.set_quality, the environment's set_rain, ...).

signal changed(index: int)

var options: PackedStringArray = PackedStringArray()
var index: int = 0


func _init(title: String, subtitle: String, choices: PackedStringArray, start_index: int = 0) -> void:
	super(title, subtitle)
	options = choices
	index = clampi(start_index, 0, maxi(choices.size() - 1, 0))
	show_arrows = true
	set_value(current_text())
	value_label.add_theme_color_override("font_color", Palette.CYAN)


func current_text() -> String:
	if index < 0 or index >= options.size():
		return ""
	return options[index]


func set_index(value: int, notify: bool = false) -> void:
	index = clampi(value, 0, maxi(options.size() - 1, 0))
	set_value(current_text())
	if notify:
		changed.emit(index)


func adjust(direction: int) -> bool:
	if options.is_empty() or not enabled:
		return false
	index = wrapi(index + signi(direction), 0, options.size())
	set_value(current_text())
	changed.emit(index)
	return true


func activate() -> bool:
	if not enabled:
		return false
	return adjust(1)

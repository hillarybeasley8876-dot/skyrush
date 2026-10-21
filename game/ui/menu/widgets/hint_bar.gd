extends Control
## The key hints along the bottom of a screen.
##
## The hints follow the device in use: the keyboard hints after a key, the gamepad hints after a
## joypad event. The screens pass both strings and the bar picks the right one.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const MenuInput := preload("res://ui/menu/menu_input.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")

var label: Label

var _keyboard_text: String = ""
var _gamepad_text: String = ""
var _device: StringName = &"keyboard"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -54.0
	offset_bottom = -22.0
	label = UI.label("", 19, Palette.TEXT_DIM, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)


## The hints for both devices.
func set_hints(keyboard: String, gamepad: String) -> void:
	_keyboard_text = keyboard
	_gamepad_text = gamepad
	_refresh()


## The device the player is using.
func set_device(device: StringName) -> void:
	if device == _device:
		return
	_device = device
	_refresh()


func _process(_delta: float) -> void:
	# The hints follow the device the player is using.
	if MenuInput.last_device != _device:
		set_device(MenuInput.last_device)


func _refresh() -> void:
	label.text = _gamepad_text if _device == &"gamepad" else _keyboard_text


## The default hints of a list that can also be adjusted left / right.
static func default_hints(adjustable: bool = false) -> Dictionary:
	if adjustable:
		return {
			&"keyboard": "↑↓ 选择  ·  ←→ 调整  ·  Enter 确认  ·  Esc 返回",
			&"gamepad": "D-Pad 选择  ·  L/R 调整  ·  A 确认  ·  B 返回",
		}
	return {
		&"keyboard": "↑↓ 选择  ·  Enter 确认  ·  Esc 返回",
		&"gamepad": "D-Pad 选择  ·  A 确认  ·  B 返回",
	}

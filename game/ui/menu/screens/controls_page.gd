extends "res://ui/menu/screens/menu_screen.gd"
## The controls reference: the keyboard and the gamepad tables.
##
## The bindings are read from the InputMap (the actions `core/input_setup.gd` registers), so the
## page cannot drift from what the game really uses. The keys are drawn as key caps.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const KeyChip := preload("res://ui/menu/widgets/key_chip.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

## The rows of the table: the Chinese name, the English name and the actions behind them.
const ROWS: Array[Dictionary] = [
	{"cn": "加速 / 刹车", "en": "ACCELERATE / BRAKE", "actions": ["accelerate", "brake"]},
	{"cn": "转向", "en": "STEER", "actions": ["steer_left", "steer_right"]},
	{"cn": "漂移", "en": "DRIFT", "actions": ["drift"]},
	{"cn": "氮气加速", "en": "N₂ BOOST", "actions": ["nitro"]},
	{"cn": "小喷", "en": "MINI BOOST", "actions": ["mini_boost"]},
	{"cn": "跳跃 / 悬停", "en": "HOP / HOVER", "actions": ["hop"]},
	{"cn": "离开飞行航道", "en": "EXIT SKY LANE", "actions": ["flight"]},
	{"cn": "空中翻滚", "en": "BARREL ROLL", "actions": ["roll_left", "roll_right"]},
	{"cn": "后视 / 视角", "en": "LOOK BACK / CAMERA", "actions": ["look_back", "camera_toggle"]},
	{"cn": "喇叭 / 重置 / 暂停", "en": "HORN / RESET / PAUSE",
		"actions": ["horn", "reset_car", "pause"]},
]

## The captions of the gamepad buttons.
const PAD_LABELS: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
}
## The gamepad buttons that are drawn as a circle (with their Xbox colour).
const ROUND_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
## The gamepad buttons that are drawn as a pill.
const PILL_BUTTONS: Array[int] = [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
## The Start button is drawn as three bars (the ☰ glyph is in none of the fonts).
const BARS_BUTTONS: Array[int] = [JOY_BUTTON_START]
## The captions of the stick axes (the stick is one chip, not two).
const AXIS_LABELS: Dictionary = {
	JOY_AXIS_LEFT_X: "左摇杆", JOY_AXIS_LEFT_Y: "左摇杆",
	JOY_AXIS_RIGHT_X: "右摇杆", JOY_AXIS_RIGHT_Y: "右摇杆",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

var list: OptionList
var hints: HintBar


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := UI.display_label("操作说明  CONTROLS", 44, Palette.WHITE)
	UI.place(title, 0.5, 0, 0.5, 0, -430, 46, 430, 112)
	add_child(title)

	var panel := MenuPanel.new("")
	UI.place(panel, 0.5, 0, 0.5, 0, -600, 96, 600, 838)
	add_child(panel)

	var columns := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, 40)
	panel.content.add_child(columns)
	columns.add_child(_column("键盘  KEYBOARD", false))
	columns.add_child(_column("手柄  GAMEPAD", true))

	list = OptionList.new()
	var back := MenuItem.new()
	back.set_text("返回", "BACK", "")
	back.activated.connect(func() -> void: request_back.emit())
	list.add_row(back)
	panel.content.add_child(list)

	hints = HintBar.new()
	hints.set_hints("Esc 返回  ·  Enter 确认", "B 返回  ·  A 确认")
	add_child(hints)


## One column of the table. `gamepad` picks the gamepad bindings instead of the keyboard ones.
func _column(header: String, gamepad: bool) -> VBoxContainer:
	var box := UI.v_box(BoxContainer.ALIGNMENT_BEGIN, 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UI.bold_label(header, 22, Palette.CYAN))
	box.add_child(_rule())
	for row: Dictionary in ROWS:
		box.add_child(_row(row, gamepad))
	return box


func _row(row: Dictionary, gamepad: bool) -> Control:
	var line := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, 12)
	var names := UI.v_box(BoxContainer.ALIGNMENT_CENTER, 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UI.label(String(row["cn"]), 19, Palette.TEXT, Fonts.text()))
	names.add_child(UI.label(String(row["en"]), 14, Palette.TEXT_DIM, Fonts.text()))
	line.add_child(names)
	var chips := UI.h_box(BoxContainer.ALIGNMENT_END, 6)
	line.add_child(chips)
	# The same control twice (the stick) is one chip.
	var seen: Array[String] = []
	for action: String in row["actions"]:
		for chip: Control in _chips_for(action, gamepad):
			var key_chip := chip as KeyChip
			if key_chip == null:
				continue
			var caption := key_chip.text
			if seen.has(caption):
				continue
			seen.append(caption)
			chips.add_child(chip)
	return line


## The chips of one action (the keys or the buttons).
func _chips_for(action: String, gamepad: bool) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		if gamepad:
			out.append_array(_gamepad_chips(event))
		else:
			out.append_array(_keyboard_chips(event))
	return out


func _keyboard_chips(event: InputEvent) -> Array:
	var out: Array = []
	if event is InputEventKey:
		var key := event as InputEventKey
		var caption := KeyChip.caption_for(key.physical_keycode)
		if caption.is_empty():
			caption = KeyChip.caption_for(key.keycode)
		if not caption.is_empty():
			out.append(KeyChip.new(caption, KeyChip.Shape.KEY))
	return out


func _gamepad_chips(event: InputEvent) -> Array:
	var out: Array = []
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		var caption := String(PAD_LABELS.get(button.button_index, "?"))
		var shape := KeyChip.Shape.KEY
		if ROUND_BUTTONS.has(button.button_index):
			shape = KeyChip.Shape.ROUND
		elif PILL_BUTTONS.has(button.button_index):
			shape = KeyChip.Shape.PILL
		elif BARS_BUTTONS.has(button.button_index):
			shape = KeyChip.Shape.BARS
		out.append(KeyChip.new(caption, shape))
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var caption := String(AXIS_LABELS.get(motion.axis, "轴"))
		out.append(KeyChip.new(caption, KeyChip.Shape.PILL))
	return out


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.30)
	rule.custom_minimum_size = Vector2(0, 1)
	return rule


func handle_action(action: StringName, _event: InputEvent) -> bool:
	match action:
		&"menu_up":
			return list.move_selection(-1)
		&"menu_down":
			return list.move_selection(1)
		&"menu_accept":
			return list.activate_selected()
	return false


func handle_back() -> bool:
	request_back.emit()
	return true

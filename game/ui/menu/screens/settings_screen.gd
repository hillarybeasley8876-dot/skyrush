extends "res://ui/menu/screens/menu_screen.gd"
## Settings: quality preset, the four volume buses, rain, motion blur and the controls page.
##
## Everything is written straight through to the owning unit (Settings, the environment's weather
## controller, the camera) and mirrored into the menu's own preferences file.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Prefs := preload("res://ui/menu/prefs.gd")
const Bridge := preload("res://ui/menu/bridge.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const ChoiceRow := preload("res://ui/menu/widgets/choice_row.gd")
const SliderRow := preload("res://ui/menu/widgets/slider_row.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

const QUALITIES: PackedStringArray = ["低", "中", "高", "极致"]
const QUALITY_IDS: PackedStringArray = ["low", "medium", "high", "ultra"]
const ON_OFF: PackedStringArray = ["开", "关"]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Voice"]
const BUS_LABELS: PackedStringArray = ["主音量", "音乐", "音效", "语音"]
const BUS_ENGLISH: PackedStringArray = ["MASTER", "MUSIC", "SFX", "VOICE"]

var list: OptionList
var hints: HintBar

var _prefs: Prefs
## The row the cursor was on (so it survives a rebuild).
var _selected_row: int = 0


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := UI.display_label("设置  SETTINGS", 44, Palette.WHITE)
	UI.place(title, 0.5, 0, 0.5, 0, -430, 46, 430, 112)
	add_child(title)

	var panel := MenuPanel.new("")
	UI.place(panel, 0.5, 0, 0.5, 0, -430, 108, 430, 772)
	add_child(panel)

	list = OptionList.new()
	panel.content.add_child(list)
	# Connected once: the rows are rebuilt on every visit, the list is not.
	list.selection_changed.connect(_on_selection_changed)

	hints = HintBar.new()
	hints.set_hints("↑↓ 选择  ·  ←→ 调整  ·  Enter 切换  ·  Esc 返回",
			"D-Pad 选择  ·  L/R 调整  ·  A 切换  ·  B 返回")
	add_child(hints)


func on_enter() -> void:
	_prefs = prefs as Prefs
	_build_rows()


func handle_action(action: StringName, _event: InputEvent) -> bool:
	match action:
		&"menu_up":
			return list.move_selection(-1)
		&"menu_down":
			return list.move_selection(1)
		&"menu_left":
			return list.adjust_selected(-1)
		&"menu_right":
			return list.adjust_selected(1)
		&"menu_accept":
			return list.activate_selected()
	return false


func handle_back() -> bool:
	request_back.emit()
	return true


## Index of the highlighted row (the tests use it).
func debug_selection() -> int:
	return list.get_selected_index()


func _build_rows() -> void:
	list.clear_rows()

	var quality_index := QUALITY_IDS.find(String(Settings.quality))
	if quality_index < 0:
		quality_index = 2
	var quality := ChoiceRow.new("画质  QUALITY", "阴影 / 反射 / 雾效", QUALITIES, quality_index)
	quality.changed.connect(_on_quality_changed)
	list.add_row(quality)

	for i in BUSES.size():
		var bus := BUSES[i]
		var value := float(Settings.volumes.get(bus, 0.9))
		var row := SliderRow.new("%s  %s" % [BUS_LABELS[i], BUS_ENGLISH[i]], "", value)
		row.changed.connect(_on_volume_changed.bind(bus))
		list.add_row(row)

	# The rain row shows the state of the weather controller, not the saved preference.
	var rain := ChoiceRow.new("雨效  RAIN", "雨幕与湿滑路面", ON_OFF, 0 if Bridge.is_raining() else 1)
	rain.changed.connect(_on_rain_changed)
	list.add_row(rain)

	var blur := ChoiceRow.new("动态模糊  MOTION BLUR", "高速时的速度感", ON_OFF,
			0 if Bridge.motion_blur_enabled() else 1)
	blur.changed.connect(_on_blur_changed)
	list.add_row(blur)

	var controls := MenuItem.new()
	controls.set_text("操作说明", "CONTROLS", "键盘 / 手柄")
	controls.activated.connect(func() -> void: request_screen.emit(&"controls", {}))
	list.add_row(controls)

	var back := MenuItem.new()
	back.set_text("返回", "BACK", "")
	back.activated.connect(func() -> void: request_back.emit())
	list.add_row(back)

	list.select(_selected_row)


func _on_selection_changed(index: int) -> void:
	_selected_row = index


func _on_quality_changed(index: int) -> void:
	Settings.set_quality(StringName(QUALITY_IDS[index]))


func _on_volume_changed(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, value)


func _on_rain_changed(index: int) -> void:
	var active := index == 0
	Bridge.set_rain(active)
	if _prefs != null:
		_prefs.rain = active
		_prefs.save_to_disk()


func _on_blur_changed(index: int) -> void:
	var active := index == 0
	Bridge.set_motion_blur(active)
	if _prefs != null:
		_prefs.motion_blur = active
		_prefs.save_to_disk()

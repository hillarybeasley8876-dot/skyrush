extends "res://ui/menu/screens/menu_screen.gd"
## Pursuit setup: the goal (escape the police or take them down), the number of police cars and
## the heat the pursuit starts at.
##
## The options are the ones the modes unit accepts (`goal`, `count`, `heat`).

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const ChoiceRow := preload("res://ui/menu/widgets/choice_row.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")
const Prefs := preload("res://ui/menu/prefs.gd")

const GOALS: PackedStringArray = ["逃脱追捕", "撞毁警车"]
const GOAL_IDS: PackedStringArray = ["escape", "takedowns"]
const COUNT_CHOICES: PackedStringArray = ["1 辆", "2 辆", "3 辆", "4 辆", "5 辆"]
const HEAT_CHOICES: PackedStringArray = ["1 级", "2 级", "3 级", "4 级", "5 级"]

var list: OptionList
var hints: HintBar

var _goal: int = 0
var _count: int = 2
var _heat: int = 2
var _prefs: Prefs
## The row with the number of police cars (it follows the goal).
var _target_row: ChoiceRow = null


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := UI.display_label("警匪追逐  PURSUIT", 46, Palette.WHITE)
	UI.place(title, 0.5, 0, 0.5, 0, -430, 60, 430, 130)
	add_child(title)

	var panel := MenuPanel.new("追捕设置  PURSUIT SETUP")
	UI.place(panel, 0.5, 0, 0.5, 0, -380, 150, 380, 520)
	add_child(panel)

	list = OptionList.new()
	panel.content.add_child(list)

	hints = HintBar.new()
	var texts := HintBar.default_hints(true)
	hints.set_hints(String(texts[&"keyboard"]), String(texts[&"gamepad"]))
	add_child(hints)


func on_enter() -> void:
	_prefs = prefs as Prefs
	if _prefs != null:
		_goal = 0 if _prefs.pursuit_goal == "escape" else 1
		_count = clampi(_prefs.pursuit_count - 1, 0, COUNT_CHOICES.size() - 1)
		_heat = clampi(_prefs.pursuit_heat - 1, 0, HEAT_CHOICES.size() - 1)
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

	var goal := ChoiceRow.new("目标  GOAL", "甩掉他们，或者撞废他们", GOALS, _goal)
	goal.changed.connect(_on_goal_changed)
	list.add_row(goal)

	var count := ChoiceRow.new("撞毁目标  TARGET", "要撞掉几辆警车", COUNT_CHOICES, _count)
	count.changed.connect(_on_count_changed)
	list.add_row(count)
	_target_row = count

	var heat := ChoiceRow.new("起始热度  HEAT", "警方的初始警戒级别", HEAT_CHOICES, _heat)
	heat.changed.connect(_on_heat_changed)
	list.add_row(heat)

	var start := MenuItem.new()
	start.set_text("开始追捕", "START PURSUIT", "")
	start.activated.connect(_on_start)
	list.add_row(start)

	var back := MenuItem.new()
	back.set_text("返回", "BACK", "")
	back.activated.connect(func() -> void: request_back.emit())
	list.add_row(back)

	# The target row is only live when the goal is to take the police down.
	if _target_row != null:
		_target_row.set_enabled(_goal == 1)
	list.select(3)


func _on_goal_changed(index: int) -> void:
	_goal = index
	# The target only matters when the goal is to take the police down.
	if _target_row != null:
		_target_row.set_enabled(index == 1)


func _on_count_changed(index: int) -> void:
	_count = index


func _on_heat_changed(index: int) -> void:
	_heat = index


func _on_start() -> void:
	if _prefs != null:
		_prefs.pursuit_goal = GOAL_IDS[_goal]
		_prefs.pursuit_count = _count + 1
		_prefs.pursuit_heat = _heat + 1
		_prefs.save_to_disk()
	request_mode.emit(&"pursuit", {
		"goal": GOAL_IDS[_goal],
		"count": _count + 1,
		"heat": _heat + 1,
	})

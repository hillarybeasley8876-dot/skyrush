extends "res://ui/menu/screens/menu_screen.gd"
## The pause overlay: resume, restart, settings, quit to the main menu.
##
## Opened by the core `pause` action (Esc / P / Start). The tree is paused while it is up, so the
## screen itself must run with PROCESS_MODE_ALWAYS (the menu root does that).

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

const MODE_NAMES: Dictionary = {
	&"free": "自由驾驶  FREE ROAM",
	&"race": "竞速赛  RACE",
	&"pursuit": "警匪追逐  PURSUIT",
}

var list: OptionList
var mode_label: Label
var hints: HintBar
var panel: MenuPanel

var _mode: StringName = &"free"


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.035, 0.55)
	Layout.fill(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	panel = MenuPanel.new("暂停  PAUSED")
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -300, -200, 300, 200)
	add_child(panel)

	mode_label = UI.label("", 20, Palette.CYAN, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	panel.content.add_child(mode_label)

	list = OptionList.new()
	panel.content.add_child(list)

	hints = HintBar.new()
	hints.set_hints("↑↓ 选择  ·  Enter 确认  ·  Esc 继续游戏",
			"D-Pad 选择  ·  A 确认  ·  B 继续游戏  ·  Start 继续游戏")
	add_child(hints)


func on_enter() -> void:
	_mode = StringName(payload.get("mode", Game.mode))
	mode_label.text = String(MODE_NAMES.get(_mode, "自由驾驶  FREE ROAM"))
	_build_rows()


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


func _build_rows() -> void:
	list.clear_rows()

	var resume := MenuItem.new()
	resume.set_text("继续游戏", "RESUME", "")
	resume.activated.connect(func() -> void: request_back.emit())
	list.add_row(resume)

	var restart := MenuItem.new()
	restart.set_text("重新开始", "RESTART", "")
	restart.activated.connect(_on_restart)
	list.add_row(restart)

	var settings := MenuItem.new()
	settings.set_text("设置", "SETTINGS", "")
	settings.activated.connect(func() -> void: request_screen.emit(&"settings", {}))
	list.add_row(settings)

	var quit := MenuItem.new()
	quit.set_text("退出到主菜单", "QUIT TO MENU", "")
	quit.activated.connect(_on_quit)
	list.add_row(quit)

	list.select(0)
	_fit_panel()


## Sizes the panel to its content: a pause panel with four rows is not a tall box.
func _fit_panel() -> void:
	var height := panel.content.get_combined_minimum_size().y \
			+ MenuPanel.MARGIN * 2.0 + MenuPanel.HEADER_HEIGHT
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -300, -height * 0.5, 300, height * 0.5)


func _on_restart() -> void:
	request_mode.emit(_mode, payload.get("options", {}))


## Leaving a free-roam session shows the score summary first.
func _on_quit() -> void:
	if _mode == &"free" and router != null:
		var results := router.session_results()
		if not results.is_empty():
			request_screen.emit(&"results", router.build_payload(results))
			return
	request_main_menu.emit()

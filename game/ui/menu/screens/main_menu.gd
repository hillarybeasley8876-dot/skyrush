extends "res://ui/menu/screens/menu_screen.gd"
## The main menu: 自由驾驶 / 竞速赛 / 警匪追逐 / 设置 / 退出.
##
## The list on the left, a description panel on the right; both are anchored so the layout holds
## at 16:9, 16:10 and 21:9 without overlapping. The panel follows the highlighted row.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const Logo := preload("res://ui/menu/widgets/logo.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

## The five rows of the main menu: the Chinese title, the English name and the description.
const ITEMS: Array[Dictionary] = [
	{"title": "自由驾驶", "en": "FREE ROAM",
		"desc": "在申城街头随意驰骋。特技、闪充、飞行航道，纪录由你破。"},
	{"title": "竞速赛", "en": "RACE",
		"desc": "挑一条路线，和五位车手在雨夜的上海竞速。"},
	{"title": "警匪追逐", "en": "PURSUIT",
		"desc": "警灯已经亮了。甩掉他们，或者把他们全部撞废。"},
	{"title": "设置", "en": "SETTINGS",
		"desc": "画质、音量、雨效、动态模糊，以及完整操作说明。"},
	{"title": "退出", "en": "QUIT",
		"desc": "离开申城，回到桌面。"},
]

const ITEM_FREE := 0
const ITEM_RACE := 1
const ITEM_PURSUIT := 2
const ITEM_SETTINGS := 3
const ITEM_QUIT := 4

## The logo of the menu: its size, where it sits and the gap to the list below it.
const LOGO_SIZE := 58
const LOGO_LEFT := 84.0
const LOGO_TOP := 56.0
const LOGO_GAP := 16.0

var list: OptionList
var description: Label
var stats: Label
var title_label: Label
var hints: HintBar

var _quit_armed: bool = false


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var logo := Logo.new()
	logo.font_size = LOGO_SIZE
	# The logo reports the height it needs, so the list never sits on the Chinese name.
	var logo_height := logo.content_height()
	UI.place(logo, 0, 0, 0, 0, LOGO_LEFT, LOGO_TOP, 560, LOGO_TOP + logo_height)
	add_child(logo)

	var list_top := LOGO_TOP + logo_height + LOGO_GAP
	list = OptionList.new()
	UI.place(list, 0, 0, 0, 0, LOGO_LEFT, list_top, 620, 660)
	add_child(list)
	for i in ITEMS.size():
		var item: Dictionary = ITEMS[i]
		list.add_item(String(item["title"]), String(item["en"]))
	list.item_activated.connect(_on_item_activated)
	list.selection_changed.connect(_on_selection_changed)

	var panel := MenuPanel.new("菜单  MENU")
	UI.place(panel, 1, 0, 1, 0, -520, list_top, -84, 520)
	add_child(panel)

	title_label = UI.display_label("", 40, Palette.WHITE)
	panel.content.add_child(title_label)

	description = UI.label("", 21, Palette.TEXT, Fonts.text())
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(0, 120)
	panel.content.add_child(description)

	stats = UI.label("", 19, Palette.CYAN, Fonts.text())
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.content.add_child(stats)

	hints = HintBar.new()
	# The main menu has nothing to go back to.
	hints.set_hints("↑↓ 选择  ·  Enter 确认",
			"D-Pad 选择  ·  A 确认")
	add_child(hints)


func on_enter() -> void:
	_disarm_quit()
	_show_details(list.get_selected_index())


## Index of the highlighted row (the tests use it).
func debug_selection() -> int:
	return list.get_selected_index()


## Up / down move the selection; the description panel follows.
func handle_action(action: StringName, _event: InputEvent) -> bool:
	match action:
		&"menu_up":
			if list.move_selection(-1):
				_disarm_quit()
				return true
		&"menu_down":
			if list.move_selection(1):
				_disarm_quit()
				return true
		&"menu_accept":
			return _activate(list.get_selected_index())
	return false


func _on_item_activated(index: int) -> void:
	_activate(index)


func _activate(index: int) -> bool:
	match index:
		ITEM_FREE:
			request_mode.emit(&"free", {})
		ITEM_RACE:
			request_screen.emit(&"race_setup", {})
		ITEM_PURSUIT:
			request_screen.emit(&"pursuit_setup", {})
		ITEM_SETTINGS:
			request_screen.emit(&"settings", {})
		ITEM_QUIT:
			if _quit_armed:
				request_quit.emit()
			else:
				_arm_quit()
	return true


func _on_selection_changed(index: int) -> void:
	_show_details(index)


func _arm_quit() -> void:
	_quit_armed = true
	var item := list.get_item(ITEM_QUIT)
	if item != null:
		item.set_text("确认退出", "CONFIRM QUIT", "")
	hints.set_hints("再次按 Enter 退出  ·  选择其它项目取消",
			"再次按 A 退出  ·  选择其它项目取消")


func _disarm_quit() -> void:
	if not _quit_armed:
		return
	_quit_armed = false
	var item := list.get_item(ITEM_QUIT)
	if item != null:
		item.set_text(String(ITEMS[ITEM_QUIT]["title"]), String(ITEMS[ITEM_QUIT]["en"]), "")
	# The main menu has nothing to go back to.
	hints.set_hints("↑↓ 选择  ·  Enter 确认",
			"D-Pad 选择  ·  A 确认")


func _show_details(index: int) -> void:
	if index < 0 or index >= ITEMS.size():
		return
	var item: Dictionary = ITEMS[index]
	title_label.text = "%s  %s" % [item["title"], item["en"]]
	description.text = String(item["desc"])
	stats.text = _stats_for(index)


func _stats_for(index: int) -> String:
	var world := Game.world
	var route_count := 0
	if world != null:
		route_count = world.get_route_ids().size()
	match index:
		ITEM_FREE:
			return "自由驾驶 · 随时开始"
		ITEM_RACE:
			return "可用路线 %d 条" % route_count
		ITEM_PURSUIT:
			return "热度 2–3 级起步 · 甩脱或撞废警车"
		ITEM_SETTINGS:
			return "画质 · 音量 · 雨效 · 动态模糊"
		_:
			return ""

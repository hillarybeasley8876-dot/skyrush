extends "res://ui/menu/screens/menu_screen.gd"
## Race setup: pick a route, a difficulty and a lap count, then start.
##
## The cursor only *previews* a route: Enter (or A) on a route row picks it (a cyan check and a
## bar that stays lit) and jumps to 开始比赛. The length of a route is the length of its racing
## line, per lap.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Prefs := preload("res://ui/menu/prefs.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const ChoiceRow := preload("res://ui/menu/widgets/choice_row.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

const DIFFICULTIES: PackedStringArray = ["简单", "普通", "困难"]
const DIFFICULTY_IDS: PackedStringArray = ["easy", "normal", "hard"]
const LAP_CHOICES: PackedStringArray = ["1 圈", "2 圈", "3 圈", "4 圈", "5 圈"]
## The height of the list of the routes: nine rows of 60 px and eight gaps of 6 px, so every
## row (the last one is 返回) fits without scrolling at 1080.
const ROW_HEIGHT := 60.0
const ROW_GAP := 6.0
const LIST_ROWS := 9
const LIST_HEIGHT := LIST_ROWS * ROW_HEIGHT + (LIST_ROWS - 1) * ROW_GAP
## The bottom of the panel of the list (it holds the header and the margins).
const LIST_PANEL_BOTTOM := 140.0 + LIST_HEIGHT + 26.0 + 52.0

var list: OptionList
var route_name: Label
var route_length: Label
var route_total: Label
var route_best: Label
var route_note: Label
var route_picked: Label
var hints: HintBar

var _prefs: Prefs
var _routes: Array[RaceRoute] = []
var _route_rows: Array[MenuItem] = []
## The list of the routes scrolls (there are more rows than fit on the screen).
var _scroll: ScrollContainer = null
## The length of a lap of every route (baking the racing lines is expensive).
var _length_cache: Dictionary = {}
var _picked: int = -1
var _preview: int = 0
var _difficulty: int = 1
var _laps: int = 2
var _start_row: int = 0


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := UI.display_label("竞速赛  RACE", 46, Palette.WHITE)
	UI.place(title, 0, 0, 0, 0, 84, 52, 700, 124)
	add_child(title)

	var list_panel := MenuPanel.new("选择路线  ROUTE")
	UI.place(list_panel, 0, 0, 0, 0, 84, 140, 900, LIST_PANEL_BOTTOM)
	add_child(list_panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	list_panel.content.add_child(_scroll)

	list = OptionList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.selection_changed.connect(_on_selection_changed)
	_scroll.add_child(list)

	var panel := MenuPanel.new("路线信息  ROUTE INFO")
	UI.place(panel, 1, 0, 1, 0, -520, 140, -84, 560)
	add_child(panel)

	route_name = UI.display_label("", 34, Palette.CYAN)
	panel.content.add_child(route_name)

	route_length = UI.label("", 22, Palette.TEXT, Fonts.text())
	panel.content.add_child(route_length)

	route_total = UI.label("", 22, Palette.TEXT, Fonts.text())
	panel.content.add_child(route_total)

	route_best = UI.label("", 22, Palette.TEXT, Fonts.text())
	panel.content.add_child(route_best)

	route_picked = UI.label("", 18, Palette.GREEN, Fonts.text())
	panel.content.add_child(route_picked)

	route_note = UI.label("", 16, Palette.TEXT_DIM, Fonts.text())
	route_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.content.add_child(route_note)

	hints = HintBar.new()
	var texts := HintBar.default_hints(true)
	hints.set_hints(String(texts[&"keyboard"]), String(texts[&"gamepad"]))
	add_child(hints)


func on_enter() -> void:
	_prefs = prefs as Prefs
	_build_list()


## Up / down walk the list, left / right change the option on the highlighted row.
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
			return _activate()
	return false


func handle_back() -> bool:
	request_back.emit()
	return true


## Index of the highlighted row (the tests use it).
func debug_selection() -> int:
	return list.get_selected_index()


func _build_list() -> void:
	list.clear_rows()
	_route_rows.clear()
	_length_cache.clear()
	_routes = _collect_routes()
	_picked = -1
	_preview = 0
	for i in _routes.size():
		var route := _routes[i]
		var item := MenuItem.new()
		item.set_text(_route_title(route), _route_subtitle(route), "")
		item.activated.connect(_on_route_clicked.bind(i))
		list.add_row(item)
		_route_rows.append(item)
	if _routes.is_empty():
		var empty := MenuItem.new()
		empty.set_text("暂无可用路线", "NO ROUTES AVAILABLE", "")
		list.add_row(empty)

	_difficulty = _difficulty_index()
	_laps = _laps_from_prefs()
	var difficulty_row := ChoiceRow.new("难度  DIFFICULTY", "车手强度与橡皮筋", DIFFICULTIES, _difficulty)
	difficulty_row.changed.connect(_on_difficulty_changed)
	list.add_row(difficulty_row)

	var lap_row := ChoiceRow.new("圈数  LAPS", "要跑几圈", LAP_CHOICES, clampi(_laps - 1, 0, LAP_CHOICES.size() - 1))
	lap_row.changed.connect(_on_laps_changed)
	list.add_row(lap_row)

	_start_row = list.rows.size()
	var start := MenuItem.new()
	start.set_text("开始比赛", "START RACE", "")
	start.activated.connect(_on_start)
	list.add_row(start)

	var back := MenuItem.new()
	back.set_text("返回", "BACK", "")
	back.activated.connect(_on_back)
	list.add_row(back)

	# The route of the last race is preselected.
	var last := _last_route_index()
	if last >= 0:
		_pick_route(last)
	list.select(_start_row if _picked >= 0 else 0)
	_show_route()
	_scroll_into_view(list.get_selected_index())


## The routes of the world.
func _collect_routes() -> Array[RaceRoute]:
	var out: Array[RaceRoute] = []
	var world := Game.world
	if world == null:
		return out
	for id in world.get_route_ids():
		var route := world.get_route(id)
		if route != null:
			out.append(route)
	return out


func _route_title(route: RaceRoute) -> String:
	if route.title.is_empty():
		return String(route.id)
	return route.title


## The length of one lap: the racing line of the route, or the gates when it has none.
## The lengths are cached: baking the racing line of every route is expensive.
func _lap_length_km(route: RaceRoute) -> float:
	var key := String(route.id)
	if _length_cache.has(key):
		return float(_length_cache[key])
	var length := _measure_lap_length(route)
	_length_cache[key] = length
	return length


## The length of one lap, measured on the racing line of the route.
func _measure_lap_length(route: RaceRoute) -> float:
	if route.racing_line != null:
		return route.racing_line.get_baked_length() / 1000.0
	var points := route.checkpoints
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in points.size():
		total += points[i].origin.distance_to(points[(i + 1) % points.size()].origin)
	return total / 1000.0


func _route_subtitle(route: RaceRoute) -> String:
	return "每圈 %.2f km  ·  最佳 %s" % [_lap_length_km(route), Prefs.format_time(_best_time(route))]


## The best time of a route (the modes unit owns the records).
func _best_time(route: RaceRoute) -> float:
	if router == null:
		return -1.0
	return router.best_time(String(route.id))


func _difficulty_index() -> int:
	if _prefs == null:
		return 1
	var index := DIFFICULTY_IDS.find(_prefs.difficulty)
	return maxi(index, 0)


func _laps_from_prefs() -> int:
	if _prefs == null:
		return 2
	return clampi(_prefs.laps, 1, LAP_CHOICES.size())


func _last_route_index() -> int:
	if _prefs == null:
		return -1
	for i in _routes.size():
		if String(_routes[i].id) == _prefs.last_route:
			return i
	return -1


## Enter on a route row picks it and jumps to 开始比赛.
func _activate() -> bool:
	var index := list.get_selected_index()
	if index >= 0 and index < _route_rows.size():
		_pick_route(index)
		list.select(_start_row)
		return true
	var row := list.get_item(index)
	if row != null:
		return row.activate()
	return false


func _on_route_clicked(index: int) -> void:
	_pick_route(index)
	list.select(_start_row)


## Picks a route: the check mark, the persistent bar and the laps of the route.
func _pick_route(index: int) -> void:
	if index < 0 or index >= _routes.size():
		return
	_picked = index
	_preview = index
	for i in _route_rows.size():
		_route_rows[i].set_picked(i == index)
	_laps = clampi(_routes[index].laps, 1, LAP_CHOICES.size())
	var lap_row := list.get_item(_route_rows.size() + 1)
	if lap_row != null:
		lap_row.set_value(LAP_CHOICES[_laps - 1])
	if _prefs != null:
		_prefs.last_route = String(_routes[index].id)
		_prefs.laps = _laps
	_show_route()


func _on_selection_changed(index: int) -> void:
	if index >= 0 and index < _route_rows.size():
		_preview = index
		_show_route()
	_scroll_into_view(index)


## Scrolls the highlighted row into view: the list of the routes is longer than the panel.
func _scroll_into_view(index: int) -> void:
	if _scroll == null or index < 0:
		return
	var row := list.get_item(index)
	if row != null:
		_scroll.ensure_control_visible(row)


func _on_difficulty_changed(index: int) -> void:
	_difficulty = index
	if _prefs != null:
		_prefs.difficulty = DIFFICULTY_IDS[index]


func _on_laps_changed(index: int) -> void:
	_laps = index + 1
	if _prefs != null:
		_prefs.laps = _laps


func _on_start() -> void:
	# The cursor only previews: the race starts with the route that was picked (or the first one).
	var index := _picked if _picked >= 0 else 0
	if index < 0 or index >= _routes.size():
		return
	var route := _routes[index]
	if _prefs != null:
		_prefs.last_route = String(route.id)
		_prefs.save_to_disk()
	request_mode.emit(&"race", {
		"route": String(route.id),
		"difficulty": DIFFICULTY_IDS[_difficulty],
		"laps": _laps,
	})


func _on_back() -> void:
	request_back.emit()


## The panel shows the route under the cursor; the picked one is marked in the list.
func _show_route() -> void:
	if _routes.is_empty():
		route_name.text = "暂无路线"
		route_length.text = "世界数据尚未载入"
		route_best.text = ""
		route_note.text = ""
		return
	var index := clampi(_preview, 0, _routes.size() - 1)
	var route := _routes[index]
	route_name.text = _route_title(route)
	route_length.text = "每圈  LAP   %.2f km" % _lap_length_km(route)
	route_total.text = "全程  TOTAL  %.2f km" % (_lap_length_km(route) * float(_laps))
	route_best.text = "最佳  BEST      %s" % Prefs.format_time(_best_time(route))
	route_note.text = "难度 %s  ·  %d 圈  ·  %d 个检查点" % [
		DIFFICULTIES[_difficulty], _laps, route.checkpoints.size()]
	if _picked >= 0 and _picked < _routes.size():
		route_picked.text = "已选路线  PICKED   %s" % _route_title(_routes[_picked])
		route_picked.add_theme_color_override("font_color", Palette.GREEN)
	else:
		route_picked.text = "尚未选择路线  PICK A ROUTE"
		route_picked.add_theme_color_override("font_color", Palette.TEXT_DIM)

extends "res://ui/menu/screens/menu_screen.gd"
## The results screen: the race standings, the pursuit outcome or the free-roam score summary.
##
## Everything comes from the modes unit (the session that ran the mode and its records); the menu
## only shows it. Every kind ends with the same answers — retry, continue, main menu — and they
## answer in the frame the key is pressed (no double-confirm cadence).

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Prefs := preload("res://ui/menu/prefs.gd")
const OptionList := preload("res://ui/menu/widgets/option_list.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")
const MenuPanel := preload("res://ui/menu/widgets/panel.gd")
const HintBar := preload("res://ui/menu/widgets/hint_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

## The titles of the three kinds.
const RACE_TITLE := "比赛成绩  RACE RESULTS"
const PURSUIT_TITLES: Dictionary = {
	"escaped": "成功逃脱  ESCAPED",
	"busted": "被捕  BUSTED",
	"success": "任务完成  SUCCESS",
	"timeout": "时间到  TIMEOUT",
}
## The height of a row of the results table.
const ROW_HEIGHT := 34.0
## The width of the Chinese column of a stat row (the English label sits behind it).
const STAT_CN_X := 16.0
const STAT_EN_X := 160.0
## The width of the rank column of the standings.
const RANK_WIDTH := 56.0
## The distance of the value from the right edge of the row.
const VALUE_MARGIN := 16.0
## The subtitle of every pursuit result.
const PURSUIT_SUBTITLES: Dictionary = {
	"escaped": "甩开了追捕",
	"busted": "被警察拦下",
	"success": "目标达成 · 撞毁 %d 辆",
	"timeout": "时间到 · 未能甩开",
}

var heading: Label
var subtitle: Label
var table: VBoxContainer
var record_label: Label
var list: OptionList
var hints: HintBar
var panel: MenuPanel

var _kind: String = "free"
## The index of the row that is being added (the rows alternate their tint).
var _row_index: int = 0


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.035, 0.60)
	Layout.fill(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	panel = MenuPanel.new("")
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -460, -300, 460, 300)
	add_child(panel)

	heading = UI.display_label("", 44, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	panel.content.add_child(heading)

	subtitle = UI.label("", 18, Palette.TEXT_DIM, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	panel.content.add_child(subtitle)

	table = UI.v_box(BoxContainer.ALIGNMENT_BEGIN, 4)
	panel.content.add_child(table)

	record_label = UI.label("", 20, Palette.AMBER, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	panel.content.add_child(record_label)

	list = OptionList.new()
	panel.content.add_child(list)

	hints = HintBar.new()
	hints.set_hints("↑↓ 选择  ·  Enter 确认  ·  Esc 返回",
			"D-Pad 选择  ·  A 确认  ·  B 返回")
	add_child(hints)


func on_enter() -> void:
	_kind = String(payload.get("kind", "free"))
	_build()


func handle_action(action: StringName, _event: InputEvent) -> bool:
	match action:
		&"menu_up":
			return list.move_selection(-1)
		&"menu_down":
			return list.move_selection(1)
		&"menu_accept":
			return list.activate_selected()
	return false


## The back is the same as 继续: it must not pop back into the finished session.
func handle_back() -> bool:
	_continue()
	return true


## What the 继续 row does: a free-roam session is resumed, a finished one goes back to the
## free roam.
func _continue() -> void:
	if _kind == "free":
		request_resume.emit()
	else:
		request_mode.emit(&"free", {})


func _build() -> void:
	for child in table.get_children():
		child.queue_free()
	list.clear_rows()
	_row_index = 0
	match _kind:
		"race":
			_build_race()
		"pursuit":
			_build_pursuit()
		_:
			_build_free()
	list.select(0)
	_fit_panel()


## Sizes the panel to its content (the standings and the buttons decide the height).
func _fit_panel() -> void:
	var height := panel.content.get_combined_minimum_size().y \
			+ MenuPanel.MARGIN * 2.0 + MenuPanel.HEADER_HEIGHT
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -460, -height * 0.5, 460, height * 0.5)


## The standings of the race, sorted by position, with the unfinished racers at the end.
func _build_race() -> void:
	heading.text = RACE_TITLE
	subtitle.text = String(payload.get("route_title", ""))
	var results: Array = payload.get("results", [])
	var sorted := results.duplicate()
	sorted.sort_custom(_by_position)
	var player_time := -1.0
	var player_position := 0
	for entry: Dictionary in sorted:
		var is_player := bool(entry.get("is_player", false))
		var finished := bool(entry.get("finished", true))
		var time_text := Prefs.format_time(float(entry.get("time", -1.0)))
		if not finished:
			time_text = "DNF"
		_add_rank_row("%d" % int(entry.get("position", 0)), String(entry.get("name", "车手")),
				time_text, is_player)
		if is_player:
			player_time = float(entry.get("time", -1.0))
			player_position = int(entry.get("position", 0))
	var best_time := float(payload.get("best_time", -1.0))
	var best_lap := float(payload.get("best_lap", -1.0))
	if player_time > 0.0 and (best_time < 0.0 or player_time < best_time):
		record_label.text = "新纪录  NEW RECORD"
	elif player_position > 0:
		record_label.text = "名次  第 %d 名" % player_position
	if best_lap >= 0.0:
		record_label.text += "     最佳单圈  BEST LAP  %s" % Prefs.format_time(best_lap)
	_add_buttons(&"race", true)


func _build_pursuit() -> void:
	var result := String(payload.get("result", "running"))
	heading.text = String(PURSUIT_TITLES.get(result, "追捕结束  PURSUIT OVER"))
	var colour := Palette.AMBER
	if result == "escaped" or result == "success":
		colour = Palette.GREEN
	elif result == "busted":
		colour = Palette.RED
	heading.add_theme_color_override("font_color", colour)
	var subtitle_text := String(PURSUIT_SUBTITLES.get(result, "追捕结束"))
	if result == "success":
		subtitle_text = subtitle_text % int(payload.get("takedowns", 0))
	subtitle.text = subtitle_text
	_add_stat_row("热度", "HEAT", "%d 级" % int(payload.get("heat", 0)), false)
	_add_stat_row("撞毁警车", "TAKEDOWNS", "%d / %d" % [int(payload.get("takedowns", 0)),
			int(payload.get("target", 0))], false)
	_add_stat_row("用时", "TIME", Prefs.format_time(float(payload.get("time", 0.0))), false)
	record_label.text = ""
	_add_buttons(&"pursuit", true)


func _build_free() -> void:
	heading.text = "本局总结  SESSION SUMMARY"
	subtitle.text = "自由驾驶  FREE ROAM"
	_add_stat_row("得分", "SCORE", "%d" % int(payload.get("score", 0)), false)
	_add_stat_row("最佳", "BEST", "%d" % int(payload.get("best_score", 0)), false)
	_add_stat_row("特技", "STUNTS", "%d" % int(payload.get("stunts", 0)), false)
	_add_stat_row("擦肩而过", "NEAR MISS", "%d" % int(payload.get("near_misses", 0)), false)
	_add_stat_row("撞毁车辆", "WRECKS", "%d" % int(payload.get("wrecks", 0)), false)
	_add_stat_row("撞毁警车", "TAKEDOWNS", "%d" % int(payload.get("takedowns", 0)), false)
	_add_stat_row("用时", "TIME", Prefs.format_time(float(payload.get("time", 0.0))), false)
	var score := int(payload.get("score", 0))
	var best := int(payload.get("best_score", 0))
	record_label.text = "新纪录  NEW RECORD" if score >= best and score > 0 else ""
	_add_buttons(&"free", false)


## One row of the table: the player's row sits on a lit plate, the other rows alternate.
func _make_row(player: bool) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plate := ColorRect.new()
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := 0.05 if _row_index % 2 == 0 else 0.02
	plate.color = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.14) if player \
			else Color(1.0, 1.0, 1.0, shade)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(plate)
	table.add_child(row)
	_row_index += 1
	return row


## A stat row: the Chinese label, the English label behind it and the value on the right.
func _add_stat_row(cn: String, en: String, value: String, player: bool) -> void:
	var row := _make_row(player)
	var cn_label := UI.display_label(cn, 22, Palette.WHITE if player else Palette.TEXT)
	cn_label.position = Vector2(STAT_CN_X, 2)
	row.add_child(cn_label)
	var en_label := UI.label(en, 15, Palette.TEXT_DIM, Fonts.text())
	en_label.position = Vector2(STAT_EN_X, 6)
	row.add_child(en_label)
	var value_label := UI.display_label(value, 22, Palette.CYAN if player else Palette.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(value_label)
	_layout_value(row, value_label)
	row.resized.connect(func() -> void: _layout_value(row, value_label))


## A row of the standings: the rank, the name and the time on the right.
func _add_rank_row(rank: String, name_text: String, time_text: String, player: bool) -> void:
	var row := _make_row(player)
	var rank_label := UI.display_label(rank, 22, Palette.AMBER if player else Palette.TEXT_DIM)
	rank_label.position = Vector2(2, 1)
	row.add_child(rank_label)
	var name_label := UI.label(name_text, 20, Palette.WHITE if player else Palette.TEXT, Fonts.text())
	name_label.position = Vector2(RANK_WIDTH, 3)
	name_label.clip_text = true
	row.add_child(name_label)
	var time_label := UI.display_label(time_text, 22, Palette.CYAN if player else Palette.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(time_label)
	_layout_standings(row, name_label, time_label)
	row.resized.connect(func() -> void: _layout_standings(row, name_label, time_label))


## Puts the value at the right edge of the row.
func _layout_value(row: Control, value_label: Label) -> void:
	var width := value_label.get_minimum_size().x
	value_label.position = Vector2(row.size.x - VALUE_MARGIN - width, 2)


## Puts the time at the right edge of the row; the name takes the room in between.
func _layout_standings(row: Control, name_label: Label, time_label: Label) -> void:
	var time_width := time_label.get_minimum_size().x
	time_label.position = Vector2(row.size.x - VALUE_MARGIN - time_width, 1)
	var name_width := maxf(row.size.x - RANK_WIDTH - VALUE_MARGIN - time_width - 12.0, 0.0)
	name_label.size = Vector2(name_width, 26)


func _add_buttons(mode: StringName, show_retry: bool) -> void:
	if show_retry:
		var again := MenuItem.new()
		again.set_text("重试", "RETRY", "")
		again.activated.connect(func() -> void: request_mode.emit(mode, payload.get("options", {})))
		list.add_row(again)

	var cont := MenuItem.new()
	cont.set_text("继续", "CONTINUE", "回到自由驾驶")
	cont.activated.connect(_continue)
	list.add_row(cont)

	var menu := MenuItem.new()
	menu.set_text("返回主菜单", "MAIN MENU", "")
	menu.activated.connect(func() -> void: request_main_menu.emit())
	list.add_row(menu)


## The racers are ordered by their position; the ones that did not finish come last.
func _by_position(a: Dictionary, b: Dictionary) -> bool:
	var finished_a := bool(a.get("finished", true))
	var finished_b := bool(b.get("finished", true))
	if finished_a != finished_b:
		return finished_a
	return int(a.get("position", 0)) < int(b.get("position", 0))

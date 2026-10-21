extends "res://ui/hud/glass_panel.gd"
## Top-left race panel: the big italic position ("1ST" / "第1名") and the racer list below it.
## The rank and the "/N" are drawn on ONE baseline; the player row gets a cyan pill.


const MAX_ROWS := 6
const RANK_SIZE := 96
const TOTAL_SIZE := 40
const ROW_SIZE := 28
const ROW_GAP := 4
const BADGE_SIZE := 28
const PLAYER_PILL := Color(0.0, 0.898, 1.0, 0.25)
const PANEL_WIDTH := 276.0
## The vertical layout of the panel.
const HEADER_OFFSET := 26.0
const RANK_HEIGHT := 88.0
const RANK_ZH_HEIGHT := 34.0
const CONTENT_GAP := 8.0
const PADDING := 14.0

var _rank_text: String = "1ST"
var _total_text: String = "/2"
var _zh_text: String = "第1名"
var _rows: VBoxContainer
var _row_labels: Array[Label] = []
var _row_badges: Array[PanelContainer] = []
var _row_marks: Array[Label] = []
var _row_bars: Array[HBoxContainer] = []
## The change detection: the player index, the number of cars and the instance ids.
var _last_player: int = -1
var _last_count: int = -1
var _last_ids: PackedInt64Array = PackedInt64Array()


func _ready() -> void:
	super._ready()
	cut = 18.0
	header = "RACE"
	custom_minimum_size = Vector2(PANEL_WIDTH, 240)
	size = custom_minimum_size
	_build()


func _build() -> void:
	_rows = UI.v_box(BoxContainer.ALIGNMENT_BEGIN, ROW_GAP)
	_rows.position = Vector2(16, HEADER_OFFSET + RANK_HEIGHT + RANK_ZH_HEIGHT + CONTENT_GAP)
	_rows.size = Vector2(PANEL_WIDTH - 32, 0)
	add_child(_rows)

	for i in MAX_ROWS:
		var row := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, 8)
		_rows.add_child(row)
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(badge)
		var mark := UI.display_label(str(i + 1), 20, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(mark)
		var name_label := UI.outlined_label("", ROW_SIZE - 6, Palette.TEXT)
		name_label.custom_minimum_size = Vector2(170, ROW_SIZE)
		row.add_child(name_label)
		_row_bars.append(row)
		_row_badges.append(badge)
		_row_marks.append(mark)
		_row_labels.append(name_label)


## standings: Array of {name, is_player, progress, id}, best first.
func set_standings(standings: Array[Dictionary]) -> void:
	var ids := PackedInt64Array()
	for s in standings:
		ids.append(int(s.get("id", 0)))
	var player_index := 0
	for i in standings.size():
		if bool(standings[i].get("is_player", false)):
			player_index = i
			break
	if player_index == _last_player and standings.size() == _last_count and ids == _last_ids:
		return
	_last_player = player_index
	_last_count = standings.size()
	_last_ids = ids

	var total := standings.size()
	_rank_text = _rank_text_for(player_index + 1)
	_total_text = "/%d" % total
	_zh_text = "第%d名" % (player_index + 1)

	for i in MAX_ROWS:
		var row := _row_bars[i]
		if i >= total:
			# The whole row is hidden: an empty badge must not hang outside the panel.
			row.visible = false
			continue
		row.visible = true
		var s: Dictionary = standings[i]
		var name_label := _row_labels[i]
		var mark := _row_marks[i]
		name_label.text = str(s.get("name", ""))
		mark.text = str(i + 1)
		var is_player := bool(s.get("is_player", false))
		name_label.add_theme_color_override("font_color",
			Palette.CYAN if is_player else Palette.TEXT)
		mark.add_theme_color_override("font_color",
			Palette.CYAN if is_player else Palette.TEXT_DIM)
		_row_badges[i].add_theme_stylebox_override("panel", _badge_style(is_player))
	_layout()
	queue_redraw()


## The panel grows with its content.
func _layout() -> void:
	var height := HEADER_OFFSET + RANK_HEIGHT + RANK_ZH_HEIGHT + CONTENT_GAP
	height += _last_count * (ROW_SIZE + ROW_GAP) + PADDING
	custom_minimum_size = Vector2(PANEL_WIDTH, height)
	size = custom_minimum_size
	_rows.size = Vector2(PANEL_WIDTH - 32, _last_count * (ROW_SIZE + ROW_GAP))


func _draw() -> void:
	super._draw()
	# The rank and the car count share one baseline.
	var font := UI.Fonts.display()
	var baseline := HEADER_OFFSET + RANK_HEIGHT - 12.0
	var rank_w := font.get_string_size(_rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_SIZE).x
	draw_string_outline(font, Vector2(16, baseline), _rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		RANK_SIZE, 5, Color(0.02, 0.024, 0.059, 0.9))
	draw_string(font, Vector2(16, baseline), _rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_SIZE,
		Palette.WHITE)
	var total_x := 16.0 + rank_w + 6.0
	draw_string_outline(font, Vector2(total_x, baseline), _total_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		TOTAL_SIZE, 4, Color(0.02, 0.024, 0.059, 0.9))
	draw_string(font, Vector2(total_x, baseline), _total_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		TOTAL_SIZE, Palette.TEXT_DIM)
	# The Chinese position under the rank.
	draw_string(UI.Fonts.text_bold(), Vector2(16, baseline + 30.0), _zh_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.CYAN)
	# The player row gets a full-width pill.
	if _last_player >= 0 and _last_player < _row_bars.size():
		var y := HEADER_OFFSET + RANK_HEIGHT + RANK_ZH_HEIGHT + CONTENT_GAP \
			+ float(_last_player) * (ROW_SIZE + ROW_GAP)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PLAYER_PILL
		sb.set_corner_radius_all(6)
		draw_style_box(sb, Rect2(10, y - 2.0, PANEL_WIDTH - 20.0, ROW_SIZE + 4.0))


## The position badge: a cyan pill for the player, a dark chip for the others.
func _badge_style(is_player: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLAYER_PILL if is_player else Color(1, 1, 1, 0.07)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.45 if is_player else 0.15)
	sb.set_border_width_all(1)
	return sb


func _rank_text_for(position: int) -> String:
	match position:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
		_:
			return "%dTH" % position

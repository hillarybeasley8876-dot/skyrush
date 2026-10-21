extends Control
## Centre pop-up stack. Up to three toasts are visible at once; the rest wait in a queue.
## Repeats are merged ("擦身而过 ×3") and queued items older than two seconds are dropped.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const ToastRow := preload("res://ui/hud/toast_row.gd")

const MAX_VISIBLE := 3
const MAX_PENDING := 4
## A repeated toast inside this window is merged into a counter (seconds).
const MERGE_WINDOW := 2.0
## A queued toast older than this is dropped (seconds).
const DROP_AGE := 2.0

var _box: VBoxContainer
var _queue: Array[Dictionary] = []
var _rows: Array[ToastRow] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_box = UI.v_box(BoxContainer.ALIGNMENT_CENTER, 2)
	_box.anchor_left = 0.0
	_box.anchor_right = 1.0
	_box.anchor_top = 0.24
	_box.anchor_bottom = 0.24
	_box.offset_bottom = 0.0
	_box.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_box)


## zh: the Chinese line; en: the small English sub-label; color: the accent colour;
## points: an optional "+800"; zh_size: the size of the Chinese line (the dossier §8.4 makes
## the near miss a small 40 px pop-up).
func push(zh: String, en: String = "", color: Color = Palette.TEXT, points: String = "",
		zh_size: int = 60, bar_color: Color = Color(0, 0, 0, 0)) -> void:
	if zh.strip_edges().is_empty():
		return
	# The merge key is the Chinese AND the English line: "通缉等级 ↑ HEAT 3" and
	# "通缉等级 ↑ HEAT 5" are different toasts.
	var key := zh + "|" + en
	# Merge into a visible toast with the same key.
	for row in _rows:
		if is_instance_valid(row) and row.is_valid() and row.merge_key() == key:
			row.add_count()
			row.set_content(zh, en, points)
			row.restart()
			return
	# Merge into a queued toast with the same key.
	var now := Time.get_ticks_msec() / 1000.0
	for item in _queue:
		if str(item["key"]) == key and now - float(item["born"]) < MERGE_WINDOW:
			item["count"] = int(item["count"]) + 1
			item["en"] = en
			item["points"] = points
			return
	if _queue.size() >= MAX_PENDING:
		_queue.pop_front()
	_queue.append({"zh": zh, "en": en, "key": key, "color": color, "points": points,
		"born": now, "count": 1, "zh_size": zh_size, "bar": bar_color})
	_pump()


func _pump() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while _box.get_child_count() < MAX_VISIBLE and not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		if now - float(item["born"]) > DROP_AGE:
			continue
		var row := ToastRow.new()
		_box.add_child(row)
		row.setup(str(item["zh"]), str(item["en"]), item["color"], str(item["points"]),
			int(item["zh_size"]), item["bar"])
		var count := int(item["count"])
		for i in range(count - 1):
			row.add_count()
		row.finished.connect(_on_row_finished)
		_rows.append(row)
		row.play()


func _on_row_finished() -> void:
	var alive: Array[ToastRow] = []
	for r in _rows:
		if is_instance_valid(r) and r.is_valid():
			alive.append(r)
	_rows = alive
	_pump()

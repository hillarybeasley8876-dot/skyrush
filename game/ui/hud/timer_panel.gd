extends "res://ui/hud/glass_panel.gd"
## Top-right timing panel: current time, best lap and the big lap counter ("1/2 圈数").
## The rows are hidden outside a race (free roam has no clock).


var _box: VBoxContainer
var _time: Label
var _best: Label
var _lap: Label
var _last_time: float = -1.0
var _last_best: float = -999.0
var _last_lap: int = -1
var _last_laps: int = -1
var _last_racing: bool = true


func _ready() -> void:
	super._ready()
	cut = 18.0
	header = "TIME"
	custom_minimum_size = Vector2(244, 160)
	size = custom_minimum_size
	_build()


func _build() -> void:
	_box = UI.v_box(BoxContainer.ALIGNMENT_END, 2)
	UI.place(_box, 0, 0, 1, 1, 18, 26, -18, -12)
	add_child(_box)

	_time = UI.outlined_display_label("时间 00'00\"00", 30, Palette.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_box.add_child(_time)
	_best = UI.outlined_label("最佳 --'--\"--", 21, Palette.TEXT_DIM, null, HORIZONTAL_ALIGNMENT_RIGHT)
	_box.add_child(_best)

	var row := UI.h_box(BoxContainer.ALIGNMENT_END, 8)
	_box.add_child(row)
	row.add_child(UI.outlined_label("圈", 26, Palette.TEXT_DIM, null, HORIZONTAL_ALIGNMENT_RIGHT))
	_lap = UI.outlined_display_label("1/2", 46, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_lap)


## current: race clock in seconds; best: best lap in seconds (-1 when unknown); lap: the current
## lap (1-based); laps: the total laps; racing: false hides the rows (free roam).
func update_values(current: float, best: float, lap: int, laps: int, racing: bool) -> void:
	if is_equal_approx(current, _last_time) and is_equal_approx(best, _last_best) \
			and lap == _last_lap and laps == _last_laps and racing == _last_racing:
		return
	_last_time = current
	_last_best = best
	_last_lap = lap
	_last_laps = laps
	_last_racing = racing
	_box.visible = racing
	if not racing:
		return
	_time.text = "时间 " + format_time(current)
	_best.text = "最佳 " + (format_time(best) if best >= 0.0 else "--'--\"--")
	_lap.text = "%d/%d" % [maxi(lap, 1), maxi(laps, 1)]


## QQ style: mm'ss"cc — the centiseconds are floored, never rounded up, so the clock never steps
## backwards. The epsilon absorbs the float representation error (27.74 * 100 is 2773.9999...).
static func format_time(seconds: float) -> String:
	var total_cs := int(floor(maxf(seconds, 0.0) * 100.0 + 1e-6))
	var m := total_cs / 6000
	var sec := (total_cs / 100) % 60
	var cs := total_cs % 100
	return "%02d'%02d\"%02d" % [m, sec, cs]

extends Control
## The mode status readout: the free-roam score, the takedown goal of a pursuit and its
## countdown. The HUD only draws what the bus says (`Events.mode_status`); the modes unit owns
## the truth, the HUD never reads the mode session.
##
## The rows sit in the left column of the HUD: the score where the race / pursuit panel stands
## (both of them are hidden in free roam) and the pursuit readouts under the pursuit panel.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

## The caption of every readout (the English sub-label of the HUD).
const SCORE_CAPTION := "SCORE"
const GOAL_CAPTION := "TAKEDOWNS"
const TIME_CAPTION := "TIME"
const CAPTION_SIZE := 20
const VALUE_SIZE := 30
## The gap between the caption and the value.
const GAP := 12
## The place of the readouts in the HUD: the score in the middle of the top row (nothing else is
## drawn there, in any mode) and the pursuit readouts under the pursuit panel (the left column).
const SCORE_TOP := 36.0
const LEFT := 40.0
const GOAL_TOP := 226.0
const TIME_TOP := 264.0

var _score_row: HBoxContainer
var _score: Label
var _goal_row: HBoxContainer
var _goal: Label
var _time_row: HBoxContainer
var _time: Label
## The change detection: a readout is only written when its data changed.
var _last_score: int = -1
var _last_goal: String = ""
var _last_time: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_row = _row(SCORE_CAPTION)
	_score = _value("ScoreLabel", Palette.CYAN)
	_score_row.add_child(_score)
	# The score sits in the middle of the top row: the race panel is on the left, the clock and
	# the map on the right, so nothing can collide with it.
	_score_row.anchor_left = 0.5
	_score_row.anchor_right = 0.5
	_score_row.offset_left = 0.0
	_score_row.offset_right = 0.0
	_score_row.offset_top = SCORE_TOP
	_score_row.offset_bottom = SCORE_TOP
	_score_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_score_row)

	_goal_row = _row(GOAL_CAPTION)
	_goal = _value("GoalLabel", Palette.AMBER)
	_goal_row.add_child(_goal)
	_place_left(_goal_row, GOAL_TOP)
	add_child(_goal_row)

	_time_row = _row(TIME_CAPTION)
	_time = _value("TimeLabel", Palette.RED)
	_time_row.add_child(_time)
	_place_left(_time_row, TIME_TOP)
	add_child(_time_row)

	# Nothing of a mode is shown before the bus says what is going on.
	_score_row.visible = false
	_goal_row.visible = false
	_time_row.visible = false


## A caption and the value that belongs to it.
func _row(caption: String) -> HBoxContainer:
	var row := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, GAP)
	var cap := UI.outlined_label(caption, CAPTION_SIZE, Palette.TEXT_DIM)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	return row


## A row in the left column of the HUD, under the panels.
func _place_left(row: Control, top: float) -> void:
	row.anchor_left = 0.0
	row.anchor_right = 0.0
	row.anchor_top = 0.0
	row.anchor_bottom = 0.0
	row.offset_left = LEFT
	row.offset_right = LEFT
	row.offset_top = top
	row.offset_bottom = top


## The value of a readout (the node name is the contract of the test).
func _value(node_name: String, color: Color) -> Label:
	var label := UI.outlined_display_label("0", VALUE_SIZE, color)
	label.name = node_name
	return label


## The state of the running mode: &"free" (the score), &"race" (nothing here) and &"pursuit"
## (the takedown goal and the countdown). Everything else hides the readouts.
func set_status(kind: StringName, data: Dictionary) -> void:
	_score_row.visible = kind == &"free"
	_goal_row.visible = kind == &"pursuit"
	_time_row.visible = false
	match kind:
		&"free":
			_set_score(int(data.get("score", 0)))
		&"pursuit":
			_set_goal(int(data.get("takedowns", 0)), int(data.get("target", 0)))
			_set_time(float(data.get("time_left", -1.0)))


func _set_score(score: int) -> void:
	var value := maxi(score, 0)
	if value == _last_score:
		return
	_last_score = value
	_score.text = str(value)


## The takedowns of the player and the goal of the mode (no goal: the row is gone).
func _set_goal(takedowns: int, target: int) -> void:
	_goal_row.visible = target > 0
	if target <= 0:
		return
	var text := "%d / %d" % [maxi(takedowns, 0), target]
	if text == _last_goal:
		return
	_last_goal = text
	_goal.text = text


## The seconds left (no limit: the row is gone).
func _set_time(seconds: float) -> void:
	_time_row.visible = seconds >= 0.0
	if seconds < 0.0:
		return
	var text := format_countdown(seconds)
	if text == _last_time:
		return
	_last_time = text
	_time.text = text


## The seconds left as mm:ss. The clock never shows a negative time.
static func format_countdown(seconds: float) -> String:
	var total := int(floor(maxf(seconds, 0.0)))
	return "%02d:%02d" % [floori(float(total) / 60.0), total % 60]

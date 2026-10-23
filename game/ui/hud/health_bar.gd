extends Control
## The health of the car: a thin bar with the caption "HP" and the number of the health
## (dossier §7.3: the health is HP out of 100).
##
## The fill turns green above 60 %, amber from 25 % to 60 % and red below 25 %. The number is
## written only when the whole percent changes, so a draining health does not rewrite the label
## every frame. The bar is hidden while the car is wrecked (health 0) and in the menu.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

## The caption of the bar.
const CAPTION := "HP"
## The colour thresholds (whole percent).
const GREEN_ABOVE := 60
const AMBER_ABOVE := 25
## The height of the bar, the width of the caption and of the number.
const BAR_HEIGHT := 10.0
const CAPTION_WIDTH := 36.0
const VALUE_WIDTH := 40.0
const SIZE := Vector2(220.0, 28.0)

var _caption: Label
var _value: Label
var _last_pct: int = -1
## The state of the bar (the test reads it).
var _ratio: float = 0.0
var _fill_color: Color = Palette.GREEN
## How often the number was written (the test counts the writes).
var text_writes: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	_caption = UI.outlined_label(CAPTION, 18, Palette.TEXT_DIM)
	UI.place(_caption, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, CAPTION_WIDTH, 0.0)
	add_child(_caption)
	_value = UI.outlined_display_label("0", 20, Palette.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	UI.place(_value, 1.0, 0.0, 1.0, 1.0, -VALUE_WIDTH, 0.0, 0.0, 0.0)
	add_child(_value)


## The health of the car (0..1). The number is written only when the whole percent changes.
func set_health(norm: float) -> void:
	var value := clampf(norm, 0.0, 1.0)
	var pct := int(round(value * 100.0))
	# A wrecked car has no health to show, and the menu shows no HUD at all.
	visible = pct > 0 and Game.mode != &"menu"
	if _value == null or pct == _last_pct:
		return
	_last_pct = pct
	_ratio = value
	_fill_color = _color_for(pct)
	_value.text = str(pct)
	_value.add_theme_color_override("font_color", _fill_color)
	text_writes += 1
	queue_redraw()


## The colour of the fill: green, amber or red.
func _color_for(pct: int) -> Color:
	if pct > GREEN_ABOVE:
		return Palette.GREEN
	if pct >= AMBER_ABOVE:
		return Palette.AMBER
	return Palette.RED


## The track of the bar and the fill of the health.
func _draw() -> void:
	var left := CAPTION_WIDTH
	var right := maxf(size.x - VALUE_WIDTH - 8.0, left + 1.0)
	var bar := Rect2(left, (size.y - BAR_HEIGHT) * 0.5, right - left, BAR_HEIGHT)
	draw_rect(bar.grow(1.0), Color(0.02, 0.024, 0.059, 0.8))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	if _ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _ratio, bar.size.y)), _fill_color)

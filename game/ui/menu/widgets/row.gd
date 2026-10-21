extends Control
## The base of every row in a menu list.
##
## A row is either a menu item (an action) or a settings row (a value that is changed with left /
## right). The list only needs these calls, so both kinds can live in the same list.
##
## The row owns the focus treatment: the film brightens, a cyan bar wipes in, a ▶ chevron
## appears, the title slides 10 px to the right and the sub-label turns cyan. The unselected rows
## sit at 75 % alpha; a disabled row is dimmed further (it still shows its own text, only dim).
##
## A row is *not* glass: it is a flat film over the panel. A row that sampled the screen would
## replace the panel's see-through with its own copy of the scene and hide it.

## The row was activated (Enter, A or a click).
signal activated

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")

const UNSELECTED_ALPHA := 0.75
## The extra dim of a disabled row (on top of the focus alpha).
const DISABLED_ALPHA := 0.45
## How long the focus highlight takes to wipe in / out.
const FOCUS_TIME := 0.12
## How far the title slides when the row is focused.
const TITLE_SLIDE := 10.0
## The size of the ▶ chevron (drawn, so it does not depend on the font).
const CHEVRON_SIZE := 9.0
## The film of a row: a flat tint, never the screen texture.
const FILM := Color(1.0, 1.0, 1.0, 0.035)
## The film of the focused row.
const FILM_FOCUSED := Color(0.098, 0.898, 1.0, 0.10)
## The cyan bar that wipes in from the left edge.
const BAR_WIDTH := 26.0
const BAR_ALPHA := 0.9
const BAR_STEPS := 8

var title_label: Label
var sub_label: Label
## The row is the highlighted one.
var selected: bool = false
## A picked row keeps its bar lit even when the cursor moves on.
var picked: bool = false
## A disabled row is dim and does not react.
var enabled: bool = true

var _focus: float = 0.0
## The x of the title when the row is not focused (the subclass sets it).
var title_x: float = 0.0
## Where the ▶ chevron is drawn (the subclass sets it).
var chevron_position: Vector2 = Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = UI.display_label("", 26, Palette.TEXT)
	add_child(title_label)

	sub_label = UI.label("", 14, Palette.TEXT_DIM, Fonts.text())
	add_child(sub_label)


## Highlights (or un-highlights) the row.
func set_selected(value: bool) -> void:
	selected = value


## Marks the row as picked (it keeps its cyan bar).
func set_picked(value: bool) -> void:
	picked = value
	_apply_focus()


## Dims the row and stops it from reacting.
func set_enabled(value: bool) -> void:
	enabled = value
	_apply_focus()


## The text of the row (a menu item: the title, the sub-label and the value).
func set_text(_title: String, _subtitle: String, _value: String) -> void:
	pass


## The value of the row.
func set_value(_value: String) -> void:
	pass


## Left / right on the row. Return true when the value changed.
func adjust(_direction: int) -> bool:
	return false


## Accept on the row. Return true when the row did something.
func activate() -> bool:
	activated.emit()
	return true


func _process(delta: float) -> void:
	var target := 1.0 if selected else 0.0
	if is_equal_approx(_focus, target):
		return
	_focus = move_toward(_focus, target, delta / FOCUS_TIME)
	_apply_focus()


## The film, the focus bar and the ▶ chevron of the row.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FILM_FOCUSED if _focus > 0.5 else FILM)
	_draw_bar()
	_draw_chevron()


## The cyan bar that wipes in from the left edge of the row.
func _draw_bar() -> void:
	var amount := maxf(_focus, 1.0 if picked else 0.0)
	if amount <= 0.01:
		return
	for i in BAR_STEPS:
		var t0 := float(i) / float(BAR_STEPS)
		var t1 := float(i + 1) / float(BAR_STEPS)
		var alpha := pow(1.0 - t0, 1.5) * amount * BAR_ALPHA
		draw_rect(Rect2(t0 * BAR_WIDTH, 0.0, (t1 - t0) * BAR_WIDTH, size.y),
				Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, alpha))


## The ▶ chevron of the focused row.
func _draw_chevron() -> void:
	if _focus <= 0.01:
		return
	var centre := chevron_position + Vector2(CHEVRON_SIZE * 0.5, CHEVRON_SIZE * 0.5)
	var half := CHEVRON_SIZE * 0.5
	var colour := Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, _focus)
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(-half * 0.6, -half),
		centre + Vector2(half * 0.6, 0.0),
		centre + Vector2(-half * 0.6, half)]), colour)


## The focus treatment: the alpha, the title slide, the cyan sub-label and the bar.
func _apply_focus() -> void:
	var dim := 1.0 if enabled else DISABLED_ALPHA
	modulate.a = lerpf(UNSELECTED_ALPHA, 1.0, _focus) * dim
	title_label.position.x = title_x + TITLE_SLIDE * _focus
	sub_label.add_theme_color_override("font_color", Palette.TEXT_DIM.lerp(Palette.CYAN, _focus))
	queue_redraw()

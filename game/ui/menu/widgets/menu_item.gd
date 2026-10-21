extends "res://ui/menu/widgets/row.gd"
## One row of a menu list: a Chinese title, an English sub-label and a value on the right.
##
## The film, the focus bar and the ▶ chevron come from `row.gd`.

const ROW_HEIGHT := 60.0
const TITLE_SIZE := 30
const SUB_SIZE := 15
const VALUE_SIZE := 24
const TEXT_X := 34.0
const CHEVRON_X := 10.0
## The mark on a picked row (a race route that was chosen with Enter).
const PICKED_TEXT := "已选"
## The size of the ✓ mark of a picked row (drawn, so it does not depend on the font).
const CHECK_SIZE := 9.0

var value_label: Label


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	sub_label.add_theme_font_size_override("font_size", SUB_SIZE)
	value_label = UI.display_label("", VALUE_SIZE, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(value_label)
	gui_input.connect(_on_gui_input)
	resized.connect(_layout)


## Sets the three text fields of the row.
func set_text(title: String, subtitle: String, value: String = "") -> void:
	title_label.text = title
	sub_label.text = subtitle
	value_label.text = value
	_layout()


func set_value(value: String) -> void:
	value_label.text = value
	_layout()


## The film, the focus bar and the ▶ chevron come from `row.gd`; the ✓ of a picked row is
## drawn here.
func _draw() -> void:
	super._draw()
	if not picked:
		return
	# The ✓ of a picked row, drawn next to the value.
	var centre := Vector2(size.x - 24.0 - value_label.get_minimum_size().x, size.y * 0.5)
	var half := CHECK_SIZE * 0.5
	var colour := Palette.CYAN
	draw_polyline(PackedVector2Array([
		centre + Vector2(-half, 0.0),
		centre + Vector2(-half * 0.25, half * 0.7),
		centre + Vector2(half, -half * 0.8)]), colour, 2.0, true)


func _layout() -> void:
	var top := maxf((size.y - ROW_HEIGHT) * 0.5, 0.0)
	chevron_position = Vector2(CHEVRON_X, top + 16.0)
	title_x = TEXT_X
	title_label.position = Vector2(title_x, top - 2.0)
	sub_label.position = Vector2(title_x, top + 36.0)
	value_label.position = Vector2(size.x - 20.0 - value_label.get_minimum_size().x, top + 12.0)
	_apply_focus()


func _on_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		activate()

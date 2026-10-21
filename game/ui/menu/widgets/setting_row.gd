extends "res://ui/menu/widgets/row.gd"
## Base for a settings row: a title on the left, a value widget on the right.
##
## Subclasses (choice_row.gd, slider_row.gd) implement `adjust()` (left / right) and `activate()`
## (accept). Both are optional: a row that handles nothing simply returns false.
##
## The film, the focus bar and the ▶ chevron come from `row.gd`.

const ROW_HEIGHT := 60.0
const TITLE_SIZE := 24
const SUB_SIZE := 14
const VALUE_SIZE := 24
const TEXT_X := 30.0
## The x of the ▶ chevron (it sits on the cyan bar, so it needs room).
const CHEVRON_X := 10.0
const VALUE_MARGIN := 18.0
## The gap between the value text and the arrow next to it.
const ARROW_GAP := 8.0
## The width of the ◀ ▶ arrow.
const ARROW_WIDTH := 6.0
## The half height of the ◀ ▶ arrow.
const ARROW_HALF := 5.0
## The room the two arrows need next to the value.
const ARROW_SPACE := 2.0 * (ARROW_GAP + ARROW_WIDTH)

var value_area: HBoxContainer
var value_label: Label
## The row shows the ◀ value ▶ arrows (the value can be changed with left / right).
var show_arrows: bool = false


func _init(title: String, subtitle: String = "") -> void:
	super()
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	sub_label.add_theme_font_size_override("font_size", SUB_SIZE)
	title_label.text = title
	sub_label.text = subtitle

	value_area = UI.h_box(BoxContainer.ALIGNMENT_END, 12)
	add_child(value_area)

	value_label = UI.display_label("", VALUE_SIZE, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	value_area.add_child(value_label)

	resized.connect(_layout)
	_layout()


func set_value(value: String) -> void:
	value_label.text = value
	_layout()


## The film, the focus bar and the ▶ chevron come from `row.gd`; the ◀ ▶ arrows are drawn here.
func _draw() -> void:
	super._draw()
	if not show_arrows:
		return
	# The left arrow ends ARROW_GAP before the text, the right one starts ARROW_GAP after it.
	var text_left := value_area.position.x + value_label.position.x
	var text_right := text_left + value_label.get_minimum_size().x
	var middle := value_area.position.y + value_label.position.y \
			+ value_label.get_minimum_size().y * 0.5
	_draw_left_arrow(Vector2(text_left - ARROW_GAP, middle))
	_draw_right_arrow(Vector2(text_right + ARROW_GAP, middle))


## The ◀ arrow: its tip points at the text.
func _draw_left_arrow(tip: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(ARROW_WIDTH, -ARROW_HALF),
		tip + Vector2(ARROW_WIDTH, ARROW_HALF)]), Palette.CYAN)


## The ▶ arrow: its tip points at the text.
func _draw_right_arrow(tip: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-ARROW_WIDTH, -ARROW_HALF),
		tip + Vector2(-ARROW_WIDTH, ARROW_HALF)]), Palette.CYAN)


func _layout() -> void:
	var top := maxf((size.y - ROW_HEIGHT) * 0.5, 0.0)
	title_x = TEXT_X
	chevron_position = Vector2(CHEVRON_X, top + 16.0)
	title_label.position = Vector2(title_x, top - 2.0)
	sub_label.position = Vector2(title_x, top + 30.0)
	var value_size := value_area.get_combined_minimum_size()
	var arrow_space := ARROW_SPACE if show_arrows else 0.0
	value_area.position = Vector2(size.x - VALUE_MARGIN - value_size.x - arrow_space,
			top + (ROW_HEIGHT - value_size.y) * 0.5)
	_apply_focus()
	queue_redraw()

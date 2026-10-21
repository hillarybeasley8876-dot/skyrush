extends VBoxContainer
## A list of rows that can be plain menu items (an action) or settings rows (a value that is
## adjusted with left / right).
##
## Rows are any `row.gd` (a menu item or a settings row): the list only moves the highlight and
## forwards the actions, so both kinds can live in the same list.

signal selection_changed(index: int)
## A row was activated (Enter, A or a click).
signal item_activated(index: int)

const Row := preload("res://ui/menu/widgets/row.gd")
const MenuItem := preload("res://ui/menu/widgets/menu_item.gd")

var rows: Array[Row] = []
var selected_index: int = 0


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_row(row: Row) -> Row:
	rows.append(row)
	add_child(row)
	row.activated.connect(_on_row_activated.bind(rows.size() - 1))
	_refresh()
	return row


## Appends a menu item (a title, a sub-label and a value).
func add_item(title: String, subtitle: String = "", value: String = "") -> MenuItem:
	var item := MenuItem.new()
	item.set_text(title, subtitle, value)
	add_row(item)
	return item


func clear_rows() -> void:
	for row in rows:
		row.queue_free()
	rows.clear()
	selected_index = 0


## The row at an index.
func get_item(index: int) -> Row:
	if index < 0 or index >= rows.size():
		return null
	return rows[index]


func get_selected() -> Row:
	return get_item(selected_index)


func get_selected_index() -> int:
	return selected_index


func move_selection(delta: int) -> bool:
	if rows.is_empty():
		return false
	var next := clampi(selected_index + delta, 0, rows.size() - 1)
	if next == selected_index:
		return false
	selected_index = next
	_refresh()
	selection_changed.emit(selected_index)
	return true


func select(index: int) -> void:
	if rows.is_empty():
		return
	var changed := selected_index != clampi(index, 0, rows.size() - 1)
	selected_index = clampi(index, 0, rows.size() - 1)
	_refresh()
	if changed:
		selection_changed.emit(selected_index)


## Left / right on the highlighted row. Returns true when the value changed.
func adjust_selected(direction: int) -> bool:
	var row := get_selected()
	if row == null:
		return false
	return row.adjust(direction)


## Accept on the highlighted row. Returns true when the row did something.
func activate_selected() -> bool:
	var row := get_selected()
	if row == null:
		return false
	return row.activate()


func _on_row_activated(index: int) -> void:
	select(index)
	item_activated.emit(index)


func _refresh() -> void:
	for i in rows.size():
		rows[i].set_selected(i == selected_index)

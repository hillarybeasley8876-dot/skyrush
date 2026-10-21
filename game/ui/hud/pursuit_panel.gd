extends "res://ui/hud/glass_panel.gd"
## Top-left pursuit panel: heat pips, the number of police units on you and the MW05-style
## evade/busted bar (fills right = green/blue evading, left = red busted).
##
## The bar is a child control of its own, so a moving bar only redraws the bar: the glass panel
## is not repainted every frame.

const HeatPips := preload("res://ui/hud/heat_pips.gd")

const BAR_WIDTH := 236.0
const BAR_HEIGHT := 14.0


## The evade / busted bar. It lives in its own control, so the panel above it is not redrawn
## while the bar moves.
class EvadeBar extends Control:
	const Palette := preload("res://ui/theme/skyrush_palette.gd")
	var evade: float = 0.0
	var busted: float = 0.0
	var state: StringName = &""

	func set_values(evade_value: float, busted_value: float, pursuit_state: StringName) -> void:
		if is_equal_approx(evade_value, evade) and is_equal_approx(busted_value, busted) \
				and pursuit_state == state:
			return
		evade = evade_value
		busted = busted_value
		state = pursuit_state
		queue_redraw()

	func _draw() -> void:
		var track := Rect2(Vector2.ZERO, size)
		draw_rect(track, Color(0.02, 0.024, 0.059, 0.8))
		draw_rect(track, Color(1, 1, 1, 0.18), false, 1.0)
		var mid := track.size.x * 0.5
		draw_line(Vector2(mid, -2.0), Vector2(mid, track.size.y + 2.0),
			Color(1, 1, 1, 0.35), 1.0, true)
		if busted > 0.001:
			var w := track.size.x * 0.5 * busted
			draw_rect(Rect2(Vector2(mid - w, 0.0), Vector2(w, track.size.y)), Palette.RED)
		if evade > 0.001:
			var col := Palette.POLICE_BLUE if state == &"cooldown" or state == &"search" else Palette.GREEN
			var w2 := track.size.x * 0.5 * evade
			draw_rect(Rect2(Vector2(mid, 0.0), Vector2(w2, track.size.y)), col)


var _pips: HeatPips
var _units: Label
var _status: Label
var _bar: EvadeBar
var _last_heat: int = -1
var _last_units: int = -1
var _last_max: int = -1
var _last_state: StringName = &""


func _ready() -> void:
	super._ready()
	cut = 18.0
	header = "PURSUIT"
	custom_minimum_size = Vector2(276, 176)
	size = custom_minimum_size
	_build()


func _build() -> void:
	var box := UI.v_box(BoxContainer.ALIGNMENT_BEGIN, 6)
	UI.place(box, 0, 0, 1, 1, 18, 28, -18, -52)
	add_child(box)

	var head := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, 10)
	box.add_child(head)
	var title := UI.outlined_label("通缉", 26, Palette.RED)
	title.custom_minimum_size = Vector2(64, 28)
	head.add_child(title)
	_pips = HeatPips.new()
	_pips.custom_minimum_size = Vector2(120, 20)
	_pips.size = Vector2(120, 20)
	head.add_child(_pips)

	_units = UI.outlined_label("警力 0/12", 21, Palette.TEXT_DIM)
	box.add_child(_units)

	_status = UI.outlined_label("追捕中 PURSUIT", 24, Palette.RED)
	box.add_child(_status)

	_bar = EvadeBar.new()
	_bar.position = Vector2((size.x - BAR_WIDTH) * 0.5, size.y - 26.0)
	_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)


## heat: 0..5; units: engaged units; units_max: allowed units for this heat; state: pursuit state
## StringName; evade: 0..1 cooldown progress; busted: 0..1 busted meter.
func update_values(heat: int, units: int, units_max: int, state: StringName, evade: float,
		busted: float) -> void:
	_pips.set_level(heat)
	if heat != _last_heat or units != _last_units or units_max != _last_max or state != _last_state:
		_last_heat = heat
		_last_units = units
		_last_max = units_max
		_last_state = state
		_units.text = "警力 %d/%d  UNITS" % [units, units_max]
		var text := "追捕中 PURSUIT"
		var col := Palette.RED
		match state:
			&"search", &"cooldown":
				text = "甩开警察 EVADING…"
				col = Palette.POLICE_BLUE
			&"escaped":
				text = "成功逃脱！ ESCAPED"
				col = Palette.GREEN
			&"busted":
				text = "被捕 BUSTED"
				col = Palette.RED
			&"none":
				text = "追捕中 PURSUIT"
				col = Palette.RED
		_status.text = text
		_status.add_theme_color_override("font_color", col)
	# The bar redraws itself, so the glass panel above it is untouched.
	_bar.set_values(clampf(evade, 0.0, 1.0), clampf(busted, 0.0, 1.0), state)

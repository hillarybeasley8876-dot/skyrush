extends "res://ui/hud/glass_panel.gd"
## Bottom-left N2 cluster on a glass plate: the two COPV slots, the 小喷 mini-boost prompt with
## its timing bar and the Big Hop charge ring.

const N2Slot := preload("res://ui/hud/n2_slot.gd")
const HopRing := preload("res://ui/hud/hop_ring.gd")

const MINI_WINDOW_TIME := 0.50   ## dossier §5.2 / §1.4: the 小喷 window is 0.50 s.
const SLOT_SIZE := Vector2(44, 132)

var _slots: Array[N2Slot] = []
var _count_label: Label
var _prompt: Label
var _prompt_bar_bg: ColorRect
var _prompt_bar: ColorRect
var _ring: HopRing

var _mini_open: bool = false
var _mini_start_ms: int = 0
## The flight layout hides the 小喷 prompt row.
var _prompt_allowed: bool = true
var _last_count: int = -1


func _ready() -> void:
	super._ready()
	cut = 10.0
	custom_minimum_size = Vector2(210, 244)
	size = custom_minimum_size
	_build()


func _build() -> void:
	var title := UI.display_label("N", 30, Palette.CYAN)
	title.size = Vector2(24, 34)
	title.position = Vector2(16, 8)
	add_child(title)
	# The subscript is drawn as a separate, smaller "2" (the ₂ glyph falls back to a tiny glyph).
	var sub := UI.display_label("2", 19, Palette.CYAN)
	sub.size = Vector2(14, 24)
	sub.position = Vector2(38, 16)
	add_child(sub)

	_count_label = UI.outlined_display_label("0", 28, Palette.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label.size = Vector2(70, 32)
	_count_label.position = Vector2(122, 8)
	add_child(_count_label)

	for i in 2:
		var slot := N2Slot.new()
		slot.position = Vector2(18.0 + float(i) * (SLOT_SIZE.x + 12.0), 46)
		add_child(slot)
		_slots.append(slot)

	_ring = HopRing.new()
	_ring.position = Vector2(124, 74)
	add_child(_ring)

	_prompt = UI.outlined_label("小喷!", 34, Palette.AMBER, null, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.size = Vector2(210, 42)
	_prompt.position = Vector2(0, 184)
	_prompt.visible = false
	add_child(_prompt)

	_prompt_bar_bg = ColorRect.new()
	_prompt_bar_bg.color = Color(0.02, 0.024, 0.059, 0.8)
	_prompt_bar_bg.size = Vector2(152, 8)
	_prompt_bar_bg.position = Vector2(28, 230)
	_prompt_bar_bg.visible = false
	_prompt_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_bar_bg)

	_prompt_bar = ColorRect.new()
	_prompt_bar.color = Palette.AMBER
	_prompt_bar.size = Vector2(152, 4)
	_prompt_bar.position = Vector2(29, 232)
	_prompt_bar.visible = false
	_prompt_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_bar)


## Hide the 小喷 prompt row (the flight layout hides it: the window is a ground trick).
func set_prompt_visible(visible: bool) -> void:
	_prompt_allowed = visible
	_prompt.visible = visible and _mini_open
	_prompt_bar_bg.visible = visible and _mini_open
	_prompt_bar.visible = visible and _mini_open


## n2: 0..200 total; pending: uncommitted drift gain 0..100; mini_window: 小喷 window open;
## hop_charge: 0..1.
func update_values(n2: float, pending: float, mini_window: bool, hop_charge: float) -> void:
	var slot0 := clampf(n2, 0.0, 100.0)
	var slot1 := clampf(n2 - 100.0, 0.0, 100.0)
	# The pending gain of the running drift rides on the slot that is currently filling; what does
	# not fit there overflows into the next slot.
	var pending0 := 0.0
	var pending1 := 0.0
	if pending > 0.0:
		pending0 = minf(pending, 100.0 - slot0)
		pending1 = pending - pending0
	_slots[0].set_values(slot0, pending0)
	_slots[1].set_values(slot1, pending1)

	var count := int(round(n2))
	if count != _last_count:
		_last_count = count
		_count_label.text = str(count)

	_ring.set_charge(hop_charge)
	_ring.visible = hop_charge > 0.001

	_update_mini(mini_window)


func _update_mini(open: bool) -> void:
	if open and not _mini_open:
		_mini_start_ms = Time.get_ticks_msec()
	_mini_open = open
	_prompt.visible = open and _prompt_allowed
	_prompt_bar_bg.visible = open and _prompt_allowed
	_prompt_bar.visible = open and _prompt_allowed
	if not open:
		return
	var elapsed := float(Time.get_ticks_msec() - _mini_start_ms) / 1000.0
	var left := clampf(1.0 - elapsed / MINI_WINDOW_TIME, 0.0, 1.0)
	_prompt_bar.size = Vector2(152.0 * left, 4)
	_prompt.modulate = Color(1, 1, 1, 1) if left > 0.25 else Color(1, 1, 1, 0.6 + 0.4 * left)

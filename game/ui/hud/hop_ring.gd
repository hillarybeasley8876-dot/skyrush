extends Control
## Big Hop charge ring: fills clockwise from the top while the hop key is held.
##
## `CarTelemetry.hop_charge` is already normalised against the Big Hop hold time
## (vehicle/modules/thruster.gd: hop_charge = hold / Tuning.HOP_CHARGE_TIME, 0.25 s), so the ring
## is only "armed" - the full Big Hop - at charge >= 1.0. Below that the car would only do a small
## hop, so the ring stays grey.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

const ARMED_CHARGE := 1.0
const RING_SIZE := Vector2(64, 64)
## The armed pulse needs a redraw even when the charge does not change.
const PULSE_SPEED := 0.012
const PULSE_PERIOD := 1.0 / 20.0

var charge: float = 0.0
var _last_charge: float = -1.0
var _pulse_accum: float = 0.0

## True only at the full Big Hop hold.
var armed: bool:
	get:
		return charge >= ARMED_CHARGE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = RING_SIZE


func set_charge(value: float) -> void:
	if is_equal_approx(value, _last_charge):
		return
	_last_charge = value
	charge = clampf(value, 0.0, 1.0)
	queue_redraw()


## The armed pulse animates, so the ring is redrawn 20 times a second while it is armed.
func _process(delta: float) -> void:
	if not armed:
		_pulse_accum = 0.0
		return
	_pulse_accum += delta
	if _pulse_accum >= PULSE_PERIOD:
		_pulse_accum = 0.0
		queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 5.0
	if r <= 2.0:
		return
	draw_texture_rect(UI.backing_texture(),
		Rect2(centre - Vector2(r + 6, r + 6), Vector2((r + 6) * 2, (r + 6) * 2)), false)
	var armed := charge >= ARMED_CHARGE
	draw_arc(centre, r, 0.0, TAU, 32, Color(1, 1, 1, 0.16), 4.0, true)
	var col := Palette.AMBER if armed else Color(1, 1, 1, 0.35)
	if armed:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * PULSE_SPEED)
		col = col.lerp(Palette.WHITE, 0.35 * pulse)
		draw_arc(centre, r - 6.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.22), 2.0, true)
	if charge > 0.001:
		draw_arc(centre, r, -PI * 0.5, -PI * 0.5 + TAU * charge, 32, col, 5.0, true)
	var font := UI.Fonts.text_bold()
	var text := "大跳" if armed else "跳"
	var size_px := 20 if armed else 18
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string_outline(font, centre + Vector2(-ts.x * 0.5, ts.y * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color(0.02, 0.024, 0.059, 0.9))
	draw_string(font, centre + Vector2(-ts.x * 0.5, ts.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size_px, Color(1, 1, 1, 0.92))

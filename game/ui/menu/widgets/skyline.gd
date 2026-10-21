extends Control
## The skyline of the loading screen: the Lujiazui silhouette (东方明珠, 上海中心, 环球金融中心,
## 金茂) over the Huangpu, the Bund roofline in front of it and a perspective grid on the
## ground.
##
## Everything is drawn in code (no texture): the grid scrolls, the neon signs flicker at ≤ 15 Hz
## and the river reflects the skyline. The values follow ART §3: the sky is #05060F, the masses
## are #0B1024–#141A2E and the landmarks are the brightest thing after the logo.

const Lujiazui := preload("res://ui/menu/widgets/skyline_lujiazui.gd")
const Bund := preload("res://ui/menu/widgets/skyline_bund.gd")
const River := preload("res://ui/menu/widgets/skyline_river.gd")

## The sky.
const SKY_ZENITH := Color("05060f")
const SKY_HORIZON := Color("1a1033")
const HORIZON_GLOW := Color("5a1f4f")
const CITY_ORANGE := Color("ff6a3d")
## The ground.
const GROUND := Color("04060f")
const GRID_LINE := Color(0.10, 0.45, 0.65, 0.10)

## The bands of the picture, as a fraction of the height.
const HORIZON := 0.58
const RIVER_BOTTOM := 0.70
const BUND_BOTTOM := 0.84
## The neon flicker rate (the art bible: nothing faster than 15 Hz).
const FLICKER_HZ := 9.0
## How fast the ground grid scrolls.
const GRID_SPEED := 0.12
## The number of the sky bands.
const SKY_BANDS := 14

var _lujiazui: Lujiazui
var _bund: Bund
var _river: River
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lujiazui = Lujiazui.new()
	_bund = Bund.new()
	_river = River.new()
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	# The wall clock: the world is built at a few frames per second, and a delta driven
	# animation would crawl.
	_time = float(Time.get_ticks_usec()) * 0.000001
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var horizon := h * HORIZON
	# The sky is opaque: the loading screen never shows the world through it.
	draw_rect(Rect2(0.0, 0.0, w, h), SKY_ZENITH)
	_draw_sky(w, horizon)
	_lujiazui.draw(self, Rect2(0.0, 0.0, w, horizon), _time, _sky_at(horizon))
	_river.draw(self, Rect2(0.0, horizon, w, h * RIVER_BOTTOM - horizon), _reflections(), _time)
	_bund.draw(self, Rect2(0.0, h * RIVER_BOTTOM, w, h * BUND_BOTTOM - h * RIVER_BOTTOM))
	_draw_grid(w, h * BUND_BOTTOM, h)


## The night sky with the city's glow on the horizon.
func _draw_sky(w: float, horizon: float) -> void:
	var band_h := horizon / float(SKY_BANDS - 1) + 1.0
	for i in SKY_BANDS:
		var t := float(i) / float(SKY_BANDS - 1)
		draw_rect(Rect2(0.0, horizon * t, w, band_h), SKY_ZENITH.lerp(SKY_HORIZON, t))
	# The glow of the city on the horizon, and the faint orange of the sodium lamps.
	for i in 6:
		var t := float(i) / 5.0
		draw_rect(Rect2(0.0, horizon - 60.0 + t * 60.0, w, 12.0),
				Color(HORIZON_GLOW.r, HORIZON_GLOW.g, HORIZON_GLOW.b, 0.05 * (1.0 - t)))
	draw_rect(Rect2(0.0, horizon - 8.0, w, 8.0),
			Color(CITY_ORANGE.r, CITY_ORANGE.g, CITY_ORANGE.b, 0.05))


## The sky colour at a height (the aperture of the SWFC is a hole in the tower).
func _sky_at(y: float) -> Color:
	var horizon := size.y * HORIZON
	if horizon <= 0.0:
		return SKY_ZENITH
	return SKY_ZENITH.lerp(SKY_HORIZON, clampf(y / horizon, 0.0, 1.0))


## The reflections of the landmarks in the river.
func _reflections() -> Array:
	return [
		{"x": 0.12, "colour": Color("ff2bd6")},
		{"x": 0.30, "colour": Color("ffcf87")},
		{"x": 0.47, "colour": Color("7fd4ff")},
		{"x": 0.64, "colour": Color("cfe8ff")},
	]


## The ground: a perspective grid that scrolls towards the viewer.
func _draw_grid(w: float, top: float, bottom: float) -> void:
	draw_rect(Rect2(0.0, top, w, bottom - top), GROUND)
	var centre := w * 0.5
	var scroll := fmod(_time * GRID_SPEED, 1.0)
	for i in 16:
		var t := float(i) / 15.0
		var y := top + pow(t, 2.4) * (bottom - top)
		draw_line(Vector2(0.0, y), Vector2(w, y), GRID_LINE, 1.0)
	for i in 15:
		var t := (float(i) + scroll) / 15.0
		var x := centre + (t - 0.5) * w * 1.6
		draw_line(Vector2(centre, top), Vector2(x, bottom), GRID_LINE, 1.0)

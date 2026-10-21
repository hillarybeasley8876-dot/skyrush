extends Control
## The SKYRUSH 飞驰申城 logo.
##
## SKYRUSH is set in Smiley Sans (得意黑) with a magenta → cyan sweep, a white hot spot that runs
## along the word, a scanline shimmer, a chromatic split and a real glow. The glow is the word
## drawn once into a SubViewport and blurred (`logo_glow.gd`): it hugs every letter, where a
## scaled copy of the word would float around it and leave a displaced duplicate of the outer
## letters. The Chinese name sits under the word in the same display face, letter-spaced
## (ART §7: Chinese first), with its own cyan glow, and a neon underline wipes in under the word.
##
## The layout is driven by the font: the logo reports the height it needs, so a screen can place
## what comes below it without guessing.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const LogoGlow := preload("res://ui/menu/widgets/logo_glow.gd")

const WORD := "SKYRUSH"
const CN := "飞驰申城"

## The size of the Chinese name, relative to the font size.
const CN_RATIO := 0.64
## The room between the word's baseline and the Chinese name (of the font size).
const CN_GAP := 0.34
## The distance of the underline under the baseline of the word.
const UNDERLINE_GAP := 0.06
const TRACKING_RATIO := 0.16
## The chromatic split of the glyphs.
const CHROMATIC_SPLIT := 2.0
const CHROMATIC_ALPHA := 0.45
## The sweep of the hot spot and the reveal of the word.
const SWEEP_SPEED := 0.32
const REVEAL_SPEED := 1.4
## The width of the hot spot that runs along the word.
const HOT_SPOT := 0.14
## The shimmer of the scanlines.
const SHIMMER_BANDS := 5.0
const SHIMMER_SPEED := 1.8
## The alpha of the two glow passes (the tight one and the wide one).
const GLOW_TIGHT_ALPHA := 0.6
const GLOW_WIDE_ALPHA := 0.25
## The neon underline: the glow, the core and the bright head that runs along it.
const UNDERLINE_THICK := 6.0
const UNDERLINE_CORE := 2.0
const UNDERLINE_HEAD := 40.0
const UNDERLINE_GLOW_ALPHA := 0.18
const UNDERLINE_HEAD_ALPHA := 0.25

var font_size: int = 92
## The size of the Chinese name (0 = derived from the font size).
var sub_size: int = 0
## How much of the word is drawn (0 = none, 1 = the whole word).
var reveal: float = 1.0
## Where the hot spot runs along the word (0 = the first letter, 1 = the last one).
var sweep: float = 0.0

var _font: Font
var _glow: LogoGlow
var _glow_wide: TextureRect
var _glow_tight: TextureRect
var _reveal_started_us: int = 0
var _shown: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Fonts.display()


func _ready() -> void:
	_glow = LogoGlow.new()
	add_child(_glow)
	_glow.source_canvas.painter = _paint_source
	# The glow is drawn behind the glyphs. A viewport texture holds premultiplied colour, so
	# it is composited with the premultiplied blend mode (the plain one would darken it twice).
	_glow_wide = _make_glow_rect(_glow.wide_viewport, GLOW_WIDE_ALPHA)
	_glow_tight = _make_glow_rect(_glow.tight_viewport, GLOW_TIGHT_ALPHA)
	add_child(_glow_wide)
	add_child(_glow_tight)
	resized.connect(_sync_glow)
	_sync_glow()


## A rectangle that shows a blurred glow behind the glyphs.
func _make_glow_rect(viewport: SubViewport, alpha: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = viewport.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(1.0, 1.0, 1.0, alpha)
	rect.show_behind_parent = true
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	rect.material = material
	return rect


## The height the logo needs: the word's ascent, the gap and the Chinese name's ascent.
func content_height() -> float:
	return _word_ascent() + font_size * CN_GAP + _font.get_ascent(_sub_size())


## The x of every glyph of the word (the tests check the spacing).
func glyph_positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := 0.0
	for advance in _advances():
		out.append(x)
		x += advance
	return out


## The advance of every glyph of the word (the word and the positions share this one loop).
func _advances() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in WORD.length():
		out.append(_font.get_string_size(WORD.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x)
	return out


func _process(_delta: float) -> void:
	# The logo runs on the wall clock: the world is built at a few frames per second, and a
	# delta driven animation would crawl.
	var now := Time.get_ticks_usec()
	if _reveal_started_us == 0:
		_reveal_started_us = now
	var elapsed := float(now - _reveal_started_us) * 0.000001
	if reveal < 1.0:
		reveal = minf(1.0, elapsed * REVEAL_SPEED)
	sweep = fmod(elapsed * SWEEP_SPEED, 1.0)
	queue_redraw()


## The glow is rendered at the size of the logo.
func _sync_glow() -> void:
	if _glow == null:
		return
	_glow.setup(size)
	queue_redraw()


func _draw() -> void:
	_draw_word(self, _word_left(), _word_baseline(), _shown_glyphs(), true)
	_draw_underline(self, _word_left(), _word_width())
	_draw_chinese(self)


## Draws the word into the glow source: the plain gradient, without the hot spot.
func _paint_source(canvas: CanvasItem) -> void:
	_draw_word(canvas, _word_left(), _word_baseline(), _shown_glyphs(), false)
	_draw_chinese(canvas)


## The word of the logo. `crisp` draws the hot spot, the shimmer and the chromatic split.
func _draw_word(canvas: CanvasItem, left: float, baseline: float, shown: int,
		crisp: bool) -> void:
	var advances := _advances()
	var x := left
	for i in mini(shown, WORD.length()):
		var glyph := WORD.substr(i, 1)
		var t := float(i) / float(maxi(WORD.length() - 1, 1))
		var colour := Palette.MAGENTA.lerp(Palette.CYAN, t)
		if not crisp:
			canvas.draw_string(_font, Vector2(x, baseline), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size, colour)
			x += advances[i]
			continue
		# The hot spot that runs along the word.
		var distance := absf(t - sweep)
		if distance < HOT_SPOT:
			colour = colour.lerp(Color.WHITE, (HOT_SPOT - distance) / HOT_SPOT)
		# The scanline shimmer: a soft band travelling across the word.
		var band := 0.5 + 0.5 * sin(t * SHIMMER_BANDS * TAU - _now() * SHIMMER_SPEED)
		colour = colour.lerp(Color.WHITE, band * 0.12)
		# The chromatic split: magenta to the left, cyan to the right.
		canvas.draw_string(_font, Vector2(x - CHROMATIC_SPLIT, baseline), glyph,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(Palette.MAGENTA.r, Palette.MAGENTA.g, Palette.MAGENTA.b, CHROMATIC_ALPHA))
		canvas.draw_string(_font, Vector2(x + CHROMATIC_SPLIT, baseline), glyph,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, CHROMATIC_ALPHA))
		canvas.draw_string(_font, Vector2(x, baseline), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, colour)
		x += advances[i]


## The neon underline that wipes in under the word.
func _draw_underline(canvas: CanvasItem, left: float, word_width: float) -> void:
	var y := _word_baseline() + font_size * UNDERLINE_GAP
	var width := word_width * reveal
	var cyan := Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.85)
	canvas.draw_rect(Rect2(left, y - UNDERLINE_THICK * 0.5, width, UNDERLINE_THICK),
			Color(cyan.r, cyan.g, cyan.b, UNDERLINE_GLOW_ALPHA))
	canvas.draw_rect(Rect2(left, y - UNDERLINE_CORE * 0.5, width, UNDERLINE_CORE), cyan)
	canvas.draw_rect(Rect2(left + width - UNDERLINE_HEAD, y - UNDERLINE_THICK * 0.5,
			UNDERLINE_HEAD, UNDERLINE_THICK), Color(1, 1, 1, UNDERLINE_HEAD_ALPHA))


## The Chinese name, letter-spaced, in the same display face.
func _draw_chinese(canvas: CanvasItem) -> void:
	var sub := _sub_size()
	var tracking := sub * TRACKING_RATIO
	var width := 0.0
	for i in CN.length():
		width += _font.get_string_size(CN.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, sub).x
	width += tracking * float(CN.length() - 1)
	var left := (size.x - width) * 0.5
	var baseline := _chinese_baseline()
	var x := left
	for i in CN.length():
		var glyph := CN.substr(i, 1)
		canvas.draw_string(_font, Vector2(x, baseline), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, sub,
				Palette.CYAN)
		x += _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, sub).x + tracking


## How many glyphs of the word are shown.
func _shown_glyphs() -> int:
	var shown := int(ceil(reveal * float(WORD.length())))
	if shown != _shown:
		_shown = shown
		if _glow != null:
			_glow.invalidate()
	return shown


## The width of the word.
func _word_width() -> float:
	return _font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## The x of the word (it is centred).
func _word_left() -> float:
	return (size.x - _word_width()) * 0.5


## The baseline of the word (the top of the logo is the ascent of the font).
func _word_baseline() -> float:
	return _word_ascent()


## The baseline of the Chinese name.
func _chinese_baseline() -> float:
	return _word_baseline() + font_size * CN_GAP + _font.get_ascent(_sub_size())


## The ascent of the display face at the logo's size.
func _word_ascent() -> float:
	return _font.get_ascent(font_size)


## The size of the Chinese name.
func _sub_size() -> int:
	return sub_size if sub_size > 0 else int(font_size * CN_RATIO)


## The seconds since the logo appeared.
func _now() -> float:
	return float(Time.get_ticks_usec()) * 0.000001

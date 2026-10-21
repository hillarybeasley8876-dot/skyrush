extends Node
## The glow of the logo.
##
## The glyphs are drawn once into a transparent SubViewport and blurred with a two pass separable
## gaussian (a horizontal and a vertical pass). The logo composites the result under its crisp
## glyphs, so the glow hugs every letter: a scaled copy of the word would float around it and
## leave a displaced duplicate of the outer letters.
##
## Two blurs are made: a tight one (radius 14) and a wide one (radius 28) that carries the halo
## further out.

const BlurPass := preload("res://ui/menu/widgets/blur_pass.gdshader")
const GlowSource := preload("res://ui/menu/widgets/logo_glow_source.gd")

## The radius, the sigma and the gain of the tight glow.
const TIGHT_RADIUS := 8.0
const TIGHT_SIGMA := 3.0
const TIGHT_GAIN := 2.4
## The radius, the sigma and the gain of the wide glow.
const WIDE_RADIUS := 16.0
const WIDE_SIGMA := 6.0
const WIDE_GAIN := 3.0

## The viewport the glyphs are drawn into.
var source_viewport: SubViewport
## The canvas the glyphs are drawn on (the logo's painter works on it).
var source_canvas: Control
## The blurred glyphs: the horizontal pass and the vertical pass of each blur.
var tight_h_viewport: SubViewport
var tight_viewport: SubViewport
var wide_h_viewport: SubViewport
var wide_viewport: SubViewport

var _tight_h: TextureRect
var _tight_v: TextureRect
var _wide_h: TextureRect
var _wide_v: TextureRect
var _size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	source_viewport = _make_viewport(Vector2i(16, 16))
	source_canvas = GlowSource.new()
	source_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	source_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_viewport.add_child(source_canvas)

	# A separable blur needs one viewport per pass: a viewport cannot sample its own texture.
	tight_h_viewport = _make_viewport(Vector2i(16, 16))
	_tight_h = _make_blur_rect(source_viewport, Vector2(1.0, 0.0), TIGHT_RADIUS, TIGHT_SIGMA,
			TIGHT_GAIN)
	tight_h_viewport.add_child(_tight_h)
	tight_viewport = _make_viewport(Vector2i(16, 16))
	_tight_v = _make_blur_rect(tight_h_viewport, Vector2(0.0, 1.0), TIGHT_RADIUS, TIGHT_SIGMA,
			TIGHT_GAIN)
	tight_viewport.add_child(_tight_v)

	wide_h_viewport = _make_viewport(Vector2i(16, 16))
	_wide_h = _make_blur_rect(source_viewport, Vector2(1.0, 0.0), WIDE_RADIUS, WIDE_SIGMA,
			WIDE_GAIN)
	wide_h_viewport.add_child(_wide_h)
	wide_viewport = _make_viewport(Vector2i(16, 16))
	_wide_v = _make_blur_rect(wide_h_viewport, Vector2(0.0, 1.0), WIDE_RADIUS, WIDE_SIGMA,
			WIDE_GAIN)
	wide_viewport.add_child(_wide_v)


## Prepares the glow for a logo of that size (the source is rendered at the logo's size, so the
## glow and the crisp glyphs share one coordinate system).
func setup(size: Vector2) -> void:
	var wanted := Vector2i(maxi(int(round(size.x)), 16), maxi(int(round(size.y)), 16))
	if wanted == _size:
		return
	_size = wanted
	for viewport: SubViewport in [source_viewport, tight_h_viewport, tight_viewport,
			wide_h_viewport, wide_viewport]:
		viewport.size = _size
	# The canvas the glyphs are drawn on is pinned to the size of the source: a Control in a
	# viewport does not follow the viewport's size on its own.
	_pin(source_canvas, _size)
	for rect: TextureRect in [_tight_h, _tight_v, _wide_h, _wide_v]:
		_pin(rect, _size)
	var texel := Vector2(1.0 / float(_size.x), 1.0 / float(_size.y))
	for pair: Array in [[_tight_h, texel], [_tight_v, texel], [_wide_h, texel], [_wide_v, texel]]:
		var rect := pair[0] as TextureRect
		var material := rect.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("texel_size", pair[1])
	invalidate()


## Pins a control to a size (no anchors: the layout must not move it).
func _pin(control: Control, size: Vector2i) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = float(size.x)
	control.offset_bottom = float(size.y)


## Renders the glow again (the glyphs changed).
func invalidate() -> void:
	if source_viewport == null:
		return
	source_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	tight_h_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	tight_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	wide_h_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	wide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The size of the glow source.
func source_size() -> Vector2i:
	return _size


## A transparent viewport that only draws the logo.
func _make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = size
	add_child(viewport)
	return viewport


## A rectangle that blurs a viewport's texture along one direction.
func _make_blur_rect(source: SubViewport, direction: Vector2, radius: float,
		sigma: float, gain: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = source.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BlurPass
	material.set_shader_parameter("texel_size", Vector2.ONE)
	material.set_shader_parameter("direction", direction)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("sigma", sigma)
	material.set_shader_parameter("gain", gain)
	rect.material = material
	return rect

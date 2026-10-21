extends RefCounted
## Shared SKYRUSH Theme + the small widget factories every UI unit uses.
##
## The theme is built in code (no hand-written .tres) so the HUD, the menu and the demo all share
## one source of truth: `SkyrushTheme.build()`.
## Fonts are applied per control with `theme_override_fonts/font` so a control never depends on
## theme type-variation lookup order.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")

## Outline / shadow used by every free-floating number so it stays legible over bright scenes
## (brief acceptance: readable over white and saturated magenta).
const OUTLINE_COLOR := Color(0.02, 0.024, 0.059, 0.92)
const OUTLINE_SIZE := 5
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const SHADOW_OFFSET := Vector2(0, 2)

static var _backing: GradientTexture2D = null
static var _dial_face: ImageTexture = null
static var _glass: ImageTexture = null


## Shared Theme: Noto Sans SC as the default face, 20 px, light text.
static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = Fonts.text()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("default_color", "RichTextLabel", Palette.TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 20)
	return theme


## A Label with an explicit face, size and colour.
static func label(text: String, size: int, color: Color, face: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", face if face != null else Fonts.text())
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Label using the display face (Smiley Sans 得意黑) — big numbers and titles.
static func display_label(text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text, size, color, Fonts.display(), align)


## Bold Chinese label (Noto Sans SC 800).
static func bold_label(text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text, size, color, Fonts.text_bold(), align)


## Black-weight Chinese label (Noto Sans SC 900) — the takedown banner.
static func black_label(text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text, size, color, Fonts.text_black(), align)


## Upright techno label (Oxanium) — the reveal livestream gauge values.
static func techno_label(text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text, size, color, Fonts.techno(), align)


## A label with a 5 px dark outline and a soft shadow: legible over any background.
static func outlined_label(text: String, size: int, color: Color, face: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, face, align)
	l.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	l.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	l.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	l.add_theme_constant_override("shadow_offset_x", int(SHADOW_OFFSET.x))
	l.add_theme_constant_override("shadow_offset_y", int(SHADOW_OFFSET.y))
	return l


## Same as `outlined_label` but with the display face.
static func outlined_display_label(text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return outlined_label(text, size, color, Fonts.display(), align)


## A container that never eats mouse input and hugs its children.
static func h_box(alignment: int = BoxContainer.ALIGNMENT_BEGIN,
		separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = alignment as BoxContainer.AlignmentMode
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## A container that never eats mouse input and hugs its children.
static func v_box(alignment: int = BoxContainer.ALIGNMENT_BEGIN,
		separation: int = 4) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = alignment as BoxContainer.AlignmentMode
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## Anchored container helper: sets anchors, offsets and mouse behaviour in one call.
static func place(c: Control, anchor_left: float, anchor_top: float, anchor_right: float,
		anchor_bottom: float, off_left: float = 0.0, off_top: float = 0.0,
		off_right: float = 0.0, off_bottom: float = 0.0) -> Control:
	c.anchor_left = anchor_left
	c.anchor_top = anchor_top
	c.anchor_right = anchor_right
	c.anchor_bottom = anchor_bottom
	c.offset_left = off_left
	c.offset_top = off_top
	c.offset_right = off_right
	c.offset_bottom = off_bottom
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A soft radial vignette used under the free-floating gauges. One smooth gradient, not stacked
## circles (stacked circles show as bands over a flat background).
static func backing_texture() -> GradientTexture2D:
	if _backing == null:
		var gradient := Gradient.new()
		gradient.set_offset(0, 0.0)
		gradient.set_color(0, Color(0.02, 0.024, 0.059, 0.88))
		gradient.set_offset(1, 1.0)
		gradient.set_color(1, Color(0.02, 0.024, 0.059, 0.0))
		_backing = GradientTexture2D.new()
		_backing.gradient = gradient
		_backing.width = 128
		_backing.height = 128
		_backing.fill = GradientTexture2D.FILL_RADIAL
		_backing.fill_from = Vector2(0.5, 0.5)
		_backing.fill_to = Vector2(1.0, 0.5)
	return _backing


## The dial face of the speedometer: a radial gradient #101A2E -> #05070D with a faint sunburst
## (1 px radial lines every 6 degrees, white alpha 0.03) baked in, so the face is not a flat
## gradient.
static func dial_face_texture() -> ImageTexture:
	if _dial_face == null:
		_dial_face = _bake_dial_face(192)
	return _dial_face


## The face image: the radial gradient plus the sunburst rays.
static func _bake_dial_face(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centre := Vector2(size * 0.5, size * 0.5)
	var rmax := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre) / rmax
			var t := clampf(d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.063, 0.102, 0.180, 0.95).lerp(
				Color(0.020, 0.027, 0.051, 0.0), t))
	# The sunburst: one 1 px ray every 6 degrees.
	for i in 60:
		var dir := Vector2(cos(TAU * float(i) / 60.0), sin(TAU * float(i) / 60.0))
		for d2 in range(int(rmax)):
			var p := centre + dir * float(d2)
			var px := int(p.x)
			var py := int(p.y)
			if px < 0 or py < 0 or px >= size or py >= size:
				continue
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py, Color(lerpf(c.r, 1.0, 0.03), lerpf(c.g, 1.0, 0.03),
				lerpf(c.b, 1.0, 0.03), c.a))
	return ImageTexture.create_from_image(img)


## The tileable glass texture of the panels: 3 px scanlines, a seeded value grain and a 16 px
## dot grid. 128 x 128 so it can be repeated over any panel.
static func glass_texture() -> ImageTexture:
	if _glass == null:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261020
		for y in size:
			for x in size:
				var v := rng.randf_range(-0.03, 0.03)
				var col := Color(1, 1, 1, 0.0)
				# A scanline on every third row.
				if y % 3 == 0:
					col.a = 0.05
				# A dot grid every 16 px.
				if x % 16 == 0 and y % 16 == 0:
					col.a = 0.04
				col.r = clampf(1.0 + v, 0.0, 1.0)
				col.g = clampf(1.0 + v, 0.0, 1.0)
				col.b = clampf(1.0 + v, 0.0, 1.0)
				img.set_pixel(x, y, col)
		_glass = ImageTexture.create_from_image(img)
	return _glass

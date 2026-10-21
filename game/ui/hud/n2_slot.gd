extends Control
## One N2 COPV slot: a stylised cold-gas cylinder (dome caps, carbon overwrap, a valve nub, level
## ticks, a specular strip) that fills from the BOTTOM with a cyan liquid. The pending gain of the
## running drift is drawn as diagonal stripes directly above the liquid.
##
## Everything static is baked into textures once per size (at 3x, so the domes are smooth and the
## rim is 2 px): the shell, the liquid gradient, the stripe pattern and the gloss overlay. The
## textures are CACHED and shared by every slot of the same size, so the two slots of the cluster
## bake once, not twice. A redraw is then three textured quads and a meniscus line.

const SLOT_SIZE := Vector2(44, 132)
const CAP_RATIO := 0.5          ## dome radius = half the width
const BAKE_SCALE := 3           ## the textures are baked at 3x and drawn scaled down
const RIM_COLOR := Color(0.110, 0.165, 0.227, 1.0)
const VALVE_COLOR := Color(0.604, 0.651, 0.769, 1.0)
const HATCH_COLOR := Color(1, 1, 1, 0.10)
const HATCH_PITCH := 6.0
const HATCH_ANGLE := 35.0
const HATCH_WIDTH := 2          ## the hatch is 2 texels wide, so it reads as a weave
const TICK_COLOR := Color(1, 1, 1, 0.35)
const LIQUID_BOTTOM := Color("00b8d4")
const LIQUID_TOP := Color("7ff4ff")
const MENISCUS_COLOR := Color("d8fdff")
const STRIPE_COLOR := Color(0.0, 0.898, 1.0, 0.6)
const STRIPE_WIDTH := 3.0
const STRIPE_PITCH := 8.0
const STRIPE_ANGLE := 45.0
const GLOW_COLOR := Color(0.0, 0.898, 1.0, 1.0)
const PULSE_HZ := 1.0
const FULL_VALUE := 99.9
const PULSE_PERIOD := 1.0 / 20.0
## The level ticks on the right edge of the cylinder.
const LEVEL_TICKS: Array[float] = [0.25, 0.5, 0.75]
## Below this many units the slot stays empty: no liquid and no meniscus.
const MIN_LIQUID_UNITS := 0.5

## The baked textures, shared by every slot of the same size (keyed by the pixel size).
static var _tex_cache: Dictionary = {}

var value: float = 0.0      ## committed units in this slot (0..100)
var pending: float = 0.0    ## uncommitted drift gain shown striped (0..100)

var _shell_tex: ImageTexture = null
var _liquid_tex: ImageTexture = null
var _stripe_tex: ImageTexture = null
var _gloss_tex: ImageTexture = null
var _outline: PackedVector2Array = PackedVector2Array()
var _valve: PackedVector2Array = PackedVector2Array()
var _last_committed: int = -1
var _last_pending: int = -1
var _pulse_accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The slot draws texture REGIONS; a repeating canvas item would wrap the region coordinates
	# and spill the liquid outside the cylinder.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	# The baked textures are 3x and drawn at 1/3: without mipmaps the 1 px hatch lines alias
	# into random dots.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = SLOT_SIZE
	resized.connect(_rebuild)
	_rebuild()


## The committed and pending units of this slot.
func set_values(committed: float, pending_units: float) -> void:
	# The floats are stored on EVERY call, so a slot that falls from 0.4 to 0.0 units is empty
	# again. Only the redraw is skipped when the rounded values did not change.
	value = committed
	pending = pending_units
	var c := int(round(committed))
	var p := int(round(pending_units))
	if c == _last_committed and p == _last_pending:
		return
	_last_committed = c
	_last_pending = p
	queue_redraw()


## The 1 Hz "slot full" pulse needs a redraw even when the value does not change.
func _process(delta: float) -> void:
	if value < FULL_VALUE:
		_pulse_accum = 0.0
		return
	_pulse_accum += delta
	if _pulse_accum >= PULSE_PERIOD:
		_pulse_accum = 0.0
		queue_redraw()


func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	_outline = _capsule_outline(w, h)
	_valve = PackedVector2Array([
		Vector2(w * 0.5 - 5.0, 0.0), Vector2(w * 0.5 + 5.0, 0.0),
		Vector2(w * 0.5 + 4.0, -6.0), Vector2(w * 0.5 - 4.0, -6.0)])
	var tex := _textures_for(w, h)
	_shell_tex = tex["shell"]
	_liquid_tex = tex["liquid"]
	_stripe_tex = tex["stripes"]
	_gloss_tex = tex["gloss"]
	queue_redraw()


## The baked textures of a size, baked once and shared by every slot of that size.
func _textures_for(w: float, h: float) -> Dictionary:
	var key := Vector2i(int(w), int(h))
	if _tex_cache.has(key):
		return _tex_cache[key]
	var iw := int(w * BAKE_SCALE)
	var ih := int(h * BAKE_SCALE)
	var out := {
		"shell": _to_texture(_bake_shell(iw, ih)),
		"liquid": _to_texture(_bake_liquid(iw, ih)),
		"stripes": _to_texture(_bake_stripes(iw, ih)),
		"gloss": _to_texture(_bake_gloss(iw, ih)),
	}
	_tex_cache[key] = out
	return out


## An image with mipmaps, so the 3x bake does not alias when it is drawn at 1/3.
func _to_texture(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The capsule outline: a rounded body with a dome cap at the top and the bottom.
func _capsule_outline(w: float, h: float) -> PackedVector2Array:
	var r := w * CAP_RATIO
	var pts := PackedVector2Array()
	var steps := 14
	for i in range(steps + 1):
		var a := PI + PI * float(i) / float(steps)
		pts.append(Vector2(w * 0.5 + cos(a) * r, r + sin(a) * r))
	for i in range(steps + 1):
		var a2 := PI * float(i) / float(steps)
		pts.append(Vector2(w * 0.5 + cos(a2) * r, h - r + sin(a2) * r))
	pts.append(pts[0])
	return pts


## Is the point inside the capsule (a rounded body with a dome cap top and bottom)?
func _inside_capsule(w: float, h: float, x: float, y: float) -> bool:
	var r := w * CAP_RATIO
	if y < r:
		var dx := x - w * 0.5
		var dy := y - r
		return dx * dx + dy * dy <= r * r
	if y > h - r:
		var dx2 := x - w * 0.5
		var dy2 := y - (h - r)
		return dx2 * dx2 + dy2 * dy2 <= r * r
	return true


## The capsule's horizontal span at a given y: x in [xmin, xmax].
func _span(w: float, h: float, y: float) -> Vector2:
	var r := w * CAP_RATIO
	var cy := r
	if y < r:
		cy = r
	elif y > h - r:
		cy = h - r
	else:
		return Vector2(0.0, w)
	var d := sqrt(maxf(r * r - (y - cy) * (y - cy), 0.0))
	return Vector2(w * 0.5 - d, w * 0.5 + d)


## The shell: the capsule body, the carbon overwrap and the 2 px rim that follows the capsule.
## The specular strip is NOT baked in here: it is a separate overlay, so the liquid cannot hide it.
func _bake_shell(iw: int, ih: int) -> Image:
	var w := float(iw)
	var h := float(ih)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in ih:
		var t := float(y) / maxf(float(ih - 1), 1.0)
		var base := Color(0.055, 0.075, 0.11, 0.94).lerp(Color(0.09, 0.12, 0.17, 0.94), t)
		for x in iw:
			if _inside_capsule(w, h, float(x) + 0.5, float(y) + 0.5):
				img.set_pixel(x, y, base)
	_bake_hatch(img, w, h)
	# The rim: every shell pixel with an outside neighbour.
	for y in ih:
		for x in iw:
			if img.get_pixel(x, y).a <= 0.0:
				continue
			var edge := (x == 0 or y == 0 or x == iw - 1 or y == ih - 1
				or img.get_pixel(x - 1, y).a <= 0.0 or img.get_pixel(x + 1, y).a <= 0.0
				or img.get_pixel(x, y - 1).a <= 0.0 or img.get_pixel(x, y + 1).a <= 0.0)
			if edge:
				img.set_pixel(x, y, RIM_COLOR)
	return img


## The carbon overwrap: two sets of 35 degree lines, 2 texels wide, blended into the shell.
func _bake_hatch(img: Image, w: float, h: float) -> void:
	var step := tan(deg_to_rad(HATCH_ANGLE))
	var iw := img.get_width()
	var ih := img.get_height()
	for pass_i in 2:
		var dir := 1.0 if pass_i == 0 else -1.0
		var offset := -h * step
		while offset < w + h * step:
			var y := 0
			while y < ih:
				var x := offset + dir * step * float(y)
				if x >= 0.0 and x < w:
					var px := int(x)
					for d in HATCH_WIDTH:
						var sx := px - d
						if sx < 0 or sx >= iw:
							continue
						var c := img.get_pixel(sx, y)
						if c.a > 0.0:
							img.set_pixel(sx, y, c.lerp(Color(1, 1, 1, 1.0), HATCH_COLOR.a))
				y += 1
			offset += HATCH_PITCH * BAKE_SCALE


## The liquid: a cylindrical shading (the edges 20 % darker than the centre) masked to the
## capsule. The VERTICAL gradient is NOT baked in: it is drawn per band, so the surface of the
## liquid is always the light #7FF4FF, whatever the level of the tank is.
func _bake_liquid(iw: int, ih: int) -> Image:
	var w := float(iw)
	var h := float(ih)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in ih:
		for x in iw:
			if not _inside_capsule(w, h, float(x) + 0.5, float(y) + 0.5):
				continue
			# The cylindrical shading: the edges are 20 % darker.
			var edge := absf(float(x) / w - 0.5) * 2.0
			var shade := 1.0 - 0.20 * edge * edge
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	return img


## The pending gain: 45 degree stripes, 3 px wide with an 8 px pitch, masked to the capsule.
func _bake_stripes(iw: int, ih: int) -> Image:
	var w := float(iw)
	var h := float(ih)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var step := tan(deg_to_rad(STRIPE_ANGLE))
	var pitch := STRIPE_PITCH * BAKE_SCALE
	var width := STRIPE_WIDTH * BAKE_SCALE
	for offset in range(-int(h * step) - int(pitch), int(w + h * step), int(pitch)):
		var y := 0
		while y < ih:
			var x := float(offset) + step * float(y)
			if x >= 0.0 and x < w:
				var px := int(x)
				for d in range(int(width)):
					var sx := px - d
					if sx < 0 or sx >= iw:
						continue
					if not _inside_capsule(w, h, float(sx) + 0.5, float(y) + 0.5):
						continue
					img.set_pixel(sx, y, STRIPE_COLOR)
			y += 1
	return img


## The specular strip on the left third (white alpha 0.20 -> 0), masked to the capsule. It is a
## separate overlay, drawn last, so a full tank still shows the gloss.
func _bake_gloss(iw: int, ih: int) -> Image:
	var w := float(iw)
	var h := float(ih)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var strip := w / 3.0
	for y in ih:
		for x in int(strip):
			if not _inside_capsule(w, h, float(x) + 0.5, float(y) + 0.5):
				continue
			var a := 0.20 * (1.0 - float(x) / strip)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0 or _shell_tex == null:
		return
	draw_texture_rect(_shell_tex, Rect2(Vector2.ZERO, size), false)
	# Valve nub on top.
	if _valve.size() >= 4:
		draw_colored_polygon(_valve, VALVE_COLOR)
		draw_line(Vector2(w * 0.5 - 4.0, -5.0), Vector2(w * 0.5 + 4.0, -5.0),
			Color(1, 1, 1, 0.55), 1.0, true)
	var solid_h := 0.0
	if value >= MIN_LIQUID_UNITS:
		solid_h = h * clampf(value / 100.0, 0.0, 1.0)
		_draw_liquid_band(h - solid_h, solid_h)
		# The meniscus, clipped to the capsule.
		var sp := _span(w, h, h - solid_h)
		draw_line(Vector2(sp.x, h - solid_h), Vector2(sp.y, h - solid_h), MENISCUS_COLOR, 2.0, true)
	var pend_h := h * clampf(pending / 100.0, 0.0, 1.0 - clampf(value / 100.0, 0.0, 1.0))
	if pend_h > 0.5:
		_draw_band(_stripe_tex, h - solid_h - pend_h, pend_h)
	_draw_level_ticks(w, h)
	# The gloss is drawn last, over the liquid.
	draw_texture_rect(_gloss_tex, Rect2(Vector2.ZERO, size), false)
	if value >= FULL_VALUE:
		_draw_glow()


## The level ticks on the right edge: 6 x 1 px lines at 25 / 50 / 75 %, above the liquid.
func _draw_level_ticks(w: float, h: float) -> void:
	for frac in LEVEL_TICKS:
		var ty := h * (1.0 - frac)
		var sp := _span(w, h, ty)
		var x0 := maxf(w - 8.0, sp.x + 1.0)
		var x1 := minf(w - 2.0, sp.y - 1.0)
		if x1 <= x0:
			continue
		draw_line(Vector2(x0, ty), Vector2(x1, ty), TICK_COLOR, 1.0, true)


## The liquid band: a vertical gradient from the light #7FF4FF at the surface to the dark
## #00B8D4 at the bottom, masked to the capsule by the baked texture. The gradient is relative to
## the BAND, so the surface of the liquid is always light, whatever the level of the tank is.
func _draw_liquid_band(top: float, height: float) -> void:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(0.0, top), Vector2(w, top), Vector2(w, top + height), Vector2(0.0, top + height)])
	# The uvs map the band onto the region of the capsule mask it covers.
	var uvs := PackedVector2Array([
		Vector2(0.0, top / h), Vector2(1.0, top / h), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	draw_polygon(pts, PackedColorArray([
		LIQUID_TOP, LIQUID_TOP, LIQUID_BOTTOM, LIQUID_BOTTOM]), uvs, _liquid_tex)


## Draw a band of a baked texture (the texture is masked to the capsule already). The source rect
## of the texture is the LAST argument, as documented.
func _draw_band(texture: ImageTexture, top: float, height: float) -> void:
	var s := BAKE_SCALE
	var region := Rect2(0.0, top * s, size.x * s, height * s)
	draw_texture_rect_region(texture, Rect2(0.0, top, size.x, height), region)


## The full-slot glow: a 6 px cyan halo pulsing at 1 Hz.
func _draw_glow() -> void:
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * PULSE_HZ)
	draw_polyline(_outline, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.30 + 0.25 * pulse),
		6.0, true)

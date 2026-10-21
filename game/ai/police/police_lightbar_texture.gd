class_name PoliceLightBarTexture
extends RefCounted
## The lens texture of the light bar of the police (ref/art/DOSSIER.md §4.8).
##
## The glb of the npc_cars unit has no texture on the light bar: the halves are flat slabs
## that glow as one brick. The police unit builds its own lens texture in code: a module tile
## with a grid of round LED dots and a reflector ring, so the bar reads as a light module and
## not as a glowing brick (the user asks for a texture on everything).
##
## The texture is built once and shared by every police car: a car that flashes drives the
## emission energy, not the texture.

## The size of the module tile (px).
const TILE_WIDTH := 64
const TILE_HEIGHT := 32
## The grid of the LED dots in the tile.
const LED_COLUMNS := 3
const LED_ROWS := 2
## The radius of an LED dot (px) and the width of its soft falloff (px).
const LED_RADIUS := 6.0
const LED_FALLOFF := 2.0
## The width of the reflector ring around the tile (px).
const RING_WIDTH := 2.0
## The background of the lens: the unlit red and the unlit blue.
const RED_BACKGROUND := Color("1a0306")
const BLUE_BACKGROUND := Color("03081a")
## The colour of the reflector ring.
const RING_COLOR := Color("5a5a60")
## The colour of the LED dot.
const LED_COLOR := Color("f2f2f2")
## The texture scale of the lens: about twelve modules on a half of the bar.
const UV_SCALE := 19.0
## The roughness of the lens: it is glass, not paint.
const ROUGHNESS := 0.12

static var _red: ImageTexture = null
static var _blue: ImageTexture = null


## The lens texture of the red half.
static func red() -> ImageTexture:
	if _red == null:
		_red = _build(RED_BACKGROUND)
	return _red


## The lens texture of the blue half.
static func blue() -> ImageTexture:
	if _blue == null:
		_blue = _build(BLUE_BACKGROUND)
	return _blue


## Puts the lens texture on a copy of the material of a light bar half.
static func apply(material: Material, half: String) -> void:
	var base := material as BaseMaterial3D
	if base == null:
		return
	var texture := red() if half == "red" else blue()
	if texture == null:
		return
	base.albedo_texture = texture
	base.emission_texture = texture
	base.emission_enabled = true
	base.uv1_triplanar = true
	base.uv1_scale = Vector3.ONE * UV_SCALE
	base.roughness = ROUGHNESS


## Builds one module tile: the background, the LED dots and the reflector ring.
static func _build(background: Color) -> ImageTexture:
	var image := Image.create(TILE_WIDTH, TILE_HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(background)
	_draw_ring(image)
	var step_x := float(TILE_WIDTH) / float(LED_COLUMNS)
	var step_y := float(TILE_HEIGHT) / float(LED_ROWS)
	for row in LED_ROWS:
		for column in LED_COLUMNS:
			var centre := Vector2((float(column) + 0.5) * step_x, (float(row) + 0.5) * step_y)
			_draw_dot(image, centre, LED_RADIUS)
	return ImageTexture.create_from_image(image)


## The reflector ring around the tile.
static func _draw_ring(image: Image) -> void:
	for y in TILE_HEIGHT:
		for x in TILE_WIDTH:
			var edge := mini(mini(x, y), mini(TILE_WIDTH - 1 - x, TILE_HEIGHT - 1 - y))
			if edge >= int(RING_WIDTH):
				continue
			image.set_pixel(x, y, RING_COLOR)


## One round LED dot with a soft falloff at its rim.
static func _draw_dot(image: Image, centre: Vector2, radius: float) -> void:
	var min_x := maxi(int(centre.x - radius - 1.0), 0)
	var max_x := mini(int(centre.x + radius + 1.0), TILE_WIDTH - 1)
	var min_y := maxi(int(centre.y - radius - 1.0), 0)
	var max_y := mini(int(centre.y + radius + 1.0), TILE_HEIGHT - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
			var amount := clampf((radius - distance) / LED_FALLOFF, 0.0, 1.0)
			if amount <= 0.0:
				continue
			var colour := image.get_pixel(x, y)
			image.set_pixel(x, y, colour.lerp(LED_COLOR, amount))

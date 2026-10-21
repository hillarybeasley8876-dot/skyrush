extends Node
## The atlas of the shop name boards (ART §7: real words in context).
##
## The 1,187 shop boards of the city are one MultiMesh per tile, not one node each: the name of
## a board is a cell of one atlas texture, and the cell is taken from the INSTANCE_CUSTOM of the
## instance (the uv offset and the uv scale). The board therefore carries a shop name and not the
## road guide of the props unit.

const SHADER_PATH := "res://world/build/shaders/shop_atlas.gdshader"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"

## The grid of the atlas.
const COLUMNS := 4
const ROWS := 4
## The size of one cell, in pixels.
const CELL := Vector2i(512, 288)
## The ground of a board.
const BOARD := Color("0d1218")
## The frame of a board.
const FRAME := Color("f2a03c")
## The colour of the name.
const NAME := Color("fff3e0")
## The energy of the emission of a board (the name is neon).
const EMISSION := 1.8

## The names of the shops (Chinese parody names, ART §7).
const NAMES: Array[String] = [
	"东方霓虹", "浦江电讯", "申城快递", "量子奶茶",
	"老城隍面馆", "夜半书坊", "机械火锅", "云端洗衣",
	"海派理发", "梧桐咖啡", "赛博照相", "小笼包铺",
	"沪上琴行", "银河电器", "弄堂烧烤", "天际打印",
]

var _material: ShaderMaterial = null
var _texture: Texture2D = null
var _headless := false


## The material of the shop boards (one shader material for the whole city).
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var shader: Shader = null
	if ResourceLoader.exists(SHADER_PATH):
		shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("[world] the shop atlas shader is missing")
		return null
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("emission_energy", EMISSION)
	if _texture != null:
		_material.set_shader_parameter("albedo_texture", _texture)
	return _material


## The uv offset and the uv scale of the cell of a name.
func cell(name: String) -> Vector4:
	var index := NAMES.find(name)
	if index < 0:
		index = 0
	var column := index % COLUMNS
	var row := index / COLUMNS
	return Vector4(float(column) / float(COLUMNS), float(row) / float(ROWS),
		1.0 / float(COLUMNS), 1.0 / float(ROWS))


## Renders the atlas: one cell per name. Yields two frames (the viewport has to be drawn).
func generate() -> void:
	_headless = DisplayServer.get_name() == "headless"
	var size := Vector2i(CELL.x * COLUMNS, CELL.y * ROWS)
	if _headless:
		_texture = _flat(size)
	else:
		_texture = await _render(size)
	var mat := material()
	if mat != null:
		mat.set_shader_parameter("albedo_texture", _texture)


## The atlas texture: a board per cell, with the name of the shop.
func _render(size: Vector2i) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)
	var ground := ColorRect.new()
	ground.color = BOARD
	ground.size = Vector2(size)
	viewport.add_child(ground)
	var font: Font = null
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH) as Font
	for i in NAMES.size():
		_cell(viewport, i, font)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return _flat(size)
	return ImageTexture.create_from_image(image)


## One cell of the atlas: the frame of the board and the name of the shop.
func _cell(viewport: SubViewport, index: int, font: Font) -> void:
	var column := index % COLUMNS
	var row := index / COLUMNS
	var origin := Vector2(float(column * CELL.x), float(row * CELL.y))
	var frame := ColorRect.new()
	frame.color = FRAME
	frame.position = origin
	frame.size = Vector2(CELL)
	viewport.add_child(frame)
	var inner := ColorRect.new()
	inner.color = BOARD
	inner.position = origin + Vector2(10, 10)
	inner.size = Vector2(CELL) - Vector2(20, 20)
	viewport.add_child(inner)
	var label := Label.new()
	label.text = NAMES[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = origin + Vector2(16, 16)
	label.size = Vector2(CELL) - Vector2(32, 32)
	label.add_theme_color_override("font_color", NAME)
	label.add_theme_font_size_override("font_size", 80)
	if font != null:
		label.add_theme_font_override("font", font)
	viewport.add_child(label)


## A flat atlas (a headless run has no renderer).
func _flat(size: Vector2i) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(BOARD)
	return ImageTexture.create_from_image(image)

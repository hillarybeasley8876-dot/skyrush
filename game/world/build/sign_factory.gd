extends Node
## Generates the sign textures of the guide gantries and the VMS boards: the Chinese and the
## English text of the road_furniture.json entry are rendered with the project's font into an
## offscreen viewport and applied to the sign panel of the prop.
##
## Every panel gets its own material: a shared material would show the last rendered text on
## every panel of the city. The emission only comes from the white text and the border, so the
## green of GB 5768.2 does not glow.
##
## The VMS boards show one of five messages; the textures are rendered once and cycled.

const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"
const VmsCycle := preload("res://world/build/vms_cycle.gd")
## The size of the texture of a guide gantry (GB 5768.2: 2048 px wide).
const GANTRY_SIZE := Vector2i(2048, 256)
## The size of the texture of a VMS board.
const VMS_SIZE := Vector2i(512, 128)
## The size of the texture of the name of a police station.
const STATION_SIZE := Vector2i(1024, 256)
## The size of the texture of the emblem of the police.
const BADGE_SIZE := Vector2i(256, 256)
## The ground of an elevated road sign.
const GREEN := Color("00704a")
## The ground of a surface road sign.
const BLUE := Color("1f57c3")
## The ground of the name of a police station.
const STATION_BLUE := Color("1e4fb8")
## The ground of the emblem of the police.
const BADGE_RED := Color("c8102e")
## The ground of a VMS board.
const BOARD := Color("101418")
## The colour of the dot matrix of a VMS board.
const DOT_AMBER := Color("ffb000")
## The ground of a shop name board.
const SHOP_BOARD := Color("101820")
## The size of one dot of the VMS matrix, in pixels.
const DOT_SIZE := 4
## The energy of the emission of a panel (the green must not glow).
const PANEL_EMISSION := 0.25
## The energy of the emission of the name of a police station.
const STATION_EMISSION := 1.1
## The energy of the emission of a shop name board (the name is neon).
const SHOP_EMISSION := 1.4
## The messages of the VMS boards (real words, no glyph soup).
const VMS_MESSAGES: Array[String] = [
	"前方畅通", "注意车距", "前方施工 减速慢行", "路面湿滑", "请保持车距",
]

var _vms_textures: Array[Texture2D] = []
## The textures of the texts that were already rendered (the shop names repeat).
var _text_cache: Dictionary = {}
var _headless := false


## `signs` are the dictionaries returned by the furniture builder.
func apply_signs(signs: Array[Dictionary]) -> void:
	if signs.is_empty():
		return
	_headless = DisplayServer.get_name() == "headless"
	_generate.call_deferred(signs)


func _generate(signs: Array[Dictionary]) -> void:
	for sign in signs:
		var panels: Array = sign.get("panels", [])
		if not panels.is_empty():
			for panel in panels:
				await _apply_panel(panel)
			continue
		if str(sign.get("type", "")) == "vms":
			_setup_vms(sign)
			continue
		await _apply_panel(sign)


## One panel with its own material and its own texture.
func _apply_panel(panel: Dictionary) -> void:
	var mesh := panel.get("node") as MeshInstance3D
	if mesh == null:
		mesh = panel.get("sign") as MeshInstance3D
	if mesh == null:
		return
	var text := str(panel.get("text", ""))
	if text == "":
		return
	var text_en := str(panel.get("text_en", ""))
	var style := str(panel.get("style", "green"))
	var texture: Texture2D = _text_cache.get(text, null)
	if texture == null:
		texture = await _render_style(text, text_en, style)
		if texture == null:
			return
		_text_cache[text] = texture
	var energy := SHOP_EMISSION if style == "shop" else PANEL_EMISSION
	if style == "station":
		energy = STATION_EMISSION
	_apply(mesh, texture, energy)


## The texture of a sign, in the style of the sign.
func _render_style(text: String, text_en: String, style: String) -> Texture2D:
	match style:
		"shop":
			return await _render_shop(text)
		"station":
			return await _render_station(text)
		"badge":
			return await _render_badge(text)
		_:
			return await _render_panel(text, text_en, style)


## The material of a panel: its own albedo texture. The emission is low (0.25), so the green
## of the sign does not glow; the white text is four times brighter than the ground and
## reads at night.
func _apply(mesh: MeshInstance3D, texture: Texture2D, energy: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.42
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission_texture = texture
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = energy
	mesh.material_override = mat


## The VMS board: the five messages are rendered once and cycled.
func _setup_vms(sign: Dictionary) -> void:
	var mesh := sign.get("sign") as MeshInstance3D
	if mesh == null:
		return
	if _vms_textures.is_empty():
		for message in VMS_MESSAGES:
			_vms_textures.append(await _render_vms(message))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _vms_textures[0] if not _vms_textures.is_empty() else null
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission_texture = mat.albedo_texture
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 1.2
	mesh.material_override = mat
	var animator := VmsCycle.new()
	animator.mesh = mesh
	animator.factory = self
	# Every board starts on another message, so a street of boards does not read as one sign.
	var spot := mesh.get_global_position()
	animator.index = absi(int(spot.x) + int(spot.z)) % maxi(VMS_MESSAGES.size(), 1)
	add_child(animator)


## The textures of the VMS messages, in the order of VMS_MESSAGES.
func vms_textures() -> Array[Texture2D]:
	return _vms_textures


# --- rendering --------------------------------------------------------------------------------------

## The texture of a gantry panel: the border, the ground, the lane arrows, the Chinese line
## and the English line.
func _render_panel(text: String, text_en: String, style: String) -> Texture2D:
	var background := GREEN if style != "blue" else BLUE
	if _headless:
		return _flat_texture(GANTRY_SIZE, background)
	var viewport := _make_viewport(GANTRY_SIZE, background)
	_border(viewport, GANTRY_SIZE, background)
	_arrows(viewport, GANTRY_SIZE)
	_text(viewport, text, text_en, GANTRY_SIZE, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## The texture of a shop name board: the name in white on a dark board.
func _render_shop(text: String) -> Texture2D:
	if _headless:
		return _flat_texture(GANTRY_SIZE, SHOP_BOARD)
	var viewport := _make_viewport(GANTRY_SIZE, SHOP_BOARD)
	_text(viewport, text, "", GANTRY_SIZE, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## The texture of the name of a police station: white letters on the blue band of the
## station. The letters are 1.2 m high on a band of 1.9 m, so they read from 30 m.
func _render_station(text: String) -> Texture2D:
	if _headless:
		return _flat_texture(STATION_SIZE, STATION_BLUE)
	var viewport := _make_viewport(STATION_SIZE, STATION_BLUE)
	_text(viewport, text, "", STATION_SIZE, true, 0.62)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## The texture of the emblem of the police: the character 警 on a red ground.
func _render_badge(text: String) -> Texture2D:
	if _headless:
		return _flat_texture(BADGE_SIZE, BADGE_RED)
	var viewport := _make_viewport(BADGE_SIZE, BADGE_RED)
	_text(viewport, text, "", BADGE_SIZE, true, 0.78)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## The texture of a VMS message: amber dot matrix on a dark board.
func _render_vms(message: String) -> Texture2D:
	if _headless:
		return _flat_texture(VMS_SIZE, BOARD)
	var viewport := _make_viewport(VMS_SIZE, BOARD)
	_text(viewport, message, "", VMS_SIZE, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	return ImageTexture.create_from_image(_dot_matrix(image))


## A viewport with the ground of the sign.
func _make_viewport(size: Vector2i, background: Color) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)
	var ground := ColorRect.new()
	ground.color = background
	ground.size = Vector2(size)
	viewport.add_child(ground)
	return viewport


## The white border of a gantry panel.
func _border(viewport: SubViewport, size: Vector2i, background: Color) -> void:
	var border := ColorRect.new()
	border.color = Color.WHITE
	border.size = Vector2(size)
	viewport.add_child(border)
	var inner := ColorRect.new()
	inner.color = background
	inner.position = Vector2(8, 8)
	inner.size = Vector2(size) - Vector2(16, 16)
	viewport.add_child(inner)


## The lane arrows of a gantry panel: straight ahead and to the right.
func _arrows(viewport: SubViewport, size: Vector2i) -> void:
	viewport.add_child(_straight_arrow(Vector2(150.0, size.y * 0.5)))
	viewport.add_child(_turn_arrow(Vector2(330.0, size.y * 0.5)))


## A white arrow straight ahead: a shaft and a triangular head.
func _straight_arrow(at: Vector2) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = Color.WHITE
	var w := 13.0
	var h := 88.0
	var head := 34.0
	poly.polygon = PackedVector2Array([
		at + Vector2(-w, h * 0.5), at + Vector2(w, h * 0.5),
		at + Vector2(w, h * 0.05), at + Vector2(w + head, h * 0.05),
		at + Vector2(0.0, -h * 0.45), at + Vector2(-w - head, h * 0.05),
		at + Vector2(-w, h * 0.05),
	])
	return poly


## A white arrow that turns to the right.
func _turn_arrow(at: Vector2) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = Color.WHITE
	var w := 13.0
	var h := 88.0
	var head := 30.0
	var arm := 62.0
	poly.polygon = PackedVector2Array([
		at + Vector2(-w, h * 0.5), at + Vector2(w, h * 0.5),
		at + Vector2(w, w * 2.0), at + Vector2(arm, w * 2.0),
		at + Vector2(arm, w + head * 0.5), at + Vector2(arm + head, w),
		at + Vector2(arm, w - head * 0.5), at + Vector2(arm, 0.0),
		at + Vector2(-w, 0.0),
	])
	return poly


## The Chinese line and the English line of a panel.
func _text(viewport: SubViewport, chinese: String, english: String, size: Vector2i,
		big: bool, fill: float = 0.0) -> void:
	var font: Font = null
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH) as Font
	var left := size.x * 0.25 if big else 0.0
	var label := Label.new()
	label.text = chinese
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(left, 0)
	label.size = Vector2(size.x - left, size.y)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", int(size.y * (fill if fill > 0.0 else 0.42)))
	if font != null:
		label.add_theme_font_override("font", font)
	viewport.add_child(label)
	if english == "":
		return
	var sub := Label.new()
	sub.text = english
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.position = Vector2(left, size.y * 0.5)
	sub.size = Vector2(size.x - left, size.y * 0.5)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	sub.add_theme_font_size_override("font_size", int(size.y * 0.24))
	if font != null:
		sub.add_theme_font_override("font", font)
	viewport.add_child(sub)


## Turns the rendered text into a dot matrix: every DOT_SIZE square is one dot.
func _dot_matrix(image: Image) -> Image:
	var size := image.get_size()
	var out := Image.create(size.x, size.y, false, image.get_format())
	out.fill(BOARD)
	var half := DOT_SIZE / 2
	for by in range(0, size.y - DOT_SIZE + 1, DOT_SIZE):
		for bx in range(0, size.x - DOT_SIZE + 1, DOT_SIZE):
			# The centre of the block decides whether the dot is lit.
			var c := image.get_pixel(bx + half, by + half)
			if c.r <= 0.45:
				continue
			for y in DOT_SIZE:
				for x in DOT_SIZE:
					out.set_pixel(bx + x, by + y, DOT_AMBER)
	return out


## A plain texture, used when there is no renderer (a headless test).
func _flat_texture(size: Vector2i, colour: Color) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

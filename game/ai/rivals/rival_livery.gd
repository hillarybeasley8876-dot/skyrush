class_name RivalLivery
extends RefCounted
## The livery of a rival car: the racing number on the doors and the hood, the handle on the
## side skirts, a two-tone stripe along the flanks and a parody sponsor.
##
## The marks are quads parented to the body of the car, not decals: a decal is a projector in
## the world and would swim on a car that moves. The textures are generated once per racer
## into `res://ai/rivals/textures/`.

const DIR := "res://ai/rivals/textures/"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"
const NUMBER_SIZE := Vector2i(256, 256)
const TEXT_SIZE := Vector2i(512, 96)
const DISC_COLOR := Color("f2f6ff")
const NUMBER_COLOR := Color("111113")
const TEXT_COLOR := Color("f2f6ff")
const ROUNDEL := 0.55     ## m: the diameter of the number roundel
const HANDLE_HEIGHT := 0.18 ## m: the height of the handle on the skirt
const SPONSOR_HEIGHT := 0.2 ## m
const STRIPE_HEIGHT := 0.12 ## m
const SKIN_OFFSET := 0.006  ## m: the marks stand off the body, so they never z-fight

static var _cache: Dictionary = {}


## Puts the livery of a racer on its car.
static func apply(visual: Node3D, index: int) -> void:
	if visual == null:
		return
	var half_width := _body_half_width(visual)
	var roof := _body_top(visual)
	_add_stripes(visual, index, half_width)
	await _add_roundels(visual, index, half_width, roof)
	await _add_handles(visual, index, half_width)
	await _add_sponsors(visual, index, half_width)


## The number roundel on both doors and the hood.
static func _add_roundels(visual: Node3D, index: int, half_width: float, roof: float) -> void:
	var texture := await number_texture(RivalFleet.number_of(index))
	if texture == null:
		return
	var material := _mark_material(texture)
	for side in [-1.0, 1.0]:
		var quad := _quad(visual, "Roundel%s" % ("L" if side < 0.0 else "R"), material,
			Vector3(side * (half_width + SKIN_OFFSET), 0.62, -0.35), Vector2(ROUNDEL, ROUNDEL))
		quad.rotation.y = side * PI * 0.5
	var hood := _quad(visual, "RoundelHood", material,
		Vector3(0.0, roof + SKIN_OFFSET, -1.25), Vector2(ROUNDEL, ROUNDEL))
	hood.rotation.x = -PI * 0.5


## The handle of the racer on the side skirts.
static func _add_handles(visual: Node3D, index: int, half_width: float) -> void:
	var texture := await handle_texture(RivalFleet.name_of(index))
	if texture == null:
		return
	var material := _mark_material(texture)
	for side in [-1.0, 1.0]:
		var quad := _quad(visual, "Handle%s" % ("L" if side < 0.0 else "R"), material,
			Vector3(side * (half_width + SKIN_OFFSET), 0.32, 0.15),
			Vector2(ROUNDEL * 1.7, HANDLE_HEIGHT))
		quad.rotation.y = side * PI * 0.5


## The parody sponsor on the rear quarter panels.
static func _add_sponsors(visual: Node3D, index: int, half_width: float) -> void:
	var texture := await sponsor_texture(RivalFleet.sponsor_of(index))
	if texture == null:
		return
	var material := _mark_material(texture)
	for side in [-1.0, 1.0]:
		var quad := _quad(visual, "Sponsor%s" % ("L" if side < 0.0 else "R"), material,
			Vector3(side * (half_width + SKIN_OFFSET), 0.78, 0.85),
			Vector2(ROUNDEL * 1.6, SPONSOR_HEIGHT))
		quad.rotation.y = side * PI * 0.5


## The two-tone stripe along the flanks.
static func _add_stripes(visual: Node3D, index: int, half_width: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = RivalFleet.stripe_of(index)
	material.roughness = 0.3
	material.metallic = 0.1
	for side in [-1.0, 1.0]:
		var quad := _quad(visual, "Stripe%s" % ("L" if side < 0.0 else "R"), material,
			Vector3(side * (half_width + SKIN_OFFSET), 0.46, -0.2),
			Vector2(3.4, STRIPE_HEIGHT))
		quad.rotation.y = side * PI * 0.5


## A mark quad on the car.
static func _quad(visual: Node3D, node_name: String, material: Material, position: Vector3,
		size: Vector2) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var plane := QuadMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.position = position
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(mesh)
	return mesh


## The material of a mark: the texture with its alpha, lit like the paint.
static func _mark_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.32
	material.metallic = 0.05
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


## The half width of the body of the car (the marks follow the real shape).
static func _body_half_width(visual: Node3D) -> float:
	var body := visual.find_child("Body", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		return 0.97
	var box := body.mesh.get_aabb()
	return maxf(absf(box.position.x + box.size.x * 0.5), absf(box.end.x)) * 0.98


## The height of the roof of the car.
static func _body_top(visual: Node3D) -> float:
	var body := visual.find_child("Body", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		return 0.98
	var box := body.mesh.get_aabb()
	return box.end.y


## The number roundel of a racer: a white disc with the number on it.
static func number_texture(number: int) -> Texture2D:
	var setup := func(label: Label) -> void:
		label.text = str(number)
		label.add_theme_font_size_override("font_size", 150)
		label.add_theme_color_override("font_color", NUMBER_COLOR)
	var disc := _disc_texture()
	return await _texture("number_%d" % number, NUMBER_SIZE, setup, disc)


## The handle of a racer (its Chinese name).
static func handle_texture(handle: String) -> Texture2D:
	var setup := func(label: Label) -> void:
		label.text = handle
		label.add_theme_font_size_override("font_size", 64)
		label.add_theme_color_override("font_color", TEXT_COLOR)
	return await _texture("handle_%s" % handle, TEXT_SIZE, setup)


## The parody sponsor of a racer.
static func sponsor_texture(sponsor: String) -> Texture2D:
	var setup := func(label: Label) -> void:
		label.text = sponsor
		label.add_theme_font_size_override("font_size", 56)
		label.add_theme_color_override("font_color", Color("ffd23f"))
	return await _texture("sponsor_%s" % sponsor, TEXT_SIZE, setup)


## Generates (or loads) a texture with a label in it.
static func _texture(key: String, size: Vector2i, setup: Callable,
		background: Texture2D = null) -> Texture2D:
	if _cache.has(key):
		return _cache[key] as Texture2D
	var file := DIR + "livery_%s.png" % key
	if ResourceLoader.exists(file):
		var loaded := load(file) as Texture2D
		if loaded != null:
			_cache[key] = loaded
			return loaded
	var image := await _render(size, setup, background)
	if image == null:
		return null
	_save(image, file)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Draws a label into an image.
static func _render(size: Vector2i, setup: Callable, background: Texture2D = null) -> Image:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists(FONT_PATH):
		var font := load(FONT_PATH) as Font
		if font != null:
			label.add_theme_font_override("font", font)
	if background != null:
		var plate := TextureRect.new()
		plate.texture = background
		plate.size = Vector2(size)
		plate.stretch_mode = TextureRect.STRETCH_SCALE
		viewport.add_child(plate)
	setup.call(label)
	viewport.add_child(label)
	tree.root.add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## The white disc of the number roundel.
static func _disc_texture() -> Texture2D:
	if _cache.has("disc"):
		return _cache["disc"] as Texture2D
	var image := Image.create(NUMBER_SIZE.x, NUMBER_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var centre := Vector2(NUMBER_SIZE.x, NUMBER_SIZE.y) * 0.5
	var radius := float(NUMBER_SIZE.x) * 0.46
	for y in NUMBER_SIZE.y:
		for x in NUMBER_SIZE.x:
			if Vector2(x, y).distance_to(centre) < radius:
				image.set_pixel(x, y, DISC_COLOR)
	var texture := ImageTexture.create_from_image(image)
	_cache["disc"] = texture
	return texture


## Writes a texture to the project (a failure is not an error: the texture stays in memory).
static func _save(image: Image, file: String) -> void:
	var dir := DirAccess.open("res://ai/rivals")
	if dir == null:
		return
	if not dir.dir_exists("textures"):
		dir.make_dir("textures")
	var error := image.save_png(file)
	if error != OK:
		push_warning("[rivals] could not write %s (error %d)" % [file, error])

extends Control
## One centre pop-up ("toast"): a big Chinese line, a small tracked English sub-label with the
## points after it, over a skewed glass plate with an accent bar.
## Dossier §8.4: 0.12 s pop to 110 % → 100 %, 0.8 s hold, 0.25 s fade.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")

signal finished

const HOLD_TIME := 0.8
const FADE_TIME := 0.25
const POP_TIME := 0.12
const ZH_SIZE := 60
const EN_SIZE := 22
const OUTLINE := 8
const PLATE_TOP := Color(0.043, 0.059, 0.102, 0.65)
const PLATE_BOTTOM := Color(0.043, 0.059, 0.102, 0.45)
## The plate leans to the RIGHT, like the takedown banner (dossier §3.5): the bottom edge is
## s = tan(12 deg) * h further LEFT than the top edge.
const SKEW_DEG := 12.0
const ACCENT_WIDTH := 3.0
const PAD_X := 26.0
const PAD_Y := 12.0
const SUB_GAP := 12.0
## The glass texture is a 128 px tile.
const GLASS_TILE := 128.0

var _zh: Label
var _en: Label
var _points: Label
var _sub: HBoxContainer
var _tween: Tween
var _accent: Color = Palette.CYAN
## The colour of the bar along the slanted edge. It defaults to the accent, but a white accent
## would be invisible on the light glass plate, so it can be set apart.
var _bar: Color = Palette.CYAN
var _base_points: String = ""
var _count: int = 1
var _zh_text: String = ""
var _en_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The glass texture is tiled over the skewed plate, so the row must repeat it.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size * 0.5


## zh: the Chinese line; en: the small English sub-label; color: the accent colour;
## points: an optional "+800".
func setup(zh: String, en: String, color: Color, points: String = "", zh_size: int = ZH_SIZE,
		bar_color: Color = Color(0, 0, 0, 0)) -> void:
	_accent = color
	_bar = bar_color if bar_color.a > 0.0 else color
	_base_points = points
	_zh_text = zh
	_en_text = en
	_zh = UI.outlined_display_label(zh, zh_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	_zh.add_theme_constant_override("outline_size", OUTLINE)
	add_child(_zh)

	_sub = UI.h_box(BoxContainer.ALIGNMENT_CENTER, SUB_GAP)
	add_child(_sub)
	_en = UI.label(en, EN_SIZE, Color(1, 1, 1, 0.85), UI.Fonts.text_tracked(2),
		HORIZONTAL_ALIGNMENT_CENTER)
	_en.visible = not en.is_empty()
	_sub.add_child(_en)
	_points = UI.label(points, EN_SIZE, Palette.AMBER, UI.Fonts.text_tracked(2),
		HORIZONTAL_ALIGNMENT_CENTER)
	_points.visible = not points.is_empty()
	_sub.add_child(_points)
	_fit()


## Update the content of a live toast (used when a repeat is merged into it).
func set_content(zh: String, en: String, points: String) -> void:
	_zh_text = zh
	_en_text = en
	_base_points = points
	if _zh != null:
		_zh.text = zh
	if _en != null:
		_en.text = en
		_en.visible = not en.is_empty()
	if _points != null:
		_points.text = _points_text()
		_points.visible = not _points_text().is_empty()
	_fit()


## The points with the merge counter: "+5 ×3".
func _points_text() -> String:
	if _base_points.is_empty():
		return "" if _count <= 1 else "×%d" % _count
	return _base_points if _count <= 1 else "%s ×%d" % [_base_points, _count]


## Merge a repeat into this toast.
func add_count() -> void:
	_count += 1
	if _points != null:
		_points.text = _points_text()
		_points.visible = not _points_text().is_empty()


## The merge key of this toast: the Chinese and the English line.
func merge_key() -> String:
	return _zh_text + "|" + _en_text


## The Chinese line of this toast.
func zh_text() -> String:
	return _zh_text


## The English sub-label of this toast.
func en_text() -> String:
	return _en_text


## Is the row still on screen?
func is_valid() -> bool:
	return _zh != null and is_instance_valid(_zh)


## Size the row around its content and place the lines.
func _fit() -> void:
	if _zh == null:
		return
	var zh_size := _zh.get_minimum_size()
	var sub_w := 0.0
	if _en.visible:
		sub_w += _en.get_minimum_size().x
	if _points.visible:
		sub_w += _points.get_minimum_size().x
	if _en.visible and _points.visible:
		sub_w += SUB_GAP
	var w := maxf(zh_size.x, sub_w) + PAD_X * 2.0
	# The sub row is a container: its height is at least the height of its labels.
	var sub_h := maxf(EN_SIZE + 6.0, _sub.get_combined_minimum_size().y)
	var h := zh_size.y + PAD_Y * 2.0
	if _en.visible or _points.visible:
		h = PAD_Y + zh_size.y + 4.0 + sub_h + PAD_Y
	var skew := tan(deg_to_rad(SKEW_DEG)) * h
	# The row is the bounding box of the skewed plate.
	custom_minimum_size = Vector2(w + skew, h)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	_zh.size = Vector2(w, zh_size.y)
	_zh.position = Vector2(_edge_x(skew, h, PAD_Y + zh_size.y * 0.5), PAD_Y)
	_zh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub_y := PAD_Y + zh_size.y + 4.0
	_sub.position = Vector2(_edge_x(skew, h, sub_y + sub_h * 0.5), sub_y)
	_sub.size = Vector2(w, sub_h)
	_sub.alignment = BoxContainer.ALIGNMENT_CENTER


## The x of the plate's left edge at a given height: the plate leans to the right, so the edge
## moves LEFT as y grows. Every line is shifted by the edge offset at its own height, so the text
## keeps the same margin over the accent bar.
func _edge_x(skew: float, h: float, y: float) -> float:
	return skew - skew * clampf(y / maxf(h, 1.0), 0.0, 1.0)


func play() -> void:
	modulate.a = 0.0
	scale = Vector2(0.75, 0.75)
	pivot_offset = size * 0.5
	_scanline()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.set_parallel(false)
	_tween.tween_property(self, "modulate:a", 1.0, 0.08)
	_tween.parallel().tween_property(self, "scale", Vector2(1.1, 1.1), POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(_on_finished)


## Restart the animation of a merged toast so it does not fade away with the old content.
func restart() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	play()


## One cyan scanline sweeps across the pop-up as it appears (the only glitch in the HUD).
func _scanline() -> void:
	var band := ColorRect.new()
	band.color = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.55)
	band.size = Vector2(size.x, 2.0)
	band.position = Vector2(0.0, -4.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.tween_property(band, "position:y", size.y + 4.0, 0.22).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(band, "color:a", 0.0, 0.22)
	t.tween_callback(band.queue_free)


## The skewed glass plate behind the text, with an accent bar along its slanted left edge.
func _draw() -> void:
	if size.x <= 0.0:
		return
	var h := size.y
	var skew := tan(deg_to_rad(SKEW_DEG)) * h
	var w := size.x - skew
	var pts := PackedVector2Array([
		Vector2(skew, 0.0), Vector2(skew + w, 0.0), Vector2(w, h), Vector2(0.0, h)])
	var colors := PackedColorArray([PLATE_TOP, PLATE_TOP, PLATE_BOTTOM, PLATE_BOTTOM])
	draw_polygon(pts, colors)
	# The glass texture, clipped to the parallelogram (a plain rect would spill out of it).
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / GLASS_TILE)
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
		uvs, UI.glass_texture())
	# The accent bar along the slanted left edge.
	draw_line(Vector2(skew, 0.0), Vector2(0.0, h), _bar, ACCENT_WIDTH, true)


func _on_finished() -> void:
	finished.emit()
	queue_free()

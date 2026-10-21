extends Control
## A SKYRUSH glass panel: the chamfered plate of `glass_panel.gdshader` (blurred backdrop, dark
## tint, film grain, scanlines, a cyan edge and corner brackets) with the panel's English header
## in the strip under the top edge, like the HUD panels.
##
## The panel owns a vertical box so screens can drop their content into `content`.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const GLASS := preload("res://ui/menu/widgets/glass_panel.gdshader")

const MARGIN := 26.0
const HEADER_SIZE := 13
const HEADER_TRACKING := 2.5
const HEADER_HEIGHT := 26.0

var content: VBoxContainer

var _header: String = ""
var _header_label: Label
var _material: ShaderMaterial


func _init(title: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = GLASS
	material = _material

	_header_label = UI.label("", HEADER_SIZE, Palette.TEXT, Fonts.display())
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header_label)

	content = UI.v_box(BoxContainer.ALIGNMENT_BEGIN, 10)
	add_child(content)

	resized.connect(_sync_size)
	set_header(title)
	_sync_size()


## The material needs a draw command: the whole rect is drawn and the shader paints it.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _process(_delta: float) -> void:
	# The shader needs the panel size in pixels; the layout can change it at any time.
	if _material != null and _material.get_shader_parameter("panel_size") != size:
		_sync_size()


## The English label in the header strip ("" = none).
func set_header(text: String) -> void:
	_header = text
	_header_label.text = text
	_header_label.visible = not text.is_empty()
	_sync_size()


func _sync_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("panel_size", size)
	_material.set_shader_parameter("header_h", HEADER_HEIGHT if not _header.is_empty() else 0.0)
	var top := MARGIN + (HEADER_HEIGHT if not _header.is_empty() else 0.0)
	content.position = Vector2(MARGIN, top)
	content.size = Vector2(maxf(size.x - MARGIN * 2.0, 0.0), maxf(size.y - top - MARGIN, 0.0))
	_header_label.position = Vector2(34.0, 6.0)

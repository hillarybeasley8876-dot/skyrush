extends CanvasLayer
## Screen-space overlay of the camera unit: the speed-line streaks and the white
## hit-stop flash. Lives on canvas layer 0 so the HUD (layer 1+) always draws on top.

const STREAK_SHADER := preload("res://vehicle/camera/speed_lines.gdshader")

const FLASH_ALPHA := 0.35

## The speed-line material; the effects node writes its uniforms every frame.
var streak_material: ShaderMaterial = null

var _streaks: ColorRect
var _flash: ColorRect


func _ready() -> void:
	layer = 0
	streak_material = ShaderMaterial.new()
	streak_material.shader = STREAK_SHADER
	_streaks = ColorRect.new()
	_streaks.name = "SpeedLines"
	_streaks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streaks.material = streak_material
	_streaks.color = Color(1.0, 1.0, 1.0, 1.0)
	_streaks.visible = false
	add_child(_streaks)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_flash)


## The streak quad: hidden while there is nothing to draw.
func set_streaks_visible(value: bool) -> void:
	if _streaks != null:
		_streaks.visible = value


## White flash for a single frame (takedown hit-stop, dossier §3.5). The alpha is
## cleared after the frame that draws it, so exactly one frame is white.
func flash_frame() -> void:
	if _flash == null:
		return
	_flash.color = Color(1.0, 1.0, 1.0, FLASH_ALPHA)
	if not RenderingServer.frame_post_draw.is_connected(_clear_flash):
		RenderingServer.frame_post_draw.connect(_clear_flash, CONNECT_ONE_SHOT)


func _clear_flash() -> void:
	if _flash != null:
		_flash.color = Color(1.0, 1.0, 1.0, 0.0)

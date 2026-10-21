extends Node
## A VMS board: the message changes every few seconds. The five textures are rendered once by
## the sign factory and cycled here, so no viewport is created every eight seconds.

## The seconds a message is shown.
const INTERVAL := 8.0

var mesh: MeshInstance3D
var factory: Node
## The index of the message that is shown.
var index := 0
var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = 0.0
	var messages: Array = factory.VMS_MESSAGES if factory != null else []
	if messages.is_empty():
		return
	index = (index + 1) % messages.size()
	_apply()


## Puts the texture of the current message on the board.
func _apply() -> void:
	if factory == null or mesh == null:
		return
	var textures: Array = factory.vms_textures()
	if textures.is_empty():
		return
	var texture: Texture2D = textures[index % textures.size()]
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_texture = texture
	mat.emission_texture = texture

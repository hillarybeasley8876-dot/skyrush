extends Camera3D
## Placeholder chase camera: follows Game.player from behind with smoothing.

const OFFSET := Vector3(0.0, 2.4, 7.0)


func _ready() -> void:
	fov = 72.0
	far = 4000.0
	current = true


func _physics_process(delta: float) -> void:
	var target := Game.player
	if target == null:
		return
	var desired := target.global_transform * OFFSET
	global_position = global_position.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
	look_at(target.global_position + Vector3.UP * 1.0, Vector3.UP)

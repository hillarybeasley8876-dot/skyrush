extends RefCounted
## Chase camera presets (briefs/camera.md: near / far / bumper, cycled with `camera_toggle`).
## near is the dossier §2.3 default (6.0 m back, 1.9 m up, look 4 m ahead / 1.2 m up);
## far and bumper take their geometry from the clone camera in dossier §2.2
## ({12.5, 4.6, 6, 1.5} and bumper look-ahead 8 m / height 1.1 m).

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

enum Preset { NEAR, FAR, BUMPER }


## One preset: how far back and how high the camera sits, and what it aims at.
class Setup extends RefCounted:
	var name: String = ""
	var dist: float = 0.0
	var height: float = 0.0
	var look_ahead: float = 0.0
	var look_height: float = 0.0

	func _init(p_name: String, p_dist: float, p_height: float, p_ahead: float, p_lheight: float) -> void:
		name = p_name
		dist = p_dist
		height = p_height
		look_ahead = p_ahead
		look_height = p_lheight


## Fallback bumper mount when the car has no `Camera_Hood` marker (contract §6):
## 0.9 m above the car origin, 1.0 m ahead of it.
const BUMPER_FALLBACK := Vector3(0.0, 0.9, -1.0)
## The hood view looking back: a mount behind the car, so the view is not through the body.
const BUMPER_REAR_MOUNT := Vector3(0.0, 1.1, 2.3)

## The far preset and the bumper preset are the clone camera's (dossier §2.2).
const FAR_DIST := 12.5
const FAR_HEIGHT := 4.6
const FAR_LOOK_AHEAD := 6.0
const FAR_LOOK_HEIGHT := 1.5
const BUMPER_LOOK_AHEAD := 8.0
const BUMPER_LOOK_HEIGHT := 1.1

const NAMES: Array[String] = ["near", "far", "bumper"]

static var _setups: Array[Setup] = []


static func _build() -> void:
	if not _setups.is_empty():
		return
	_setups = [
		Setup.new("near", CameraMath.DIST_REST, CameraMath.HEIGHT_REST,
				CameraMath.LOOK_AHEAD, CameraMath.LOOK_HEIGHT),
		Setup.new("far", FAR_DIST, FAR_HEIGHT, FAR_LOOK_AHEAD, FAR_LOOK_HEIGHT),
		Setup.new("bumper", 0.0, 0.0, BUMPER_LOOK_AHEAD, BUMPER_LOOK_HEIGHT),
	]


static func get_preset(preset: int) -> Setup:
	_build()
	return _setups[clampi(preset, 0, _setups.size() - 1)]


static func next_preset(preset: int) -> int:
	return (preset + 1) % NAMES.size()

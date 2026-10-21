extends Node3D
## The menu's title stage: the camera that frames the player's Roadster parked on the Bund
## promenade, in three authored beats.
##
## The spot is derived from the lane data at run time and validated before the car is parked
## there: it must stand at least MIN_CLEARANCE away from every lane centreline of the
## neighbourhood, on the ground, and clear of the props (a lamp, a tree, a wall). The world is
## built over several seconds, so the spot is only derived once `Game.world_ready()` has come
## back — before that there are no lanes and the car would be parked in the traffic.
##
## Each beat lasts BEAT_SECONDS with a slow dolly; the change between the beats is covered by a
## 1.2 s cross-fade (the title screen snapshots the frame and fades it out).
##
## The stage owns the menu camera: it takes over when the front end is open and gives the game
## camera back when it closes.

## The beats: the camera offset and the aim, both relative to the car, the field of view and
## the dolly (how far the camera drifts out over the beat).
##
## The camera stands on the promenade and looks along the Bund, so the background is the
## street, the trees, the neon signs and the night sky — never a wall.
const BEATS: Array[Dictionary] = [
	{"name": "along_the_bund", "offset": Vector3(0.0, 1.7, 11.0), "aim": Vector3(-0.5, 1.0, -5.0),
		"fov": 44.0, "dolly": 0.8},
	{"name": "three_quarter", "offset": Vector3(6.0, 2.0, 9.0), "aim": Vector3(-2.0, 1.1, -3.0),
		"fov": 44.0, "dolly": 0.6},
	{"name": "low_hero", "offset": Vector3(2.0, 1.1, 7.0), "aim": Vector3(-1.0, 0.9, -2.0),
		"fov": 48.0, "dolly": 1.0},
]
const BEAT_SECONDS := 9.0
const CROSSFADE_SECONDS := 1.2

const TitleSpot := preload("res://ui/menu/widgets/title_spot.gd")

## The beat changed: the title screen cross-fades over it.
signal beat_changed(index: int)

var camera: Camera3D

## The beats the capture rig previews (empty = the authored ones).
var beat_override: Array[Dictionary] = []
## How long a preview beat lasts (0 = the authored nine seconds).
var beat_seconds_override: float = 0.0

var _beat: int = 0
var _beat_time: float = 0.0
var _blend: float = 1.0
var _offset: Vector3 = Vector3.ZERO
var _from_offset: Vector3 = Vector3.ZERO
var _to_offset: Vector3 = Vector3.ZERO
var _game_camera: Camera3D = null
var _active: bool = false
## The validated parking spot (zero when the world has no lanes yet).
var _spot: Vector3 = Vector3.ZERO
var _has_spot: bool = false
## The search of the parking spot.
var _spot_search: TitleSpot = null


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 1200.0
	add_child(camera)
	_to_offset = _beat_offset(0)
	_offset = _to_offset
	# The stage may have been asked to take the camera before it was in the tree.
	_apply_active()


## Where the car is parked (derived from the lanes of the world).
func parking_spot() -> Vector3:
	return _spot


## The distance the parked car keeps from the nearest lane centreline.
func lane_clearance() -> float:
	return _spot_search.clearance if _spot_search != null else 0.0


## True when a validated spot was found.
func has_spot() -> bool:
	return _has_spot


## Derives the parking spot from the lanes of the world. The world must be built.
func prepare() -> void:
	if _has_spot:
		return
	_spot_search = TitleSpot.new()
	_spot_search.node = self
	_spot_search.camera_offsets = _camera_offsets()
	_has_spot = _spot_search.search()
	if _has_spot:
		_spot = _spot_search.spot


## Parks the player's car on the promenade, facing north (-Z, the traffic direction).
func park_the_car() -> void:
	if Game.player == null or not _has_spot:
		return
	Game.player.reset_to(Transform3D(Basis.IDENTITY, _spot))


## Takes the camera over from the game (the camera only exists once the stage is in the tree).
func activate() -> void:
	_active = true
	_apply_active()


## Gives the camera back to the game.
func deactivate() -> void:
	if not _active:
		return
	_active = false
	if camera != null:
		camera.clear_current(false)
	if _game_camera != null and is_instance_valid(_game_camera):
		_game_camera.make_current()
	_game_camera = null


## Makes the menu camera the current one (and remembers the game camera).
func _apply_active() -> void:
	if not _active or camera == null or not is_instance_valid(camera):
		return
	var current := get_viewport().get_camera_3d()
	if current != null and current != camera:
		_game_camera = current
	camera.make_current()


func _process(delta: float) -> void:
	if camera == null or not _active:
		return
	_beat_time += delta
	if _beat_time >= _beat_seconds():
		_beat_time = 0.0
		_next_beat()
	_blend = minf(1.0, _blend + delta / CROSSFADE_SECONDS)
	_update_camera()


func _next_beat() -> void:
	_beat = (_beat + 1) % _beats().size()
	_from_offset = _offset
	_to_offset = _beat_offset(_beat)
	_blend = 0.0
	# The signal comes first: the title screen snapshots the frame of the old camera.
	beat_changed.emit(_beat)


## The beats in use (the preview ones when the capture rig set them).
func _beats() -> Array[Dictionary]:
	return beat_override if not beat_override.is_empty() else BEATS


## How long a beat lasts.
func _beat_seconds() -> float:
	return beat_seconds_override if beat_seconds_override > 0.0 else BEAT_SECONDS


## The camera offsets of every beat (the spot search needs them).
func _camera_offsets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in _beats().size():
		out.append(_beat_offset(index))
	return out


## The camera offset of a beat, relative to the car.
func _beat_offset(index: int) -> Vector3:
	var beat: Dictionary = _beats()[index]
	var offset: Vector3 = beat["offset"]
	return offset


## The point the beat looks at, relative to the car.
func _beat_aim(index: int) -> Vector3:
	var beat: Dictionary = _beats()[index]
	var aim: Vector3 = beat["aim"]
	return aim


func _update_camera() -> void:
	var beat: Dictionary = _beats()[_beat]
	# The dolly pushes the camera slowly out along its own radius.
	var dolly := float(beat["dolly"]) * (_beat_time / _beat_seconds())
	var target := _beat_offset(_beat)
	var flat := Vector2(target.x, target.z)
	if flat.length() > 0.01:
		flat = flat.normalized() * (flat.length() + dolly)
		target = Vector3(flat.x, target.y, flat.y)
	_to_offset = target
	_offset = _from_offset.lerp(_to_offset, _blend)
	var aim := _car_aim()
	camera.global_position = aim + _offset
	camera.fov = lerpf(float(beat["fov"]), float(beat["fov"]) * 0.92, _beat_time / _beat_seconds())
	camera.look_at(aim + _beat_aim(_beat), Vector3.UP)
	if not camera.current:
		camera.make_current()


## The point the camera looks at: the car, or the spot when there is no car.
func _car_aim() -> Vector3:
	if Game.player != null:
		return Game.player.global_position
	return _spot


## The physics space of the world (null when there is none).
func _space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var world := get_world_3d()
	if world == null:
		return null
	return world.direct_space_state

extends Node
## The base of the two event mappers (the vehicle sounds and the race sounds).
##
## It holds the helpers that talk to the director, so both mappers stay small and share the
## same defensive style: a missing player, a missing stream or a null event argument must
## never break the game loop.

const AudioDirectorScript := preload("res://audio/audio_director.gd")
const Tuning := preload("res://audio/audio_tuning.gd")

## The director (the parent node).
var _audio: AudioDirectorScript


func _ready() -> void:
	# the mappers follow the game: they are paused with it (the signals still arrive)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_audio = get_parent() as AudioDirectorScript
	_connect_all()


## The subclasses connect their events here.
func _connect_all() -> void:
	pass


## True when the vehicle is the player's car.
func _is_player(vehicle: VehicleBase) -> bool:
	return vehicle != null and vehicle == Game.player


## Plays a voice line (the queue decides whether it is cut).
func _voice(id: StringName, priority: int = Tuning.VOICE_PRIORITY_QUEUED) -> void:
	if id == &"" or _audio == null:
		return
	_audio.play_voice(id, priority)


## Plays a one-shot in front of the listener.
func _sfx(id: StringName, volume_db: float = 0.0, pitch: float = 1.0, priority: int = 1) -> void:
	if _audio != null:
		_audio.play_sfx(id, volume_db, pitch, priority)


## Plays a one-shot at a position in the world.
func _sfx_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0,
		priority: int = 1) -> void:
	if _audio != null:
		_audio.play_3d(id, position, volume_db, pitch, priority)

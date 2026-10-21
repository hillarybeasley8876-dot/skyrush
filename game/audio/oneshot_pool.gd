extends Node
## Pool of AudioStreamPlayers for one-shot sounds (2D and 3D).
##
## The bookkeeping is exact: `active_count()` is the number of players that are really playing,
## every player appears at most once in the pool bookkeeping, and a full pool steals the oldest
## low-priority sound of that pool (never a high-priority one: a lower priority number means a
## more important sound, so an important sound is never cut for a less important one).
##
## Loop ids are rejected here: they need a dedicated player that can be moved and stopped
## (see world_emitters.gd :: attach_loop).

const Tuning := preload("res://audio/audio_tuning.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")

## Emitted whenever a one-shot is played (the demo scene captions it).
signal played(id: StringName)

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
## One entry per playing sound: {node, id, started, priority, is_3d}.
var _entries: Array[Dictionary] = []
## True while the game is paused (the gameplay sounds are dropped, the ui sounds still play).
var _paused := false


func _ready() -> void:
	for i in Tuning.POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool_2d.append(p)
	for i in Tuning.POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX"
		p3.max_distance = Tuning.POOL_MAX_DISTANCE_M
		p3.unit_size = Tuning.POOL_UNIT_SIZE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(p3)
		_pool_3d.append(p3)


## Plays a 2D one-shot. Returns false when the id is a loop id or the stream is missing.
func play_2d(id: StringName, volume_db: float = 0.0, pitch: float = 1.0, priority: int = 1) -> bool:
	if Tuning.LOOP_IDS.has(id):
		push_warning("[audio] %s is a loop and needs attach_loop()" % id)
		return false
	var stream := SfxLibrary.stream(id)
	if stream == null:
		push_warning("[audio] missing sfx: %s" % id)
		return false
	if _dropped(id):
		return false
	var p := _take_2d(priority)
	if p == null:
		return false
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	# a player that was paused with the game has to run again
	p.stream_paused = false
	p.play()
	_entries.append({"node": p, "id": id, "started": _now(), "priority": priority, "is_3d": false})
	played.emit(id)
	return true


## Plays a 3D one-shot at a world position.
func play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, priority: int = 1) -> bool:
	if Tuning.LOOP_IDS.has(id):
		push_warning("[audio] %s is a loop and needs attach_loop()" % id)
		return false
	var stream := SfxLibrary.stream(id)
	if stream == null:
		push_warning("[audio] missing sfx: %s" % id)
		return false
	if _dropped(id):
		return false
	var p := _take_3d(priority)
	if p == null:
		return false
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db
	p.pitch_scale = pitch
	# a player that was paused with the game has to run again
	p.stream_paused = false
	p.play()
	_entries.append({"node": p, "id": id, "started": _now(), "priority": priority, "is_3d": true})
	played.emit(id)
	return true


## True when the sound has to be dropped (the game is paused and it is not a ui sound).
func _dropped(id: StringName) -> bool:
	if not _paused:
		return false
	return not String(id).begins_with("ui_")


## Number of one-shots playing right now (never above the pool size).
func active_count() -> int:
	_prune()
	return _entries.size()


## The number of pool players that are really playing (the same as active_count, checked by tests).
func playing_players() -> int:
	var count := 0
	for p in _pool_2d:
		if p.playing:
			count += 1
	for p in _pool_3d:
		if p.playing:
			count += 1
	return count


## Stops every one-shot (used when the game is paused or the scene is torn down).
func stop_all() -> void:
	for e in _entries:
		_stop(e["node"])
	_entries.clear()


## Pauses or resumes every one-shot (the game pause). The gameplay sounds are dropped while
## the game is paused, the ui sounds of the pause menu still play.
func set_paused(paused: bool) -> void:
	_paused = paused
	for e in _entries:
		var node := e["node"] as Node
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stream_paused = paused
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stream_paused = paused


func _now() -> float:
	return Time.get_ticks_msec() * Tuning.SECONDS_PER_MS


## True while the entry's player is still alive and playing.
func _is_playing(entry: Dictionary) -> bool:
	var node := entry["node"] as Node
	if node == null or not is_instance_valid(node):
		return false
	if node is AudioStreamPlayer:
		return (node as AudioStreamPlayer).playing
	if node is AudioStreamPlayer3D:
		return (node as AudioStreamPlayer3D).playing
	return false


func _prune() -> void:
	for i in range(_entries.size() - 1, -1, -1):
		if not _is_playing(_entries[i]):
			_entries.remove_at(i)


func _take_2d(priority: int) -> AudioStreamPlayer:
	_prune()
	for p in _pool_2d:
		if not p.playing:
			return p
	return _steal_in(false, priority) as AudioStreamPlayer


func _take_3d(priority: int) -> AudioStreamPlayer3D:
	_prune()
	for p in _pool_3d:
		if not p.playing:
			return p
	return _steal_in(true, priority) as AudioStreamPlayer3D


## Steals the oldest entry of the given pool that is less important than the incoming one (a
## lower priority number means a more important sound). It returns null when nothing may be
## stolen: an important sound is never cut for a less important one, the incoming sound is
## dropped instead.
func _steal_in(want_3d: bool, priority: int) -> Node:
	var best: Dictionary = {}
	for e in _entries:
		if bool(e["is_3d"]) != want_3d:
			continue
		if int(e["priority"]) < priority:
			continue
		if best.is_empty() or float(e["started"]) < float(best["started"]):
			best = e
	if best.is_empty():
		return null
	var victim := best["node"] as Node
	_stop(victim)
	_entries.erase(best)
	return victim


func _stop(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()

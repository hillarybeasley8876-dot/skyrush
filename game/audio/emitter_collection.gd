extends Node
## The collection of the positional loop emitters: a loop follows a target node, moves with it
## (so the doppler works) and is freed with it.
##
## The base class owns the voices, the fades and the scan of the scene groups. The sirens and
## the river bed live in world_emitters.gd, which extends this class.
##
## Every emitter fades in and out (no clicks, no level steps), every entry keeps the Callable it
## connected, so every removal path disconnects it again — a freed target can never reach a
## stale signal. The one-shots of the emitters go through the `one_shot_requested` signal, so
## the emitters never need to know the director.

const Tuning := preload("res://audio/audio_tuning.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const EmitterVoice := preload("res://audio/emitter_voice.gd")

## Emitted when the emitters want a one-shot (the director owns the pool).
signal one_shot_requested(id: StringName, position: Vector3, volume_db: float)

## The heat level (0..5) — below HEAT_SIREN_FROM no siren is placed at all.
var heat := 0

## One entry per emitter: {voice, target, callable, horn_callable, id, player, yelp, alternate,
## yelp_timer}.
var _emitters: Array[Dictionary] = []
var _scan_timer := 0.0
## The police horn timer (the seconds since the last horn).
var _horn_timer := 0.0
## True while the game is paused.
var _paused := false


func _ready() -> void:
	# the emitters follow the world, so they are paused with the game (the signals still arrive)
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Creates a looping emitter that follows `target`. Returns the player (null when the id is not a
## loop or the stream is missing).
func attach_loop(id: StringName, target: Node3D, volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer3D:
	if target == null or not is_instance_valid(target):
		return null
	var streams := _streams_for(id)
	if streams.is_empty():
		push_warning("[audio] missing loop: %s" % id)
		return null
	var voice := EmitterVoice.new()
	voice.setup(self, streams, id, volume_db, _unit_size(id), target)
	if pitch != 1.0:
		voice.player.pitch_scale = pitch
		if voice.standby != null:
			voice.standby.pitch_scale = pitch
	voice.set_paused(_paused)
	# the callable is kept in the entry so it can be disconnected in every removal path
	var on_exit := _on_target_exiting.bind(voice)
	target.tree_exiting.connect(on_exit)
	var entry := {
		"voice": voice, "target": target, "callable": on_exit, "id": id,
		"player": voice.player, "yelp": false, "alternate": false,
		"yelp_timer": _siren_timer(id),
	}
	_emitters.append(entry)
	if id == &"traffic_ev_hum":
		_connect_horn(target, entry)
	return voice.player


## The countdown of a siren to its first switch (the subclasses spread the cars).
func _siren_timer(_id: StringName) -> float:
	return 0.0


## The samples of an emitter kind (a siren carries the wail and the yelp).
func _streams_for(id: StringName) -> Array:
	if id == &"siren_wail":
		return [SfxLibrary.stream(&"siren_wail", SfxLibrary.SFX_DIR, true),
				SfxLibrary.stream(&"siren_yelp", SfxLibrary.SFX_DIR, true)]
	return [SfxLibrary.stream(id, SfxLibrary.SFX_DIR, true)]


## The audio sphere of an emitter kind (m): inside it the sound is heard at its full level.
func _unit_size(id: StringName) -> float:
	match id:
		&"siren_wail":
			return Tuning.SIREN_UNIT_SIZE_M
		&"traffic_ev_hum":
			return Tuning.HUM_UNIT_SIZE_M
		&"river_ambience":
			return Tuning.RIVER_UNIT_SIZE_M
	return Tuning.EMITTER_DEFAULT_UNIT_SIZE_M


## Stops and frees an emitter created by attach_loop().
func stop_loop(handle: AudioStreamPlayer3D) -> void:
	if handle == null:
		return
	for i in range(_emitters.size() - 1, -1, -1):
		var voice := _entry_voice(_emitters[i])
		if voice != null and voice.player == handle:
			_remove(i)
			return


## Stops every emitter.
func stop_all() -> void:
	for i in range(_emitters.size() - 1, -1, -1):
		_remove(i)


## Pauses or resumes every emitter (the game pause).
func set_paused(paused: bool) -> void:
	_paused = paused
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice != null:
			voice.set_paused(paused)


## The number of emitters that are alive (the test uses it).
func emitter_count() -> int:
	return _emitters.size()


## The number of emitters of a kind (the test checks the sirens).
func emitter_count_for(id: StringName) -> int:
	var count := 0
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice != null and voice.id == id:
			count += 1
	return count


## The player of the traffic hum (the test checks its pitch).
func hum_player() -> AudioStreamPlayer3D:
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice != null and voice.id == &"traffic_ev_hum":
			return voice.player
	return null


## The number of emitters that are really playing.
func playing_count() -> int:
	var count := 0
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice != null and voice.player != null and voice.player.playing:
			count += 1
	return count


func _exit_tree() -> void:
	stop_all()


## The voice of an entry, or null when it is gone (never a cast of a freed object).
func _entry_voice(entry: Dictionary) -> EmitterVoice:
	var obj: Variant = entry.get("voice", null)
	if obj == null or not is_instance_valid(obj):
		return null
	return obj as EmitterVoice


## The target of an entry, or null when it is gone.
func _entry_target(entry: Dictionary) -> Node3D:
	var obj: Variant = entry.get("target", null)
	if obj == null or not is_instance_valid(obj):
		return null
	return obj as Node3D


## Removes the entry, disconnects the signal and frees the players.
func _remove(index: int) -> void:
	var e := _emitters[index]
	_emitters.remove_at(index)
	var target := _entry_target(e)
	if target != null:
		var cb: Variant = e.get("callable", null)
		if cb is Callable and (cb as Callable).is_valid() \
				and target.tree_exiting.is_connected(cb as Callable):
			target.tree_exiting.disconnect(cb as Callable)
	_disconnect_horn(e)
	var voice := _entry_voice(e)
	if voice != null:
		voice.free_players()


## Lets an emitter fade out; it is freed when the fade is over.
func _drop(index: int) -> void:
	var voice := _entry_voice(_emitters[index])
	if voice == null:
		_remove(index)
		return
	voice.fade_out()


## The target's car leaves the tree: the emitter has to go with it.
func _on_target_exiting(voice: EmitterVoice) -> void:
	for i in range(_emitters.size() - 1, -1, -1):
		var v := _entry_voice(_emitters[i])
		if v == voice:
			_remove(i)
			return


# --- the traffic horn ----------------------------------------------------------------------------------
## The traffic unit asks for a horn through its own signal; the audio unit plays the sound.
func _connect_horn(target: Node3D, entry: Dictionary) -> void:
	if not target.has_signal(&"horn_requested"):
		return
	var cb := _on_traffic_horn.bind(target)
	if not target.is_connected(&"horn_requested", cb):
		target.connect(&"horn_requested", cb)
	entry["horn_callable"] = cb


func _disconnect_horn(entry: Dictionary) -> void:
	var target := _entry_target(entry)
	if target == null:
		return
	var cb: Variant = entry.get("horn_callable", null)
	if cb is Callable and (cb as Callable).is_valid() \
			and target.is_connected(&"horn_requested", cb as Callable):
		target.disconnect(&"horn_requested", cb as Callable)


func _on_traffic_horn(_car: Node, target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_play_one_shot(&"horn_traffic", target.global_position, Tuning.TRAFFIC_HORN_MIX_DB)


# --- the police horn ----------------------------------------------------------------------------------
## A short horn on the patrol cars that are close, while the heat is up.
func _update_horns(delta: float) -> void:
	_horn_timer += delta
	if _horn_timer < Tuning.POLICE_HORN_INTERVAL_S:
		return
	_horn_timer = 0.0
	if heat < Tuning.HEAT_SIREN_FROM + 1:
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var origin := player.global_position
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice == null or voice.id != &"siren_wail":
			continue
		var target := _entry_target(e)
		if target == null:
			continue
		if target.global_position.distance_to(origin) > Tuning.POLICE_HORN_RANGE_M:
			continue
		_play_one_shot(&"police_horn", target.global_position, Tuning.POLICE_HORN_MIX_DB)
		return


## Plays a one-shot through the director's pool (the emitters own no pool of their own).
func _play_one_shot(id: StringName, position: Vector3, volume_db: float) -> void:
	one_shot_requested.emit(id, position, volume_db)


func _physics_process(delta: float) -> void:
	# the emitters follow their targets so the doppler shift is correct
	for i in range(_emitters.size() - 1, -1, -1):
		var voice := _entry_voice(_emitters[i])
		if voice == null:
			_remove(i)
			continue
		var target := _entry_target(_emitters[i])
		if voice.id == &"traffic_ev_hum" and target != null:
			# the hum pitch follows the car's speed
			voice.player.pitch_scale = _speed_pitch(target)
		if not voice.process(delta):
			# the fade is over: the emitter is freed
			_remove(i)
	_scan_timer += delta
	if _scan_timer >= Tuning.EMITTER_SCAN_INTERVAL_S:
		_scan_timer = 0.0
		_scan_world()
	_update_horns(delta)


## The pitch of a traffic hum: faster cars hum higher.
func _speed_pitch(target: Node3D) -> float:
	var telemetry: Variant = target.get("telemetry")
	if telemetry == null:
		return 1.0
	var speed := float(telemetry.get("speed_kmh"))
	var norm := clampf(speed / Tuning.HUM_PITCH_SPEED_KMH, 0.0, 1.0)
	return Tuning.HUM_PITCH_MIN + (Tuning.HUM_PITCH_MAX - Tuning.HUM_PITCH_MIN) * norm


func _scan_world() -> void:
	_refresh_group_emitters(&"traffic", &"traffic_ev_hum", Tuning.TRAFFIC_EMITTER_MAX,
			Tuning.TRAFFIC_EMITTER_RANGE_M)
	_refresh_group_emitters(&"police", &"siren_wail", Tuning.POLICE_EMITTER_MAX,
			Tuning.POLICE_EMITTER_RANGE_M)
	_update_sources()


## The sources that need a scan of their own (the sirens and the river).
func _update_sources() -> void:
	pass


## The mix trim of an emitter kind (dB).
func _mix_db(id: StringName) -> float:
	if id == &"siren_wail":
		return Tuning.SIREN_EMITTER_DB
	if id == &"traffic_ev_hum":
		return Tuning.HUM_EMITTER_DB
	return 0.0


## Keeps one emitter per group member: the closest ones get a sound, the rest are silent.
func _refresh_group_emitters(group: StringName, id: StringName, max_count: int,
		range_m: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	# the sirens only exist while the heat is up
	if group == &"police" and heat < Tuning.HEAT_SIREN_FROM:
		max_count = 0
	var origin := player.global_position
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		var n3 := node as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		if n3.global_position.distance_to(origin) <= range_m:
			candidates.append(n3)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	var wanted := candidates.slice(0, maxi(0, max_count))
	# drop the emitters whose target is gone or too far
	for i in range(_emitters.size() - 1, -1, -1):
		var voice := _entry_voice(_emitters[i])
		if voice == null or voice.id != id:
			continue
		var target := _entry_target(_emitters[i])
		if target == null or not wanted.has(target):
			_drop(i)
	# add the missing ones
	for target in wanted:
		if _has_emitter(id, target):
			continue
		attach_loop(id, target, _mix_db(id), 1.0)


func _has_emitter(id: StringName, target: Node3D) -> bool:
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice != null and voice.id == id and _entry_target(e) == target:
			return true
	return false

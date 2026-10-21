extends Node
## The voice channels: an announcer channel and a police radio channel, each with its own player
## and its own queue, so a line is never cut off mid-sentence and one channel never blocks the
## other.
##
## Priorities (game/audio/audio_tuning.gd):
##   0 = never cut (countdown, finish, busted, escaped) — it waits for the channel, no timeout
##   1 = queued for up to 2 s (heat, stunts)
##   2 = dropped when the channel is busy (drift, hop, near miss)
##
## Repeating lines ("漂移！" on every drift, "电量不足" every few seconds) are throttled: they play
## once per crossing and then only every 30 s.

const Tuning := preload("res://audio/audio_tuning.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const VoiceLines := preload("res://audio/voice/voice_lines.gd")

## Emitted when a line starts, so the HUD can show the subtitle.
signal line_started(id: StringName, text: String, kind: StringName)
## Emitted when a line ends.
signal line_finished(id: StringName)

## The two channels: the announcer and the police radio.
const CHANNELS: Array[StringName] = [&"announcer", &"radio"]

var _players: Dictionary = {}       # kind -> AudioStreamPlayer
var _current: Dictionary = {}       # kind -> the line that is playing
var _queues: Dictionary = {}        # kind -> Array[Dictionary]
var _last_played: Dictionary = {}


func _ready() -> void:
	for kind in CHANNELS:
		var p := AudioStreamPlayer.new()
		p.bus = &"Voice"
		if kind == &"radio":
			p.volume_db = Tuning.VOICE_RADIO_TRIM_DB
		add_child(p)
		p.finished.connect(_on_channel_finished.bind(kind))
		_players[kind] = p
		_current[kind] = &""
		_queues[kind] = []


## Requests a line. `priority` follows the table in the tuning file.
func play(id: StringName, priority: int = Tuning.VOICE_PRIORITY_QUEUED) -> bool:
	var entry := VoiceLines.get_line(id)
	if entry.is_empty():
		push_warning("[audio] unknown voice line: %s" % id)
		return false
	var kind := StringName(entry.get("kind", "announcer"))
	if not _may_repeat(id, priority):
		return false
	var player: AudioStreamPlayer = _players.get(kind, null)
	if player == null:
		return false
	if player.playing:
		if priority == Tuning.VOICE_PRIORITY_DROP:
			return false
		_queue(kind, id, priority)
		return true
	_start(id, kind)
	return true


## The id of the line that is playing on the announcer channel (empty when it is idle).
func current_id() -> StringName:
	return StringName(_current.get(&"announcer", &""))


## The id of the line that is playing on the radio channel (empty when it is idle).
func radio_current_id() -> StringName:
	return StringName(_current.get(&"radio", &""))


## True while any channel is playing (the director ducks the music then).
func is_playing() -> bool:
	for kind in CHANNELS:
		if StringName(_current.get(kind, &"")) != &"":
			return true
	return false


## How many lines are waiting for a free channel.
func queued_count() -> int:
	var total := 0
	for kind in CHANNELS:
		total += (_queues[kind] as Array).size()
	return total


## How many lines are waiting on one channel.
func queued_count_for(kind: StringName) -> int:
	return (_queues.get(kind, []) as Array).size()


func stop_all() -> void:
	for kind in CHANNELS:
		(_queues[kind] as Array).clear()
		_current[kind] = &""
		var p: AudioStreamPlayer = _players.get(kind, null)
		if p != null and is_instance_valid(p):
			p.stop()


func _player_for(kind: StringName) -> AudioStreamPlayer:
	return _players.get(kind, null) as AudioStreamPlayer


func _start(id: StringName, kind: StringName) -> void:
	var entry := VoiceLines.get_line(id)
	var path := String(entry.get("file", ""))
	var stream := SfxLibrary.stream_path(path)
	if stream == null:
		push_warning("[audio] missing voice file: %s" % path)
		return
	var player := _player_for(kind)
	if player == null:
		return
	player.stream = stream
	player.volume_db = Tuning.VOICE_RADIO_TRIM_DB if kind == &"radio" else 0.0
	player.play()
	_current[kind] = id
	_last_played[id] = Time.get_ticks_msec() * Tuning.SECONDS_PER_MS
	line_started.emit(id, String(entry.get("text", "")), kind)


func _queue(kind: StringName, id: StringName, priority: int) -> void:
	var queue: Array = _queues[kind]
	# keep the queue short: the highest priority first, the newest of that priority
	queue.append({"id": id, "priority": priority, "queued_at": Time.get_ticks_msec() * Tuning.SECONDS_PER_MS})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) == int(b["priority"]):
			return float(a["queued_at"]) < float(b["queued_at"])
		return int(a["priority"]) < int(b["priority"]))
	while queue.size() > Tuning.VOICE_QUEUE_MAX:
		queue.pop_back()


func _on_channel_finished(kind: StringName) -> void:
	var id := StringName(_current.get(kind, &""))
	_current[kind] = &""
	if id != &"":
		line_finished.emit(id)
	_pump(kind)


## Starts the next waiting line of a channel (the highest priority first).
func _pump(kind: StringName) -> void:
	var player := _player_for(kind)
	if player == null or player.playing:
		return
	var queue: Array = _queues[kind]
	var now := Time.get_ticks_msec() * Tuning.SECONDS_PER_MS
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var priority := int(item["priority"])
		# a line that is never cut waits as long as it takes
		if priority != Tuning.VOICE_PRIORITY_NEVER_CUT:
			if now - float(item["queued_at"]) > Tuning.VOICE_QUEUE_TIMEOUT_S:
				continue  # it waited too long, drop it
		var id := StringName(item["id"])
		_start(id, kind)
		return


func _may_repeat(id: StringName, priority: int) -> bool:
	# the high-priority lines are never throttled
	if priority == Tuning.VOICE_PRIORITY_NEVER_CUT:
		return true
	var last := float(_last_played.get(id, Tuning.VOICE_NO_PREVIOUS))
	var now := Time.get_ticks_msec() * Tuning.SECONDS_PER_MS
	var gap := Tuning.VOICE_REPEAT_GAP_S
	if id == &"battery_low":
		gap = Tuning.VOICE_WARNING_GAP_S
	return now - last >= gap

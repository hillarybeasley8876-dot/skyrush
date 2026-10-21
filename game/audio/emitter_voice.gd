extends RefCounted
## One positional loop emitter of the world: the player, the fade in and out and (for the police
## sirens) the crossfade between the wail and the yelp.
##
## The voice is a plain object (not a node): the emitter node owns it and frees it with the
## players. A siren has two players that play all the time — the wail and the yelp — so a
## switch never restarts a sample and never cuts.
##
## The level of the voice is the mix trim of the emitter kind (the sirens, the traffic hum and
## the river bed have their own). The engine attenuates the player with its audio sphere
## (`unit_size`): inside the sphere the sound is heard at its full level, at twice the sphere
## it is 6 dB quieter.

const Tuning := preload("res://audio/audio_tuning.gd")

## The level a voice is silent at (the epsilon of the fade out).
const SILENT_EPSILON_DB := 0.5

## The player that carries the main sound (the wail of a siren).
var player: AudioStreamPlayer3D
## The second player of a siren (the yelp).
var standby: AudioStreamPlayer3D
## The node the voice follows (null when it stands still, e.g. the river bed).
var target: Node3D
## The position of the voice (it follows the target when there is one).
var position := Vector3.ZERO
## The id of the sound the voice carries.
var id: StringName = &""
## The level the voice fades to (dB).
var mix_db := Tuning.SILENT_DB

## The current level of the voice (dB).
var level := Tuning.EMITTER_FADE_START_DB
## The crossfade position: 0 = the main sample, 1 = the standby sample.
var mode := 0.0
## The crossfade position the voice moves to.
var mode_target := 0.0

var _paused := false


## Creates the voice. `streams` holds the sounds: one for a normal emitter, two for a siren
## (the wail first, the yelp second). The voice fades in from the silence.
func setup(owner: Node, streams: Array, id_value: StringName, mix: float, unit_size: float,
		follow: Node3D) -> void:
	id = id_value
	mix_db = mix
	target = follow
	level = Tuning.EMITTER_FADE_START_DB
	mode = 0.0
	mode_target = 0.0
	if streams.size() > 0 and streams[0] != null:
		player = _make_player(owner, streams[0], unit_size)
	if streams.size() > 1 and streams[1] != null:
		standby = _make_player(owner, streams[1], unit_size)
	_apply_volumes()


## Creates a player that plays a loop and follows the target.
func _make_player(owner: Node, stream: AudioStream, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	# the player always runs: the emitters node is pausable, and a 3D player only takes a
	# pause while the tree is paused (Godot 4.7 ignores the flag otherwise)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = Tuning.SILENT_DB
	p.max_distance = Tuning.EMITTER_MAX_DISTANCE_M
	p.unit_size = unit_size
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	owner.add_child(p)
	p.play()
	# the pause flag is re-applied, a fresh player is never paused
	p.stream_paused = _paused
	return p


## Advances the fade and the crossfade and moves the players. Returns false when the voice has
## faded out and can be freed.
func process(delta: float) -> bool:
	if target != null and is_instance_valid(target):
		position = target.global_position
	if player != null:
		player.global_position = position
		if standby != null:
			standby.global_position = position
	# the fade covers the span from the start level to the mix level in EMITTER_FADE_S
	var step := -Tuning.EMITTER_FADE_START_DB / Tuning.EMITTER_FADE_S * delta
	if level < mix_db:
		level = minf(level + step, mix_db)
	elif level > mix_db:
		level = maxf(level - step, mix_db)
	if standby != null:
		var mode_step := delta / Tuning.SIREN_CROSSFADE_S
		if mode < mode_target:
			mode = minf(mode + mode_step, mode_target)
		elif mode > mode_target:
			mode = maxf(mode - mode_step, mode_target)
	_apply_volumes()
	return not _finished()


## True when the voice has faded out completely.
func _finished() -> bool:
	if level > Tuning.SILENT_DB + SILENT_EPSILON_DB:
		return false
	if standby != null and absf(mode - mode_target) > 0.0:
		return false
	return true


## The levels of the players: the two samples of a siren share the level of the voice.
func _apply_volumes() -> void:
	if player == null:
		return
	if standby == null:
		player.volume_db = level
		return
	player.volume_db = level + (Tuning.SILENT_DB - level) * mode
	standby.volume_db = level + (Tuning.SILENT_DB - level) * (1.0 - mode)


## Fades the voice out (the emitter is dropped).
func fade_out() -> void:
	mix_db = Tuning.SILENT_DB


## Fades the voice in to a new level.
func set_mix_db(db: float) -> void:
	mix_db = db


## Crossfades to the other sample of a siren (0 = the wail, 1 = the yelp).
func set_mode(value: float) -> void:
	mode_target = value


## Pauses or resumes the players (the game pause).
func set_paused(paused: bool) -> void:
	_paused = paused
	if player != null:
		player.stream_paused = paused
	if standby != null:
		standby.stream_paused = paused


## True while the voice is still audible.
func audible() -> bool:
	return level > Tuning.SILENT_DB + SILENT_EPSILON_DB


## Frees the players (the voice itself is not a node).
func free_players() -> void:
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
	if standby != null and is_instance_valid(standby):
		standby.stop()
		standby.queue_free()
	player = null
	standby = null

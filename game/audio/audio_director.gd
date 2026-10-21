extends Node
## SKYRUSH audio director (unit `audio`).
##
## Owns: the bus setup (the MusicBed sub-bus, the voice ducking, the master limiter), the one-shot
## pool, the voice queue, the world emitters, the music bed, the player's two synth voices and the
## road/wind beds. The event mapping lives in sound_mapper.gd (a child).
##
## Other units talk to this node through the "audio" group:
##   var audio := get_tree().get_first_node_in_group("audio")
##   audio.play_sfx(&"impact_medium")
##   audio.play_3d(&"impact_heavy", global_position)
##   audio.play_voice(&"police_arrive")

const VoiceLines := preload("res://audio/voice/voice_lines.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const Tuning := preload("res://audio/audio_tuning.gd")
const EvSynthScript := preload("res://audio/synth/ev_synth.gd")
const ThrusterSynthScript := preload("res://audio/synth/thruster_synth.gd")
const OneShotPoolScript := preload("res://audio/oneshot_pool.gd")
const VoiceQueueScript := preload("res://audio/voice_queue.gd")
const WorldEmittersScript := preload("res://audio/world_emitters.gd")
const MusicBedScript := preload("res://audio/music_bed.gd")
const LoopPlayersScript := preload("res://audio/loop_players.gd")
const BusSetup := preload("res://audio/bus_setup.gd")
const PlayerVoices := preload("res://audio/player_voices.gd")

## Emitted when a voice line starts, so the HUD can show the subtitle.
signal voice_line(id: StringName, text: String, kind: StringName)
## Emitted for every one-shot that is played (the demo scene captions it).
signal sfx_played(id: StringName)

var last_voice_id: StringName = &""
var last_voice_text: String = ""
var music_state: StringName = &"cruise"

var _pool: OneShotPoolScript
var _voices: VoiceQueueScript
var _emitters: WorldEmittersScript
var _bed: MusicBedScript
var _loops: LoopPlayersScript
var _ev_synth: AudioStreamPlayer3D
var _thr_synth: AudioStreamPlayer3D
## The helper that maps the telemetry of the car onto the voices and the beds.
var _voices_of_car: PlayerVoices
var _duck_effect: AudioEffectAmplify
var _duck_amount := 0.0
var _duck_target := 0.0
var _player: VehicleBase
var _heat := 0
var _paused := false
var _total_laps := 0
## True while a car is driving the voices.
var _had_player := false


func _ready() -> void:
	add_to_group(&"audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_duck_effect = BusSetup.setup()
	_build_children()
	_update_player_ref()


func _build_children() -> void:
	_pool = OneShotPoolScript.new()
	_pool.name = "OneShotPool"
	_pool.played.connect(_on_sfx_played)
	add_child(_pool)
	_voices = VoiceQueueScript.new()
	_voices.name = "VoiceQueue"
	_voices.line_started.connect(_on_voice_started)
	_voices.line_finished.connect(_on_voice_finished)
	add_child(_voices)
	_emitters = WorldEmittersScript.new()
	_emitters.name = "WorldEmitters"
	_emitters.one_shot_requested.connect(_on_emitter_one_shot)
	add_child(_emitters)
	_bed = MusicBedScript.new()
	_bed.name = "MusicBed"
	add_child(_bed)
	_loops = LoopPlayersScript.new()
	_loops.name = "LoopPlayers"
	add_child(_loops)
	_ev_synth = EvSynthScript.new()
	_ev_synth.name = "EvVoice"
	# the synth voices play on the SFX bus: the SFX volume and the slow-motion effect reach them
	_ev_synth.bus = &"SFX"
	_setup_synth_voice(_ev_synth)
	add_child(_ev_synth)
	_thr_synth = ThrusterSynthScript.new()
	_thr_synth.name = "ThrusterVoice"
	_thr_synth.bus = &"SFX"
	_setup_synth_voice(_thr_synth)
	add_child(_thr_synth)
	_voices_of_car = PlayerVoices.new()
	_voices_of_car.setup(_ev_synth, _thr_synth, _loops)


## The setup of a synth voice: the player hears its own car from inside it, so the audio sphere
## covers the chase camera (the synth sets its own doppler tracking).
func _setup_synth_voice(voice: AudioStreamPlayer3D) -> void:
	voice.unit_size = Tuning.SYNTH_UNIT_SIZE_M
	voice.max_distance = Tuning.SYNTH_MAX_DISTANCE_M


## The scrape loop of the player car (a sustained contact against a wall or a car).
func set_scrape(level_db: float, pitch: float) -> void:
	if _loops != null:
		_loops.set_scrape(level_db, pitch)


## Lets the scrape loop of the player car fade out.
func release_scrape() -> void:
	if _loops != null:
		_loops.release_scrape()


## The scrape loop of the nearest other car (a 3D one, it sits at the contact point).
func set_scrape_3d(position: Vector3, level_db: float, pitch: float) -> void:
	if _loops != null:
		_loops.set_scrape_3d(position, level_db, pitch)


## Lets the scrape loop of the other car fade out.
func release_scrape_3d() -> void:
	if _loops != null:
		_loops.release_scrape_3d()


# --- public API ----------------------------------------------------------------------------------------
func play_sfx(id: StringName, volume_db: float = 0.0, pitch: float = 1.0, priority: int = 1) -> bool:
	return _pool.play_2d(id, volume_db, pitch, priority)


func play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, priority: int = 1) -> bool:
	return _pool.play_3d(id, position, volume_db, pitch, priority)


func play_voice(id: StringName, priority: int = Tuning.VOICE_PRIORITY_QUEUED) -> bool:
	return _voices.play(id, priority)


## Creates a looping emitter that follows a target (a siren on a police car, a hum on a traffic car).
func attach_loop(id: StringName, target: Node3D, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	return _emitters.attach_loop(id, target, volume_db, pitch)


func stop_loop(handle: AudioStreamPlayer3D) -> void:
	_emitters.stop_loop(handle)


func set_music_state(state: StringName) -> void:
	music_state = state
	if _bed != null:
		_bed.set_state(state)


func set_music_paused(paused: bool) -> void:
	if _bed != null:
		_bed.set_paused(paused)


## Starts or stops the music bed completely (the demo plays the loops on its own players).
func set_music_enabled(enabled: bool) -> void:
	if _bed != null:
		_bed.set_enabled(enabled)


## Switches the city ambience on or off (the demo wants a silent floor).
func set_ambience_enabled(enabled: bool) -> void:
	if _bed != null:
		_bed.set_ambience_enabled(enabled)


## Pauses or resumes every gameplay sound (the game pause). The voice lines may finish, the
## music drops to the menu state instead of stopping.
func set_paused(paused: bool) -> void:
	_paused = paused
	if _pool != null:
		_pool.set_paused(paused)
	if _emitters != null:
		_emitters.set_paused(paused)
	if _loops != null:
		_loops.set_paused(paused)
	_apply_pause()
	if _bed != null:
		if paused:
			_bed.set_state(Tuning.PAUSE_MENU_STATE)
		else:
			_bed.set_state(music_state)
	_paused = paused


## Sets the pause flag of every gameplay player.
##
## The flag is set again every frame while the game is paused: Godot only takes the pause of a
## 3D player when the tree has been paused for a frame, and a player that stops clears it.
func _apply_pause() -> void:
	if _ev_synth != null:
		_ev_synth.stream_paused = _paused
	if _thr_synth != null:
		_thr_synth.stream_paused = _paused
	if _emitters != null:
		_emitters.set_paused(_paused)


## The slow-motion takedown cam: the SFX bus is pitched down and low-passed.
func set_slow_mo(active: bool) -> void:
	BusSetup.set_slow_mo(active)


## The player's EV drive voice (motor whine + fan whine).
func ev_voice() -> AudioStreamPlayer3D:
	return _ev_synth


## The player's cold-gas thruster voice.
func thruster_voice() -> AudioStreamPlayer3D:
	return _thr_synth


## Stops every sound (used when the scene is torn down).
func stop_all_sounds() -> void:
	if _pool != null:
		_pool.stop_all()
	if _voices != null:
		_voices.stop_all()
	if _emitters != null:
		_emitters.stop_all()
	if _loops != null:
		_loops.stop_all()
	if _ev_synth != null:
		_ev_synth.stop()
	if _thr_synth != null:
		_thr_synth.stop()


## The heat level (0..5) — the world emitters use it to pick the siren.
func set_heat(level: int) -> void:
	_heat = level
	if _emitters != null:
		_emitters.heat = level


## The number of laps of the current race (0 = unknown). The modes unit publishes it, the
## announcer uses it to call the last lap.
func set_total_laps(laps: int) -> void:
	_total_laps = laps


## The number of laps of the current race (0 = unknown).
func total_laps() -> int:
	return _total_laps


## True while a voice line is playing (the music is ducked then).
func duck_target() -> float:
	return _duck_target


## True when the scrape loop of the player car is playing.
func scrape_playing() -> bool:
	return _loops != null and _loops.scrape_playing()


## The level of the scrape loop of the player car (dB).
func scrape_level_db() -> float:
	return Tuning.SILENT_DB if _loops == null else _loops.scrape_level_db()


## True when every gameplay player is paused (the game pause).
func gameplay_paused() -> bool:
	if _loops != null and not _loops.gameplay_paused():
		return false
	if _ev_synth != null and not _ev_synth.stream_paused:
		return false
	if _thr_synth != null and not _thr_synth.stream_paused:
		return false
	return true


## The cutoff of the music bed's low-pass filter (the menu state filters the bed).
func bed_cutoff_hz() -> float:
	if _bed == null:
		return 0.0
	return _bed.cutoff_hz()


# --- per frame -----------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_ducking(delta)
	_update_player(delta)
	if _paused:
		_apply_pause()


func _physics_process(_delta: float) -> void:
	_update_player_ref()
	if _player == null or not is_instance_valid(_player):
		return
	# the synth voices ride with the car without being reparented into it
	var pos := _player.global_position
	_ev_synth.global_position = pos
	_thr_synth.global_position = pos


func _update_ducking(delta: float) -> void:
	if _duck_effect == null:
		return
	# the music ducks while ANY channel is playing (the announcer and the radio are independent)
	_duck_target = 1.0 if _voices != null and _voices.is_playing() else 0.0
	var speed := 1.0 / Tuning.DUCK_ATTACK_S
	if _duck_amount < _duck_target:
		_duck_amount = minf(_duck_amount + delta * speed, _duck_target)
	else:
		_duck_amount = maxf(_duck_amount - delta * speed * Tuning.DUCK_RELEASE_FACTOR, _duck_target)
	_duck_effect.volume_db = -Tuning.DUCK_DB * _duck_amount


func _update_player_ref() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = Game.player


func _update_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		# the car is gone: the voices have to fall silent (the synths keep their last state).
		# A scene without a car (the demo) drives the synths itself, so they are only silenced
		# when the car was there before.
		if _had_player:
			_voices_of_car.silence()
			_had_player = false
		return
	_had_player = true
	_voices_of_car.update(_player, delta)


# --- callbacks -----------------------------------------------------------------------------------------
func _on_sfx_played(id: StringName) -> void:
	sfx_played.emit(id)


## The world emitters ask for a one-shot (the pool of the director plays it).
func _on_emitter_one_shot(id: StringName, position: Vector3, volume_db: float) -> void:
	if _pool != null:
		_pool.play_3d(id, position, volume_db, 1.0, 1)


func _on_voice_started(id: StringName, text: String, kind: StringName) -> void:
	last_voice_id = id
	last_voice_text = text
	_duck_target = 1.0
	if kind == &"radio":
		# the radio squelch opens the channel
		play_sfx(&"radio_squelch", Tuning.RADIO_SQUELCH_MIX_DB)
	voice_line.emit(id, text, kind)


func _on_voice_finished(id: StringName) -> void:
	# the music stays ducked while the other channel is still talking
	_duck_target = 1.0 if _voices != null and _voices.is_playing() else 0.0
	var entry := VoiceLines.get_line(id)
	if StringName(entry.get("kind", "announcer")) == &"radio":
		# the radio squelch closes the channel
		play_sfx(&"radio_squelch", Tuning.RADIO_SQUELCH_MIX_DB)


func _exit_tree() -> void:
	# stop everything and drop the stream cache, so the engine reports no leaked resources
	stop_all_sounds()
	SfxLibrary.clear_cache()

extends "res://audio/event_mapper.gd"
## Maps the race and pursuit events of the core event bus to sounds. Child of the AudioDirector.
##
## The vehicle events are mapped by sound_mapper.gd. The music state follows the race and the
## pursuit, so the bed is switched here as well.

const COUNTDOWN_VOICES: Dictionary = {3: &"countdown_3", 2: &"countdown_2", 1: &"countdown_1"}

## The heat level the audio unit knows about.
var _heat := 0
## The seconds the slow-motion effect is still on.
var _slowmo_timer := 0.0


func _connect_all() -> void:
	Events.race_countdown.connect(_on_countdown)
	Events.race_started.connect(_on_race_started)
	Events.race_finished.connect(_on_race_finished)
	Events.checkpoint_passed.connect(_on_checkpoint)
	Events.lap_completed.connect(_on_lap_completed)
	Events.heat_changed.connect(_on_heat_changed)
	Events.pursuit_state_changed.connect(_on_pursuit_state)
	Events.player_respawned.connect(_on_respawned)
	Events.game_paused.connect(_on_paused)
	Events.slowmo_request.connect(_on_slow_mo)


# --- race ----------------------------------------------------------------------------------------------
func _on_countdown(seconds_left: int) -> void:
	if seconds_left > 0:
		_sfx(&"countdown_beep", Tuning.COUNTDOWN_BEEP_MIX_DB)
		_voice(COUNTDOWN_VOICES.get(seconds_left, &""), Tuning.VOICE_PRIORITY_NEVER_CUT)
	else:
		_sfx(&"countdown_go", Tuning.COUNTDOWN_GO_MIX_DB)
		_voice(&"countdown_go", Tuning.VOICE_PRIORITY_NEVER_CUT)


func _on_race_started() -> void:
	_voice(&"race_start", Tuning.VOICE_PRIORITY_QUEUED)
	if _audio != null:
		_audio.set_music_state(&"race")


func _on_race_finished(_results: Array) -> void:
	_voice(&"race_finish", Tuning.VOICE_PRIORITY_NEVER_CUT)
	_voice(&"race_end", Tuning.VOICE_PRIORITY_QUEUED)
	if _audio != null:
		_audio.set_music_state(&"cruise")


func _on_checkpoint(_vehicle: VehicleBase, _index: int, _total: int) -> void:
	_voice(&"checkpoint", Tuning.VOICE_PRIORITY_DROP)


func _on_lap_completed(vehicle: VehicleBase, lap: int, _lap_time: float) -> void:
	if not _is_player(vehicle):
		return
	# only the last lap of a race is announced (the lap count comes from the modes unit)
	var total := 0
	if _audio != null:
		total = _audio.total_laps()
	if total <= 0:
		return
	# the event carries the number of completed laps: the last lap is announced when the
	# player has finished total - 1 laps (the finish itself is a different line)
	if lap != total - 1:
		return
	_voice(&"final_lap", Tuning.VOICE_PRIORITY_QUEUED)


# --- pursuit -------------------------------------------------------------------------------------------
func _on_heat_changed(level: int) -> void:
	var previous := _heat
	_heat = level
	if _audio != null:
		_audio.set_heat(level)
	# "警察来了" only on the way up, not on every step of the heat
	if previous == 0 and level >= Tuning.HEAT_POLICE_FROM:
		_voice(&"police_arrive", Tuning.VOICE_PRIORITY_QUEUED)
	# the pursuit line is only for a rising heat (a heat that drops is not announced)
	if level > previous and level >= Tuning.HEAT_PURSUIT_FROM:
		if level >= Tuning.HEAT_MAX_FROM:
			_voice(&"heat_max", Tuning.VOICE_PRIORITY_QUEUED)
		else:
			_voice(&"heat_up", Tuning.VOICE_PRIORITY_QUEUED)
	if level >= Tuning.HEAT_PURSUIT_FROM:
		if _audio != null:
			_audio.set_music_state(&"pursuit")
	else:
		if _audio != null:
			_audio.set_music_state(&"cruise")


func _on_pursuit_state(state: StringName) -> void:
	match state:
		&"busted":
			_voice(&"busted", Tuning.VOICE_PRIORITY_NEVER_CUT)
			if _audio != null:
				_audio.set_music_state(&"cruise")
		&"escaped":
			_voice(&"escaped", Tuning.VOICE_PRIORITY_NEVER_CUT)
			if _audio != null:
				_audio.set_music_state(&"cruise")
		&"chase", &"search":
			if _audio != null:
				_audio.set_music_state(&"pursuit")
		_:
			pass


func _on_respawned() -> void:
	_voice(&"respawn", Tuning.VOICE_PRIORITY_QUEUED)


# --- modes ---------------------------------------------------------------------------------------------
func _on_paused(paused: bool) -> void:
	if _audio != null:
		_audio.set_paused(paused)


## The slow-motion takedown cam: the SFX bus is pitched down and low-passed.
func _on_slow_mo(time_scale: float, duration: float, _focus: Node3D) -> void:
	if _audio == null:
		return
	_audio.set_slow_mo(time_scale < Tuning.SLOWMO_TRIGGER_SCALE)
	if time_scale >= Tuning.SLOWMO_TRIGGER_SCALE:
		return
	# the effect is released again after the slow motion is over
	_slowmo_timer = duration


func _process(delta: float) -> void:
	_watch_slow_mo(delta)


## The slow-motion effect is released when the slow motion is over.
func _watch_slow_mo(delta: float) -> void:
	if _slowmo_timer <= 0.0:
		return
	_slowmo_timer -= delta
	if _slowmo_timer > 0.0:
		return
	_slowmo_timer = 0.0
	if _audio != null:
		_audio.set_slow_mo(false)

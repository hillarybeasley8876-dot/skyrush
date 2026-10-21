extends Node
## The music bed: three loops that play at the same time and are crossfaded by state.
##
## The crossfade is equal power (the gains are cos/sin of the transition angle), so switching
## states never drops the bed by more than 3 dB. The menu state filters the bed down instead of
## detuning it.

const Tuning := preload("res://audio/audio_tuning.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")

const TRACKS: Array[StringName] = [&"cruise", &"pursuit", &"race"]
## The smallest gain the bed tracks (a linear gain of 0 is -inf dB).
const MIN_GAIN := 0.0001
## Which track each state uses, and its level on the MusicBed bus.
const STATES: Dictionary = {
	&"menu": {&"cruise": Tuning.MUSIC_LEVEL_MENU_DB},
	&"cruise": {&"cruise": Tuning.MUSIC_LEVEL_CRUISE_DB},
	&"pursuit": {&"pursuit": Tuning.MUSIC_LEVEL_PURSUIT_DB},
	&"race": {&"race": Tuning.MUSIC_LEVEL_RACE_DB},
}

var _players: Dictionary = {}
var _gain: Dictionary = {}          # track -> current linear gain
var _from: Dictionary = {}          # track -> gain at the start of the transition
var _target: Dictionary = {}        # track -> gain the transition ends at
var _transition := 1.0              # 0..1 over the crossfade
var _filter: AudioEffectLowPassFilter
var _filter_target := Tuning.FILTER_MAX_HZ
var _filter_current := Tuning.FILTER_MAX_HZ
var _menu_active := false
## True when the old and the new state play the same track (then the blend is linear).
var _same_track := false
var _ambience: AudioStreamPlayer
var _rain: AudioStreamPlayer


func _ready() -> void:
	for name in TRACKS:
		var p := AudioStreamPlayer.new()
		p.bus = Tuning.MUSIC_BUS
		p.stream = SfxLibrary.stream(name, SfxLibrary.MUSIC_DIR, true)
		p.volume_db = Tuning.SILENT_DB
		add_child(p)
		if p.stream != null:
			p.play()
		_players[name] = p
		_gain[name] = 0.0
		_from[name] = 0.0
		_target[name] = 0.0
	_ensure_filter()
	_start_ambience()
	# a debug hook: --mute-music records the car without the music bed
	if Game.has_option("mute-music"):
		set_enabled(false)
	set_state(&"cruise")


func _ensure_filter() -> void:
	var bus := AudioServer.get_bus_index(Tuning.MUSIC_BUS)
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			_filter = AudioServer.get_bus_effect(bus, i) as AudioEffectLowPassFilter
			_filter.cutoff_hz = Tuning.FILTER_MAX_HZ
			return
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = Tuning.FILTER_MAX_HZ
	AudioServer.add_bus_effect(bus, _filter)


func _start_ambience() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"SFX"
	_ambience.stream = SfxLibrary.stream(&"city_ambience")
	_ambience.volume_db = Tuning.AMBIENCE_CITY_DB
	add_child(_ambience)
	if _ambience.stream != null:
		_ambience.play()
	if bool(Settings.feature("rain")):
		_rain = AudioStreamPlayer.new()
		_rain.bus = &"SFX"
		_rain.stream = SfxLibrary.stream(&"rain_layer")
		_rain.volume_db = Tuning.AMBIENCE_RAIN_DB
		add_child(_rain)
		_rain.play()


## Switches the city ambience (and the rain) on or off (the demo wants a silent floor).
func set_ambience_enabled(enabled: bool) -> void:
	if _ambience != null:
		if enabled and not _ambience.playing:
			_ambience.play()
		elif not enabled and _ambience.playing:
			_ambience.stop()
	if _rain != null:
		if enabled and not _rain.playing:
			_rain.play()
		elif not enabled and _rain.playing:
			_rain.stop()


## Crossfades the bed to a state: &"menu", &"cruise", &"pursuit" or &"race".
## The state the bed is in.
var _state: StringName = &"cruise"


## True when both states play the same track.
func _same_track_in(a: StringName, b: StringName) -> bool:
	var cfg_a: Dictionary = STATES.get(a, STATES[&"cruise"])
	var cfg_b: Dictionary = STATES.get(b, STATES[&"cruise"])
	for name in TRACKS:
		if cfg_a.has(name) and cfg_b.has(name):
			return true
	return false


func set_state(state: StringName) -> void:
	var cfg: Dictionary = STATES.get(state, STATES[&"cruise"])
	for name in TRACKS:
		_from[name] = float(_gain.get(name, 0.0))
		var db := Tuning.SILENT_DB
		if cfg.has(name):
			db = float(cfg[name])
		_target[name] = db_to_linear(db)
	_transition = 0.0
	_menu_active = state == &"menu"
	_filter_target = Tuning.MENU_LOWPASS_HZ if _menu_active else Tuning.SLOWMO_LOWPASS_HZ_MAX
	# a track that is in both states only changes its level: a linear blend keeps it flat
	_same_track = _same_track_in(_state, state)
	_state = state


## Stops or starts the bed completely (the demo plays the loops on its own players).
func set_enabled(enabled: bool) -> void:
	for name in _players:
		var p := _players[name] as AudioStreamPlayer
		if enabled and not p.playing:
			p.play()
		elif not enabled and p.playing:
			p.stop()
	_gain.clear()
	_from.clear()
	_target.clear()
	for name in _players:
		_gain[name] = 0.0
		_from[name] = 0.0
		_target[name] = 0.0


## Pauses or resumes the music bed (used when the game is paused).
func set_paused(paused: bool) -> void:
	for name in _players:
		(_players[name] as AudioStreamPlayer).stream_paused = paused


## The cutoff of the low-pass filter (the menu state filters the bed down).
func cutoff_hz() -> float:
	return _filter_current if _filter != null else 0.0


## The current linear gain of a track (the test checks the crossfade does not dip).
func track_gain(name: StringName) -> float:
	return float(_gain.get(name, 0.0))


## The summed gain of the bed — it must stay roughly constant during a state change.
func bed_gain() -> float:
	var total := 0.0
	for name in _players:
		var g := float(_gain.get(name, 0.0))
		total += g * g
	return sqrt(total)


func _process(delta: float) -> void:
	if _transition < 1.0:
		_transition = minf(1.0, _transition + delta / Tuning.MUSIC_CROSSFADE_S)
		var angle := _transition * PI * 0.5
		for name in _players:
			var g := 0.0
			if _same_track:
				g = lerpf(float(_from.get(name, 0.0)), float(_target.get(name, 0.0)), _transition)
			else:
				g = float(_from.get(name, 0.0)) * cos(angle) + float(_target.get(name, 0.0)) * sin(angle)
			_gain[name] = g
			var p := _players[name] as AudioStreamPlayer
			p.volume_db = linear_to_db(maxf(g, MIN_GAIN))
	# the menu filter sweep
	var step := Tuning.FILTER_MAX_HZ * delta / Tuning.MENU_LOWPASS_SWEEP_S
	if _filter_current < _filter_target:
		_filter_current = minf(_filter_target, _filter_current + step)
	elif _filter_current > _filter_target:
		_filter_current = maxf(_filter_target, _filter_current - step)
	if _filter != null:
		_filter.cutoff_hz = _filter_current

extends Node
## Audio demo: plays every category in sequence with a caption and a live level meter, so the lead
## can review the whole palette (and the mix levels) in one run.
##
##   tools/godot.sh shot --scene=res://audio/demo/audio_demo.tscn --out=audio_demo
##   tools/godot.sh run  res://audio/demo/audio_demo.tscn 240
##
## Sequence: the synth voices -> every one-shot -> every loop (on its own player) -> the three
## music beds -> every voice line. The loops are stopped at the end of their step, so nothing
## bleeds into the next section, and the demo keeps the shipped gains of the game.

const AudioDirectorScript := preload("res://audio/audio_director.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const VoiceLines := preload("res://audio/voice/voice_lines.gd")
const Spectrum := preload("res://audio/spectrum.gd")
const Tuning := preload("res://audio/audio_tuning.gd")

const SYNTH_TIME := 6.0
const SFX_TIME := 1.5
const LOOP_TIME := 3.0
## The loop stops this long before the step ends, so the next step starts in silence.
const LOOP_TAIL := 0.7
const MUSIC_TIME := 7.0
## A voice step lasts as long as the line plus a small tail.
const VOICE_TAIL := 0.4
## The band the thruster hiss lives in (the meter shows how much of the mix is in it).
const HISS_BAND_LO := 2000.0
const HISS_BAND_HI := 4000.0
## The moving emitter passes the listener at this speed (m/s).
const PASS_SPEED := 30.0
## The distance the moving emitter starts and ends at (m).
const PASS_START_M := -45.0
const PASS_END_M := 45.0
## The reach and the audio sphere of the moving source.
const MOVING_MAX_DISTANCE := 300.0
const MOVING_UNIT_SIZE := 8.0
## The font size of the meter.
const METER_FONT_SIZE := 24
## The length of a voice step when the file is missing.
const DEFAULT_VOICE_DURATION := 1.6
## The synth sweep: the rpm, the load, the speed and the downforce.
const SYNTH_RPM_MIN := 3000.0
const SYNTH_RPM_SPAN := 12000.0
const SYNTH_RPM_RATE := 1.1
const SYNTH_LOAD_MIN := 0.35
const SYNTH_LOAD_SPAN := 0.65
const SYNTH_LOAD_RATE := 1.7
const SYNTH_SPEED_MIN := 60.0
const SYNTH_SPEED_SPAN := 220.0
const SYNTH_SPEED_RATE := 0.9
const SYNTH_DOWNFORCE_RATE := 0.7
## The share of the rear thrust in the synth step.
const SYNTH_REAR_SHARE := 0.6
## The scale of the band share in the meter (a percentage).
const BAND_PERCENT_SCALE := 100.0
## The smallest share the meter shows.
const MIN_BAND_SHARE := 0.0001
## The UI colours (ART.md §3).
const COLOR_CYAN := Color(0.098, 0.902, 1.0)
const COLOR_TEXT := Color(0.949, 0.965, 1.0)
const COLOR_WARN := Color(1.0, 0.8, 0.0)

@onready var _label: Label = $Ui/Label
@onready var _meter: Label = $Ui/Meter
@onready var _peak_bar: ColorRect = $Ui/PeakFill
@onready var _rms_bar: ColorRect = $Ui/RmsFill
@onready var _band_bar: ColorRect = $Ui/BandFill
@onready var _director: AudioDirectorScript = $AudioDirector

var _steps: Array[Dictionary] = []
var _index := -1
var _timer := 0.0
var _synth_t := 0.0
## The time the moving source has been driving (the doppler follows the physics steps).
var _moving_t := 0.0
var _running := false
var _capture: AudioEffectCapture
var _loop_player: AudioStreamPlayer
var _moving: AudioStreamPlayer3D
var _listener: AudioListener3D
var _camera: Camera3D
var _peak := -120.0
var _rms := -120.0
var _band := 0.0
## The bar backgrounds (the full width of a bar).
var _bar_width := 600.0


func _ready() -> void:
	_build_steps()
	# the demo plays the loops on its own players, so the music bed stays silent
	_director.set_music_enabled(false)
	_director.set_ambience_enabled(false)
	_capture = AudioEffectCapture.new()
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.add_bus_effect(master, _capture)
	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = &"SFX"
	add_child(_loop_player)
	# the synth voices and the moving emitter are 3D, so the demo needs a listener
	_camera = Camera3D.new()
	_camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_camera)
	_listener = AudioListener3D.new()
	_camera.add_child(_listener)
	_moving = AudioStreamPlayer3D.new()
	_moving.bus = &"SFX"
	_moving.max_distance = MOVING_MAX_DISTANCE
	_moving.unit_size = MOVING_UNIT_SIZE
	_moving.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_moving)
	_meter.add_theme_color_override("font_color", COLOR_TEXT)
	_meter.add_theme_font_size_override("font_size", METER_FONT_SIZE)
	_label.text = "SKYRUSH 音频演示 / audio demo — 准备 / ready"
	await get_tree().process_frame
	_next_step()


func _build_steps() -> void:
	_steps.append({"kind": "synth", "id": &"", "label": "合成音 / synth voices — 电机 + 冷气推进器"})
	for id in SfxLibrary.sfx_ids():
		if Tuning.LOOP_IDS.has(id):
			continue
		_steps.append({"kind": "sfx", "id": id, "label": "音效 / sfx — %s" % id})
	for id in Tuning.LOOP_IDS:
		_steps.append({"kind": "loop", "id": id, "label": "循环音 / loop — %s" % id})
	for id in [&"cruise", &"pursuit", &"race"]:
		_steps.append({"kind": "music", "id": id, "label": "音乐 / music — %s" % id})
	for id in VoiceLines.LINES:
		var entry: Dictionary = VoiceLines.LINES[id]
		_steps.append({"kind": "voice", "id": id, "label": "语音 / voice — %s  %s"
			% [String(entry.get("text", "")), String(entry.get("en", ""))],
			"duration": _voice_duration(id)})


func _voice_duration(id: StringName) -> float:
	var entry := VoiceLines.get_line(id)
	var path := String(entry.get("file", ""))
	if path == "" or not ResourceLoader.exists(path):
		return DEFAULT_VOICE_DURATION
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		return DEFAULT_VOICE_DURATION
	return stream.get_length() + VOICE_TAIL


func _next_step() -> void:
	_stop_loop()
	_silence_synths()
	_index += 1
	if _index >= _steps.size():
		_index = 0
	var step := _steps[_index]
	_timer = 0.0
	var kind := String(step["kind"])
	var id := StringName(step["id"])
	match kind:
		"synth":
			_synth_t = 0.0
		"sfx":
			_director.play_sfx(id, 0.0)
		"loop":
			_start_loop(id)
		"music":
			_start_loop(id, SfxLibrary.MUSIC_DIR, Tuning.DEMO_MUSIC_DB)
		"voice":
			_director.play_voice(id)
	_label.text = "%s\n%03d / %03d" % [String(step["label"]), _index + 1, _steps.size()]
	_running = true


## The loop beds get their own player so they can be stopped at the end of their step.
func _start_loop(id: StringName, folder: String = SfxLibrary.SFX_DIR,
		volume_db: float = Tuning.DEMO_LOOP_DB) -> void:
	var stream := SfxLibrary.stream(id, folder, true)
	if stream == null:
		return
	# the siren and the traffic hum are shown as a moving source (the doppler)
	if id == &"siren_wail" or id == &"siren_yelp" or id == &"traffic_ev_hum":
		_start_moving(id, folder, volume_db)
		return
	_loop_player.stream = stream
	_loop_player.volume_db = volume_db
	_loop_player.play()


## A source that passes the listener, so the doppler shift is audible.
func _start_moving(id: StringName, folder: String, volume_db: float = Tuning.DEMO_LOOP_DB) -> void:
	var stream := SfxLibrary.stream(id, folder, true)
	if stream == null:
		return
	_moving.stream = stream
	_moving.volume_db = volume_db
	_moving.global_position = Vector3(PASS_START_M, 0.0, 0.0)
	_moving_t = 0.0
	_moving.play()


func _stop_loop() -> void:
	if _loop_player != null:
		_loop_player.stop()
	if _moving != null:
		_moving.stop()


## The moving source is driven in the physics step, so the doppler shift is correct.
func _physics_process(delta: float) -> void:
	if _moving == null or not _moving.playing:
		return
	_moving_t += delta
	var x := PASS_START_M + PASS_SPEED * _moving_t
	_moving.global_position = Vector3(x, 0.0, 0.0)


func _process(delta: float) -> void:
	_update_meter()
	if not _running:
		return
	_timer += delta
	var step := _steps[_index]
	var kind := String(step["kind"])
	if kind == "synth":
		_drive_synth(delta)
		if _timer >= SYNTH_TIME:
			_next_step()
		return
	var limit := SFX_TIME
	if kind == "loop":
		limit = LOOP_TIME
	elif kind == "music":
		limit = MUSIC_TIME
	elif kind == "voice":
		limit = float(step.get("duration", DEFAULT_VOICE_DURATION))
	# the loop beds stop before the step ends, so the next step starts in silence
	if (kind == "loop" or kind == "music") and _timer >= limit - LOOP_TAIL:
		_stop_loop()
	if _timer >= limit:
		_next_step()


## Sweeps the two synth voices so the review hears the motor and the thruster hiss.
## The gains are the shipped ones — the demo shows the mix the game plays.
func _drive_synth(delta: float) -> void:
	_synth_t += delta
	var ev := _director.ev_voice()
	var thr := _director.thruster_voice()
	if ev != null:
		ev.motor_rpm = SYNTH_RPM_MIN + SYNTH_RPM_SPAN * (0.5 + 0.5 * sin(_synth_t * SYNTH_RPM_RATE))
		ev.motor_load = SYNTH_LOAD_MIN + SYNTH_LOAD_SPAN * (0.5 + 0.5 * sin(_synth_t * SYNTH_LOAD_RATE))
		ev.speed_kmh = SYNTH_SPEED_MIN + SYNTH_SPEED_SPAN * (0.5 + 0.5 * sin(_synth_t * SYNTH_SPEED_RATE))
		ev.downforce_kg = Tuning.DOWNFORCE_MAX_KG * (0.5 + 0.5 * sin(_synth_t * SYNTH_DOWNFORCE_RATE))
	if thr != null:
		# one second of hiss, one second of silence: the pulses are easy to hear
		var t := fmod(_synth_t, 2.0)
		var on := 1.0 if t < 1.0 else 0.0
		thr.thrust_perimeter = on
		thr.thrust_rear = SYNTH_REAR_SHARE * on
		thr.hop_charge = clampf(fmod(_synth_t, 1.0), 0.0, 1.0)


## The synth voices fall silent after their step (a voice that keeps its last state drones).
func _silence_synths() -> void:
	var ev := _director.ev_voice()
	var thr := _director.thruster_voice()
	if ev != null:
		ev.motor_rpm = 0.0
		ev.motor_load = 0.0
		ev.downforce_kg = 0.0
	if thr != null:
		thr.thrust_rear = 0.0
		thr.thrust_perimeter = 0.0
		thr.hop_charge = 0.0


## The live meter: the master peak, the master RMS and the share of the mix in the hiss band.
func _update_meter() -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0 or not _capture.can_get_buffer(available):
		return
	var frames := _capture.get_buffer(available)
	if frames.is_empty():
		return
	_peak = Spectrum.peak_dbfs(frames)
	_rms = Spectrum.rms_dbfs(frames)
	_band = Spectrum.band_energy_ratio(frames, HISS_BAND_LO, HISS_BAND_HI)
	_meter.text = "Master 峰值 peak %.1f dBFS   RMS %.1f dBFS   2-4 kHz %.0f%%" % [
		_peak, _rms, _band * BAND_PERCENT_SCALE]
	_set_bar(_peak_bar, _peak, Spectrum.DB_FLOOR, 0.0)
	_set_bar(_rms_bar, _rms, Spectrum.DB_FLOOR, 0.0)
	_set_bar(_band_bar, linear_to_db(maxf(_band, MIN_BAND_SHARE)), Spectrum.DB_FLOOR, 0.0)


## Draws a meter bar: the fill grows from the left, it turns amber near the ceiling.
func _set_bar(bar: ColorRect, value_db: float, floor_db: float, ceil_db: float) -> void:
	if bar == null:
		return
	var norm := clampf((value_db - floor_db) / (ceil_db - floor_db), 0.0, 1.0)
	bar.size.x = _bar_width * norm
	bar.color = COLOR_WARN if value_db > Tuning.METER_WARN_DB else COLOR_CYAN

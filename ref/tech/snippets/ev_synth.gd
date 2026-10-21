class_name EvSynth
extends AudioStreamPlayer3D
## Procedural electric-motor whine + cold-gas thruster hiss on an AudioStreamGenerator.
## Verified Godot 4.7.2 (headless Dummy + CoreAudio 48 kHz): ~0.7 ms GDScript per 1000 frames
## (~3.4 % of one M1 Max core per voice), 0 buffer skips. Budget: <= 2 voices (player + 1 hero).
## Usage: add as child of the car; every frame set `motor_rpm` (0..20000) and `thrust` (0..1).
## Doppler: set doppler_tracking here AND on the active Camera3D (DOPPLER_TRACKING_PHYSICS_STEP).

@export var motor_rpm := 0.0           # EV motor speed; whine pitch follows it
@export var thrust := 0.0              # 0..1 cold-gas thruster level (noise burst)
@export var whine_gain := 0.25
@export var hiss_gain := 0.6

var _pb: AudioStreamGeneratorPlayback
var _phase1 := 0.0
var _phase2 := 0.0
var _lp := 0.0                         # one-pole low-pass state for the hiss
var _rate := 48000.0

func _ready() -> void:
	_rate = AudioServer.get_mix_rate()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = 0.1            # 100 ms: enough slack for a 30 fps hitch
	stream = gen
	doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(_delta: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var f1 := motor_rpm / 60.0 * 6.0   # 6 pole-pair whine fundamental (est. timbre, tune by ear)
	var inc1 := f1 / _rate
	var inc2 := f1 * 2.76 / _rate      # inharmonic partial -> "electric" character
	var a := clampf(0.15 + 0.85 * (1.0 - exp(-motor_rpm / 4000.0)), 0.0, 1.0) * whine_gain
	var cutoff := 0.05 + 0.5 * thrust  # brighter hiss at higher thrust
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_phase1 = fmod(_phase1 + inc1, 1.0)
		_phase2 = fmod(_phase2 + inc2, 1.0)
		var whine := sin(_phase1 * TAU) * 0.7 + sin(_phase2 * TAU) * 0.3
		_lp += cutoff * (randf_range(-1.0, 1.0) - _lp)
		var s := whine * a + _lp * thrust * hiss_gain
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)

func skips() -> int:
	return _pb.get_skips() if _pb else -1

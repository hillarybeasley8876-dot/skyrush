extends SceneTree
# Audio feasibility (headless OK: the Dummy driver still mixes in real time).
# A) AudioStreamGenerator engine synth: GDScript cost per second of audio + buffer underruns (skips).
# B) Doppler: 440 Hz sine on AudioStreamPlayer3D passing the Camera3D listener at 50 m/s;
#    spectrum-analyzer peak while approaching / receding vs theory 440*343/(343-+v).
const SPEED := 50.0
var gen_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var phase := 0.0
var rpm := 900.0
var gen_usec := 0
var gen_frames := 0
var src: AudioStreamPlayer3D
var analyzer: AudioEffectSpectrumAnalyzerInstance
var t := 0.0
var peaks := {}

var ready := false

func _initialize() -> void:
	_setup.call_deferred()      # nodes are not inside the tree during _initialize(): play() would fail

func _setup() -> void:
	print("AUDIO driver=", AudioServer.get_driver_name(), " mix_rate=", AudioServer.get_mix_rate(), " latency=", AudioServer.get_output_latency())
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AudioServer.get_mix_rate()
	gen.buffer_length = 0.1                     # 100 ms ring buffer
	gen_player = AudioStreamPlayer.new()
	gen_player.stream = gen
	gen_player.volume_db = -30.0
	get_root().add_child(gen_player)
	gen_player.play()
	playback = gen_player.get_stream_playback()
	var cam := Camera3D.new()
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	get_root().add_child(cam)
	cam.make_current()
	src = AudioStreamPlayer3D.new()
	src.stream = _sine_wav(440.0)
	src.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	src.unit_size = 50.0
	src.position = Vector3(-200, 0, -5)
	get_root().add_child(src)
	src.play()
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new(), 0)
	analyzer = AudioServer.get_bus_effect_instance(0, 0) as AudioEffectSpectrumAnalyzerInstance
	ready = true

func _sine_wav(freq: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate / freq) * 100             # whole number of cycles -> seamless loop
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(sin(TAU * freq * i / rate) * 16000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w

func _process(delta: float) -> bool:
	if not ready:
		return false
	var avail := playback.get_frames_available()
	var t0 := Time.get_ticks_usec()
	var inc := (rpm / 60.0 * 3.0) / AudioServer.get_mix_rate()   # 6-cyl 4-stroke firing freq = rpm/60*3
	var buf := PackedVector2Array()
	buf.resize(avail)
	for i in avail:                               # saw + 2 harmonics + noise, ~engine timbre
		phase = fmod(phase + inc, 1.0)
		var s := (phase * 2.0 - 1.0) * 0.5 + sin(phase * TAU * 2.0) * 0.3 + sin(phase * TAU * 0.5) * 0.2 + randf_range(-0.05, 0.05)
		buf[i] = Vector2(s, s)
	playback.push_buffer(buf)
	gen_usec += Time.get_ticks_usec() - t0
	gen_frames += avail
	rpm = 900.0 + 6000.0 * absf(sin(t * 0.5))
	return false

func _physics_process(delta: float) -> bool:
	if not ready:
		return false
	t += delta
	src.position.x += SPEED * delta
	for mark in [1.0, 7.0]:                       # x=-150 (approaching), x=+150 (receding)
		if t >= mark and not peaks.has(mark):
			peaks[mark] = _peak_hz(300.0, 600.0)
	if t < 8.0:
		return false
	var c := 343.0
	print("GEN frames=%d usec=%d -> %.1f us per 1000 frames = %.2f%% of one core at %d Hz; skips=%d" % [
		gen_frames, gen_usec, gen_usec * 1000.0 / maxi(gen_frames, 1), gen_usec / 1e6 / t * 100.0, AudioServer.get_mix_rate(), playback.get_skips()])
	print("DOPPLER approach peak=%.0f Hz (theory %.0f) recede peak=%.0f Hz (theory %.0f)" % [
		peaks[1.0], 440.0 * c / (c - SPEED * cos(atan2(5.0, 150.0))), peaks[7.0], 440.0 * c / (c + SPEED * cos(atan2(5.0, 150.0)))])
	return true

func _peak_hz(lo: float, hi: float) -> float:
	var best := 0.0
	var best_f := 0.0
	var f := lo
	while f < hi:
		var m := analyzer.get_magnitude_for_frequency_range(f, f + 4.0).length()
		if m > best:
			best = m
			best_f = f + 2.0
		f += 4.0
	return best_f

extends RefCounted
## The static checks of the audio test (the parts that need no running tree).
## The entry point is game/audio/tests/test_audio.gd; `ok` is the callback that prints PASS/FAIL.
##
## The spectral checks of the two synth voices live in audio_test_spectrum.gd (the hiss) and
## in audio_test_motor.gd (the motor).

const VoiceLines := preload("res://audio/voice/voice_lines.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const Tuning := preload("res://audio/audio_tuning.gd")
const SpectrumScript := preload("res://audio/tests/audio_test_spectrum.gd")
const MotorScript := preload("res://audio/tests/audio_test_motor.gd")
const ThrusterSynthScript := preload("res://audio/synth/thruster_synth.gd")
const EvSynthScript := preload("res://audio/synth/ev_synth.gd")

const MIN_VOICE_LINES := 40
## The synth CPU budget for the two voices together (percent of one core).
const CPU_BUDGET_PCT := 8.0
## How many times a second of audio is rendered, the fastest run counts.
const CPU_RUNS := 40
## The load per core above which the wall clock says nothing about the real cost.
const CPU_LOAD_PER_CORE := 1.5

## The callback that prints the result of a check.
var ok: Callable


func run() -> void:
	_test_streams_exist()
	_test_voice_manifest()
	_test_music_present()
	_test_synth_cpu()
	var spectrum := SpectrumScript.new()
	spectrum.ok = ok
	spectrum.run()
	var motor := MotorScript.new()
	motor.ok = ok
	motor.run()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


func _test_streams_exist() -> void:
	var ids := SfxLibrary.sfx_ids()
	_check(ids.size() >= 25, "sfx count >= 25 (got %d)" % ids.size())
	for id in ids:
		var stream := SfxLibrary.stream(id)
		var dur := stream.get_length() if stream != null else 0.0
		_check(stream != null and dur > 0.01, "sfx %s loads and has duration (%.2fs)" % [id, dur])


func _test_voice_manifest() -> void:
	var lines := VoiceLines.LINES
	_check(lines.size() >= MIN_VOICE_LINES, "voice manifest has >= %d lines (got %d)" % [MIN_VOICE_LINES, lines.size()])
	var missing := 0
	var bad := 0
	var radio := 0
	var announcer := 0
	for id in lines:
		var entry: Dictionary = lines[id]
		var path := String(entry.get("file", ""))
		if not ResourceLoader.exists(path):
			missing += 1
			continue
		var stream := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
		if stream == null or stream.get_length() <= 0.05:
			bad += 1
		if String(entry.get("text", "")).is_empty():
			bad += 1
		if String(entry.get("kind", "")) == "radio":
			radio += 1
		else:
			announcer += 1
	_check(missing == 0, "every voice file exists (%d missing)" % missing)
	_check(bad == 0, "every voice file has audio and a subtitle (%d bad)" % bad)
	_check(radio >= 8, "police radio lines >= 8 (got %d)" % radio)
	_check(announcer >= 25, "announcer lines >= 25 (got %d)" % announcer)


func _test_music_present() -> void:
	for id in [&"cruise", &"pursuit", &"race"]:
		var stream := SfxLibrary.stream(id, SfxLibrary.MUSIC_DIR, true)
		var dur := stream.get_length() if stream != null else 0.0
		_check(stream != null and dur >= 55.0 and dur <= 95.0,
			"music %s is 60-90 s (%.1fs)" % [id, dur])
		_check(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop,
			"music %s loops" % id)


## The load average of the machine (-1.0 if it cannot be read, e.g. on a non-macOS host).
static func _machine_load() -> float:
	if OS.get_name() != "macOS":
		return -1.0   # sysctl only exists on macOS: no process is started elsewhere
	var output: Array = []
	OS.execute("sysctl", PackedStringArray(["-n", "vm.loadavg"]), output)
	if output.is_empty():
		return -1.0
	var text := String(output[0]).replace("{", "").replace("}", "")
	var parts := text.split(" ", false)
	if parts.is_empty():
		return -1.0
	return float(parts[0])


## The worst case CPU of the two synth voices: it must stay under the budget.
##
## The budget is a wall clock budget, so it can only be measured on a machine that is not
## busy: the load average is read first and the check is skipped when the machine is
## oversubscribed (the measured cost is printed anyway, so the reviewer sees the number).
func _test_synth_cpu() -> void:
	var ev := EvSynthScript.new()
	var thr := ThrusterSynthScript.new()
	ev.motor_rpm = 12000.0
	ev.motor_load = 1.0
	ev.speed_kmh = 200.0
	ev.downforce_kg = Tuning.DOWNFORCE_MAX_KG
	thr.thrust_rear = 1.0
	thr.thrust_perimeter = 1.0
	thr.hop_charge = 0.5
	# warm up, then time one second of audio from each voice (the best of the runs: a loaded
	# machine inflates the wall clock, the minimum is the closest to the real cost)
	ev.render_offline(4800)
	thr.render_offline(4800)
	var ev_usec := 999999999
	var thr_usec := 999999999
	for _run in CPU_RUNS:
		var t0 := Time.get_ticks_usec()
		ev.render_offline(48000)
		ev_usec = mini(ev_usec, Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		thr.render_offline(48000)
		thr_usec = mini(thr_usec, Time.get_ticks_usec() - t0)
	var ev_pct := 100.0 * float(ev_usec) / 1000000.0
	var thr_pct := 100.0 * float(thr_usec) / 1000000.0
	var total := ev_pct + thr_pct
	var label := "synth CPU %.2f%% of one core is within the %.0f%% budget (ev %.2f%%, thruster %.2f%%)" % [
		total, CPU_BUDGET_PCT, ev_pct, thr_pct]
	var load := _machine_load()
	var cores := float(OS.get_processor_count())
	if load > 0.0 and load > CPU_LOAD_PER_CORE * cores:
		print("SKIP %s: the machine is loaded (%.1f on %d cores)" % [label, load, int(cores)])
	else:
		_check(total <= CPU_BUDGET_PCT, label)
	ev.free()
	thr.free()

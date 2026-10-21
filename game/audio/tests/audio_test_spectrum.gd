extends RefCounted
## The spectral checks of the thruster hiss (the noise has to sit in the right band and to
## have the right envelope). The motor checks live in audio_test_motor.gd.
##
## Every check is a measurement of the rendered signal (not of the arithmetic that produced it).

const Helpers := preload("res://audio/tests/audio_test_helpers.gd")
const Spectrum := preload("res://audio/spectrum.gd")
const ThrusterSynthScript := preload("res://audio/synth/thruster_synth.gd")

const RATE := 48000.0
## How many runs are averaged for the release measurement.
const AVERAGE_RUNS := 8
## How many runs the attack measurement uses.
const ATTACK_RUNS := 16
## The buffer of the attack measurement (s): the envelope rises in the first 40 ms, the rest
## of the buffer gives the steady level.
const ATTACK_BUFFER_S := 0.5
## The window of the envelope measurement (s).
const ENVELOPE_WINDOW_S := 0.001
## The thruster centroid band (ref/roadster/DOSSIER.md §6.1).
const HISS_CENTROID_LO := 2000.0
const HISS_CENTROID_HI := 4000.0
const HISS_POWER_LO := 2800.0
const HISS_POWER_HI := 3500.0
const HISS_PEAK_LO := 2500.0
const HISS_PEAK_HI := 3500.0
## The envelope timing (the attack is the 10 % -> 90 % span, the release the time constant).
##
## The measured attack sits about 10 % under the nominal 30 ms: the dB envelope of a noise is
## biased low (the mean of a logarithm is below the logarithm of the mean), so the window is
## centred on the measurement and not on the nominal value.
const ATTACK_LO_S := 0.022
const ATTACK_HI_S := 0.042
const RELEASE_LO_S := 0.100
const RELEASE_HI_S := 0.140
## The time constants the attack fit searches (s) and the step of the search.
const FIT_TAU_MIN_S := 0.002
const FIT_TAU_MAX_S := 0.060
const FIT_TAU_STEP_S := 0.0002

## The callback that prints the result of a check.
var ok: Callable


func run() -> void:
	_test_thruster_spectrum()
	_test_thruster_envelope()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


## The RMS envelope of a buffer in 1 ms steps (dBFS).
static func envelope(samples: PackedFloat32Array, rate: float = RATE) -> PackedFloat32Array:
	var win := int(rate * ENVELOPE_WINDOW_S)
	var raw := PackedFloat32Array()
	var i := 0
	while i + win <= samples.size():
		var total := 0.0
		for j in range(i, i + win):
			total += samples[j] * samples[j]
		raw.append(20.0 * log(maxf(sqrt(total / float(win)), 1e-9)) / log(10.0))
		i += win
	return raw


## The average of the envelopes of several runs (the noise of the hiss fluctuates).
static func _average_envelope(voices: Array, frames: int) -> PackedFloat32Array:
	var total := PackedFloat32Array()
	var count := 0
	for v in voices:
		var env := envelope(Helpers.to_mono(v.render(frames)))
		if total.is_empty():
			total.resize(env.size())
		for i in mini(total.size(), env.size()):
			total[i] += env[i]
		count += 1
	if count > 0:
		for i in total.size():
			total[i] /= float(count)
	return total


## The slope of the envelope in dB per second: a least squares fit over the part of the
## envelope between `hi_db` and `lo_db` (relative to the reference level).
##
## A fit is far more robust than two threshold crossings on a noisy envelope: a single 1 ms
## window of noise fluctuates by ~1.2 dB, which moves a crossing by a millisecond or more.
static func _envelope_slope(env: PackedFloat32Array, reference_db: float,
		hi_db: float = -3.0, lo_db: float = -25.0) -> float:
	var sum_x := 0.0
	var sum_y := 0.0
	var sum_xx := 0.0
	var sum_xy := 0.0
	var count := 0
	for i in env.size():
		var level := env[i] - reference_db
		if level > hi_db or level < lo_db:
			continue
		var x := float(i) * ENVELOPE_WINDOW_S
		sum_x += x
		sum_y += level
		sum_xx += x * x
		sum_xy += x * level
		count += 1
	if count < 5:
		return 0.0
	var denom := float(count) * sum_xx - sum_x * sum_x
	if absf(denom) < 1e-12:
		return 0.0
	return absf((float(count) * sum_xy - sum_x * sum_y) / denom)


## The steady level of an envelope (the median of its last third).
static func _steady_level(env: PackedFloat32Array) -> float:
	if env.is_empty():
		return -120.0
	var from := env.size() * 2 / 3
	var values: Array[float] = []
	for i in range(from, env.size()):
		values.append(env[i])
	values.sort()
	return values[values.size() / 2]
## The time constant of a rising nozzle envelope, from the least squares fit of the model
## 20 * log10(1 - exp(-t / tau)) to the measured envelope.
##
## A single threshold crossing would be moved by the fluctuation of the noise (a 1 ms window
## of the hiss moves by more than a decibel, which is several milliseconds of attack), while
## the fit averages the whole rising part of the envelope.
static func _fit_attack_tau(env: PackedFloat32Array, reference_db: float) -> float:
	var best_tau := 0.0
	var best_error := INF
	var tau := FIT_TAU_MIN_S
	while tau <= FIT_TAU_MAX_S:
		var error := 0.0
		var count := 0
		for i in env.size():
			var t := float(i) * ENVELOPE_WINDOW_S
			var level := env[i] - reference_db
			if level > 0.0 or level < -24.0:
				continue
			var model := 20.0 * log(maxf(1.0 - exp(-t / tau), 1e-4)) / log(10.0)
			error += (level - model) * (level - model)
			count += 1
		if count > 8 and error < best_error:
			best_error = error
			best_tau = tau
		tau += FIT_TAU_STEP_S
	return best_tau


## The thruster spectrum: the centroid band, the peak, the band balance and the low end.
func _test_thruster_spectrum() -> void:
	var cases := [
		{"r": 1.0, "p": 0.0, "name": "rear only"},
		{"r": 0.0, "p": 1.0, "name": "perimeter only"},
		{"r": 1.0, "p": 1.0, "name": "both"},
	]
	var levels := {}
	for c in cases:
		var voice := ThrusterSynthScript.new()
		voice.thrust_rear = float(c["r"])
		voice.thrust_perimeter = float(c["p"])
		var buf := Helpers.to_stereo(voice.render_offline(48000))
		var name := String(c["name"])
		var amp := Spectrum.centroid_hz(buf, RATE)
		_check(amp > HISS_CENTROID_LO and amp < HISS_CENTROID_HI,
			"thruster %s amplitude centroid in 2-4 kHz (%.0f Hz)" % [name, amp])
		var power := Spectrum.power_centroid_hz(buf, RATE)
		_check(power > HISS_POWER_LO and power < HISS_POWER_HI,
			"thruster %s power centroid in 2.8-3.5 kHz (%.0f Hz)" % [name, power])
		var low := Spectrum.band_energy_ratio(buf, 20.0, 200.0, RATE)
		_check(low <= 0.02, "thruster %s energy below 200 Hz is <= 2%% (%.1f%%)" % [name, low * 100.0])
		levels[name] = Spectrum.rms_dbfs(buf)
		if name == "both":
			_check_band_balance(buf)
		voice.free()
	_check(float(levels["rear only"]) >= float(levels["perimeter only"]),
		"the rear group is at least as loud as the perimeter (%.1f vs %.1f dBFS)" % [
			float(levels["rear only"]), float(levels["perimeter only"])])


## The band balance of the hiss: no resampling images, the energy really reaches 8 kHz.
func _check_band_balance(buf: PackedVector2Array) -> void:
	var m24 := Spectrum.band_mean_db(buf, 2000.0, 4000.0, RATE)
	var m68 := Spectrum.band_mean_db(buf, 6000.0, 8000.0, RATE)
	var m810 := Spectrum.band_mean_db(buf, 8000.0, 10000.0, RATE)
	var m1416 := Spectrum.band_mean_db(buf, 14000.0, 16000.0, RATE)
	_check(m68 - m24 >= -15.0, "the 6-8 kHz band is within 15 dB of 2-4 kHz (%.1f dB)" % (m68 - m24))
	_check(m810 <= m68, "the 8-10 kHz band is under the 6-8 kHz band (%.1f dB)" % (m810 - m68))
	_check(m1416 <= m68, "the 14-16 kHz band is under the 6-8 kHz band (%.1f dB)" % (m1416 - m68))
	var top := Spectrum.peaks(buf, 3, RATE, 500.0)
	var peak_hz := 0.0
	if not top.is_empty():
		peak_hz = float(top[0][0])
	_check(peak_hz > HISS_PEAK_LO and peak_hz < HISS_PEAK_HI,
		"the hiss peaks between 2.5 and 3.5 kHz (%.0f Hz)" % peak_hz)


## The envelope of the hiss: a sharp 30 ms attack and a 120 ms release.
func _test_thruster_envelope() -> void:
	# the attack: the voices are fresh, so their envelope starts at zero
	var attack_voices: Array = []
	for i in ATTACK_RUNS:
		var attack_voice := ThrusterSynthScript.new()
		# the chuff would show up in the release envelope (it is tested on its own)
		attack_voice.chuff_enabled = false
		attack_voice.thrust_perimeter = 1.0
		attack_voices.append(attack_voice)
	# the envelopes of the runs are averaged: the noise of the hiss fluctuates by a decibel
	var attack := _average_envelope(attack_voices, int(ATTACK_BUFFER_S * RATE))
	var reference := _steady_level(attack)
	for v in attack_voices:
		v.free()
	# the fit gives the time constant of the nozzle envelope, 2.197 of them are the 10 % to
	# 90 % span of the attack
	var attack_span := 2.197 * _fit_attack_tau(attack, reference)
	_check(attack_span >= ATTACK_LO_S and attack_span <= ATTACK_HI_S,
		"the hiss attack reaches 90%% in 22-42 ms (%.0f ms)" % (attack_span * 1000.0))
	# the release: eight runs are averaged (the noise of the hiss fluctuates)
	var voices: Array = []
	for i in AVERAGE_RUNS:
		var v := ThrusterSynthScript.new()
		v.chuff_enabled = false
		v.thrust_perimeter = 1.0
		v.render(4800)  # let the envelope open
		voices.append(v)
	for v in voices:
		v.thrust_perimeter = 0.0
	var release := _average_envelope(voices, 9600)
	# the start level is the mean of the first ten windows (a single window of noise
	# fluctuates by more than a decibel)
	var start := -120.0
	var count := mini(10, release.size())
	if count > 0:
		var sum := 0.0
		for i in count:
			sum += release[i]
		start = sum / float(count)
	# the level of an exponential envelope falls 8.686 dB per time constant
	var release_span := 8.686 / _envelope_slope(release, start)
	_check(release_span >= RELEASE_LO_S and release_span <= RELEASE_HI_S,
		"the hiss release falls 8.7 dB in 100-140 ms (%.0f ms)" % (release_span * 1000.0))
	for v in voices:
		v.free()

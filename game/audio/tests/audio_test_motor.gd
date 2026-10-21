extends RefCounted
## The spectral checks of the motor voice and of the chuff (the thruster checks live in
## audio_test_spectrum.gd).
##
## Every check is a measurement of the rendered signal (not of the arithmetic that produced it).

const Helpers := preload("res://audio/tests/audio_test_helpers.gd")
const Tuning := preload("res://audio/audio_tuning.gd")
const Spectrum := preload("res://audio/spectrum.gd")
const ThrusterSynthScript := preload("res://audio/synth/thruster_synth.gd")
const EvSynthScript := preload("res://audio/synth/ev_synth.gd")

const RATE := 48000.0
## The motor partials at 12000 rpm (the fundamental is 800 Hz).
const MOTOR_F0 := 800.0
const MOTOR_P2 := 2208.0
const MOTOR_P3 := 4328.0

## The callback that prints the result of a check.
var ok: Callable


func run() -> void:
	_test_motor_partials()
	_test_fan_level()
	_test_chuff_shape()
	_test_standstill()
	_test_motor_recovery()
	_test_motor_stability()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


## The motor voice: the fundamental, the two inverter partials and no DC.
func _test_motor_partials() -> void:
	var ev := EvSynthScript.new()
	ev.motor_rpm = 12000.0
	ev.motor_load = 1.0
	ev.downforce_kg = 0.0
	var buf := Helpers.to_stereo(ev.render_offline(24000))
	_check(Spectrum.level_at(buf, MOTOR_F0, 40.0, RATE) > -6.0,
		"the motor fundamental is at %.0f Hz (%.1f dB)" % [
			MOTOR_F0, Spectrum.level_at(buf, MOTOR_F0, 40.0, RATE)])
	_check(Spectrum.level_at(buf, MOTOR_P2, 25.0, RATE) > -12.0,
		"the inverter partial 2.76x is at %.0f Hz (%.1f dB)" % [
			MOTOR_P2, Spectrum.level_at(buf, MOTOR_P2, 25.0, RATE)])
	_check(Spectrum.level_at(buf, MOTOR_P3, 45.0, RATE) > -18.0,
		"the inverter partial 5.41x is at %.0f Hz (%.1f dB)" % [
			MOTOR_P3, Spectrum.level_at(buf, MOTOR_P3, 45.0, RATE)])
	_check(Spectrum.level_at(buf, 2400.0, 40.0, RATE) <= -30.0,
		"there is no 2.4 kHz integer harmonic (%.1f dB)" % Spectrum.level_at(buf, 2400.0, 40.0, RATE))
	var peak := Spectrum.peak_dbfs(buf)
	var dc := Spectrum.dc_offset(buf)
	_check(20.0 * log(maxf(absf(dc), 1e-12) / 10.0 ** (peak / 20.0)) / log(10.0) <= -60.0,
		"the motor voice has no DC (%.1f dB re the peak)" % (
			20.0 * log(maxf(absf(dc), 1e-12) / 10.0 ** (peak / 20.0)) / log(10.0)))
	# the load opens the harmonic mix
	ev.motor_load = 0.0
	var idle := Helpers.to_stereo(ev.render_offline(24000))
	var idle_p2 := Spectrum.level_at(idle, MOTOR_P2, 25.0, RATE) - Spectrum.level_at(idle, MOTOR_F0, 40.0, RATE)
	var load_p2 := Spectrum.level_at(buf, MOTOR_P2, 25.0, RATE) - Spectrum.level_at(buf, MOTOR_F0, 40.0, RATE)
	_check(load_p2 - idle_p2 >= 6.0,
		"the load opens the 2.76x partial by 6 dB (%.1f dB)" % (load_p2 - idle_p2))
	ev.free()


## The fan whine: 18 dB under the motor and without harmonics.
func _test_fan_level() -> void:
	var ev := EvSynthScript.new()
	ev.motor_rpm = 12000.0
	ev.motor_load = 1.0
	ev.downforce_kg = Tuning.DOWNFORCE_MAX_KG
	var buf := Helpers.to_stereo(ev.render_offline(24000))
	var fan := Spectrum.level_at(buf, 3000.0, 60.0, RATE) - Spectrum.level_at(buf, MOTOR_F0, 40.0, RATE)
	_check(absf(fan - Tuning.FAN_LEVEL_DB) <= 2.0,
		"the fan whine is %.0f dB under the motor (%.1f dB)" % [Tuning.FAN_LEVEL_DB, fan])
	_check(Spectrum.level_at(buf, 9000.0, 80.0, RATE) <= -40.0,
		"the fan whine has no 9 kHz harmonic (%.1f dB)" % Spectrum.level_at(buf, 9000.0, 80.0, RATE))
	ev.free()
## The drive voice is silent at a standstill (a frequency of zero would make the recurrence
## of the oscillators unstable).
func _test_standstill() -> void:
	var ev := EvSynthScript.new()
	ev.motor_rpm = 0.0
	ev.motor_load = 0.0
	ev.downforce_kg = 0.0
	var samples := ev.render_offline(24000)
	var broken := 0
	for v in samples:
		if is_nan(v) or is_inf(v):
			broken += 1
	_check(broken == 0, "the drive voice has no NaN at a standstill (%d)" % broken)
	_check(Spectrum.peak_dbfs(Helpers.to_stereo(samples)) < Tuning.SILENT_DB,
		"the drive voice is silent at a standstill (%.1f dBFS)" % Spectrum.peak_dbfs(Helpers.to_stereo(samples)))
	ev.free()


## The drive voice has to come back after a standstill: the car spawns frozen at 0 km/h, so the
## first render is always at rest. The level after a standstill, after a stop and after the idle
## throttle has to be the same as the level of a fresh voice.
func _test_motor_recovery() -> void:
	var fresh := _level_after([{"rpm": 6000.0, "load": 1.0, "frames": 48000}])
	var spawn := _level_after([{"rpm": 0.0, "load": 0.0, "frames": 4800},
			{"rpm": 6000.0, "load": 1.0, "frames": 48000}])
	var drive_stop := _level_after([{"rpm": 6000.0, "load": 1.0, "frames": 4800},
			{"rpm": 0.0, "load": 0.0, "frames": 800},
			{"rpm": 6000.0, "load": 1.0, "frames": 48000}])
	var idle := _level_after([{"rpm": 0.0, "load": 0.0, "frames": 4800},
			{"rpm": 3200.0, "load": 1.0, "frames": 48000}])
	_check(absf(spawn - fresh) <= 0.5,
		"the drive voice recovers after a standstill (%.1f dB, fresh %.1f dB)" % [spawn, fresh])
	_check(absf(drive_stop - fresh) <= 0.5,
		"the drive voice recovers after a stop (%.1f dB, fresh %.1f dB)" % [drive_stop, fresh])
	_check(absf(idle - fresh) <= 0.5,
		"the drive voice recovers after the idle throttle (%.1f dB, fresh %.1f dB)" % [idle, fresh])


## The level of the drive voice must not drift when the rpm moves: the oscillators are rotators,
## so the amplitude stays exactly 1 no matter how far the frequency travels.
func _test_motor_stability() -> void:
	var ev := EvSynthScript.new()
	ev.motor_load = 1.0
	ev.motor_rpm = 9000.0
	ev.render(4800)
	var reference := Spectrum.rms_dbfs(ev.render(48000))
	var worst := 0.0
	var peak := -120.0
	for cycle in 5:
		for block in 240:
			ev.motor_rpm = 3000.0 + 12000.0 * _triangle(float(block) / 239.0)
			ev.render(800)
		ev.motor_rpm = 9000.0
		var hold := ev.render(48000)
		worst = maxf(worst, absf(Spectrum.rms_dbfs(hold) - reference))
		peak = maxf(peak, Spectrum.peak_dbfs(hold))
	_check(worst <= 0.5,
		"the drive voice keeps its level over 5 rpm cycles (%.2f dB)" % worst)
	_check(peak <= -6.0,
		"the drive voice does not clip over 5 rpm cycles (%.1f dBFS)" % peak)
	ev.free()


## A triangle from 0 to 1 and back (the rpm ramp of the stability check).
func _triangle(u: float) -> float:
	if u < 0.5:
		return u * 2.0
	return (1.0 - u) * 2.0


## The level of the last step of a list of render steps (dBFS).
func _level_after(steps: Array) -> float:
	var ev := EvSynthScript.new()
	var last := PackedFloat32Array()
	for step in steps:
		ev.motor_rpm = float(step["rpm"])
		ev.motor_load = float(step["load"])
		last = ev.render_offline(int(step["frames"]))
	ev.free()
	return Spectrum.rms_dbfs(Helpers.to_stereo(last))


## The pneumatic chuff: a band-passed burst with a low puff, only on cut-off.
func _test_chuff_shape() -> void:
	var with_chuff := ThrusterSynthScript.new()
	with_chuff.thrust_perimeter = 1.0
	with_chuff.render(4800)
	with_chuff.thrust_perimeter = 0.0
	var burst := Helpers.to_mono(with_chuff.render(7200))
	var plain := ThrusterSynthScript.new()
	plain.chuff_enabled = false
	plain.thrust_perimeter = 1.0
	plain.render(4800)
	plain.thrust_perimeter = 0.0
	var release_only := Helpers.to_mono(plain.render(7200))
	var diff := PackedFloat32Array()
	diff.resize(burst.size())
	for i in burst.size():
		diff[i] = burst[i] - release_only[i]
	var diff_buf := Helpers.to_stereo(diff)
	var band := Spectrum.band_power_db(diff_buf, 800.0, 1800.0, RATE)
	var rel_band := Spectrum.band_power_db(Helpers.to_stereo(release_only), 800.0, 1800.0, RATE)
	_check(band - rel_band >= 6.0,
		"the chuff carries the 0.8-1.8 kHz band (%.1f dB above the plain release)" % (band - rel_band))
	var puff := Spectrum.level_at(diff_buf, 90.0, 25.0, RATE)
	# the measurement of a decaying line has a spread of about 3 dB (the window and the decay
	# move the peak between the bins), so the tolerance is wide enough to stay stable
	_check(absf(puff - Tuning.CHUFF_PUFF_DB) <= 4.5,
		"the chuff has a 90 Hz puff at %.0f dB (%.1f dB)" % [Tuning.CHUFF_PUFF_DB, puff])
	# 150 ms after the cut the chuff is gone
	var tail := PackedFloat32Array()
	var from := int(0.15 * RATE)
	if from < diff.size():
		tail = diff.slice(from)
	var tail_rms := 0.0
	for v in tail:
		tail_rms += v * v
	tail_rms = sqrt(tail_rms / maxf(float(tail.size()), 1.0))
	var burst_rms := 0.0
	for i in mini(int(0.09 * RATE), diff.size()):
		burst_rms += diff[i] * diff[i]
	burst_rms = sqrt(burst_rms / maxf(float(mini(int(0.09 * RATE), diff.size())), 1.0))
	_check(20.0 * log(maxf(tail_rms, 1e-9) / maxf(burst_rms, 1e-9)) / log(10.0) <= -40.0,
		"the chuff is silent 150 ms after the cut (%.1f dB)" % (
			20.0 * log(maxf(tail_rms, 1e-9) / maxf(burst_rms, 1e-9)) / log(10.0)))
	with_chuff.free()
	plain.free()

extends RefCounted
## The pneumatic chuff of the thruster voice: the burst of escaping air on cut-off.
##
## The burst is band-passed noise taken from the same pre-filtered table as the hiss (around
## 1.2 kHz), the puff is a 90 Hz tone. The helper owns the whole state, the thruster synth
## asks it for one sample at a time — the burst lasts 90 ms, so the call per sample costs
## nothing.

const Tuning := preload("res://audio/audio_tuning.gd")

## The sine table of the puff (the puff is a 90 Hz tone, a small table is enough).
const SINE_TABLE_SIZE := 4096
const SINE_TABLE_MASK := SINE_TABLE_SIZE - 1
## The smallest gain of the band-pass that is used as a divisor.
const MIN_BAND_PASS_GAIN := 0.001

var _rate := 48000.0
## The pre-filtered hiss table (the burst reads it).
var _hiss_data := PackedFloat32Array()
var _hiss_size := 0
## The read position in the table.
var _pos := 0.0
## The level of the burst (it decays, 0 when the burst is over).
var _level := 0.0
## The age of the burst (s).
var _age := 0.0
## The state of the band-pass.
var _s1 := 0.0
var _s2 := 0.0
## The coefficients of the band-pass.
var _b0 := 0.0
var _b1 := 0.0
var _b2 := 0.0
var _a1 := 0.0
var _a2 := 0.0
## The phase of the puff tone.
var _puff_phase := 0.0
var _sine := PackedFloat32Array()


func _init() -> void:
	_sine.resize(SINE_TABLE_SIZE)
	for i in SINE_TABLE_SIZE:
		_sine[i] = sin(TAU * float(i) / float(SINE_TABLE_SIZE))


## Sets the mix rate and the hiss table (the burst reads the same noise as the hiss).
func setup(rate: float, hiss_data: PackedFloat32Array) -> void:
	_rate = rate
	_hiss_data = hiss_data
	_hiss_size = hiss_data.size()
	_update_coefficients()


## The RBJ band-pass of the burst (centre 1.2 kHz, Q 1).
func _update_coefficients() -> void:
	var w := TAU * Tuning.CHUFF_CENTRE_HZ / _rate
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * Tuning.CHUFF_Q)
	var a0 := 1.0 + alpha
	_b0 = alpha / a0
	_b1 = 0.0
	_b2 = -alpha / a0
	_a1 = -2.0 * cw / a0
	_a2 = (1.0 - alpha) / a0


## Starts a burst (the cut-off of the nozzles).
func fire() -> void:
	_level = 1.0
	_age = 0.0


## True while the burst is alive.
func active() -> bool:
	return _level > Tuning.CHUFF_MIN_LEVEL


## Clears the state (used before an offline measurement).
func reset() -> void:
	_level = 0.0
	_age = 0.0
	_s1 = 0.0
	_s2 = 0.0


## The contribution of one sample of the burst (and of the puff).
func sample() -> float:
	_age += 1.0 / _rate
	# the burst is band-passed noise around 1.2 kHz
	_pos += 1.0
	if _pos >= float(_hiss_size):
		_pos -= float(_hiss_size)
	var n := _hiss_at(_pos)
	var y := _b0 * n + _s1
	_s1 = _b1 * n - _a1 * y + _s2
	_s2 = _b2 * n - _a2 * y
	# 2 ms attack, 40 ms exponential decay
	var attack := clampf(_age / Tuning.CHUFF_ATTACK_S, 0.0, 1.0)
	var decay := exp(-_age / Tuning.CHUFF_DECAY_S)
	# the band-pass is normalised, so the level of the burst is the level of the noise
	var out := y * attack * decay * Tuning.CHUFF_LEVEL / maxf(_b0, MIN_BAND_PASS_GAIN)
	# the low puff of the escaping air (90 Hz, 50 ms, 12 dB under the burst)
	_puff_phase += Tuning.CHUFF_PUFF_HZ / _rate
	if _puff_phase >= 1.0:
		_puff_phase -= 1.0
	var puff := _sin_lut(_puff_phase)
	var puff_gain := db_to_linear(Tuning.CHUFF_PUFF_DB) * Tuning.CHUFF_PUFF_TRIM * Tuning.CHUFF_LEVEL
	out += puff * attack * exp(-_age / Tuning.CHUFF_PUFF_S) * puff_gain
	_level = decay
	if _age > Tuning.CHUFF_BURST_S:
		_level = 0.0
	return out


## The hiss table read at `pos` (linear interpolation between two samples).
func _hiss_at(pos: float) -> float:
	if _hiss_size <= 1:
		return 0.0
	var i := int(pos)
	var frac := pos - float(i)
	var j := i + 1
	if j >= _hiss_size:
		j = 0
	var a := _hiss_data[i]
	var b := _hiss_data[j]
	return a + (b - a) * frac


## Sine lookup, linear interpolation (no per-sample sin()).
func _sin_lut(phase: float) -> float:
	var pos := phase * float(SINE_TABLE_SIZE)
	var idx := int(pos)
	var frac := pos - float(idx)
	var a := _sine[idx & SINE_TABLE_MASK]
	var b := _sine[(idx + 1) & SINE_TABLE_MASK]
	return a + (b - a) * frac

extends AudioStreamPlayer3D
## EV drive voice: the motor whine (the pitch follows the rpm, the load follows the throttle), the
## inverter harmonics and the fan whine that rises with the downforce.
##
## This voice is TONAL ONLY on purpose: the road roll and the wind are looping OGG beds
## (audio_director.gd plays them), so the per-sample cost stays at a few percent of one core
## (ref/tech/GODOT.md §9 budgets two synth voices).
##
## The waveform is three pure partials (the fundamental plus the two inharmonic "inverter"
## partials 2.76 and 5.41) and a separate fan sine. Each partial has its own phase, so a
## non-integer ratio is possible (a single baked table cannot do that: it would click at the
## wrap). The partial mix opens with the load, so the timbre changes with the throttle.
##
## Each partial is a quadrature rotator: the state is the unit vector (cos, sin) of its phase and
## one sample is one rotation by the phase step. The vector is renormalised once per block, so the
## amplitude of a partial is exactly 1 no matter how far the frequency moves (a two term
## recurrence cannot do that: its amplitude drifts with 1/sqrt(sin w) and jumps at every change
## of the frequency). The state is never reset, so a voice that was rendered at a standstill
## comes back at the same level when the car drives off.
##
## No per-sample sin(): the four partials need one sin() and one cos() per block each, which is
## cheaper than a table lookup and free of interpolation noise. The frequency of a rotator is
## exact, so the partials stay at 800 / 2208 / 4328 Hz.
##
## Attach it as a child of the director and set `motor_rpm`, `motor_load`, `speed_kmh` and
## `downforce_kg` every frame.

const Tuning := preload("res://audio/audio_tuning.gd")

## EV motor speed (rpm). The whine fundamental is rpm/60 * POLE_PAIRS.
@export var motor_rpm: float = 0.0
## 0..1 motor load (throttle) — drives the whine level and the harmonic mix.
@export var motor_load: float = 0.0
## Road speed in km/h (the road and wind beds read this from the director).
@export var speed_kmh: float = 0.0
## Downforce in kg (the fan whine rises with it).
@export var downforce_kg: float = 0.0

## The overall trim of the drive voice (the fundamental is the reference).
@export var whine_gain: float = 0.30
## Overall output trim (dB) — the level the car sits at in the mix.
@export var output_gain_db: float = Tuning.EV_OUTPUT_GAIN_DB
## Mute the voice (e.g. while the car is not the player's).
@export var active: bool = true

## The partials: the fundamental, the two inverter partials and the fan.
const PARTIALS := 4
## The index of every partial in the state arrays.
const PARTIAL_FUNDAMENTAL := 0
const PARTIAL_INVERTER_2 := 1
const PARTIAL_INVERTER_3 := 2
const PARTIAL_FAN := 3
## The length of the generator buffer (s).
const BUFFER_LENGTH_S := 0.1
## How many frames the CPU average covers.
const CPU_AVERAGE_FRAMES := 30
## The microseconds per millisecond.
const USEC_PER_MSEC := 1000.0

var _pb: AudioStreamGeneratorPlayback
var _rate := 48000.0
## The state of the four rotators: the cosine and the sine of the phase (a unit vector).
var _cos := PackedFloat64Array()
var _sin := PackedFloat64Array()
## The DC blocker state.
var _dc_x := 0.0
var _dc_y := 0.0
var _dc_r := 0.995
## Rolling average of the time this voice spends rendering (ms per frame) — the audio CPU budget.
var cpu_ms := 0.0
## Total time spent rendering and total samples produced, for the per-second-of-audio cost.
var cpu_total_usec := 0.0
var samples_total := 0
var _cpu_accum := 0.0
var _cpu_frames := 0


func _init() -> void:
	# the rotators exist before the node is in the tree, so an offline render (the tests)
	# produces the same signal as the live voice
	_cos.resize(PARTIALS)
	_sin.resize(PARTIALS)
	# the phase of every partial starts at zero: the cosine is 1, the sine is 0
	for i in PARTIALS:
		_cos[i] = 1.0
		_sin[i] = 0.0


func _ready() -> void:
	_rate = AudioServer.get_mix_rate()
	_dc_r = 1.0 - TAU * Tuning.DC_BLOCK_HZ / _rate
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = BUFFER_LENGTH_S
	stream = gen
	# the voice of the player's own car is not doppler shifted: the engine and the driver
	# move together, and a chase camera that does not track its velocity would pull the
	# motor note down by a fifth at 250 km/h
	doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var t0 := Time.get_ticks_usec()
	_pb.push_buffer(render(frames))
	var spent := float(Time.get_ticks_usec() - t0)
	cpu_total_usec += spent
	samples_total += frames
	_cpu_accum += spent
	_cpu_frames += 1
	if _cpu_frames >= CPU_AVERAGE_FRAMES:
		cpu_ms = _cpu_accum / float(_cpu_frames) / USEC_PER_MSEC
		_cpu_accum = 0.0
		_cpu_frames = 0


## The amplitudes of the four partials for the current rpm and load.
func _partial_gains() -> Array[float]:
	var load := clampf(motor_load, 0.0, 1.0)
	var level := lerpf(Tuning.WHINE_LEVEL_MIN, Tuning.WHINE_LEVEL_MAX, load)
	level *= clampf(motor_rpm / Tuning.RPM_FULL, 0.0, 1.0)
	var trim := whine_gain * db_to_linear(output_gain_db) * (1.0 if active else 0.0)
	var g2 := lerpf(Tuning.PARTIAL_2_GAIN_MIN, Tuning.PARTIAL_2_GAIN_MAX, load)
	var g3 := lerpf(Tuning.PARTIAL_3_GAIN_MIN, Tuning.PARTIAL_3_GAIN_MAX, load)
	var suction := clampf(downforce_kg / Tuning.DOWNFORCE_MAX_KG, 0.0, 1.0)
	var fan := db_to_linear(Tuning.FAN_LEVEL_DB) * (Tuning.FAN_FLOOR
			+ (1.0 - Tuning.FAN_FLOOR) * suction)
	return [trim * level, trim * level * g2, trim * level * g3, trim * level * fan]


## Renders `frames` samples of the drive voice.
func render(frames: int) -> PackedVector2Array:
	var f0 := motor_rpm / Tuning.SECONDS_PER_MINUTE * Tuning.POLE_PAIRS
	var f2 := f0 * Tuning.PARTIAL_2
	var f3 := f0 * Tuning.PARTIAL_3
	var suction := clampf(downforce_kg / Tuning.DOWNFORCE_MAX_KG, 0.0, 1.0)
	var fan_f := Tuning.FAN_HZ_MIN + (Tuning.FAN_HZ_MAX - Tuning.FAN_HZ_MIN) * suction
	# a partial that would run past the Nyquist limit is muted
	var cut := Tuning.PARTIAL_CUTOFF_RATIO * _rate
	var g := _partial_gains()
	# a partial below the minimum frequency is muted, its state is kept (the phase is continuous)
	var w1: float = g[PARTIAL_FUNDAMENTAL] if f0 > Tuning.MOTOR_MIN_HZ else 0.0
	var w2: float = g[PARTIAL_INVERTER_2] if f2 > Tuning.MOTOR_MIN_HZ and f2 < cut else 0.0
	var w3: float = g[PARTIAL_INVERTER_3] if f3 > Tuning.MOTOR_MIN_HZ and f3 < cut else 0.0
	var wf: float = g[PARTIAL_FAN] if fan_f < cut else 0.0
	# the rotation step of every partial (one sample is one rotation by this angle)
	var ang1 := TAU * f0 / _rate
	var ang2 := TAU * f2 / _rate
	var ang3 := TAU * f3 / _rate
	var angf := TAU * fan_f / _rate
	var cw1 := cos(ang1)
	var sw1 := sin(ang1)
	var cw2 := cos(ang2)
	var sw2 := sin(ang2)
	var cw3 := cos(ang3)
	var sw3 := sin(ang3)
	var cwf := cos(angf)
	var swf := sin(angf)
	var c1 := _cos[PARTIAL_FUNDAMENTAL]
	var s1 := _sin[PARTIAL_FUNDAMENTAL]
	var c2 := _cos[PARTIAL_INVERTER_2]
	var s2 := _sin[PARTIAL_INVERTER_2]
	var c3 := _cos[PARTIAL_INVERTER_3]
	var s3 := _sin[PARTIAL_INVERTER_3]
	var cf := _cos[PARTIAL_FAN]
	var sf := _sin[PARTIAL_FAN]
	var dc_x := _dc_x
	var dc_y := _dc_y
	var dc_r := _dc_r
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		# the four rotators: the state is the unit vector of the phase, the output is its sine
		var nc := c1 * cw1 - s1 * sw1
		s1 = c1 * sw1 + s1 * cw1
		c1 = nc
		nc = c2 * cw2 - s2 * sw2
		s2 = c2 * sw2 + s2 * cw2
		c2 = nc
		nc = c3 * cw3 - s3 * sw3
		s3 = c3 * sw3 + s3 * cw3
		c3 = nc
		nc = cf * cwf - sf * swf
		sf = cf * swf + sf * cwf
		cf = nc
		var s := s1 * w1 + s2 * w2 + s3 * w3 + sf * wf
		# the DC blocker keeps the voice free of any offset
		var y := s - dc_x + dc_r * dc_y
		dc_x = s
		dc_y = y
		buf[i] = Vector2(y, y)
	# the state is renormalised once per block: the amplitude of a partial stays exactly 1
	var n1 := _normalise(c1, s1)
	_cos[PARTIAL_FUNDAMENTAL] = n1[0]
	_sin[PARTIAL_FUNDAMENTAL] = n1[1]
	var n2 := _normalise(c2, s2)
	_cos[PARTIAL_INVERTER_2] = n2[0]
	_sin[PARTIAL_INVERTER_2] = n2[1]
	var n3 := _normalise(c3, s3)
	_cos[PARTIAL_INVERTER_3] = n3[0]
	_sin[PARTIAL_INVERTER_3] = n3[1]
	var nf := _normalise(cf, sf)
	_cos[PARTIAL_FAN] = nf[0]
	_sin[PARTIAL_FAN] = nf[1]
	_dc_x = dc_x
	_dc_y = dc_y
	return buf


## The unit vector of a rotator state (the amplitude is brought back to 1).
func _normalise(c: float, s: float) -> Array[float]:
	var mag := sqrt(c * c + s * s)
	if mag < Tuning.ROTATOR_MIN_MAGNITUDE:
		return [1.0, 0.0]
	return [c / mag, s / mag]


## Renders `frames` samples of the settled drive voice as mono (offline use).
func render_offline(frames: int) -> PackedFloat32Array:
	var buf := render(frames)
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i].x
	return out


## The whine fundamental in Hz for the current rpm.
func whine_frequency() -> float:
	return motor_rpm / Tuning.SECONDS_PER_MINUTE * Tuning.POLE_PAIRS


## The fan whine frequency in Hz for the current downforce.
func fan_frequency() -> float:
	var suction := clampf(downforce_kg / Tuning.DOWNFORCE_MAX_KG, 0.0, 1.0)
	return Tuning.FAN_HZ_MIN + (Tuning.FAN_HZ_MAX - Tuning.FAN_HZ_MIN) * suction


## Number of buffer underruns (0 is healthy).
func skips() -> int:
	return -1 if _pb == null else _pb.get_skips()

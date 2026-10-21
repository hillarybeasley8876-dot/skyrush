extends RefCounted
## Small DSP helpers for the demo meters and the audio tests: level, band energy and the
## amplitude-weighted spectral centroid. Pure GDScript, no dependencies.

const DEFAULT_RATE := 48000.0
## The level a silent meter shows (dBFS).
const DB_FLOOR := -60.0
## The level of a silent measurement (dB).
const SILENT_DB := -120.0
## A signal below this is silent.
const SILENT_EPSILON := 1e-9
## A power below this is zero.
const POWER_EPSILON := 1e-12
## A power ratio below this is zero.
const RATIO_EPSILON := 1e-30
## The dB factor of an amplitude ratio.
const DB_AMPLITUDE := 20.0
## The dB factor of a power ratio.
const DB_POWER := 10.0
## The base of the logarithm.
const LOG_BASE := 10.0
## The smallest FFT the helpers use.
const MIN_FFT_SIZE := 64
## The first FFT size the helpers try.
const FFT_START_SIZE := 4
## The default smoothing of the peak search (Hz).
const DEFAULT_SMOOTH_HZ := 150.0
## The default tolerance of a level measurement (Hz).
const DEFAULT_TOLERANCE_HZ := 30.0


## The highest absolute sample value.
static func peak(samples: PackedVector2Array) -> float:
	var p := 0.0
	for v in samples:
		p = maxf(p, maxf(absf(v.x), absf(v.y)))
	return p


## The root mean square of the buffer.
static func rms(samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for v in samples:
		total += (v.x * v.x + v.y * v.y) * 0.5
	return sqrt(total / float(samples.size()))


## The peak level in dBFS.
static func peak_dbfs(samples: PackedVector2Array) -> float:
	var p := peak(samples)
	if p < SILENT_EPSILON:
		return SILENT_DB
	return DB_AMPLITUDE * log(p / 1.0) / log(LOG_BASE)


## The RMS level in dBFS.
static func rms_dbfs(samples: PackedVector2Array) -> float:
	var r := rms(samples)
	if r < SILENT_EPSILON:
		return SILENT_DB
	return DB_AMPLITUDE * log(r / 1.0) / log(LOG_BASE)


## The fraction of the energy between lo_hz and hi_hz (0..1).
static func band_energy_ratio(samples: PackedVector2Array, lo_hz: float, hi_hz: float,
		rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return 0.0
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var total := 0.0
	var band := 0.0
	var k0 := int(lo_hz * float(n) / rate)
	var k1 := int(hi_hz * float(n) / rate)
	for k in n / 2:
		var mag := sqrt(re[k] * re[k] + im[k] * im[k])
		var e := mag * mag
		total += e
		if k >= k0 and k <= k1:
			band += e
	if total < POWER_EPSILON:
		return 0.0
	return band / total


## The amplitude-weighted mean frequency of the spectrum (Hz).
static func centroid_hz(samples: PackedVector2Array, rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return 0.0
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var total := 0.0
	var weighted := 0.0
	for k in n / 2:
		var mag := sqrt(re[k] * re[k] + im[k] * im[k])
		var f := float(k) * rate / float(n)
		total += mag
		weighted += mag * f
	if total < SILENT_EPSILON:
		return 0.0
	return weighted / total


## The power-weighted mean frequency of the spectrum (Hz).
static func power_centroid_hz(samples: PackedVector2Array, rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return 0.0
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var total := 0.0
	var weighted := 0.0
	for k in n / 2:
		var p := re[k] * re[k] + im[k] * im[k]
		var f := float(k) * rate / float(n)
		total += p
		weighted += p * f
	if total < POWER_EPSILON:
		return 0.0
	return weighted / total


## The strongest peaks of the spectrum: an array of [frequency_hz, level_db] pairs.
##
## The spectrum is smoothed over `smooth_hz` first: the peak of a noise spectrum jumps from
## bin to bin, so the raw maximum is not a measurement.
static func peaks(samples: PackedVector2Array, count: int = 5,
		rate: float = DEFAULT_RATE, smooth_hz: float = DEFAULT_SMOOTH_HZ) -> Array:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return []
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var mags: Array = []
	var half := maxi(1, int(smooth_hz * float(n) / rate))
	for k in n / 2:
		var lo := maxi(0, k - half)
		var hi := mini(n / 2 - 1, k + half)
		var sum := 0.0
		for j in range(lo, hi + 1):
			sum += sqrt(re[j] * re[j] + im[j] * im[j])
		mags.append([float(k) * rate / float(n), sum / float(hi - lo + 1)])
	mags.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out: Array = []
	var top := float(mags[0][1]) if not mags.is_empty() else 0.0
	for i in mini(count, mags.size()):
		var level := DB_AMPLITUDE * log(maxf(float(mags[i][1]), POWER_EPSILON) \
				/ maxf(top, POWER_EPSILON)) / log(LOG_BASE)
		out.append([float(mags[i][0]), level])
	return out


## The mean power of a band in dB, relative to the whole signal.
static func band_mean_db(samples: PackedVector2Array, lo_hz: float, hi_hz: float,
		rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return SILENT_DB
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var total := 0.0
	var band := 0.0
	var k0 := int(lo_hz * float(n) / rate)
	var k1 := int(hi_hz * float(n) / rate)
	for k in n / 2:
		var p := re[k] * re[k] + im[k] * im[k]
		total += p
		if k >= k0 and k <= k1:
			band += p
	if total < POWER_EPSILON:
		return SILENT_DB
	return DB_POWER * log(maxf(band, RATIO_EPSILON) / total) / log(LOG_BASE)


## The absolute power of a band in dB (the reference is a full-scale sine).
static func band_power_db(samples: PackedVector2Array, lo_hz: float, hi_hz: float,
		rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return SILENT_DB
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var band := 0.0
	var k0 := int(lo_hz * float(n) / rate)
	var k1 := int(hi_hz * float(n) / rate)
	for k in n / 2:
		if k >= k0 and k <= k1:
			band += re[k] * re[k] + im[k] * im[k]
	return DB_POWER * log(maxf(band, RATIO_EPSILON)) / log(LOG_BASE)


## The offset of the signal (the mean of the samples).
static func dc_offset(samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for v in samples:
		total += 0.5 * (v.x + v.y)
	return total / float(samples.size())


## The level of a frequency (dB relative to the strongest bin of the spectrum).
static func level_at(samples: PackedVector2Array, hz: float, tolerance_hz: float = DEFAULT_TOLERANCE_HZ,
		rate: float = DEFAULT_RATE) -> float:
	var mono := _mono(samples)
	if mono.size() < MIN_FFT_SIZE:
		return SILENT_DB
	var n := FFT_START_SIZE
	while n * 2 <= mono.size():
		n *= 2
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		re[i] = mono[i] * w if i < mono.size() else 0.0
	_fft(re, im)
	var k0 := int((hz - tolerance_hz) * float(n) / rate)
	var k1 := int((hz + tolerance_hz) * float(n) / rate)
	var best := 0.0
	var top := 0.0
	for k in n / 2:
		var mag := sqrt(re[k] * re[k] + im[k] * im[k])
		if mag > top:
			top = mag
	for k in range(maxi(0, k0), mini(n / 2, k1 + 1)):
		var mag := sqrt(re[k] * re[k] + im[k] * im[k])
		best = maxf(best, mag)
	if top < POWER_EPSILON:
		return SILENT_DB
	return DB_AMPLITUDE * log(maxf(best, POWER_EPSILON) / top) / log(LOG_BASE)


static func _mono(samples: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = (samples[i].x + samples[i].y) * 0.5
	return out


## In-place iterative radix-2 FFT.
static func _fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := re.size()
	if n <= 1:
		return
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit != 0:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			var tr := re[i]
			re[i] = re[j]
			re[j] = tr
			var ti := im[i]
			im[i] = im[j]
			im[j] = ti
	var length := 2
	while length <= n:
		var ang := -TAU / float(length)
		var w_re := cos(ang)
		var w_im := sin(ang)
		var i := 0
		while i < n:
			var cur_re := 1.0
			var cur_im := 0.0
			var half := length >> 1
			for k in half:
				var u_re := re[i + k]
				var u_im := im[i + k]
				var v_re := re[i + k + half] * cur_re - im[i + k + half] * cur_im
				var v_im := re[i + k + half] * cur_im + im[i + k + half] * cur_re
				re[i + k] = u_re + v_re
				im[i + k] = u_im + v_im
				re[i + k + half] = u_re - v_re
				im[i + k + half] = u_im - v_im
				var next_re := cur_re * w_re - cur_im * w_im
				cur_im = cur_re * w_im + cur_im * w_re
				cur_re = next_re
			i += length
		length <<= 1

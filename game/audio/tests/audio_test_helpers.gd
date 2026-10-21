extends RefCounted
## The shared helpers of the audio tests: the buffer conversions.
##
## The test scripts are `extends RefCounted` and take the `ok` callback of the entry point
## (res://audio/tests/test_audio.gd).

## Wraps a mono buffer into the stereo format the spectrum helpers expect.
static func to_stereo(samples: PackedFloat32Array) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(samples.size())
	for i in samples.size():
		buf[i] = Vector2(samples[i], samples[i])
	return buf


## The mono mix of a stereo buffer.
static func to_mono(samples: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = 0.5 * (samples[i].x + samples[i].y)
	return out

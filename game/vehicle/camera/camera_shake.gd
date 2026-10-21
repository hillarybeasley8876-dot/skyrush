extends RefCounted
## Camera shake (dossier §2.3): low-frequency noise (8-12 Hz), never white noise and
## never `randf()` per frame. Presets: landing 0.10 m x (v_y/10) for 0.30 s (capped),
## wall hit 0.08-0.15 m for 0.25 s (scaled by the impulse), N2 ignition 0.04 m for 0.20 s.
##
## The rig reads `offset` (metres) and `rotation_deg` (pitch, yaw in degrees) after `update()`.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

class Shake:
	var amplitude: float = 0.0
	var duration: float = 0.0
	var elapsed: float = 0.0
	var seed_offset: float = 0.0

	func active() -> bool:
		return amplitude > 0.0 and elapsed < duration


var _noise: FastNoiseLite = FastNoiseLite.new()
var _shakes: Array[Shake] = []
var _time: float = 0.0
var _seed_counter: float = 0.0
var enabled: bool = true
## The shake displacement this tick, in metres.
var offset: Vector3 = Vector3.ZERO
## The shake rotation this tick, in degrees: x = pitch, y = yaw (never roll).
var rotation_deg: Vector2 = Vector2.ZERO


func _init() -> void:
	_noise.seed = 1337
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0        # the caller scales the input by the Hz we want
	_noise.fractal_octaves = 1


## Adds a shake. `strength` is the displacement amplitude in metres.
func add(strength: float, duration: float) -> void:
	if not enabled or strength <= 0.0 or duration <= 0.0:
		return
	var s := Shake.new()
	s.amplitude = strength
	s.duration = duration
	# A different noise offset per shake (deterministic, never randf() per frame).
	_seed_counter += 17.0
	s.seed_offset = _seed_counter
	_shakes.append(s)


## Advances the shake clock and updates `offset` and `rotation_deg`.
func update(dt: float) -> void:
	_time += dt
	offset = Vector3.ZERO
	rotation_deg = Vector2.ZERO
	var i := _shakes.size() - 1
	while i >= 0:
		var s := _shakes[i]
		s.elapsed += dt
		if not s.active():
			_shakes.remove_at(i)
			i -= 1
			continue
		# The envelope reaches zero exactly at the end of the shake: no pop.
		var k := 1.0 - clampf(s.elapsed / s.duration, 0.0, 1.0)
		var amp := s.amplitude * k * k
		var t := _time * CameraMath.SHAKE_FREQ + s.seed_offset
		offset += Vector3(_noise.get_noise_3d(t, 0.0, 0.0), _noise.get_noise_3d(t, 17.3, 0.0),
				_noise.get_noise_3d(t, 41.7, 0.0)) * amp
		rotation_deg += Vector2(_noise.get_noise_3d(t, 71.1, 0.0), _noise.get_noise_3d(t, 91.3, 0.0)) \
				* amp * CameraMath.SHAKE_PITCH_DEG_PER_M
		i -= 1
	if offset.length() > CameraMath.SHAKE_MAX_OFFSET:
		offset = offset.normalized() * CameraMath.SHAKE_MAX_OFFSET


func clear() -> void:
	_shakes.clear()
	offset = Vector3.ZERO
	rotation_deg = Vector2.ZERO

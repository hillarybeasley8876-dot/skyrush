extends SceneTree
const Synth := preload("res://scripts/ev_synth.gd")
var s
var t := 0.0
var us := 0
func _initialize() -> void:
	_setup.call_deferred()
func _setup() -> void:
	var cam := Camera3D.new()
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	get_root().add_child(cam)
	s = Synth.new()
	s.position = Vector3(0, 0, -5)
	s.volume_db = -80.0
	get_root().add_child(s)
func _process(delta: float) -> bool:
	if s == null:
		return false
	t += delta
	s.motor_rpm = 18000.0 * absf(sin(t * 0.7))
	s.thrust = 1.0 if fmod(t, 2.0) < 0.5 else 0.0
	if t > 6.0:
		print("EV_SYNTH ok skips=", s.skips(), " rate=", AudioServer.get_mix_rate(), " driver=", AudioServer.get_driver_name())
		return true
	return false

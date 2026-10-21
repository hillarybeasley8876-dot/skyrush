extends Node
## Camera unit tests (tools/godot.sh test res://vehicle/camera/tests/test_camera.gd).
## The test host loads this script at runtime, so the autoloads (Events, Game) and the
## contract types (VehicleBase) are available here.
##
## This file checks the dossier numbers (ref/gameplay/DOSSIER.md, camera sections); the
## scene behaviour is in test_camera_scene.gd, the effects in test_camera_effects.gd and the
## takedown cam in test_camera_takedown.gd.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const CameraPresets := preload("res://vehicle/camera/camera_presets.gd")
const Report := preload("res://vehicle/camera/tests/camera_test_report.gd")
const SceneTests := preload("res://vehicle/camera/tests/test_camera_scene.gd")
const EffectTests := preload("res://vehicle/camera/tests/test_camera_effects.gd")
const TakedownTests := preload("res://vehicle/camera/tests/test_camera_takedown.gd")

var _report := Report.new()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_math()
	await _run_module(SceneTests.new())
	await _run_module(EffectTests.new())
	await _run_module(TakedownTests.new())
	print("TEST %d checks, %d failures" % [_report.checks, _report.fails])
	print("PASS" if _report.fails == 0 else "FAIL")
	get_tree().quit(1 if _report.fails > 0 else 0)


## Runs a test module (a Node with a `run(host, report)` coroutine).
func _run_module(module: Node) -> void:
	add_child(module)
	await module.call("run", self, _report)


# --- pure numbers -------------------------------------------------------------------------------

func _test_math() -> void:
	_report.near("fov rest", CameraMath.fov_target(0, false, false), 62)
	_report.near("fov at 250 km/h", CameraMath.fov_target(69.44, false, false), 68.944)
	_report.near("fov nitro at 300 km/h", CameraMath.fov_target(83.33, true, false), 78.333)
	_report.near("fov nitro and mini", CameraMath.fov_target(83.33, true, true), 82.333)
	_report.near("fov clamped", CameraMath.fov_target(200, true, true), 84)
	_report.near("distance rest", CameraMath.distance_for_speed(0), 6.0)
	_report.near("distance top speed", CameraMath.distance_for_speed(250), 7.2)
	_report.near("speed lines off at 160", CameraMath.speed_line_intensity(160), 0)
	_report.near("speed lines full at 280", CameraMath.speed_line_intensity(280), 1)
	_report.near("blur off at 200", CameraMath.blur_strength(200, false), 0)
	_report.near("blur at 300", CameraMath.blur_strength(300, false), 0.15)
	_report.near("blur in nitro", CameraMath.blur_strength(300, true), 0.25)
	_report.near("blur at 150 in nitro", CameraMath.blur_strength(150, true), 0)
	_report.near("yaw target a third to the nose", CameraMath.yaw_target(0, PI * 0.5), 0.35 * PI * 0.5)
	var look := CameraMath.look_point(Vector3(1, 0, 2), Vector3.FORWARD, 4, 1.2)
	_report.check("look point", look.is_equal_approx(Vector3(1, 1.2, -2)), str(look))
	_report.near("punch kick", CameraMath.punch_offset(CameraMath.PUNCH_KICK_TIME), -0.6)
	_report.near("punch after the kick", CameraMath.punch_offset(CameraMath.PUNCH_TIME), 0.4)
	_report.near("punch release", CameraMath.punch_release(1), 0)
	_report.near("punch release from a value", CameraMath.punch_release_from(0.2, 0.5), 0.1)
	_report.near("landing shake at 60 m/s", CameraMath.landing_shake(60), 0.25)
	_report.near("wall shake at the minimum impulse", CameraMath.wall_shake(8000), 0.08)
	_report.near("wall shake at a hard hit", CameraMath.wall_shake(30000), 0.15)
	_report.near("near preset distance", CameraPresets.get_preset(0).dist, 6.0)
	_report.near("near preset height", CameraPresets.get_preset(0).height, 1.9)
	_report.check("preset cycle", CameraPresets.next_preset(2) == 0)

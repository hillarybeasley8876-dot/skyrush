extends Node
## The takedown cam tests: the shot timeline on unscaled game time, the placement in a
## tunnel and on a deck with parapets, and the hood view's cull mask.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")
const Report := preload("res://vehicle/camera/tests/camera_test_report.gd")
const Helpers := preload("res://vehicle/camera/tests/camera_test_helpers.gd")

## The tunnnel: the floor, the walls with their inner faces at plus/minus 4.25, the ceiling.
const TUNNEL_HALF := 4.5
const TUNNEL_INNER := 4.25
const TUNNEL_CEILING := 5.5
## The deck: parapets 1.1 m tall at plus/minus 6.
const DECK_PARAPET := 6.0
const DECK_PARAPET_HEIGHT := 1.1

var _report: Report = null
var _helpers := Helpers.new()
var _requests: Array[Vector2] = []       ## (unscaled time, time scale) of every request


func run(host: Node, report: Report) -> void:
	_report = report
	await _test_timeline(host)
	await _test_tunnel(host)
	await _test_deck(host)
	await _test_cull_mask(host)
	await _test_focus_owns_no_slowmo(host)


func _on_slowmo_request(time_scale: float, _duration: float, _focus: Node3D) -> void:
	_requests.append(Vector2(_now(), time_scale))


## The unscaled ("real") seconds since the test started.
func _now() -> float:
	return _clock


var _clock: float = 0.0


func _step(host: Node) -> void:
	# One tick of unscaled game time, the same clock the camera uses.
	await host.get_tree().physics_frame
	_clock += CameraMath.physics_step()


func _test_timeline(host: Node) -> void:
	_requests.clear()
	_clock = 0.0
	_helpers.setup(host)
	Events.slowmo_request.connect(_on_slowmo_request)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 2)
	var victim := _helpers.new_car(host, Vector3(0, 0, 20), Vector3(0, 0, -15))
	await _helpers.tick(host, 2)
	Events.takedown.emit(victim, &"police")
	var cut_at := -1.0
	var cut_back := -1.0
	var scales: Array[float] = []
	for i in Engine.physics_ticks_per_second * 5:
		await _step(host)
		for r in _requests:
			scales.append(r.y)
		if cut_at < 0.0 and _has_scale(scales, CameraMath.TAKEDOWN_SLOWMO):
			cut_at = _clock
		if cut_back < 0.0 and not _helpers.cam_root.call("is_takedown_active"):
			cut_back = _clock
			break
	Events.slowmo_request.disconnect(_on_slowmo_request)
	_report.check("takedown: the shot plays", cut_at > 0.0, "no 0.30 request")
	_report.near("takedown: the cut is at 0.06 s", cut_at, CameraMath.TAKEDOWN_CUT, 0.02)
	_report.near("takedown: the cut back is at 2.70 s", cut_back, CameraMath.TAKEDOWN_TOTAL, 0.02)
	_report.check("takedown: the hit-stop uses the slow scale",
			_has_scale(scales, CameraMath.TAKEDOWN_HITSTOP_SCALE), str(scales))
	_report.check("takedown: the time scale eases to one",
			_has_scale(scales, 1.0), str(scales))
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _has_scale(scales: Array[float], value: float) -> bool:
	for s in scales:
		if absf(s - value) < 0.02:
			return true
	return false


func _test_tunnel(host: Node) -> void:
	_helpers.setup(host)
	_helpers.box(host, Vector3(TUNNEL_HALF * 2, 0.5, 400), Vector3(0, -0.25, 0))
	_helpers.box(host, Vector3(0.5, 6, 400), Vector3(-TUNNEL_HALF, 3, 0))
	_helpers.box(host, Vector3(0.5, 6, 400), Vector3(TUNNEL_HALF, 3, 0))
	_helpers.box(host, Vector3(TUNNEL_HALF * 2, 0.5, 400), Vector3(0, TUNNEL_CEILING + 0.25, 0))
	var victim := _helpers.new_car(host, Vector3(0, 0.02, 0), Vector3(0, 0, -15))
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	Events.takedown.emit(victim, &"police")
	await _helpers.tick(host, 8)
	var cam_pos := _helpers.cam.global_position
	_report.check("takedown in a tunnel: the camera stays inside", absf(cam_pos.x) <= TUNNEL_INNER,
			str(cam_pos))
	_report.check("takedown in a tunnel: the camera sees the victim",
			not _helpers.blocked(host, cam_pos, victim.global_position + Vector3.UP * 0.5), str(cam_pos))
	_report.check("takedown in a tunnel: the camera is not inside a wall",
			absf(cam_pos.x) <= TUNNEL_INNER - 0.3, str(cam_pos))
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_deck(host: Node) -> void:
	_helpers.setup(host)
	_helpers.box(host, Vector3(40, 0.5, 400), Vector3(0, -0.25, 0))
	_helpers.box(host, Vector3(0.4, DECK_PARAPET_HEIGHT, 400), Vector3(-DECK_PARAPET, 0.55, 0))
	_helpers.box(host, Vector3(0.4, DECK_PARAPET_HEIGHT, 400), Vector3(DECK_PARAPET, 0.55, 0))
	var victim := _helpers.new_car(host, Vector3(0, 0.02, 0), Vector3(0, 0, -15))
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	Events.takedown.emit(victim, &"police")
	await _helpers.tick(host, 8)
	var cam_pos := _helpers.cam.global_position
	var inside := absf(cam_pos.x) <= DECK_PARAPET - 0.3
	var above := cam_pos.y >= DECK_PARAPET_HEIGHT
	_report.check("takedown on a deck: the camera is inside the parapets or above them",
			inside or above, str(cam_pos))
	_report.check("takedown on a deck: the camera sees the victim",
			not _helpers.blocked(host, cam_pos, victim.global_position + Vector3.UP * 0.5), str(cam_pos))
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


func _test_cull_mask(host: Node) -> void:
	Game.options["camera_preset"] = "bumper"
	_helpers.setup(host)
	await _helpers.tick(host, 4)
	var bit := 1 << (CameraMath.SELF_FX_LAYER - 1)
	_report.check("hood view: the self-FX layer is hidden",
			(_helpers.cam.cull_mask & bit) == 0, str(_helpers.cam.cull_mask))
	Game.options["camera_preset"] = "near"
	_helpers.setup(host)
	await _helpers.tick(host, 4)
	_report.check("chase view: the self-FX layer is visible",
			(_helpers.cam.cull_mask & bit) != 0, str(_helpers.cam.cull_mask))
	Game.options.erase("camera_preset")
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame


## A focus shot (the damage unit's wreck cam) must not touch the caller's slow motion.
func _test_focus_owns_no_slowmo(host: Node) -> void:
	_requests.clear()
	_helpers.setup(host)
	Events.slowmo_request.connect(_on_slowmo_request)
	await _helpers.tick(host, Engine.physics_ticks_per_second / 4)
	var target := _helpers.new_car(host, Vector3(0, 0, 20), Vector3(0, 0, -15))
	Events.camera_focus.emit(target, 2.2)
	await _helpers.tick(host, Engine.physics_ticks_per_second)
	_report.check("a focus shot never asks for a slow motion", _requests.is_empty(), str(_requests))
	Events.slowmo_request.disconnect(_on_slowmo_request)
	_helpers.cam_root.queue_free()
	await host.get_tree().physics_frame

extends Node
## The minimap shows the route of the race and the next gate (the job `hud-route`).
##
## Three parts: the minimap panel on its own (the route polyline and the gate marker), the HUD
## (the bus hands the minimap the route of the race and the gate of the player) and the modes
## (the race status carries the route, the next gate and the number of gates).
##
## The members that do not exist yet are read with `get`, so a missing member is a FAIL line and
## not a script error.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const HudScene := preload("res://ui/hud/hud.tscn")
const MinimapPanelScript := preload("res://ui/hud/minimap_panel.gd")

## The gate the player has to pass in the test of the HUD.
const GATE := 2

var _failures: int = 0
var _modes: ModeDirector = null
## Every status of the bus: [kind, data].
var _records: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	_build_world()
	Events.mode_status.connect(_on_mode_status)
	await _test_panel()
	await _test_hud()
	await _test_modes()
	if _failures == 0:
		print("ROUTE MARKER TESTS OK (0 failures)")
	else:
		print("ROUTE MARKER TESTS FAILED (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The sandbox, the player, the rivals and the director of the modes.
func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	await _frames(2)


## The panel on its own: the route polyline and the gate marker.
func _test_panel() -> void:
	var panel: Variant = MinimapPanelScript.new()
	add_child(panel)
	await _frames(2)
	var points := PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(20.0, 0.0)])
	_check(panel.has_method("set_route"), "the minimap can take a route")
	if panel.has_method("set_route"):
		panel.set_route(points)
		_check(_point_count(panel) == 3, "the minimap holds the points of the route")
	_check(panel.has_method("clear_route"), "the minimap can drop the route")
	_check(panel.has_method("set_next_gate"), "the minimap can take a gate")
	if panel.has_method("set_next_gate"):
		panel.set_next_gate(Vector2(12.0, 34.0))
		_check(_flag(panel, "has_next_gate"), "the minimap has a gate")
		var gate: Variant = _member(panel, "next_gate_world")
		var ok := false
		if gate is Vector2:
			var g: Vector2 = gate
			ok = g.distance_to(Vector2(12.0, 34.0)) < 0.001
		_check(ok, "the gate of the minimap is where it was put")
	_check(panel.has_method("clear_next_gate"), "the minimap can drop the gate")
	if panel.has_method("clear_next_gate"):
		panel.clear_next_gate()
		_check(not _flag(panel, "has_next_gate"), "the gate of the minimap is gone")
	if panel.has_method("clear_route"):
		panel.clear_route()
		_check(_point_count(panel) == 0, "the route of the minimap is gone")
		_check(not _flag(panel, "has_next_gate"), "dropping the route drops the gate")
	# The gate near the player is on the map, the one 3 km away is not.
	var size := _clip_size(panel)
	var near_sp: Vector2 = panel.project_point(Vector2(50.0, 50.0))
	var far_sp: Vector2 = panel.project_point(Vector2(3000.0, 3000.0))
	_check(_inside_rect(near_sp, size), "the gate near the player is on the map")
	_check(not _inside_rect(far_sp, size), "the gate 3 km away is off the map")
	panel.queue_free()
	await _frames(1)


## The HUD: the bus hands the minimap the route of the race and the next gate of the player.
func _test_hud() -> void:
	if Game.world == null:
		_check(false, "the world of the test is there")
		return
	var route: RaceRoute = Game.world.get_route(&"sandbox_loop")
	if route == null:
		_check(false, "the world has the route of the test")
		return
	var hud: CanvasLayer = HudScene.instantiate() as CanvasLayer
	add_child(hud)
	hud.set("telemetry_override", CarTelemetry.new())
	await _frames(2)
	var minimap: Variant = hud.get("minimap")
	_check(minimap != null, "the HUD has a minimap")
	if minimap == null:
		return
	_emit_race(GATE)
	await _frames(2)
	_check(_point_count(minimap) >= 20, "the minimap has the line of the route (%d points)" %
		_point_count(minimap))
	_check(_gate_at(minimap, route, GATE), "the marker is at the gate %d of the route" % GATE)
	# The next gate moves the marker.
	_emit_race(GATE + 1)
	await _frames(2)
	_check(_gate_at(minimap, route, GATE + 1), "the marker moves to the next gate")
	# A free roam clears the route and the marker.
	Events.mode_status.emit(&"free", {"score": 10})
	await _frames(2)
	_check(not _flag(minimap, "has_next_gate"), "the free roam clears the marker")
	_check(_point_count(minimap) == 0, "the free roam clears the route")
	# A race whose player is home keeps the route but has no marker.
	_emit_race(-1)
	await _frames(2)
	_check(not _flag(minimap, "has_next_gate"), "a race without a next gate has no marker")
	_check(_point_count(minimap) >= 20, "the route stays on the map")


## The modes: the race status carries the route, the next gate and the number of gates.
func _test_modes() -> void:
	_records.clear()
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 2})
	await get_tree().create_timer(0.5).timeout
	var data := _last_of(&"race")
	_check(String(data.get("route", "")) == "sandbox_loop",
		"the race reports the route (%s)" % str(data))
	_check(int(data.get("gates", 0)) == 8, "the race reports the 8 gates (%s)" % str(data))
	_check(int(data.get("next_gate", -9)) == 0,
		"the race reports the next gate of the player (%s)" % str(data))
	# The player passes the first gate: the next gate follows.
	var session := _modes.session as RaceSession
	if session == null:
		_check(false, "the race session is there")
		return
	session.state = RaceSession.State.RUNNING
	session._on_gate_passed(Game.player, 0)
	await get_tree().create_timer(0.5).timeout
	var after := _last_of(&"race")
	_check(int(after.get("next_gate", -9)) == 1, "the next gate follows the pass (%s)" % str(after))


## The bus: every status is collected.
func _on_mode_status(kind: StringName, data: Dictionary) -> void:
	_records.append([kind, data])


## The data of the last status of a kind (empty when there is none).
func _last_of(kind: StringName) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		if _records[i][0] == kind:
			return _records[i][1] as Dictionary
	return {}


## A race status with the route of the test and the given next gate.
func _emit_race(next_gate: int) -> void:
	Events.mode_status.emit(&"race", {"lap": 1, "laps": 2, "position": 1, "racers": 6,
		"route": "sandbox_loop", "next_gate": next_gate, "gates": 8})


## The number of points of the route on the minimap (0 when there is none).
func _point_count(minimap: Variant) -> int:
	var raw: Variant = _member(minimap, "route_points")
	if raw is PackedVector2Array:
		var arr: PackedVector2Array = raw
		return arr.size()
	return 0


## True when the marker of the minimap is at the origin of the checkpoint of the route.
func _gate_at(minimap: Variant, route: RaceRoute, index: int) -> bool:
	if index < 0 or index >= route.checkpoints.size():
		return false
	var raw: Variant = _member(minimap, "next_gate_world")
	if not (raw is Vector2):
		return false
	var gate: Vector2 = raw
	var origin: Vector3 = route.checkpoints[index].origin
	return gate.distance_to(Vector2(origin.x, origin.z)) < 0.1


## The size of the map area of the minimap.
func _clip_size(minimap: Variant) -> Vector2:
	var clip: Variant = _member(minimap, "_clip")
	if clip == null:
		return Vector2.ZERO
	var raw: Variant = clip.get("size")
	if raw is Vector2:
		return raw
	return Vector2.ZERO


## True when the point is inside the rectangle.
func _inside_rect(point: Vector2, size: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= size.x and point.y <= size.y


## A member of an object (null when it is not there).
func _member(obj: Variant, name: String) -> Variant:
	if obj == null:
		return null
	return obj.get(name)


## True when a boolean member of an object is true.
func _flag(obj: Variant, name: String) -> bool:
	var raw: Variant = _member(obj, name)
	return raw == true

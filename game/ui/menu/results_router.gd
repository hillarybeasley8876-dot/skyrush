extends RefCounted
## The menu's side of the modes unit.
##
## The modes unit owns the sessions, the scores and the records (GameRecords); the menu only
## starts a mode and shows what the modes unit reports. The director is found by duck-typing the
## `start_mode` method (the modes unit documents that as the menu API) and then cached.

## A mode reported its results: the payload for the results screen.
signal results_ready(payload: Dictionary)

var director: Node = null
var route_id: String = ""
## The options the mode was started with (the retry uses them again).
var options: Dictionary = {}

var _session: Node = null


const Bridge := preload("res://ui/menu/bridge.gd")

## The modes unit's director (null when the unit is not loaded).
func find_director() -> Node:
	if director != null and is_instance_valid(director):
		return director
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	director = Bridge.find_by_method(tree.root, &"start_mode")
	return director


## Starts a mode and listens to its results.
func start(mode: StringName, options: Dictionary) -> bool:
	var node := find_director()
	if node == null:
		return false
	route_id = String(options.get("route", ""))
	self.options = options.duplicate()
	node.call(&"start_mode", mode, options)
	listen()
	return true


## Connects to the results of the running session.
func listen() -> void:
	var node := find_director()
	if node == null:
		return
	var session: Variant = node.get("session")
	if session == null or not (session is Node):
		return
	if session == _session:
		return
	_session = session
	var signal_name := &"finished"
	if not _session.has_signal(signal_name):
		return
	_session.connect(signal_name, _on_session_finished)


## The results of the running session (the free roam summary), or an empty dictionary.
func session_results() -> Dictionary:
	var node := find_director()
	if node == null:
		return {}
	var session: Variant = node.get("session")
	if session == null or not (session is Node):
		return {}
	if _session_has_results(session):
		return session.call("build_results") as Dictionary
	return {}


## Parks the running session (the menu takes over the screen, the mode does not run on).
func park_session() -> void:
	var node := find_director()
	if node == null:
		return
	var session: Variant = node.get("session")
	if session is Node:
		(session as Node).process_mode = Node.PROCESS_MODE_DISABLED


## The best race time of a route in seconds (-1 when there is none).
func best_time(id: String) -> float:
	var recs: Variant = _records()
	if recs == null:
		return -1.0
	return float(recs.call("best_time", id))


## The best lap of a route in seconds (-1 when there is none).
func best_lap(id: String) -> float:
	var recs: Variant = _records()
	if recs == null:
		return -1.0
	return float(recs.call("best_lap", id))


## The free-roam high score.
func best_score() -> float:
	var recs: Variant = _records()
	if recs == null:
		return 0.0
	return float(recs.call("best_score"))


func _records() -> Variant:
	var node := find_director()
	if node == null:
		return null
	return node.get("records")


func _session_has_results(session: Node) -> bool:
	return session.has_method("build_results")


func _on_session_finished(results: Variant) -> void:
	results_ready.emit(build_payload(results))


## Turns the results of a session into the payload of the results screen.
func build_payload(results: Variant) -> Dictionary:
	if results is Array:
		return _race_payload(results as Array)
	if results is Dictionary:
		var data := results as Dictionary
		var kind := String(data.get("kind", "free"))
		if kind == "pursuit":
			return _pursuit_payload(data)
		return _free_payload(data)
	return {}


func _race_payload(results: Array) -> Dictionary:
	var route_title := ""
	if Game.world != null and not route_id.is_empty():
		var route := Game.world.get_route(StringName(route_id))
		if route != null:
			route_title = route.title
	return {
		"kind": "race",
		"results": results,
		"route": route_id,
		"route_title": route_title,
		"best_time": best_time(route_id),
		"best_lap": best_lap(route_id),
		"options": options,
	}


func _pursuit_payload(data: Dictionary) -> Dictionary:
	return {
		"kind": "pursuit",
		"result": String(data.get("result", "running")),
		"takedowns": int(data.get("takedowns", 0)),
		"target": int(data.get("target", 0)),
		"time": float(data.get("time", 0.0)),
		"heat": int(data.get("heat", 0)),
		"options": options,
	}


func _free_payload(data: Dictionary) -> Dictionary:
	return {
		"kind": "free",
		"score": int(data.get("score", 0)),
		"stunts": int(data.get("stunts", 0)),
		"near_misses": int(data.get("near_misses", 0)),
		"wrecks": int(data.get("wrecks", 0)),
		"takedowns": int(data.get("takedowns", 0)),
		"time": float(data.get("time", 0.0)),
		"best_score": float(data.get("best_score", best_score())),
		"options": options,
	}

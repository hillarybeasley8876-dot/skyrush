extends Node
## The toggle probe: the whole game with the player car parked, and the units switched off one at a time for a few seconds each, so
## the cost of a unit is the difference against everything on. Every frame is split like in tools/frame_probe.gd: the physics of the
## frame (from the first tick to the process step, per tick) and the rest (the process callbacks, the render). A diagnostic tool, not
## a test. A unit that is switched off also takes its bodies out of the physics (the default disable mode removes them).
##
##   python tools/gd.py shot --scene=res://tools/toggle_probe.tscn --out=tp --stub=menu --times=200
##
## Option: phase=4 (the seconds of a phase).

const MAIN := "res://main.tscn"


## The first node of every physics tick: it writes down when the tick starts.
class TickClock:
	extends Node
	var probe: Node = null

	func _ready() -> void:
		process_physics_priority = -1000000

	func _physics_process(_delta: float) -> void:
		probe.call(&"_tick_started", Time.get_ticks_usec())


var _recording := false
var _tick_starts: PackedInt64Array = PackedInt64Array()
var _last_process := 0
var _frames: Array[float] = []
var _physics: Array[float] = []
var _ticks := 0


func _ready() -> void:
	process_priority = -1000000
	var clock := TickClock.new()
	clock.probe = self
	add_child(clock)
	_run.call_deferred()


func _tick_started(usec: int) -> void:
	_tick_starts.append(usec)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _recording and _last_process > 0:
		_frames.append(float(now - _last_process) / 1000.0)
		_physics.append(float(now - _tick_starts[0]) / 1000.0 if not _tick_starts.is_empty() else 0.0)
		_ticks += _tick_starts.size()
	_last_process = now
	_tick_starts.clear()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(4.0).timeout
	var car := Game.player as VehicleBase
	car.freeze = false
	car.reset_to(Game.world.respawn_transform(Vector3(-60.0, 0.0, -300.0), Vector3.FORWARD))
	await get_tree().create_timer(3.0).timeout
	var phase := float(Game.option("phase", "4"))
	var units: Array[Node] = []
	var names: Array[String] = []
	for child in main.get_children():
		if child == Game.player or child == Game.world or child is Camera3D:
			continue
		units.append(child)
		names.append("%s (%d nodes)" % [child.name, _count(child)])
	print("TOGGLE units: %s" % ", ".join(names))
	var players_3d: Array[Node] = get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false)
	var director := get_tree().get_first_node_in_group(&"traffic_director")
	await _measure("everything on", phase)
	for unit in units:
		_switch([unit], false)
		await _measure("%s off" % unit.name, phase)
		_switch([unit], true)
	_switch(players_3d, false)
	await _measure("the 3D audio players off", phase)
	_switch(players_3d, true)
	if director != null:
		_switch([director], false)
		await _measure("the traffic director alone off", phase)
		_switch([director], true)
	await _measure("everything on again", phase)
	get_tree().quit(0)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _switch(nodes: Array[Node], enabled: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _measure(label: String, seconds: float) -> void:
	await get_tree().create_timer(0.5).timeout
	_frames.clear()
	_physics.clear()
	_ticks = 0
	_recording = true
	await get_tree().create_timer(seconds).timeout
	_recording = false
	var sorted := _frames.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	var frame_sum := 0.0
	var physics_sum := 0.0
	for i in _frames.size():
		frame_sum += _frames[i]
		physics_sum += _physics[i]
	var count := maxf(float(_frames.size()), 1.0)
	print("TOGGLE %-34s frame median %6.2f ms mean %6.2f; physics %5.2f ms per tick x %.2f; rest %5.2f ms" % [label, median,
		frame_sum / count, physics_sum / maxf(float(_ticks), 1.0), float(_ticks) / count, (frame_sum - physics_sum) / count])

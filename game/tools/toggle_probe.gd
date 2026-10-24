extends Node
## The toggle probe: the whole game with the player car parked, and groups of nodes switched off for a few seconds each, so the
## cost of a group is the difference of the frame times. A diagnostic tool, not a test.
##
##   python tools/gd.py shot --scene=res://tools/toggle_probe.tscn --out=tp --stub=menu --times=90
##
## Option: phase=4 (the seconds of a phase).

const MAIN := "res://main.tscn"

var _times: Array[float] = []
var _recording := false


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	if _recording:
		_times.append(delta * 1000.0)


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
	var players_3d: Array[Node] = get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false)
	var players_2d: Array[Node] = get_tree().root.find_children("*", "AudioStreamPlayer", true, false)
	var audio_units: Array[Node] = _named(["AudioDirector", "Audio"])
	var police: Array[Node] = get_tree().get_nodes_in_group(&"police")
	var police_units: Array[Node] = _named(["PoliceDirector", "Police"])
	var traffic: Array[Node] = get_tree().get_nodes_in_group(&"traffic")
	print("TOGGLE %d 3D players (%d playing), %d 2D players, audio units %s, %d police cars, police units %s, %d traffic cars" % [
		players_3d.size(), _playing(players_3d), players_2d.size(), _paths(audio_units), police.size(), _paths(police_units),
		traffic.size()])
	await _measure("everything on", phase)
	_switch(players_3d, false)
	await _measure("3D audio players off", phase)
	_switch(players_3d, true)
	_switch(audio_units, false)
	await _measure("the audio unit off", phase)
	_switch(audio_units, true)
	_switch(police, false)
	await _measure("the police cars off", phase)
	_switch(police, true)
	_switch(police_units, false)
	await _measure("the police unit off", phase)
	_switch(police_units, true)
	_switch(traffic, false)
	await _measure("the traffic cars off", phase)
	_switch(traffic, true)
	await _measure("everything on again", phase)
	get_tree().quit(0)


func _named(names: Array) -> Array[Node]:
	var out: Array[Node] = []
	for n in names:
		var node := get_tree().root.find_child(String(n), true, false)
		if node != null:
			out.append(node)
	return out


func _paths(nodes: Array[Node]) -> String:
	var parts: Array[String] = []
	for n in nodes:
		parts.append(String(n.get_path()).trim_prefix("/root/"))
	return "[" + ", ".join(parts) + "]"


func _playing(players: Array[Node]) -> int:
	var count := 0
	for p in players:
		if p is AudioStreamPlayer3D and (p as AudioStreamPlayer3D).playing:
			count += 1
	return count


func _switch(nodes: Array[Node], enabled: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _measure(label: String, seconds: float) -> void:
	await get_tree().create_timer(0.5).timeout
	_times.clear()
	var physics_before := Engine.get_physics_frames()
	_recording = true
	await get_tree().create_timer(seconds).timeout
	_recording = false
	var sorted := _times.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	var steps := float(Engine.get_physics_frames() - physics_before) / maxf(float(sorted.size()), 1.0)
	print("TOGGLE %-26s median %6.2f ms, %4d frames, %.1f physics steps a frame" % [label, median, sorted.size(), steps])

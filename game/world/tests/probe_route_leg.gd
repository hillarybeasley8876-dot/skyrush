extends Node
## Probe (not a test): why has a leg of a route no forward path? Prints the gate lanes of both gates and the lanes that can be
## reached from the first one.
##
##   SKYRUSH_ROUTE=grand_loop SKYRUSH_FROM=26 SKYRUSH_TO=0 python tools/gd.py test res://world/tests/probe_route_leg.gd

const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const LanePathFinder := preload("res://world/api/lane_path_finder.gd")
const RouteGates := preload("res://world/api/route_gates.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var packed := load("res://world/world.tscn") as PackedScene
	var world := packed.instantiate() as WorldBase
	get_tree().root.add_child(world)
	for i in 900:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			break
	var lanes := world.get_lane_paths()
	var grid := LaneSpatial.new()
	grid.build(lanes)
	var finder := LanePathFinder.new()
	var route := world.get_route(StringName(OS.get_environment("SKYRUSH_ROUTE")))
	var from_i := int(OS.get_environment("SKYRUSH_FROM"))
	var to_i := int(OS.get_environment("SKYRUSH_TO"))
	var from := route.checkpoints[from_i]
	var to := route.checkpoints[to_i]
	print("INFO gate %d at %s facing %s, gate %d at %s facing %s" % [from_i, str(from.origin), str(-from.basis.z), to_i, str(to.origin), str(-to.basis.z)])
	var sources := finder.gate_lanes(lanes, grid, from, RouteGates.GATE_RADIUS)
	var targets := finder.gate_lanes(lanes, grid, to, RouteGates.GATE_RADIUS)
	print("INFO sources %s" % str(_names(lanes, sources)))
	for i in sources:
		print("INFO   source lane %d: first %s last %s points %d" % [i, str(lanes[i].curve.get_point_position(0)), str(lanes[i].curve.get_point_position(lanes[i].curve.get_point_count() - 1)), lanes[i].curve.get_point_count()])
	print("INFO targets %s" % str(_names(lanes, targets)))
	var seen: Dictionary = {}
	var queue: Array[int] = []
	for s in sources:
		seen[s] = true
		queue.append(s)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for n in lanes[i].next_lanes:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	print("INFO %d lanes are reachable from the sources" % seen.size())
	var hit := false
	for t in targets:
		hit = hit or seen.has(t)
	print("INFO a target is reachable: %s" % str(hit))
	var roads: Dictionary = {}
	for i in seen.keys():
		roads[String(lanes[int(i)].road_id)] = int(roads.get(String(lanes[int(i)].road_id), 0)) + 1
	var names := roads.keys()
	names.sort()
	print("INFO reachable roads: %s" % str(names.slice(0, 80)))
	var path := finder.find_multi(lanes, sources, targets)
	print("INFO find_multi gives %d lanes" % path.size())
	_check_path(lanes)
	print("PROBE DONE")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _names(lanes: Array[LanePath], list: Array[int]) -> Array:
	var out: Array = []
	for i in list:
		out.append("%d:%s" % [i, String(lanes[i].road_id)])
	return out


## The lanes of a path of lanes.json ids (SKYRUSH_PATH): the first link the game does not have.
func _check_path(lanes: Array[LanePath]) -> void:
	var path_file := OS.get_environment("SKYRUSH_PATH")
	if path_file == "":
		return
	var ids: Array = JSON.parse_string(FileAccess.get_file_as_string(path_file))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/lanes.json"))
	var by_id: Dictionary = {}
	for entry: Dictionary in data["lanes"]:
		by_id[String(entry["id"])] = entry
	var index_of: Dictionary = {}
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var p := lane.curve.get_point_position(0)
		var q := lane.curve.get_point_position(lane.curve.get_point_count() - 1)
		index_of["%s|%d|%d|%d|%d" % [String(lane.road_id), roundi(p.x * 2.0), roundi(p.z * 2.0), roundi(q.x * 2.0), roundi(q.z * 2.0)]] = i
	var previous := -1
	for k in ids.size():
		var entry: Dictionary = by_id[String(ids[k])]
		var p0: Array = entry["points"][0]
		var p1: Array = entry["points"][entry["points"].size() - 1]
		var key := "%s|%d|%d|%d|%d" % [String(entry["road"]), roundi(float(p0[0]) * 2.0), roundi(float(p0[2]) * 2.0), roundi(float(p1[0]) * 2.0), roundi(float(p1[2]) * 2.0)]
		var here: int = int(index_of.get(key, -1))
		if here < 0:
			print("INFO path lane %d (%s) is not in the game graph (key %s)" % [k, ids[k], key])
			var shown := 0
			for other: String in index_of.keys():
				if other.begins_with(String(entry["road"]) + "|") and shown < 4:
					print("INFO   the game has %s" % other)
					shown += 1
			return
		if previous >= 0 and not lanes[previous].next_lanes.has(here):
			print("INFO path link %d -> %d is missing in the game: %s -> %s" % [k - 1, k, ids[k - 1], ids[k]])
			return
		previous = here
	print("INFO the whole path of %d lanes exists in the game graph" % ids.size())

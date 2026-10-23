extends Node
## Probe (not a test): the gap histogram of the lane links of the game's lane graph.
##
##   python tools/gd.py test res://world/tests/probe_lane_links.gd
##
## An edge of the graph joins the end of one lane to the start of another. A declared link of lanes.json has a gap under half a
## metre (the connector lanes carry the turns); the links LaneLinks derives from positions can join ends and starts that are 5 to
## 60 m apart, and the racing line then jumps.


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
	var bands := [0.5, 3.0, 10.0, 30.0, 60.0, INF]
	var count: Array[int] = [0, 0, 0, 0, 0, 0]
	var total := 0
	var worst := ""
	var worst_gap := 0.0
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var end_point := lane.curve.get_point_position(lane.curve.get_point_count() - 1)
		for n in lane.next_lanes:
			var next := lanes[n]
			if next.curve == null:
				continue
			var gap := end_point.distance_to(next.curve.get_point_position(0))
			total += 1
			for b in bands.size():
				if gap <= float(bands[b]):
					count[b] += 1
					break
			if gap > worst_gap:
				worst_gap = gap
				worst = "%s -> %s" % [lane.road_id, next.road_id]
	print("INFO lanes %d, links %d" % [lanes.size(), total])
	for b in bands.size():
		print("INFO links with a gap up to %s m: %d" % [str(bands[b]), count[b]])
	print("INFO the widest gap is %.0f m (%s)" % [worst_gap, worst])
	print("PROBE DONE")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

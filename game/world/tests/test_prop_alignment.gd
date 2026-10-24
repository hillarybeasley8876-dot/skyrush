extends Node
## The long boxes of the street (bus shelters of 8 m, noise walls of 30 m) lie along their road and stay out of the lanes.
##
## The roads unit gives the heading of the road for every prop, and a heading makes the -Z of a model point along the road, so the
## shelters and the walls (whose length is the X of the model) stood across it; the heading itself is 180 degrees minus the real one
## on every diagonal road (furniture.py: atan2 of the east and of MINUS the north). Now that the props are solid (the shapes were
## freed with their builder, test_prop_collision_orientation.gd) a shelter across a road is a wall in the traffic: 426 of 541
## shelters and all 32 noise walls reached into a lane and the traffic stood against them. The furniture builder turns the box with the
## lanes next to it, moves it away from the road when its ends reach into a lane, and drops it when that is not enough.
## Run: python tools/gd.py test res://world/tests/test_prop_alignment.gd -- --timeout=290

const MAIN := "res://main.tscn"
const LaneIndex := preload("res://world/api/lane_index.gd")
const PropCollision := preload("res://world/build/prop_collision.gd")

## The least distance between the footprint of a box and the centre line of a lane (m).
const CLEARANCE := 1.2
const LEVEL := 2.5
const STEP := 1.0
## The share of the shelters and walls that lie along their lane (the angle to it under 20 degrees).
const MIN_PARALLEL := 0.9
## A city that lost most of its shelters is no answer.
const MIN_KEPT := 400

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	var lanes := Game.world.get_lane_paths()
	var index := LaneIndex.new()
	index.build(lanes)
	var entries: Array = Game.world.get("_builder").get("_furniture_entries")
	var count := {"bus_stop": 0, "noise_wall": 0}
	var parallel := {"bus_stop": 0, "noise_wall": 0}
	var reaching: Array[String] = []
	for entry: Dictionary in entries:
		var type := String(entry.get("type", ""))
		if not count.has(type):
			continue
		count[type] += 1
		var xform: Transform3D = entry["transform"]
		var along := Vector2(xform.basis.x.x, xform.basis.x.z).normalized()
		var size: Vector3 = (PropCollision.SHAPES[type]["size"] as Vector3) * (entry.get("scale_vector", Vector3.ONE) as Vector3)
		# the angle to the nearest lane of the road of the prop
		var best := INF
		var angle := 90.0
		for candidate in index.candidates(xform.origin, 20.0):
			var lane := lanes[candidate]
			if lane.curve == null or String(lane.road_id) != String(entry.get("road", "")):
				continue
			var near := lane.curve.get_closest_point(xform.origin)
			if absf(near.y - xform.origin.y) > LEVEL:
				continue
			var d := Vector2(near.x - xform.origin.x, near.z - xform.origin.z).length()
			if d < best:
				best = d
				var at := lane.curve.get_closest_offset(xform.origin)
				var tangent := lane.curve.sample_baked(minf(at + 1.0, lane.curve.get_baked_length()), true) \
						- lane.curve.sample_baked(maxf(at - 1.0, 0.0), true)
				angle = rad_to_deg(acos(clampf(absf(along.dot(Vector2(tangent.x, tangent.z).normalized())), 0.0, 1.0)))
		if angle < 20.0:
			parallel[type] += 1
		# the perimeter of the footprint against all the lanes
		var turn := Basis(Vector3.UP, PropCollision.yaw_of(xform))
		var reach := false
		for i in int(ceil(size.x / STEP)) + 1:
			var x: float = -size.x * 0.5 + size.x * float(i) / ceil(size.x / STEP)
			for z: float in [-size.z * 0.5, size.z * 0.5]:
				var point := xform.origin + turn * Vector3(x, 0.0, z)
				for candidate in index.candidates(point, CLEARANCE + 6.0):
					var lane := lanes[candidate]
					if lane.curve == null:
						continue
					var closest := lane.curve.get_closest_point(point)
					if absf(closest.y - point.y) <= LEVEL and Vector2(closest.x - point.x, closest.z - point.z).length() < CLEARANCE:
						reach = true
		if reach:
			reaching.append("%s at (%.0f %.0f)" % [type, xform.origin.x, xform.origin.z])
	_check(count["bus_stop"] >= MIN_KEPT, "the city keeps its bus shelters", "(%d)" % count["bus_stop"])
	# 20 walls are declared (the 33 entries of the data had 13 copies of the same wall at the end of the Yan'an Elevated), 6 of them stand
	# where the viaduct comes down to the ground among the ramps and the streets and have no room for 30 m of box
	_check(count["noise_wall"] >= 12, "and its noise walls", "(%d)" % count["noise_wall"])
	for type in count:
		var share := float(parallel[type]) / maxf(float(count[type]), 1.0)
		_check(share >= MIN_PARALLEL, "%s: the long axis lies along the road (angle under 20 degrees)" % type,
			"(%d of %d, %.0f %%)" % [parallel[type], count[type], share * 100.0])
	_check(reaching.size() <= 5, "no more than 5 long boxes reach into a lane (closer than %.1f m to a centre line)" % CLEARANCE,
		"(%d: %s)" % [reaching.size(), ", ".join(reaching.slice(0, 4))])
	get_tree().quit(1 if _failures > 0 else 0)

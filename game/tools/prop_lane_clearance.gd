extends Node
## Which solid street props stand in a lane? The props are boxes now (bus stops of 8 m, noise walls of 30 m, planters, bike racks, metro
## entrances): the filter that places them looks at the ORIGIN of a prop only, so a long box whose origin is on the kerb can reach into a
## lane. The probe samples the footprint of every box prop (the perimeter every metre) and reports the props that come closer than
## CLEARANCE metres to the centre line of a lane of their own level (a car is 1.9 m wide: a lane is blocked when something stands
## within 0.95 m of its centre line, plus a margin).
##
##   python tools/gd.py test res://tools/prop_lane_clearance.gd -- --timeout=600 --stub=audio,menu,hud,traffic,police,rivals
##
## Options: clearance=m (1.3)

const MAIN := "res://main.tscn"
const LaneIndex := preload("res://world/api/lane_index.gd")
const PropCollision := preload("res://world/build/prop_collision.gd")

const LEVEL := 2.5
const STEP := 1.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var clearance := float(Game.option("clearance", "1.3"))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(2.0).timeout
	var lanes := Game.world.get_lane_paths()
	var index := LaneIndex.new()
	index.build(lanes)
	var entries: Array = Game.world.get("_builder").get("_furniture_entries")
	var checked := {}
	var bad := {}
	var examples: Dictionary = {}
	var angles: Dictionary = {}
	for entry: Dictionary in entries:
		var type := String(entry.get("type", ""))
		var spec: Dictionary = PropCollision.SHAPES.get(type, {})
		if not spec.has("size"):
			continue
		checked[type] = int(checked.get(type, 0)) + 1
		var xform: Transform3D = entry["transform"]
		var stretch: Vector3 = entry.get("scale_vector", Vector3.ONE)
		var size: Vector3 = (spec["size"] as Vector3) * stretch
		var yaw := PropCollision.yaw_of(xform)
		# the angle between the long axis of the prop and the lane next to it (0 = parallel, 90 = across)
		var nearest := -1
		var nearest_d := INF
		for candidate in index.candidates(xform.origin, 20.0):
			var lane_c := lanes[candidate]
			if lane_c.curve == null or String(lane_c.road_id) != String(entry.get("road", "")):
				continue
			var near := lane_c.curve.get_closest_point(xform.origin)
			if absf(near.y - xform.origin.y) > LEVEL:
				continue
			var dd := Vector2(near.x - xform.origin.x, near.z - xform.origin.z).length()
			if dd < nearest_d:
				nearest_d = dd
				nearest = candidate
		if nearest >= 0:
			var curve := lanes[nearest].curve
			var off := curve.get_closest_offset(xform.origin)
			var tangent := curve.sample_baked(minf(off + 1.0, curve.get_baked_length()), true) - curve.sample_baked(maxf(off - 1.0, 0.0), true)
			var along := Vector2(xform.basis.x.x, xform.basis.x.z).normalized()
			var lane_dir := Vector2(tangent.x, tangent.z).normalized()
			var angle := rad_to_deg(acos(clampf(absf(along.dot(lane_dir)), 0.0, 1.0)))
			var bucket := "parallel (<20)" if angle < 20.0 else ("across (>70)" if angle > 70.0 else "diagonal")
			var key := "%s %s" % [type, bucket]
			angles[key] = int(angles.get(key, 0)) + 1
			if type == "bus_stop" and xform.origin.distance_to(Vector3(-596.0, 0.0, -389.0)) < 12.0:
				print("CLEAR near the bus stop of the screenshot: at (%.1f %.1f %.1f) yaw %.1f deg, long axis %s, lane tangent %s, angle %.0f, lane road %s" % [
					xform.origin.x, xform.origin.y, xform.origin.z, rad_to_deg(yaw), str(along), str(lane_dir), angle, str(lanes[nearest].road_id)])
			if type == "bus_stop" and bucket == "diagonal" and int(angles.get("shown", 0)) < 6:
				angles["shown"] = int(angles.get("shown", 0)) + 1
				var data_heading := -xform.basis.z
				print("CLEAR example diagonal: at (%.1f %.1f %.1f), road %s, axis %s, heading %s, lane tangent %s, angle %.0f, dist to lane %.1f" % [
					xform.origin.x, xform.origin.y, xform.origin.z, str(entry.get("road", "")), str(along), str(Vector2(data_heading.x, data_heading.z)),
					str(lane_dir), angle, nearest_d])
			var bin := "%s angle %02d" % [type, int(angle / 10.0) * 10]
			angles[bin] = int(angles.get(bin, 0)) + 1
		var turn := Basis(Vector3.UP, yaw)
		var worst := INF
		var worst_at := Vector3.ZERO
		# the perimeter of the footprint, every STEP metres
		var half := Vector2(size.x, size.z) * 0.5
		var samples: Array[Vector2] = []
		var nx := int(ceil(size.x / STEP))
		var nz := int(ceil(size.z / STEP))
		for i in nx + 1:
			var x := -half.x + size.x * float(i) / float(nx)
			samples.append(Vector2(x, -half.y))
			samples.append(Vector2(x, half.y))
		for j in nz + 1:
			var z := -half.y + size.z * float(j) / float(maxi(nz, 1))
			samples.append(Vector2(-half.x, z))
			samples.append(Vector2(half.x, z))
		for sample in samples:
			var point := xform.origin + turn * Vector3(sample.x, 0.0, sample.y)
			for candidate in index.candidates(point, clearance + 6.0):
				var lane := lanes[candidate]
				if lane.curve == null:
					continue
				var closest := lane.curve.get_closest_point(point)
				if absf(closest.y - point.y) > LEVEL:
					continue
				var d := Vector2(closest.x - point.x, closest.z - point.z).length()
				if d < worst:
					worst = d
					worst_at = point
		if worst < clearance:
			bad[type] = int(bad.get(type, 0)) + 1
			if not examples.has(type) or worst < float(examples[type]["d"]):
				examples[type] = {"d": worst, "at": xform.origin, "yaw": rad_to_deg(yaw), "edge": worst_at}
	for type in checked:
		print("CLEAR %-20s %5d props, %4d reach into a lane (closer than %.1f m to a lane centre line)%s" % [type, checked[type],
			int(bad.get(type, 0)), clearance,
			"; worst %.2f m at (%.0f %.1f %.0f) yaw %.0f" % [examples[type]["d"], examples[type]["at"].x, examples[type]["at"].y,
				examples[type]["at"].z, examples[type]["yaw"]] if examples.has(type) else ""])
	for key in angles:
		print("CLEAR axis %-34s %d" % [key, angles[key]])
	get_tree().quit(0)

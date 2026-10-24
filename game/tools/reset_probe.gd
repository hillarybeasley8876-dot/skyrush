extends Node
## One reset of tools: the respawn of a car at `--at=x,y,z` facing `--way=x,z`, and the lanes around the result.
##   python tools/gd.py test res://tools/reset_probe.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police --at=879,0,1751 --way=1,0

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var at_parts := String(Game.option("at", "0,0,0")).split(",")
	var way_parts := String(Game.option("way", "1,0")).split(",")
	var at := Vector3(float(at_parts[0]), float(at_parts[1]), float(at_parts[2]))
	var lanes: Array = Game.world.get_lane_paths()
	var placer: Object = Game.world.get("_placer")
	# the lane the test started from: the street lane whose middle is at `at`
	var start_lane: LanePath = null
	for lane: LanePath in lanes:
		if lane.curve == null or lane.curve.get_baked_length() < 30.0:
			continue
		var mid := lane.curve.sample_baked(lane.curve.get_baked_length() * 0.5, true)
		if Vector2(mid.x - at.x, mid.z - at.z).length() < 1.0:
			start_lane = lane
			at = mid
			break
	var way := Vector3(float(way_parts[0]), 0.0, float(way_parts[1]))
	if start_lane != null:
		var length := start_lane.curve.get_baked_length()
		var a := start_lane.curve.sample_baked(length * 0.5 - 2.0, true)
		var b := start_lane.curve.sample_baked(length * 0.5 + 2.0, true)
		var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		way = Vector3(-along.z, 0.0, along.x)
		print("RESET start lane %s (%.0f m, connector %s) at %s along %s; the car faces %s" % [start_lane.road_id, length,
			str(start_lane.get_meta(&"connector", false)), str(at.snapped(Vector3.ONE * 0.1)), str(along.snapped(Vector3.ONE * 0.01)),
			str(way.snapped(Vector3.ONE * 0.01))])
	var found: Dictionary = placer.call("respawn_lane", at, way)
	if not found.is_empty():
		var lane: LanePath = found["lane"]
		print("RESET respawn_lane: %s offset %.1f of %.1f, score %.2f, connector %s" % [lane.road_id, float(found["offset"]),
			lane.curve.get_baked_length(), float(found.get("distance", -1.0)), str(lane.get_meta(&"connector", false))])
	var xform: Transform3D = Game.world.respawn_transform(at, way)
	print("RESET result at %s facing %s" % [str(xform.origin.snapped(Vector3.ONE * 0.01)), str((-xform.basis.z).snapped(Vector3.ONE * 0.01))])
	var index: Object = placer.get("index")
	for candidate: int in index.call("candidates", xform.origin, 8.0):
		var lane := lanes[candidate] as LanePath
		var offset := lane.curve.get_closest_offset(xform.origin)
		var p := lane.curve.sample_baked(offset, true)
		var d := Vector2(p.x - xform.origin.x, p.z - xform.origin.z).length()
		if d > 6.0:
			continue
		var length := lane.curve.get_baked_length()
		var a := lane.curve.sample_baked(clampf(offset - 2.0, 0.0, length), true)
		var b := lane.curve.sample_baked(clampf(offset + 2.0, 0.0, length), true)
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		print("RESET   lane %s connector %s: %.2f m away at offset %.1f of %.1f (y %.2f), direction %s, %.0f deg from the car" % [
			lane.road_id, str(lane.get_meta(&"connector", false)), d, offset, length, p.y, str(dir.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(dir.angle_to(-xform.basis.z))])
	# what the road height ray of the placer meets under the result
	var space := get_viewport().get_world_3d().direct_space_state
	var from := Vector3(xform.origin.x, xform.origin.y + 3.0, xform.origin.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, 1)
	var hits: Array[String] = []
	for i in 4:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		hits.append("%s at y %.2f" % [(hit["collider"] as Node).get_path(), (hit["position"] as Vector3).y])
		query.exclude = query.exclude + [hit["rid"]]
	print("RESET surfaces under the result: %s" % "; ".join(hits))
	get_tree().quit(0)

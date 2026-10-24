extends Node
## What stops a car in the ramps of the Yan'an tunnel: a box of the size of the car (1.9 x 0.9 x 4.6 m, its floor 0.35 m over the
## road) is swept along every lane through its ramp, 1 m at a time; the first thing it meets on every metre is written down with
## its collider, its point, its normal and its height over the lane. A diagnostic tool, not a test.
##   python tools/gd.py test res://tools/ramp_sweep_probe.gd -- --timeout=300 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
const BOX := Vector3(1.9, 0.9, 4.6)
const FLOOR := 0.35


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = BOX
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4
	query.collide_with_areas = false
	var k := 0
	for lane: LanePath in Game.world.get_lane_paths():
		if String(lane.road_id) != "yanan_tunnel" or bool(lane.get_meta(&"connector", false)) or lane.curve == null \
				or lane.curve.get_baked_length() < 1000.0:
			continue
		var length := lane.curve.get_baked_length()
		var d := 0.0
		var last := ""
		while d < length - 3.0:
			var p := lane.curve.sample_baked(d, true)
			var q := lane.curve.sample_baked(d + 2.0, true)
			d += 1.0
			if p.y > 0.05 or p.y < -6.5:
				continue
			var up := Vector3.UP
			var xform := Transform3D(Basis.IDENTITY, p + up * (FLOOR + BOX.y * 0.5)).looking_at(
				Vector3(q.x, p.y + FLOOR + BOX.y * 0.5, q.z), Vector3.UP)
			query.transform = xform
			var hits := space.get_rest_info(query)
			if hits.is_empty():
				continue
			var collider := instance_from_id(int(hits["collider_id"])) as Node
			var point: Vector3 = hits["point"]
			var label := "%s %.2f m over the lane" % [collider.name if collider != null else "?", point.y - p.y]
			if label == last:
				continue
			last = label
			print("SWEEP lane %d at %.0f m (%.0f, %.2f, %.0f): %s at %s normal %s" % [k, d, p.x, p.y, p.z, label,
				str(point.snapped(Vector3.ONE * 0.01)), str((hits["normal"] as Vector3).snapped(Vector3.ONE * 0.01))])
		k += 1
	get_tree().quit(0)

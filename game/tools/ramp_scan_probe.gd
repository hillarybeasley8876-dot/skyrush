extends Node
## What stands in the ramps of the Yan'an tunnel: along every lane, in its ramp (0 to 6 m under the ground), a ray 2 m forward at
## 0.5 m and 1.2 m over the lane; every hit with its collider, its point and its normal. A diagnostic tool, not a test.
##   python tools/gd.py test res://tools/ramp_scan_probe.gd -- --timeout=300 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state
	var k := 0
	for lane: LanePath in Game.world.get_lane_paths():
		if String(lane.road_id) != "yanan_tunnel" or bool(lane.get_meta(&"connector", false)) or lane.curve == null \
				or lane.curve.get_baked_length() < 1000.0:
			continue
		var length := lane.curve.get_baked_length()
		var d := 0.0
		var hits := 0
		while d < length - 2.0 and hits < 12:
			var p := lane.curve.sample_baked(d, true)
			var q := lane.curve.sample_baked(d + 2.0, true)
			d += 1.0
			if p.y > -0.02 or p.y < -6.5:
				continue
			for h: float in [0.5, 1.2]:
				var from := p + Vector3.UP * h
				var to := q + Vector3.UP * h
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 4))
				if hit.is_empty():
					continue
				hits += 1
				print("SCAN lane %d at %.0f m (lane y %.2f), %.1f m up: %s at %s normal %s" % [k, d, p.y, h,
					(hit["collider"] as Node).name, str((hit["position"] as Vector3).snapped(Vector3.ONE * 0.01)),
					str((hit["normal"] as Vector3).snapped(Vector3.ONE * 0.01))])
		k += 1
	get_tree().quit(0)

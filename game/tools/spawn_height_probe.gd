extends Node
## The spawn height probe: every lane of the city is sampled, and the spawn placer of the world (world/api/spawn_placer.gd) is
## asked for the height of a car there. The placer casts a ray down and takes the first world surface it meets: when the ray
## started 4 m above the lane, a lane under anything (a toll booth roof, the Bund promenade, a deck, the ground over a tunnel,
## the Waibaidu bridge deck) put the car on top of it instead of on the road (334 of 68,000 points). The probe writes down every
## sample where the spawn is more than RISE metres above the lane, and what the ray met. A diagnostic tool, not a test.
##
##   python tools/gd.py test res://tools/spawn_height_probe.gd -- --timeout=1200 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
const SpawnPlacer := preload("res://world/api/spawn_placer.gd")
## The step between two samples of a lane (m).
const STEP := 10.0
## A spawn this far above its lane is on top of something.
const RISE := 0.8


func _ready() -> void:
	_run.call_deferred()


func _name_of(body: Object) -> String:
	var node := body as Node
	if node == null:
		return "?"
	var chain := String(node.name)
	var parent := node.get_parent()
	var depth := 0
	while parent != null and depth < 2 and parent != get_tree().root:
		chain = String(parent.name) + "/" + chain
		parent = parent.get_parent()
		depth += 1
	return chain


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(2.0).timeout
	var lanes: Array = Game.world.get_lane_paths()
	var space := get_viewport().get_world_3d().direct_space_state
	var placer := SpawnPlacer.new()
	var gaps := {}
	var samples := 0
	var high := 0
	var by_collider := {}
	var worst: Array = []
	for lane: LanePath in lanes:
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var d := 0.0
		while d < length:
			var point := lane.curve.sample_baked(d, true)
			d += STEP
			samples += 1
			# the height the placer gives a car there, less the clearance of the car
			var rise := placer.surface_y(Game.world, point) - SpawnPlacer.LANE_LIFT - point.y
			var bucket := clampi(int(floor(rise * 10.0)), -12, 12)
			gaps[bucket] = int(gaps.get(bucket, 0)) + 1
			if rise <= RISE:
				continue
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * SpawnPlacer.SURFACE_ABOVE,
					point - Vector3.UP * SpawnPlacer.SURFACE_REACH, SpawnPlacer.SURFACE_MASK)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			high += 1
			var name := _name_of(hit["collider"])
			var key := name.get_slice("/", 0) + "/" + name.get_slice("/", 1)
			by_collider[key] = int(by_collider.get(key, 0)) + 1
			worst.append([rise, point, name, String(lane.get_meta(&"road", "")) if lane.has_meta(&"road") else ""])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("SPAWN HEIGHT %d samples of %d lanes, %d spawns more than %.1f m above their lane" % [samples, lanes.size(), high, RISE])
	print("SPAWN HEIGHT by collider: %s" % str(by_collider))
	var keys := gaps.keys()
	keys.sort()
	var histogram := ""
	for k in keys:
		histogram += " [%.1f,%.1f):%d" % [float(k) / 10.0, float(k + 1) / 10.0, gaps[k]]
	print("SPAWN HEIGHT surface minus lane, m:%s" % histogram)
	# the worst samples of every collider (the bridge alone would fill the list)
	var shown := {}
	for w in worst:
		var key := String(w[2]).get_slice("/", 0) + "/" + String(w[2]).get_slice("/", 1)
		if int(shown.get(key, 0)) >= 4:
			continue
		shown[key] = int(shown.get(key, 0)) + 1
		var p: Vector3 = w[1]
		print("  rise %.2f m at (%.1f, %.2f, %.1f) on %s  road %s" % [w[0], p.x, p.y, p.z, w[2], w[3]])
	get_tree().quit(0)

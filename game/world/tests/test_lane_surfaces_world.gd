extends Node
## LEAD ACCEPTANCE TEST: is there solid ground under every lane the game's AI drives, in the FULL world?
## (test_drive_collision.gd loads only the road tiles; the real game also has the building tiles' ground slabs.)
##
## For every lane of the world (get_lane_paths(), connectors included), every 2 m: a ray from 0.4 m above to 4 m
## below, world layer only, must hit a collider within TOLERANCE of the lane height. Counts are split into
## ground / elevated and normal / connector lanes. SKYRUSH_LANESURF_CSV=<path> dumps every bad sample.
##
## Run: python tools/gd.py test res://world/tests/test_lane_surfaces_world.gd
## Exit code: 0 when the bad share is within MAX_BAD_PERCENT, else 1.

const CityData := preload("res://world/loader/city_data.gd")

const STEP := 2.0
const TOLERANCE := 0.40
const ELEVATED_Y := 5.0
## Allowed share of bad samples (the lead tightens it as the roads improve).
const MAX_BAD_PERCENT := 0.5

var _rows: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	var path := repo.path_join("data/city/city.json")
	if repo == "" or not FileAccess.file_exists(path):
		print("SKIP no city file")
		get_tree().quit(0)
		return
	CityData.forced_city_path = path
	var world := (load("res://world/world.tscn") as PackedScene).instantiate() as WorldBase
	get_tree().root.add_child(world)
	for i in 600:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			break
	for i in 5:
		await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var counts := {"ground": [0, 0], "elevated": [0, 0], "ground_connector": [0, 0], "elevated_connector": [0, 0]}
	var per_road: Dictionary = {}
	var lanes := world.get_lane_paths()
	print("INFO the world has %d lane paths" % lanes.size())
	for lane in lanes:
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var kind := "elevated" if lane.elevated else "ground"
		if lane.get("is_connector") == true or String(lane.road_id).begins_with("j_"):
			kind += "_connector"
		var d := 0.0
		while d <= length:
			var p := lane.curve.sample_baked(d, true)
			if p.y > ELEVATED_Y and not kind.begins_with("elevated"):
				kind = "elevated" + kind.trim_prefix("ground")
			var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p - Vector3.UP * 4.0, 1)
			var hit := space.intersect_ray(query)
			var ok := false
			var h := NAN
			if not hit.is_empty():
				h = (hit["position"] as Vector3).y
				ok = absf(h - p.y) <= TOLERANCE
			var bucket: Array = counts.get(kind, [0, 0])
			bucket[0] = int(bucket[0]) + 1
			if not ok:
				bucket[1] = int(bucket[1]) + 1
				per_road[String(lane.road_id)] = int(per_road.get(String(lane.road_id), 0)) + 1
				_rows.append("%s,%s,%.2f,%.2f,%.2f,%s" % [lane.road_id, kind, p.x, p.y, p.z, "nothing" if is_nan(h) else "%.2f" % h])
			counts[kind] = bucket
			d += STEP
	var total := 0
	var bad := 0
	for kind: String in counts:
		var b: Array = counts[kind]
		total += int(b[0])
		bad += int(b[1])
		print("LANESURF %-20s samples %7d bad %6d (%.2f %%)" % [kind, b[0], b[1], 100.0 * float(b[1]) / maxf(float(b[0]), 1.0)])
	var roads: Array = per_road.keys()
	roads.sort_custom(func(a: Variant, b: Variant) -> bool: return int(per_road[a]) > int(per_road[b]))
	print("LANESURF worst roads: %s" % ", ".join(PackedStringArray(roads.slice(0, 12).map(
		func(r: Variant) -> String: return "%s:%d" % [r, per_road[r]]))))
	var csv := OS.get_environment("SKYRUSH_LANESURF_CSV")
	if csv != "":
		var out := FileAccess.open(csv, FileAccess.WRITE)
		if out != null:
			out.store_line("road,kind,x,y,z,hit")
			for row in _rows:
				out.store_line(row)
			out.close()
	var percent := 100.0 * float(bad) / maxf(float(total), 1.0)
	var ok_all := percent <= MAX_BAD_PERCENT
	print("%s lanes have solid ground: %d of %d samples bad (%.3f %%, allowed %.2f %%)" % ["PASS" if ok_all else "FAIL", bad, total, percent, MAX_BAD_PERCENT])
	get_tree().quit(0 if ok_all else 1)

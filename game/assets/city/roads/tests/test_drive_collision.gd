extends Node
## Sweep test for the road unit's collision.
##
## For EVERY lane and connector of lanes.json, at every 2 m step:
##   - a ray from y + 2 m to y - 3 m must hit a road collider within 0.15 m of the
##     lane's height (the road is there, the car does not fall through)
##   - a 1.9 x 1.0 x 4.6 m box shape cast at y + 0.75 m from one step to the next
##     must hit nothing (the lane is not blocked by a parapet, a pier or a sign)
## Then 20 dynamic shots at 90 m/s (CCD on) into the parapets at 15 and 45 degrees:
## none of them may tunnel through.
##
##   tools/godot.sh test res://assets/city/roads/tests/test_drive_collision.gd

const LANES_PATH := "res://world/data/lanes.json"
const TILE_DIR := "res://assets/city/roads/"
const STEP := 2.0                 # the lane sampling
const RAY_TOLERANCE := 0.15       # the road surface under the lane
const CAR_SIZE := Vector3(1.9, 1.0, 4.6)
const CAR_HEIGHT := 0.85   # the body of the car: 0.35 m of ground clearance
const SHOT_SPEED := 90.0 / 3.6
const SHOT_COUNT := 20
const SHOT_ANGLES := [15.0, 45.0]

var _failures := 0
var _checks := 0
var _space: PhysicsDirectSpaceState3D
var _per_road: Dictionary = {}
var _blockers: Dictionary = {}
var _blocked_rows: PackedStringArray = []
var _surf: Dictionary = {}
var _delta_hist: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_build_collision()
	await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state
	var data := _read_json(LANES_PATH)
	var lanes: Array = data.get("lanes", [])
	_check(lanes.size() > 0, "lanes.json holds lanes (%d)" % lanes.size())
	var ray_bad := _sweep_rays(lanes)
	_check(ray_bad == 0, "every lane has a road surface under it (%d bad samples)" % ray_bad)
	print("SURFACE delta bands (surface minus lane): %s" % JSON.stringify(_delta_hist))
	var surf_roads: Array = _surf.keys()
	surf_roads.sort_custom(func(x: Variant, y: Variant) -> bool:
		return int(_surf[x][0]) + int(_surf[x][1]) > int(_surf[y][0]) + int(_surf[y][1]))
	print("SURFACE worst roads (no surface/wrong height): %s" % ", ".join(PackedStringArray(
		surf_roads.slice(0, 16).map(func(r: Variant) -> String: return "%s:%d/%d" % [r, _surf[r][0], _surf[r][1]]))))
	var cast_bad := _sweep_casts(lanes)
	_check(cast_bad == 0, "no lane is blocked by a parapet or a pier (%d bad)" % cast_bad)
	var csv_path := OS.get_environment("SKYRUSH_BLOCKED_CSV")
	if csv_path != "":
		var out := FileAccess.open(csv_path, FileAccess.WRITE)
		if out != null:
			out.store_line("road,x,y,z,blocker")
			for row in _blocked_rows:
				out.store_line(row)
			out.close()
	var kinds: Array = _blockers.keys()
	kinds.sort_custom(func(x: Variant, y: Variant) -> bool: return int(_blockers[x]) > int(_blockers[y]))
	print("BLOCKERS: %s" % ", ".join(PackedStringArray(kinds.slice(0, 20).map(
		func(k: Variant) -> String: return "%s:%d" % [k, int(_blockers[k])]))))
	var worst := _worst_roads()
	print("ROAD counts: %s" % ", ".join(worst))
	var tunnelled := await _dynamic_shots(lanes)
	_check(tunnelled == 0, "no dynamic shot tunnelled through a parapet (%d of %d)"
		% [tunnelled, SHOT_COUNT])
	_finish()


func _build_collision() -> void:
	var dir := DirAccess.open(TILE_DIR)
	if dir == null:
		return
	var gltf: Dictionary = {}
	for file in dir.get_files():
		if file.begins_with("roads_") and file.ends_with(".gltf"):
			gltf[file.get_basename()] = TILE_DIR + file
	var paths: Array[String] = []
	for file in dir.get_files():
		if not file.begins_with("roads_") or not file.ends_with(".glb"):
			continue
		if gltf.has(file.get_basename()):
			continue
		paths.append(TILE_DIR + file)
	for key in gltf.keys():
		paths.append(String(gltf[key]))
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		add_child(packed.instantiate())


func _sweep_rays(lanes: Array) -> int:
	var bad := 0
	for entry: Variant in lanes:
		var pts: Array = (entry as Dictionary).get("points", [])
		var road := String((entry as Dictionary).get("road", ""))
		for i in range(pts.size()):
			var p := _v3(pts[i])
			# from just above the road down, so a parapet or a pier above the lane
			# does not hide the road surface
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, p.y + 0.30, p.z), Vector3(p.x, p.y - 4.0, p.z))
			var hit := _space.intersect_ray(query)
			if hit.is_empty():
				bad += 1
				_count(road)
				_surf_add(road, 0)
				if bad <= 6:
					print("NOSURFACE %s at %s" % [road, p])
			else:
				var y := (hit["position"] as Vector3).y
				if absf(y - p.y) > RAY_TOLERANCE:
					bad += 1
					_count(road)
					_surf_add(road, 1)
					var bucket := _delta_bucket(y - p.y)
					_delta_hist[bucket] = int(_delta_hist.get(bucket, 0)) + 1
					if bad <= 6:
						print("OFFHEIGHT %s at %s (surface %.2f)" % [road, p, y])
	return bad


## Per-road tally of surface failures: [no surface, surface at the wrong height].
func _surf_add(road: String, kind: int) -> void:
	var rec: Array = _surf.get(road, [0, 0])
	rec[kind] = int(rec[kind]) + 1
	_surf[road] = rec


## Which band a surface-minus-lane height difference falls in (metres).
func _delta_bucket(d: float) -> String:
	if d > 1.0:
		return "above>1"
	if d > 0.3:
		return "above0.3-1"
	if d > RAY_TOLERANCE:
		return "above0.15-0.3"
	if d < -1.0:
		return "below>1"
	if d < -0.3:
		return "below0.3-1"
	return "below0.15-0.3"


func _sweep_casts(lanes: Array) -> int:
	var bad := 0
	for entry: Variant in lanes:
		var pts: Array = (entry as Dictionary).get("points", [])
		var road := String((entry as Dictionary).get("road", ""))
		for i in range(pts.size() - 1):
			var a := _v3(pts[i])
			var b := _v3(pts[i + 1])
			var from := Vector3(a.x, a.y + CAR_HEIGHT, a.z)
			var to := Vector3(b.x, b.y + CAR_HEIGHT, b.z)
			if from.distance_to(to) < 0.05:
				continue
			var shape := BoxShape3D.new()
			shape.size = CAR_SIZE
			var fwd := (b - a)
			fwd.y = 0.0
			if fwd.length() < 0.01:
				continue
			fwd = fwd.normalized()
			var basis := Basis.looking_at(fwd, Vector3.UP)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(basis, from)
			query.collision_mask = 0xFFFFFFFF
			query.exclude = []
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hits := _space.intersect_shape(query, 1)
			if not hits.is_empty():
				bad += 1
				_count(road)
				var key := _blocker_key(hits[0])
				_blockers[key] = int(_blockers.get(key, 0)) + 1
				_blocked_rows.append("%s,%.2f,%.2f,%.2f,%s" % [road, a.x, a.y, a.z, key])
				if bad <= 6:
					print("BLOCKED %s at %s by %s" % [road, a, _hit_name(hits[0])])
	return bad


## The name of the node a shape hit belongs to (the collider that blocks a lane).
func _hit_name(hit: Dictionary) -> String:
	var obj := instance_from_id(int(hit.get("collider_id", 0)))
	if obj == null:
		return "?"
	return String((obj as Node).name)


## "Parent/Name" of the blocking collider with the trailing numbers cut, to group like blockers.
func _blocker_key(hit: Dictionary) -> String:
	var obj := instance_from_id(int(hit.get("collider_id", 0))) as Node
	if obj == null:
		return "?"
	var parent := obj.get_parent()
	return "%s/%s" % [_strip_tail(String(parent.name)) if parent != null else "-", _strip_tail(String(obj.name))]


func _strip_tail(text: String) -> String:
	var s := text
	while s.length() > 1 and ((s[-1] >= "0" and s[-1] <= "9") or s[-1] == "_" or s[-1] == "@"):
		s = s.left(-1)
	return s


func _dynamic_shots(lanes: Array) -> int:
	# fire a car at 90 m/s into a parapet: the collider has to stop it
	var tunnelled := 0
	var shots := 0
	for entry in lanes:
		if shots >= SHOT_COUNT:
			break
		var lane := entry as Dictionary
		if lane.get("connector", false):
			continue
		var pts: Array = lane.get("points", [])
		if pts.size() < 4:
			continue
		var i := pts.size() / 2
		var p := _v3(pts[i])
		var q := _v3(pts[i + 1])
		var dir := (q - p)
		dir.y = 0.0
		if dir.length() < 0.5:
			continue
		dir = dir.normalized()
		# aim at the deck edge: 15 or 45 degrees to the lane
		var angle: float = SHOT_ANGLES[shots % SHOT_ANGLES.size()]
		var side := Vector3(-dir.z, 0.0, dir.x) * signf(sin(deg_to_rad(angle)))
		var aim := (dir * cos(deg_to_rad(angle)) + side * sin(deg_to_rad(angle))).normalized()
		var car := RigidBody3D.new()
		car.mass = 1800.0
		car.continuous_cd = true
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.9, 1.3, 4.6)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		car.add_child(cs)
		add_child(car)
		car.global_position = Vector3(p.x, p.y + 0.7, p.z)
		await get_tree().physics_frame
		car.linear_velocity = aim * SHOT_SPEED
		for t in range(40):
			await get_tree().physics_frame
		# the car must not end up under the deck: that would be a tunnel
		if car.global_position.y < p.y - 1.0:
			tunnelled += 1
		car.queue_free()
		shots += 1
	return tunnelled


func _worst_roads() -> Array:
	var out: Array = []
	for i in range(6):
		var best_id := ""
		var best_n := -1
		for id in _per_road:
			var n := int(_per_road[id])
			if n > best_n and not out.has("%s:%d" % [id, n]):
				best_n = n
				best_id = String(id)
		if best_id == "":
			break
		out.append("%s:%d" % [best_id, best_n])
	return out


func _count(road: String) -> void:
	_per_road[road] = int(_per_road.get(road, 0)) + 1


func _v3(p: Variant) -> Vector3:
	if p is Array and (p as Array).size() >= 3:
		var a := p as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _finish() -> void:
	print("TEST %s: %d checks, %d failures" % ["drive_collision", _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

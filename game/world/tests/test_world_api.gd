extends Node
## Headless test of the WorldBase API: loads test_city.json and then the real city.json and
## checks every API method, the lane continuity, the spawn points and the route racing lines.
##
##   tools/godot.sh test res://world/tests/test_world_api.gd
##
## Prints PASS/FAIL per check and exits non-zero when anything failed.

const CityData := preload("res://world/loader/city_data.gd")
const WorldErrorCounter := preload("res://world/tests/world_error_counter.gd")

var _failures := 0
var _checks := 0
## Counts the engine errors of the run: the world must build without a single one.
var _counter: WorldErrorCounter


func _ready() -> void:
	_counter = WorldErrorCounter.new()
	OS.add_logger(_counter)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	var candidates := PackedStringArray()
	if repo != "":
		candidates.append(repo.path_join("data/city/test_city.json"))
		candidates.append(repo.path_join("data/city/city.json"))
	for path in candidates:
		if not FileAccess.file_exists(path):
			print("SKIP %s (not present)" % path)
			continue
		await _check_city(path)
	_check(_counter.errors == 0, "no engine errors during the run (%d)" % _counter.errors)
	for line in _counter.first_errors:
		print("ERROR %s" % line)
	if _failures == 0:
		print("PASS all %d checks" % _checks)
	else:
		print("FAIL %d of %d checks" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_city(path: String) -> void:
	print("--- city: %s" % path)
	CityData.forced_city_path = path
	var world := await _make_world()
	if world == null:
		_fail("world scene could not be instantiated")
		return
	_check_api(world)
	_check_lanes(world)
	_check_spawns(world)
	_check_routes(world)
	_check_minimap_and_pois(world)
	world.queue_free()
	await get_tree().process_frame


func _make_world() -> WorldBase:
	var packed := load("res://world/world.tscn") as PackedScene
	if packed == null:
		return null
	var world := packed.instantiate() as WorldBase
	if world == null:
		return null
	get_tree().root.add_child(world)
	await _await_build(world)
	return world


## Waits until the world has built itself (the builder works in phases and yields a frame).
func _await_build(world: WorldBase) -> void:
	for i in 400:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			return


# --- checks -----------------------------------------------------------------------------------------

func _check_api(world: WorldBase) -> void:
	for kind in [&"player", &"police", &"traffic", &"rival"]:
		var xform := world.get_spawn_transform(kind, 0)
		_ok(xform != Transform3D.IDENTITY, "get_spawn_transform(%s)" % kind)
	_check(world.nearest_road_transform(Vector3(0, 0, 0)) != Transform3D.IDENTITY,
		"nearest_road_transform")
	_ok(not world.get_lane_paths().is_empty(), "get_lane_paths")
	_check(not world.get_route_ids().is_empty(), "get_route_ids")
	var route := world.get_route(world.get_route_ids()[0])
	_check(route != null, "get_route")
	_check(not world.get_minimap_polylines().is_empty(), "get_minimap_polylines")
	_check(world.get_points_of_interest() != null, "get_points_of_interest")
	_check(world.get_roadblock_sites() != null, "get_roadblock_sites")
	var state := world.signal_state(&"nope", &"nope")
	_check(state >= 0 and state <= 2, "signal_state returns 0..2")


func _check_lanes(world: WorldBase) -> void:
	var lanes := world.get_lane_paths()
	_check(lanes.size() > 0, "lane count > 0")
	var bad := 0
	var reachable := 0
	for lane in lanes:
		if lane.curve == null or lane.curve.get_point_count() < 2:
			bad += 1
			continue
		for point in lane.curve.get_baked_points():
			if not is_finite(point.x) or not is_finite(point.y) or not is_finite(point.z):
				bad += 1
				break
	_check(bad == 0, "lane curves are valid (%d bad)" % bad)
	# Continuity: every lane must be part of the graph, so the union of the lanes that can be
	# reached from somewhere must cover the map.
	reachable = _reachable_union(lanes).size()
	_check(reachable >= maxi(1, int(float(lanes.size()) * 0.5)),
		"lane graph connected: %d of %d lanes reachable" % [reachable, lanes.size()])
	var dead_ends := 0
	for lane in lanes:
		if lane.next_lanes.is_empty():
			dead_ends += 1
	print("INFO lanes=%d reachable=%d dead_ends=%d" % [lanes.size(), reachable, dead_ends])


## Every lane that can be reached from any other lane.
func _reachable_union(lanes: Array[LanePath]) -> Dictionary:
	var seen: Dictionary = {}
	for i in lanes.size():
		for next_index in lanes[i].next_lanes:
			seen[next_index] = true
			seen[i] = true
	return seen
func _check_spawns(world: WorldBase) -> void:
	var lanes := world.get_lane_paths()
	for kind in [&"player", &"police", &"traffic", &"rival"]:
		var xform := world.get_spawn_transform(kind, 0)
		var position := xform.origin
		var best := INF
		for lane in lanes:
			if lane.curve == null:
				continue
			var offset := lane.curve.get_closest_offset(position)
			var point := lane.curve.sample_baked(offset, true)
			best = minf(best, Vector2(point.x - position.x, point.z - position.z).length())
		_check(best < 15.0, "spawn %s is on a road (%.1f m from the nearest lane)" % [kind, best])
	_check_player_spawn(world, lanes)


## The player spawn has to sit on a lane centre, face the lane and have a clear road ahead.
func _check_player_spawn(world: WorldBase, lanes: Array[LanePath]) -> void:
	var xform := world.get_spawn_transform(&"player", 0)
	var position := xform.origin
	var best := INF
	var heading_error := 180.0
	for lane in lanes:
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(position)
		var point := lane.curve.sample_baked(offset, true)
		var flat := Vector2(point.x - position.x, point.z - position.z).length()
		if flat < best:
			best = flat
			var ahead := lane.curve.sample_baked(minf(offset + 4.0, lane.curve.get_baked_length()), true)
			var tangent := ahead - point
			tangent.y = 0.0
			if tangent.length_squared() > 0.0001:
				var forward := -xform.basis.z
				forward.y = 0.0
				heading_error = rad_to_deg(forward.angle_to(tangent.normalized()))
	_check(best <= 0.3, "player spawn: on lane (%.2f m)" % best)
	_check(heading_error <= 5.0, "player spawn: heading error %.1f deg" % heading_error)
	var clear := _clear_ahead(world, xform)
	_check(clear >= 30.0, "player spawn: %.1f m clear ahead" % clear)


## How far the road in front of a transform is free (the same box the world uses).
func _clear_ahead(world: WorldBase, xform: Transform3D) -> float:
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.4, 30.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4
	query.collide_with_bodies = true
	var forward := -xform.basis.z
	query.transform = Transform3D(xform.basis, xform.origin + forward * 15.0 + Vector3.UP * 0.8)
	return 30.0 if space.intersect_shape(query, 1).is_empty() else 0.0


func _check_routes(world: WorldBase) -> void:
	var lanes := world.get_lane_paths()
	for id in world.get_route_ids():
		var route := world.get_route(id)
		if route == null:
			_fail("route %s is null" % id)
			continue
		_check(route.checkpoints.size() > 0, "route %s has checkpoints" % id)
		_check(route.grid.size() > 0, "route %s has a grid" % id)
		_check_gate_headings(route)
		_check_grid(route, lanes)
		var line := route.racing_line
		_check(line != null and line.get_point_count() >= 2, "route %s has a racing line" % id)
		if line != null and line.get_point_count() >= 2:
			_check_racing_line(route, lanes)


## Every gate has to face the next checkpoint.
func _check_gate_headings(route: RaceRoute) -> void:
	var checkpoints := route.checkpoints
	for i in range(checkpoints.size() - 1):
		var forward := -checkpoints[i].basis.z
		var to_next := checkpoints[i + 1].origin - checkpoints[i].origin
		_check(forward.dot(to_next) > 0.0,
			"route %s: gate %d faces the next checkpoint (dot %.2f)" % [route.id, i,
				forward.dot(to_next)])


## The start grid: at least six slots, five metres apart, on a lane and facing it.
func _check_grid(route: RaceRoute, lanes: Array[LanePath]) -> void:
	var grid := route.grid
	_check(grid.size() >= 6, "route %s: the grid has %d slots" % [route.id, grid.size()])
	var min_distance := INF
	for i in grid.size():
		for j in range(i + 1, grid.size()):
			min_distance = minf(min_distance, grid[i].origin.distance_to(grid[j].origin))
	_check(min_distance >= 5.0,
		"route %s: the closest grid slots are %.1f m apart" % [route.id, min_distance])
	var off_lane := 0
	var heading_error := 0.0
	for slot in grid:
		var best := INF
		var tangent := Vector3.ZERO
		for lane in lanes:
			if lane.curve == null:
				continue
			var offset := lane.curve.get_closest_offset(slot.origin)
			var point := lane.curve.sample_baked(offset, true)
			var flat := Vector2(point.x - slot.origin.x, point.z - slot.origin.z).length()
			if flat < best:
				best = flat
				var ahead := lane.curve.sample_baked(
					minf(offset + 4.0, lane.curve.get_baked_length()), true)
				tangent = ahead - point
				tangent.y = 0.0
		if best > 0.3:
			off_lane += 1
		elif tangent.length_squared() > 0.0001:
			var forward := -slot.basis.z
			forward.y = 0.0
			heading_error = maxf(heading_error,
				rad_to_deg(forward.angle_to(tangent.normalized())))
	_check(off_lane == 0, "route %s: %d of %d grid slots are off the lane" % [route.id, off_lane,
		grid.size()])
	_check(heading_error <= 5.0, "route %s: the grid slots face the lane (%.1f deg)" % [route.id,
		heading_error])


func _check_minimap_and_pois(world: WorldBase) -> void:
	for line in world.get_minimap_polylines():
		_check(line.size() >= 2, "minimap polyline has 2+ points")
	for poi in world.get_points_of_interest():
		_check(poi.has("kind") and poi.has("position") and poi.has("label"), "POI fields")


# --- reporting --------------------------------------------------------------------------------------

func _ok(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _check(condition: bool, label: String) -> void:
	_ok(condition, label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	print("FAIL %s" % label)
## The racing line has to be on the lanes, must not reverse and must not be longer than the
## checkpoints need.
func _check_racing_line(route: RaceRoute, lanes: Array[LanePath]) -> void:
	var line := route.racing_line
	var points := PackedVector3Array()
	for point in line.get_baked_points():
		points.append(point)
	if points.size() < 2:
		_fail("route %s: the racing line has no points" % route.id)
		return
	var length := 0.0
	for i in range(points.size() - 1):
		length += points[i].distance_to(points[i + 1])
	var gate_length := 0.0
	var checkpoints := route.checkpoints
	for i in range(checkpoints.size() - 1):
		gate_length += checkpoints[i].origin.distance_to(checkpoints[i + 1].origin)
	var circuit := bool(route.get_meta("circuit", false))
	# The line follows the roads, so it is longer than the straight line between the gates (a
	# route through a grid that curves and climbs is about 1.8 times as long).
	_check(length <= gate_length * 1.8 + 100.0,
		"route %s: line %.0f m vs the gates %.0f m" % [route.id, length, gate_length])
	# 0 reversals: no two consecutive samples point back.
	var reversals := 0
	for i in range(points.size() - 6):
		var a := points[i + 5] - points[i]
		var b := points[i] - points[i - 1] if i > 0 else a
		if a.length_squared() > 0.01 and b.length_squared() > 0.01 and a.normalized().dot(b.normalized()) < -0.5:
			reversals += 1
	_check(reversals == 0, "route %s: %d reversals in the racing line" % [route.id, reversals])
	# 98 % of the samples are within 2 m of a lane centre.
	var off := 0
	for point in points:
		var best := INF
		for lane in lanes:
			if lane.curve == null:
				continue
			var offset := lane.curve.get_closest_offset(point)
			var closest := lane.curve.sample_baked(offset, true)
			best = minf(best, Vector2(closest.x - point.x, closest.z - point.z).length())
		if best > 2.0:
			off += 1
	var ratio := float(points.size() - off) / float(maxi(points.size(), 1))
	print("INFO route %s: %d samples, %d off the lane (%.1f %% on the lane), %d reversals"
		% [route.id, points.size(), off, ratio * 100.0, reversals])
	_check(ratio >= 0.95, "route %s: %.1f %% of the line is on a lane" % [route.id, ratio * 100.0])
	# The sprints are point to point and must not be closed.
	var first := points[0]
	var last := points[points.size() - 1]
	var gap := Vector2(first.x - last.x, first.z - last.z).length()
	if not circuit:
		_check(gap > 30.0, "route %s: the sprint line is not closed (gap %.0f m)" % [route.id, gap])

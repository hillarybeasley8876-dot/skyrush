extends Node
## Headless test: the sky lanes (飞行航道) carry obstacles — drones, neon billboards and crane
## arms — and only a car that flies is hit by one of them.
##
##   python tools/gd.py test res://world/tests/test_sky_obstacles.gd
##
## The world of the real city is built (as in test_route_layers.gd) and every SkyLane is checked:
##   1. the city has 5 sky lanes;
##   2. every lane carries obstacles (at least floor(length / 300) - 1 of them, and at least one);
##   3. every obstacle lies inside the 14 x 8 m tube of its lane;
##   4. the obstacles of a lane are 120 m apart, the first 150 m from the start, the last 100 m
##      from the end;
##   5. the longest lane carries the three kinds (drone, billboard, crane);
##   6. the same lane always gets the same obstacles (the seed is the name of the lane);
##   7. only a flying car is hit by an obstacle.
##
## The builder of the obstacles is loaded at run time (never preloaded), so that this test fails
## with FAIL lines — and not with a script error — when the builder does not exist yet.

const CityData := preload("res://world/loader/city_data.gd")
const OBSTACLES_PATH := "res://world/build/sky_obstacles.gd"
const GROUP := "sky_obstacle"
const KINDS := ["drone", "billboard", "crane"]
## The flight box of an obstacle: the tube is 14 m wide and 8 m high, the obstacles keep away
## from the walls, so there is always a line past one of them.
const LATERAL_LIMIT := 4.5
const HEIGHT_MIN := -1.5
const HEIGHT_MAX := 3.0
const TOLERANCE := 0.5

var _failures := 0
var _checks := 0


## A car that only counts the obstacle hits: the real one is in the vehicle unit.
class FakeFlyer extends VehicleBase:
	var hits := 0

	func flight_hit() -> bool:
		hits += 1
		return true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	var path := repo.path_join("data/city/city.json") if repo != "" else ""
	if path == "" or not FileAccess.file_exists(path):
		_fail("data/city/city.json is not present")
		_finish()
		return
	CityData.forced_city_path = path
	var world := await _make_world()
	if world == null:
		_fail("world scene could not be instantiated")
		_finish()
		return
	var lanes := _lanes(world)
	_check_lane_count(lanes)
	for lane in lanes:
		_check_lane(lane)
	_check_kinds(lanes)
	_check_determinism(lanes)
	await _check_hit(lanes)
	world.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("SKY OBSTACLE TESTS OK (%d checks)" % _checks)
	else:
		print("SKY OBSTACLE TESTS FAILED (%d of %d checks)" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _make_world() -> WorldBase:
	var packed := load("res://world/world.tscn") as PackedScene
	if packed == null:
		return null
	var world := packed.instantiate() as WorldBase
	if world == null:
		return null
	get_tree().root.add_child(world)
	for i in 600:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			break
	return world


# --- the lanes and their obstacles -------------------------------------------------------------------

func _lanes(world: Node) -> Array[SkyLane]:
	var out: Array[SkyLane] = []
	for node in world.find_children("*", "SkyLane", true, false):
		var lane := node as SkyLane
		if lane != null:
			out.append(lane)
	return out


## The obstacles of a lane, sorted by the offset along the curve.
func _placed(lane: SkyLane) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in lane.get_children():
		var node := child as Node3D
		if node == null or not node.is_in_group(GROUP):
			continue
		out.append({"node": node, "offset": _offset_of(lane, node)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["offset"]) < float(b["offset"]))
	return out


## The offset along the curve of the closest point to an obstacle.
func _offset_of(lane: SkyLane, node: Node3D) -> float:
	if lane.curve == null:
		return 0.0
	return lane.curve.get_closest_offset(node.position)


## The obstacle in the lane frame at its own offset: x is lateral, y is the height.
func _in_frame(lane: SkyLane, node: Node3D, offset: float) -> Vector3:
	return (lane.frame_at(offset).affine_inverse() * node.position)


# --- the checks ---------------------------------------------------------------------------------------

func _check_lane_count(lanes: Array[SkyLane]) -> void:
	_ok(lanes.size() == 5, "the city has %d sky lanes (want 5)" % lanes.size())


## 2. the number of obstacles, 3. they are inside the tube, 4. they are spread along the curve.
func _check_lane(lane: SkyLane) -> void:
	var length := lane.length()
	var placed := _placed(lane)
	var wanted := 1
	if length >= 400.0:
		wanted = maxi(int(floor(length / 300.0)) - 1, 1)
	_ok(placed.size() >= wanted, "lane %s: %d obstacles (at least %d wanted)" % [
			lane.name, placed.size(), wanted])
	if placed.is_empty():
		_fail("lane %s: no obstacle at all" % lane.name)
		return
	_check_inside(lane, placed)
	_check_parts(lane, placed)
	_check_spread(lane, placed, length)


## Every obstacle has the meshes of its kind and its trigger.
func _check_parts(lane: SkyLane, placed: Array[Dictionary]) -> void:
	var bad := 0
	for entry in placed:
		var node := entry["node"] as Node3D
		var kind := str(node.get_meta("kind", ""))
		var area := node.get_node_or_null(^"Hit") as Area3D
		if area == null or area.collision_layer != (1 << 3) or area.collision_mask != (1 << 1):
			bad += 1
			continue
		var part := "Body"
		match kind:
			"billboard":
				part = "Panel"
			"crane":
				part = "Arm"
		if node.get_node_or_null(NodePath(part)) == null:
			bad += 1
	_ok(bad == 0, "lane %s: %d of %d obstacles have no meshes or no trigger" % [
			lane.name, bad, placed.size()])


## 3. every obstacle is inside the tube of its lane.
func _check_inside(lane: SkyLane, placed: Array[Dictionary]) -> void:
	var bad := 0
	var off := 0
	var worst := Vector3.ZERO
	var worst_off := Vector3.ZERO
	for entry in placed:
		var node := entry["node"] as Node3D
		var local := _in_frame(lane, node, float(entry["offset"]))
		if absf(local.x) > lane.tube_half_width or local.y > lane.tube_up or local.y < -lane.tube_down:
			bad += 1
			if bad == 1:
				worst = local
		# The centre of an obstacle stays well inside the tube: there is always a line past it.
		if absf(local.x) > LATERAL_LIMIT + TOLERANCE or local.y > HEIGHT_MAX + TOLERANCE \
				or local.y < HEIGHT_MIN - TOLERANCE:
			off += 1
			if off == 1:
				worst_off = local
	_ok(bad == 0, "lane %s: %d of %d obstacles are outside the tube%s" % [
			lane.name, bad, placed.size(),
			"" if bad == 0 else " (first at %.1f, %.1f)" % [worst.x, worst.y]])
	_ok(off == 0, "lane %s: %d of %d obstacles are not in the flight box%s" % [
			lane.name, off, placed.size(),
			"" if off == 0 else " (first at %.1f, %.1f)" % [worst_off.x, worst_off.y]])


## 4. the obstacles are 120 m apart and keep away from the ends of the curve.
func _check_spread(lane: SkyLane, placed: Array[Dictionary], length: float) -> void:
	var bad := 0
	for i in range(1, placed.size()):
		var gap := float(placed[i]["offset"]) - float(placed[i - 1]["offset"])
		if gap < 120.0:
			bad += 1
	var first := float(placed[0]["offset"])
	var last := float(placed[placed.size() - 1]["offset"])
	_ok(bad == 0, "lane %s: %d obstacles are less than 120 m apart" % [lane.name, bad])
	_ok(first >= 150.0, "lane %s: the first obstacle is %.0f m from the start (want 150 m)" % [
		lane.name, first])
	_ok(length - last >= 100.0, "lane %s: the last obstacle is %.0f m from the end (want 100 m)" % [
		lane.name, length - last])


## 5. the longest lane carries the three kinds.
func _check_kinds(lanes: Array[SkyLane]) -> void:
	var longest: SkyLane = null
	for lane in lanes:
		if longest == null or lane.length() > longest.length():
			longest = lane
	if longest == null:
		_fail("no sky lane to check the kinds on")
		return
	# A counter per kind: the lookup is by name, the order of the kinds does not matter.
	var counts: Dictionary = {}
	for entry in _placed(longest):
		var node := entry["node"] as Node3D
		var kind := str(node.get_meta("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
	var missing: Array[String] = []
	for kind in KINDS:
		if int(counts.get(kind, 0)) < 1:
			missing.append(str(kind))
	_ok(missing.is_empty(), "lane %s: the kinds %s (missing %s)" % [
		longest.name, str(counts), str(missing)])


## 6. the same lane always gets the same obstacles: the seed is the name of the lane.
func _check_determinism(lanes: Array[SkyLane]) -> void:
	if not ResourceLoader.exists(OBSTACLES_PATH):
		_fail("%s does not exist" % OBSTACLES_PATH)
		return
	var script := load(OBSTACLES_PATH) as GDScript
	if script == null:
		_fail("%s could not be loaded" % OBSTACLES_PATH)
		return
	if lanes.is_empty():
		_fail("no sky lane to rebuild")
		return
	var lane := lanes[0]
	var before := _placed(lane)
	if before.size() < 3:
		_fail("lane %s has fewer than 3 obstacles to compare" % lane.name)
		return
	var fresh := SkyLane.new()
	fresh.name = lane.name
	fresh.curve = lane.curve
	var builder: Object = script.new()
	if builder == null:
		_fail("%s could not be instantiated" % OBSTACLES_PATH)
		fresh.free()
		return
	builder.call("build", fresh)
	var after := _placed(fresh)
	if after.size() < 3:
		_fail("the rebuilt lane %s has fewer than 3 obstacles" % lane.name)
		fresh.free()
		return
	var same := 0
	for i in 3:
		var a := before[i]["node"] as Node3D
		var b := after[i]["node"] as Node3D
		if a.position.distance_to(b.position) <= 0.01:
			same += 1
	_ok(same == 3, "the rebuilt lane %s: %d of the first 3 obstacles are at the same place" % [
		lane.name, same])
	fresh.free()


## 7. only a car that flies is hit by an obstacle.
func _check_hit(lanes: Array[SkyLane]) -> void:
	var obstacle: Node3D = null
	for lane in lanes:
		var placed := _placed(lane)
		if not placed.is_empty():
			obstacle = placed[0]["node"] as Node3D
			break
	if obstacle == null:
		_fail("no obstacle to hit")
		return
	var area := obstacle.get_node_or_null(^"Hit") as Area3D
	if area == null:
		_fail("the obstacle %s has no Hit area" % obstacle.name)
		return
	var flyer := _make_flyer(true)
	area.add_child(flyer)
	for i in 3:
		await get_tree().physics_frame
	_ok(flyer.hits == 1, "the flying car was hit %d times (want 1)" % flyer.hits)
	var grounded := _make_flyer(false)
	area.add_child(grounded)
	for i in 3:
		await get_tree().physics_frame
	_ok(grounded.hits == 0, "the car on the ground was hit %d times (want 0)" % grounded.hits)


func _make_flyer(flying: bool) -> FakeFlyer:
	var flyer := FakeFlyer.new()
	flyer.name = "FakeFlyer"
	flyer.telemetry.flying = flying
	flyer.collision_layer = 1 << 1
	flyer.collision_mask = 0
	flyer.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.2, 4.0)
	shape.shape = box
	flyer.add_child(shape)
	return flyer


# --- reporting ---------------------------------------------------------------------------------------

func _ok(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	print("FAIL %s" % label)

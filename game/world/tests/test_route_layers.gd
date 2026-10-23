extends Node
## Headless test: every race route of the real city can be driven on the lane network, on the right level.
##
##   python tools/gd.py test res://world/tests/test_route_layers.gd
##
## The routes of city.json are built by the world (RouteBuilder: the racing line is the shortest lane
## path from gate to gate). Streets run underneath the elevated roads, so a gate on a deck and a lane
## on the street below can lie at the same x/z, 5 to 45 m apart in height. This test checks, per route:
##   1. no leg of the route falls back to a straight line, drives against the traffic, or needs a lane
##      further than 8 m from its gate (the builder reports the legs in the route meta data
##      unroutable_legs / backwards_legs / relaxed_legs / partial_legs, all of them empty);
##   2. the racing line lies on a lane centre at ITS OWN level: every line point has a lane point within
##      LANE_PLAN metres in plan and LANE_HEIGHT metres in height (at most 1 % of the points may not);
##   3. the line passes every gate: within GATE_PLAN metres in plan and GATE_HEIGHT in height;
##   4. every gate faces along the racing line (the angle between its heading and the line tangent is at
##      most GATE_ANGLE degrees), not towards the straight direction to the next gate (a hairpin like the
##      Pudong loop turns the road by 180 degrees between two gates);
##   5. the part of the line between the first and the last gate is at most 1.8 times the length of the
##      straight lines between the gates plus 100 m, and no shorter than 0.9 times it.

const CityData := preload("res://world/loader/city_data.gd")

const CELL := 16.0
const LANE_PLAN := 2.5
const LANE_HEIGHT := 3.0
const GATE_PLAN := 8.0
const GATE_HEIGHT := 3.0
const GATE_ANGLE := 35.0
const LANE_STEP := 3.0
const LINK_HEIGHT := 1.5        # the end of a lane and the start of the lane it is linked to
const WINDOW := 1500            # line points (2 m apart) in which the next gate is looked for
const MISS := 40.0              # a gate the line does not come within this many metres of is missed
const MAX_REVERSAL_LINES := 12   # the reversals that are printed with their place
const LEG_KEYS := ["unroutable_legs", "backwards_legs", "relaxed_legs", "partial_legs"]

var _failures := 0
var _checks := 0
var _grid: Dictionary = {}
## The racing lines of the routes, written to SKYRUSH_ROUTE_DUMP (a file path) when it is set: the lead compares
## them with the Python replica (tools/city/check_routes_drivable.py).
var _dump: Dictionary = {}


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
	_build_lane_grid(world.get_lane_paths())
	_check_links(world.get_lane_paths())
	for id in world.get_route_ids():
		_check_route(world.get_route(id))
	world.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	var dump_path := OS.get_environment("SKYRUSH_ROUTE_DUMP")
	if dump_path != "":
		var out := FileAccess.open(dump_path, FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify(_dump))
	if _failures == 0:
		print("ROUTE LAYERS TESTS OK (%d checks)" % _checks)
	else:
		print("ROUTE LAYERS TESTS FAILED (%d of %d checks)" % [_failures, _checks])
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


# --- the lane points -----------------------------------------------------------------------------

func _key(x: float, z: float) -> int:
	return (int(floor(x / CELL)) + 32768) * 65536 + (int(floor(z / CELL)) + 32768)


func _build_lane_grid(lanes: Array[LanePath]) -> void:
	_grid.clear()
	var count := 0
	for lane in lanes:
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var steps := maxi(int(length / LANE_STEP), 1)
		for s in steps + 1:
			var p := lane.curve.sample_baked(length * float(s) / float(steps), true)
			var k := _key(p.x, p.z)
			if not _grid.has(k):
				_grid[k] = []
			var cell: Array = _grid[k]
			cell.append(p)
			count += 1
	print("INFO %d lane points in %d cells" % [count, _grid.size()])


## True when a lane point lies within LANE_PLAN (plan) and LANE_HEIGHT (height) of the point.
func _on_lane(point: Vector3) -> bool:
	var reach := LANE_PLAN + LANE_STEP
	var cx := int(floor(point.x / CELL))
	var cz := int(floor(point.z / CELL))
	var span := int(ceil(reach / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var k := (cx + dx + 32768) * 65536 + (cz + dz + 32768)
			if not _grid.has(k):
				continue
			for q: Vector3 in _grid[k]:
				if absf(q.y - point.y) > LANE_HEIGHT:
					continue
				if Vector2(q.x - point.x, q.z - point.z).length() <= reach:
					return true
	return false


# --- the links of the lane graph ---------------------------------------------------------------------

## A lane continues into the lane it is linked to: the end of the one and the start of the other are on
## the same level (1.5 m). The world links lanes of different roads that end near each other in the plan
## (LaneLinks._link_proximity), which joins a street to the deck above it.
func _check_links(lanes: Array[LanePath]) -> void:
	var bad := 0
	var worst := 0.0
	var example := ""
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null or lane.curve.get_point_count() < 2:
			continue
		var end := lane.curve.get_point_position(lane.curve.get_point_count() - 1)
		for next_index in lane.next_lanes:
			var next := lanes[next_index]
			if next.curve == null or next.curve.get_point_count() < 2:
				continue
			var start := next.curve.get_point_position(0)
			var dy := absf(start.y - end.y)
			if dy > LINK_HEIGHT:
				bad += 1
				if dy > worst:
					worst = dy
					example = "%s -> %s (%.1f m)" % [lane.road_id, next.road_id, dy]
	_ok(bad == 0, "lane links: %d links join lanes more than %.1f m apart in height%s" % [
		bad, LINK_HEIGHT, "" if bad == 0 else ", worst " + example])


# --- one route -------------------------------------------------------------------------------------

func _check_route(route: RaceRoute) -> void:
	if route == null:
		_fail("a route is null")
		return
	var id := str(route.id)
	for key in LEG_KEYS:
		if not route.has_meta(key):
			_fail("route %s: the builder does not report %s in the route meta data" % [id, key])
		else:
			var legs: Array = route.get_meta(key)
			_ok(legs.is_empty(), "route %s: %s %s" % [id, key, str(legs)])
	var line := route.racing_line
	if line == null or line.get_point_count() < 2:
		_fail("route %s has no racing line" % id)
		return
	var points := PackedVector3Array(line.get_baked_points())
	var gates := route.checkpoints
	if OS.get_environment("SKYRUSH_ROUTE_DUMP") != "":
		var flat: Array = []
		for p in points:
			flat.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		_dump[id] = flat
	# the part of the line that belongs to the legs between the gates (a circuit adds a closing leg).
	# A gate is looked for in the next WINDOW line points only; a gate the line misses by more than
	# MISS metres gets index -1 and does not move the cursor.
	var cursor := 0
	var gate_index: Array[int] = []
	for gate in gates:
		var best := INF
		var at := -1
		for i in range(cursor, mini(points.size(), cursor + WINDOW)):
			var d := points[i].distance_to(gate.origin)
			if d < best:
				best = d
				at = i
		if at < 0 or best > MISS:
			gate_index.append(-1)
		else:
			gate_index.append(at)
			cursor = at
	var last := 0
	for index in gate_index:
		last = maxi(last, index)
	if last == 0:
		last = points.size() - 1
	# 2. every point of the line is on a lane of its own level
	var off := 0
	var worst: Vector3 = Vector3.ZERO
	for i in range(0, last + 1):
		if not _on_lane(points[i]):
			off += 1
			if off == 1:
				worst = points[i]
	var total := last + 1
	_ok(off * 100 <= total, "route %s: %d of %d line points are not on a lane of their level%s" % [
		id, off, total, "" if off == 0 else " (first at %.0f, %.1f, %.0f)" % [worst.x, worst.y, worst.z]])
	# 3. the line passes every gate, 4. the gate faces along the line
	var misses := 0
	var turned := 0
	var worst_angle := 0.0
	for g in gates.size():
		var gate := gates[g]
		if gate_index[g] < 0:
			misses += 1
			print("INFO route %s gate %d: the racing line does not come within %.0f m of it" % [id, g, MISS])
			continue
		var p := points[gate_index[g]]
		var plan := Vector2(p.x - gate.origin.x, p.z - gate.origin.z).length()
		if plan > GATE_PLAN or absf(p.y - gate.origin.y) > GATE_HEIGHT:
			misses += 1
			print("INFO route %s gate %d: the line passes %.1f m (plan) and %.1f m (height) from it" % [
				id, g, plan, p.y - gate.origin.y])
		var a := points[maxi(gate_index[g] - 3, 0)]
		var b := points[mini(gate_index[g] + 3, points.size() - 1)]
		var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var forward := -gate.basis.z
		forward.y = 0.0
		if tangent.length_squared() > 0.01 and forward.length_squared() > 0.01:
			var angle := rad_to_deg(forward.angle_to(tangent))
			worst_angle = maxf(worst_angle, angle)
			if angle > GATE_ANGLE:
				turned += 1
				print("INFO route %s gate %d: the gate faces %.0f degrees away from the line (gate forward %.2f, %.2f, line tangent %.2f, %.2f at line point %d of %d)" % [
					id, g, angle, forward.x, forward.z, tangent.normalized().x, tangent.normalized().z, gate_index[g], points.size()])
	_ok(misses == 0, "route %s: %d of %d gates are not on the racing line (plan %.0f m, height %.0f m)" % [
		id, misses, gates.size(), GATE_PLAN, GATE_HEIGHT])
	_ok(turned == 0, "route %s: %d gates do not face along the line (worst %.0f degrees, at most %.0f)" % [
		id, turned, worst_angle, GATE_ANGLE])
	# 5. the length of the line between the gates
	var length := 0.0
	for i in range(0, last):
		length += points[i].distance_to(points[i + 1])
	var straight := 0.0
	for g in range(gates.size() - 1):
		straight += gates[g].origin.distance_to(gates[g + 1].origin)
	_ok(length <= straight * 1.8 + 100.0 and length >= straight * 0.9,
		"route %s: the line between the gates is %.0f m, the straight lines %.0f m" % [id, length, straight])
	# 6. the line never turns back on itself: a rival that follows a line with a U-turn drives into the
	# traffic, or gets stuck and is picked up by the marshal (the same count as test_world_api.gd)
	var reversals := PackedInt32Array()
	for i in range(1, mini(points.size() - 6, last + 1)):
		var ahead := points[i + 5] - points[i]
		var behind := points[i] - points[i - 1]
		if ahead.length_squared() > 0.01 and behind.length_squared() > 0.01 				and ahead.normalized().dot(behind.normalized()) < -0.5:
			reversals.append(i)
	_ok(reversals.is_empty(), "route %s: %d reversals in the racing line" % [id, reversals.size()])
	for k in mini(reversals.size(), MAX_REVERSAL_LINES):
		var at := reversals[k]
		var leg := 0
		for g in gate_index.size():
			if gate_index[g] >= 0 and gate_index[g] <= at:
				leg = g
		print("INFO route %s: reversal %d at (%.0f, %.1f, %.0f), after gate %d, line point %d of %d" % [
			id, k, points[at].x, points[at].y, points[at].z, leg, at, points.size()])


# --- reporting -------------------------------------------------------------------------------------

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

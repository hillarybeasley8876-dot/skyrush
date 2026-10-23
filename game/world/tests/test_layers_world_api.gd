extends Node
## Headless test: the world API tells the levels of the map apart.
##
##   python tools/gd.py test res://world/tests/test_layers_world_api.gd
##
## A street at y = 0 and a deck at y = 10 lie at the same x/z. The lane grid, the path finder, the
## link builder and the route builder must tell them apart: a gate on the deck is served by the
## lanes of the deck only, the end of a lane is linked to the lanes of its own level only, and the
## racing line of a route stays on the level of its gates.
##
## The city is not needed: the lanes are built by hand.

const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const LanePathFinder := preload("res://world/api/lane_path_finder.gd")
const LaneLinks := preload("res://world/api/lane_links.gd")
const LaneGraphBuilder := preload("res://world/api/lane_graph.gd")
const RouteBuilder := preload("res://world/api/route_builder.gd")
const Spline := preload("res://world/api/spline_util.gd")

## The height of the deck above the street.
const DECK := 10.0
## The tolerance of the level of a gate (the rule of the whole folder).
const LEVEL := 3.0
## The four keys the route builder has to report.
const LEG_KEYS := ["unroutable_legs", "backwards_legs", "relaxed_legs", "partial_legs"]

var _failures := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_query()
	_test_gate_lanes()
	_test_links()
	_test_route()
	_test_hairpin()
	_finish()


# --- the lane grid ----------------------------------------------------------------------------------

## The query of the grid takes the height of the level it is asked about.
func _test_query() -> void:
	var lanes := _two_levels()
	var grid := LaneSpatial.new()
	grid.build(lanes)
	var point := Vector3(200, DECK, 0)
	var near: Dictionary = grid.query(point, 8.0)
	_check(near.size() == 2, "query without a height returns the street and the deck (%d lanes)" % near.size())
	var deck_only := _query_at_level(grid, point, 8.0, DECK, LEVEL)
	_check(deck_only.size() == 1 and deck_only.has(1),
		"query on the level of the deck returns the deck lane only (%s)" % str(deck_only.keys()))
	var street_only := _query_at_level(grid, point, 8.0, 0.0, LEVEL)
	_check(street_only.size() == 1 and street_only.has(0),
		"query on the level of the street returns the street lane only (%s)" % str(street_only.keys()))


# --- the path finder -------------------------------------------------------------------------------

## A gate is served by the lanes of its own level only.
func _test_gate_lanes() -> void:
	var lanes := _two_levels()
	var grid := LaneSpatial.new()
	grid.build(lanes)
	var finder := LanePathFinder.new()
	var on_deck: Array[int] = finder.gate_lanes(lanes, grid,
		Transform3D(Basis.looking_at(Vector3.RIGHT), Vector3(200, DECK, 0)))
	_check(on_deck.size() == 1 and on_deck[0] == 1,
		"a gate on the deck is served by the deck lane only (%s)" % str(on_deck))
	var on_street: Array[int] = finder.gate_lanes(lanes, grid,
		Transform3D(Basis.looking_at(Vector3.RIGHT), Vector3(200, 0, 0)))
	_check(on_street.size() == 1 and on_street[0] == 0,
		"a gate on the street is served by the street lane only (%s)" % str(on_street))


# --- the links of the graph ------------------------------------------------------------------------

## The end of a lane is linked to the lanes of its own level only.
func _test_links() -> void:
	var lanes := _two_levels()
	lanes.append(_lane("street_e", Vector3(400, 0, 3), Vector3(440, 0, 3)))
	lanes.append(_lane("deck_d", Vector3(400, DECK, 3), Vector3(440, DECK, 3)))
	var grid := LaneSpatial.new()
	grid.build(lanes)
	LaneLinks.new().link(lanes, LaneGraphBuilder.new(), [], grid)
	_check(lanes[0].next_lanes.has(2), "the street lane continues into the street lane")
	_check(not lanes[0].next_lanes.has(3), "the street lane does not continue into the deck lane")
	_check(lanes[1].next_lanes.has(3), "the deck lane continues into the deck lane")
	_check(not lanes[1].next_lanes.has(2), "the deck lane does not continue into the street lane")


# --- the route builder -----------------------------------------------------------------------------

## The racing line of a route on the deck stays on the deck, and the builder reports its legs.
func _test_route() -> void:
	var lanes := _two_levels()
	var grid := LaneSpatial.new()
	grid.build(lanes)
	var spec := {"id": "deck_route", "kind": "sprint",
		"checkpoints": [[200, DECK, 0, 90], [380, DECK, 0, 90]]}
	var built: Dictionary = RouteBuilder.new().build([spec], lanes, grid)
	var route := built["deck_route"] as RaceRoute
	_check(route != null, "the route is built")
	if route == null:
		return
	var line := route.racing_line
	_check(line != null and line.get_point_count() >= 2, "the route has a racing line")
	var worst := 0.0
	if line != null:
		for point in line.get_baked_points():
			worst = maxf(worst, absf(point.y - DECK))
	_check(line != null and worst <= 1.0,
		"the racing line stays on the level of the deck (%.1f m off)" % worst)
	for key in LEG_KEYS:
		var has_key := route.has_meta(key)
		_check(has_key, "the route reports %s" % key)
		if has_key:
			var legs: Array = route.get_meta(key)
			_check(legs.is_empty(), "the route has no %s (%s)" % [key, str(legs)])


# --- a gate on a hairpin ----------------------------------------------------------------------------

## A gate at the apex of a hairpin keeps its heading: the old builder turned it towards the next gate.
func _test_hairpin() -> void:
	var lanes := _hairpin()
	var grid := LaneSpatial.new()
	grid.build(lanes)
	LaneLinks.new().link(lanes, LaneGraphBuilder.new(), [], grid)
	# the first gate is on the straight lane, the second one at the apex of the bend
	var spec := {"id": "hairpin", "kind": "sprint",
		"checkpoints": [[100, 0, 0, 90], [240, 0, 40, 180]]}
	var built: Dictionary = RouteBuilder.new().build([spec], lanes, grid)
	var route := built["hairpin"] as RaceRoute
	_check(route != null, "the hairpin route is built")
	if route == null:
		return
	var gate := route.checkpoints[1]
	var forward := -gate.basis.z
	forward.y = 0.0
	var lane_direction := Vector3(0, 0, 1)  # the road at the apex of the bend runs south
	var angle := rad_to_deg(forward.normalized().angle_to(lane_direction))
	_check(angle <= 20.0, "the gate at the apex of the hairpin keeps its heading (%.0f degrees off)" % angle)


# --- helpers ----------------------------------------------------------------------------------------

## The lanes of the grid around the point, on the level of `y`. The call is dynamic: a build of
## the grid without the height argument (the mutation check restores one) reports no lane at all
## instead of breaking the script.
func _query_at_level(grid: LaneSpatial, point: Vector3, radius: float, y: float,
		tol: float) -> Dictionary:
	var query := Callable(grid, "query")
	if query.get_argument_count() < 4:
		return {}
	var result: Variant = query.call(point, radius, y, tol)
	if result is Dictionary:
		return result
	return {}


## A street lane (y = 0) and a deck lane (y = 10) at the same x/z.
func _two_levels() -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	lanes.append(_lane("street_a", Vector3(0, 0, 0), Vector3(400, 0, 0)))
	lanes.append(_lane("deck_b", Vector3(0, DECK, 0), Vector3(400, DECK, 0)))
	return lanes


## A straight lane between two points.
func _lane(road: String, from: Vector3, to: Vector3) -> LanePath:
	var lane := LanePath.new()
	lane.road_id = StringName(road)
	lane.curve = Spline.make_curve(PackedVector3Array([from, to]), 2.0)
	return lane


## A U shaped road: a lane west to east at z = 0, a bend of 40 m radius and a lane east to west at z = 80.
func _hairpin() -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	lanes.append(_lane("west_east", Vector3(0, 0, 0), Vector3(200, 0, 0)))
	var bend := PackedVector3Array()
	for i in 17:
		var angle := PI * float(i) / 16.0
		bend.append(Vector3(200.0 + 40.0 * sin(angle), 0.0, 40.0 - 40.0 * cos(angle)))
	var curve := Spline.make_curve(bend, 2.0)
	var bend_lane := LanePath.new()
	bend_lane.road_id = &"bend"
	bend_lane.curve = curve
	lanes.append(bend_lane)
	lanes.append(_lane("east_west", Vector3(200, 0, 80), Vector3(0, 0, 80)))
	return lanes


# --- reporting --------------------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("WORLD LAYER TESTS OK (%d failures)" % _failures)
	else:
		print("WORLD LAYER TESTS FAILED (%d of %d checks failed)" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

extends Node
## The police must not cross the levels of the map (second round: the spawn spots, the roles,
## the ranking of the units and the roadblocks).
##
##   python tools/gd.py test res://ai/police/tests/test_layers_2.gd
##
## A street at y = 0 runs under the deck at y = 10. Four places of the police code measured
## with a 3D radius and never asked which level a car is on:
##
##   1. the oncoming spawn (and the lane of the head-on unit) took a lane of another level;
##   2. a unit on the street took the role of a ram against a player on the deck;
##   3. the three units that keep their roles were the nearest by 3D distance, so a unit on
##      the street below held a slot of a unit on the level of the player;
##   4. a roadblock on the street counted as passed by a player who drove over it on the deck.
##
## Every rule has two halves: on the same level everything happens as before, on the other level
## nothing happens at all.

const STUB := preload("res://core/stubs/stub_car.tscn")

## m: the height of a car on the street.
const STREET := 0.6
## m: the height of a car on the deck.
const DECK := 10.6
## m: the height of the deck lane of the test graph.
const DECK_LANE := 10.0
## m: how far ahead of the player the oncoming lanes of the test graph are.
const ONCOMING_AHEAD := 200.0
## m: the length of the oncoming lanes of the test graph.
const ONCOMING_LENGTH := 400.0
## m: the length of the lane of the route of the test.
const ROUTE_LENGTH := 600.0
## m: where the roadblock site of the test stands on the route.
const SITE_ON_ROUTE := 400.0


## A cop that is only a place for the rules: no car, no light bar, no physics.
class TestCop extends PoliceCar:
	func _ready() -> void:
		pass


## A world with the roadblock sites of the test.
class TestWorld extends WorldBase:
	var sites: Array[Transform3D] = []

	func get_roadblock_sites() -> Array[Transform3D]:
		return sites


var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_test_spawn_spots()
	_test_roles()
	_test_squad()
	_test_roadblock()
	_test_roadblock_site()
	if _failures == 0:
		print("POLICE LAYER 2 TESTS OK (0 failures)")
		get_tree().quit(0)
	else:
		print("POLICE LAYER 2 TESTS FAILED")
		get_tree().quit(1)


## The oncoming spawn: the lane of the spot has to be on the level of the player.
func _test_spawn_spots() -> void:
	var spots := PoliceSpawnSpots.new()
	spots.ctx.graph = _oncoming_graph([0.0, DECK_LANE])
	spots.grid.build(spots.ctx.graph)
	# The player drives on the deck: the spot has to be on the deck lane.
	var player := _make_player(Vector3(0.0, DECK, 0.0))
	var spot: Dictionary = spots.oncoming_spot(player, 0, 0.0)
	_check(not spot.is_empty() and int(spot.get("lane", -1)) == 1,
			"the oncoming spot of a player on the deck is on the deck lane")
	# The same graph, the player on the street: the spot is the street lane.
	var street_player := _make_player(Vector3(0.0, STREET, 0.0))
	var street_spot: Dictionary = spots.oncoming_spot(street_player, 0, 0.0)
	_check(not street_spot.is_empty() and int(street_spot.get("lane", -1)) == 0,
			"the oncoming spot of a player on the street is on the street lane")
	# Only the street lane: the player on the deck gets no spot at all.
	var only_street := PoliceSpawnSpots.new()
	only_street.ctx.graph = _oncoming_graph([0.0])
	only_street.grid.build(only_street.ctx.graph)
	var none: Dictionary = only_street.oncoming_spot(player, 0, 0.0)
	_check(none.is_empty(),
			"there is no oncoming spot for a player on the deck when the street is the only lane")
	# The lane of the head-on unit: the one that runs against the player next to a point.
	var lane := spots.oncoming_lane_at(Vector3(ONCOMING_AHEAD, DECK, 0.0), Vector3.RIGHT)
	_check(lane == 1, "the oncoming lane of a point on the deck is the deck lane")
	var street_lane := spots.oncoming_lane_at(Vector3(ONCOMING_AHEAD, STREET, 0.0), Vector3.RIGHT)
	_check(street_lane == 0, "the oncoming lane of a point on the street is the street lane")
	var only_lane := only_street.oncoming_lane_at(Vector3(ONCOMING_AHEAD, DECK, 0.0), Vector3.RIGHT)
	_check(only_lane == -1,
			"there is no oncoming lane on the deck when the street is the only lane")


## The roles: a unit on another level does not take its role.
func _test_roles() -> void:
	var player := _make_player(Vector3(0.0, STREET, 0.0))
	var ctx := DriveContext.new()
	ctx.player = player
	# The unit is 6 m behind and 2.5 m beside the player.
	var beside := Vector3(2.5, 0.0, 6.0)
	var below := Vector3(2.5, -10.0, 6.0)
	_check(_role_state(player, ctx, PoliceFleet.Role.PIT, beside) == PoliceCar.State.PIT,
			"a PIT unit on the level of the player takes its role")
	_check(_role_state(player, ctx, PoliceFleet.Role.PIT, below) == PoliceCar.State.PURSUE,
			"a PIT unit 10 m below the player keeps the state PURSUE")
	_check(_role_state(player, ctx, PoliceFleet.Role.RAM, beside) == PoliceCar.State.RAM,
			"a RAM unit on the level of the player takes its role")
	_check(_role_state(player, ctx, PoliceFleet.Role.RAM, below) == PoliceCar.State.PURSUE,
			"a RAM unit 10 m below the player keeps the state PURSUE")
	_check(_role_state(player, ctx, PoliceFleet.Role.BOX_FRONT, beside) == PoliceCar.State.BOX,
			"a BOX unit on the level of the player takes its role")
	_check(_role_state(player, ctx, PoliceFleet.Role.BOX_FRONT, below) == PoliceCar.State.PURSUE,
			"a BOX unit 10 m below the player keeps the state PURSUE")


## The ranking of the units: the ones on the level of the player come first.
func _test_squad() -> void:
	var player := _make_player(Vector3(0.0, STREET, 0.0))
	var squad := PoliceSquad.new()
	var near := _squad_unit(squad, player, Vector3(0.0, 0.0, 60.0))
	var middle := _squad_unit(squad, player, Vector3(0.0, 0.0, 70.0))
	var far := _squad_unit(squad, player, Vector3(0.0, 0.0, 80.0))
	var below := _squad_unit(squad, player, Vector3(0.0, -10.0, 20.0))
	squad._rank(player, null)
	squad._hold_back(player, Vector3.ZERO)
	_check(below.hold_back, "the unit on the street below the player holds back")
	_check(not near.hold_back and not middle.hold_back and not far.hold_back,
			"the three units on the level of the player keep their roles")


## The roadblock: only a player on the level of the block passes it.
func _test_roadblock() -> void:
	var over := _make_player(Vector3(0.0, DECK, 20.0))
	var deck_block := _make_block()
	deck_block.tick(0.1, over)
	over.global_position = Vector3(0.0, DECK, 60.0)
	deck_block.tick(0.1, over)
	_check(not deck_block.passed, "a block on the street is not passed by a player on the deck")
	var street := _make_player(Vector3(0.0, STREET, 20.0))
	var street_block := _make_block()
	street_block.tick(0.1, street)
	street.global_position = Vector3(0.0, STREET, 60.0)
	street_block.tick(0.1, street)
	_check(street_block.passed, "a block on the street is passed by a player on the street")
	# The block the player only drove over still leaves the road.
	for _i in int((PoliceRoadblock.PASSED_TIMEOUT + 1.0) * 10.0):
		deck_block.tick(0.1, over)
	_check(deck_block.is_expired(), "the block the player drove over leaves the road anyway")
	deck_block.free()
	street_block.free()


## The roadblock site: it has to be on the level of the route.
func _test_roadblock_site() -> void:
	var blockade := PoliceBlockade.new()
	blockade.ctx.graph = _route_graph()
	var world := TestWorld.new()
	blockade.world = world
	var player := _make_player(Vector3.ZERO)
	world.sites = [Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(SITE_ON_ROUTE, 0.0, 0.0))]
	var on_route: Dictionary = blockade._site_on_route(player, 0, 0.0)
	_check(bool(on_route.get("found", false)), "a roadblock site on the route is used")
	world.sites = [Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(SITE_ON_ROUTE, -10.0, 0.0))]
	var below: Dictionary = blockade._site_on_route(player, 0, 0.0)
	_check(not bool(below.get("found", false)),
			"a roadblock site 10 m below the route is not used")
	world.free()


## The state a unit ends in when it tries to take its role.
##
## The unit is at `offset` in the frame of the player (x = right, y = up, z = behind).
func _role_state(player: VehicleBase, ctx: DriveContext, role: PoliceFleet.Role,
		offset: Vector3) -> PoliceCar.State:
	var cop := TestCop.new()
	add_child(cop)
	cop.gravity_scale = 0.0
	cop.freeze = true
	cop.ctx = ctx
	cop.roles = PoliceCarRoles.new(cop)
	cop.state = PoliceCar.State.PURSUE
	cop.state_time = 1.0
	cop.role = role
	cop.global_transform = _place(player, offset)
	cop.roles._try_role_state(cop.global_position.distance_to(player.global_position))
	return cop.state


## A unit of the squad at `offset` in the frame of the player (x = right, y = up, z = behind).
func _squad_unit(squad: PoliceSquad, player: VehicleBase, offset: Vector3) -> PoliceCar:
	var cop := TestCop.new()
	add_child(cop)
	cop.gravity_scale = 0.0
	cop.freeze = true
	cop.global_transform = _place(player, offset)
	squad.add(cop)
	return cop


## The place of a car at `offset` in the frame of the player.
func _place(player: VehicleBase, offset: Vector3) -> Transform3D:
	var basis := player.global_transform.basis
	return Transform3D(basis, player.global_position + basis * offset)


## The player: the stub car of the core, frozen at a place, facing +X.
func _make_player(pos: Vector3) -> VehicleBase:
	var player := STUB.instantiate() as VehicleBase
	add_child(player)
	player.gravity_scale = 0.0
	player.freeze = true
	player.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), pos)
	return player


## A block of the test on the street (it has no cars: the rules are what matters here).
func _make_block() -> PoliceRoadblock:
	var block := PoliceRoadblock.new()
	add_child(block)
	block.global_position = Vector3.ZERO
	return block


## The lane graph of the oncoming lanes: one lane per height, all of them ahead of the player
## and against him.
func _oncoming_graph(heights: Array[float]) -> LaneGraph:
	var lanes: Array[LanePath] = []
	for height in heights:
		var path := LanePath.new()
		path.road_id = &"test_road"
		path.speed_limit_kmh = 80.0
		path.lane_width = 3.5
		path.curve = _straight(Vector3(ONCOMING_AHEAD + ONCOMING_LENGTH * 0.5, height, 0.0),
				Vector3(-ONCOMING_LENGTH, 0.0, 0.0))
		lanes.append(path)
	var graph := LaneGraph.new()
	graph.build(lanes)
	return graph


## The lane graph of the route: one straight lane of 600 m at y = 0.
func _route_graph() -> LaneGraph:
	var path := LanePath.new()
	path.road_id = &"test_route"
	path.speed_limit_kmh = 80.0
	path.lane_width = 3.5
	path.curve = _straight(Vector3.ZERO, Vector3(ROUTE_LENGTH, 0.0, 0.0))
	var lanes: Array[LanePath] = [path]
	var graph := LaneGraph.new()
	graph.build(lanes)
	return graph


## A straight lane that runs from `from` along `direction`.
func _straight(from: Vector3, direction: Vector3) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(from)
	curve.add_point(from + direction)
	return curve

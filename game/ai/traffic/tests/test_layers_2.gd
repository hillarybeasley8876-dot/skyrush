extends Node
## The traffic index and the road of the player must respect the level of the map.
##
##   python tools/gd.py test res://ai/traffic/tests/test_layers_2.gd
##
## The test builds a road with two levels by hand: a street lane at y = 0 and a deck lane at
## y = 10 above it, both along +X, with the same x/z. Then it checks:
##   - a wreck that fell off the deck to the street is indexed on the street lane and not on
##     the deck lane (the cars on the deck must not brake for a wreck that is not there);
##   - a wreck that fell where there is no lane is indexed nowhere;
##   - the road of the player is the street when the player drives on the street under the
##     deck, even when the last lane of the player is still the deck lane.
##
## Everything that happens on the same level must still happen: the wreck that stays on its
## lane is still indexed there, and the player on the deck still belongs to the deck road.

const STREET_LANE := 0        ## the lane of the street (y = 0)
const DECK_LANE := 1          ## the lane of the deck (y = 10) above the street
const LENGTH := 400.0         ## m: the length of the lanes
const DECK_HEIGHT := 10.0     ## m: the height of the deck above the street
const CAR_S := 50.0           ## m: the place of the wreck on the deck lane
const FALLEN_X := 80.0        ## m: the place of the body that fell to the street
const BODY_Y := 0.6           ## m: the height of a body that lies on the road
const STREET_ROAD := "street_road"
const DECK_ROAD := "deck_road"

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()
var _grid: LaneGrid = LaneGrid.new()
var _index: TrafficIndex = TrafficIndex.new()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_ctx.graph = _two_level_road()
	_ctx.rng.seed = 99
	_grid.build(_ctx.graph)
	_index.ctx = _ctx
	_index.grid = _grid
	_test_wreck_on_the_street()
	_test_wreck_without_a_lane()
	_test_wreck_on_its_lane()
	var director := _make_director()
	_test_player_road_on_the_street(director)
	_test_player_road_on_the_deck(director)
	director.free()
	print("TRAFFIC LAYER 2 TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A wreck that fell off the deck lies on the street: it is an obstacle of the street lane and
## nothing else. The deck lane must not keep a phantom wreck for the whole wreck time.
func _test_wreck_on_the_street() -> void:
	var wreck := _make_wreck(Vector3(FALLEN_X, BODY_Y, 0.0))
	_rebuild_index(wreck)
	_check(_holds(STREET_LANE, wreck), "the wreck that fell to the street is indexed on the street")
	_check(not _holds(DECK_LANE, wreck), "the wreck that fell to the street is not indexed on the deck")


## A wreck that fell where there is no lane at all blocks nothing.
func _test_wreck_without_a_lane() -> void:
	var wreck := _make_wreck(Vector3(200.0, BODY_Y, 60.0))
	_rebuild_index(wreck)
	_check(not _holds(STREET_LANE, wreck), "the wreck without a lane under it is not indexed on the street")
	_check(not _holds(DECK_LANE, wreck), "the wreck without a lane under it is not indexed on the deck")


## The control: a wreck that stayed within `WRECK_LANE_DISTANCE` of its lane is still indexed
## on that lane, the way it was before.
func _test_wreck_on_its_lane() -> void:
	var wreck := _make_wreck(Vector3(CAR_S + 1.0, DECK_HEIGHT, 0.0))
	_rebuild_index(wreck)
	_check(_holds(DECK_LANE, wreck), "the wreck that stayed on the deck is indexed on the deck")
	_check(not _holds(STREET_LANE, wreck), "the wreck that stayed on the deck is not indexed on the street")


## The player drives on the street under the deck, but the last lane of the player is still the
## deck lane: the traffic has to belong to the street, not to the deck.
func _test_player_road_on_the_street(director: TrafficDirector) -> void:
	var player := _make_player()
	player.global_position = Vector3(CAR_S, BODY_Y, 0.0)
	director._player = player
	director._player_lane = DECK_LANE
	director._player_s = CAR_S
	var road := director._player_road()
	_check(road == STREET_ROAD, "the road of the player on the street is the street (%s)" % road)


## The control: the player on the deck belongs to the deck road.
func _test_player_road_on_the_deck(director: TrafficDirector) -> void:
	var player := _make_player()
	player.global_position = Vector3(CAR_S, DECK_HEIGHT, 0.0)
	director._player = player
	director._player_lane = DECK_LANE
	director._player_s = CAR_S
	var road := director._player_road()
	_check(road == DECK_ROAD, "the road of the player on the deck is the deck (%s)" % road)


## A road with two levels: a street lane at y = 0 and a deck lane at y = 10 above it, both
## along +X and with the same x/z (the deck is above the street).
func _two_level_road() -> LaneGraph:
	var lanes: Array[LanePath] = []
	lanes.append(_lane(STREET_ROAD, Vector3(0.0, 0.0, 0.0)))
	lanes.append(_lane(DECK_ROAD, Vector3(0.0, DECK_HEIGHT, 0.0)))
	var graph := LaneGraph.new()
	graph.build(lanes)
	return graph


## One straight lane of `LENGTH` metres, starting at `offset`.
func _lane(road: String, offset: Vector3) -> LanePath:
	var path := LanePath.new()
	path.road_id = StringName(road)
	path.speed_limit_kmh = 80.0
	path.lane_width = 3.5
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(offset)
	curve.add_point(offset + Vector3(LENGTH, 0.0, 0.0))
	path.curve = curve
	return path


## A traffic car that was hit on the deck lane and whose body now lies at `body`.
func _make_wreck(body: Vector3) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	car.place(DECK_LANE, CAR_S)
	car.mode = TrafficCar.Mode.WRECK
	car.global_transform = Transform3D(Basis.IDENTITY, body)
	return car


## Refills the index with the wreck.
func _rebuild_index(wreck: TrafficCar) -> void:
	var cars: Array[TrafficCar] = [wreck]
	_index.rebuild(cars)


## True when the index holds the wreck on the lane (and nothing else).
func _holds(lane: int, wreck: TrafficCar) -> bool:
	return _ctx.hash.count(lane) == 1 and _ctx.hash.leader(lane, -1.0) == wreck


## A director with the two level road (it is not put in the tree: the test asks one question).
func _make_director() -> TrafficDirector:
	var director := TrafficDirector.new()
	director.ctx.graph = _ctx.graph
	director.grid.build(_ctx.graph)
	return director


## The player: the stub car of the core (a VehicleBase that can be put anywhere).
func _make_player() -> VehicleBase:
	var player := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	add_child(player)
	player.gravity_scale = 0.0
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	return player

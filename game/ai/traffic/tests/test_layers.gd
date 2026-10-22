extends Node
## The street traffic must not react to a player on another level (a deck above the street).
##
##   python tools/gd.py test res://ai/traffic/tests/test_layers.gd
##
## The test builds the traffic test road (three lanes along +X at y = 0), a traffic car and the
## stub player, and puts the player next to the car - or 10.6 m above it, on a deck:
##   - the near miss and the horn of a car on the street, and
##   - the startled driver of a car that a fast player catches from behind.
##
## Everything that happens on the same level must still happen: a fix that switches the whole
## feature off passes the wrong-level half of the test alone.

const DT := 0.016            ## s: the tick of the player events
const DECK := 10.6           ## m: the height of the deck above the street
const NEAR_GAP := 0.3        ## m: the side gap of the near miss (under 1.2 m)
const HORN_GAP := 1.4        ## m: the side gap of the horn (under 1.5 m, over the near miss)
const PLAYER_SPEED := 40.0   ## m/s: the speed of the player along the lane
const CAR_SPEED := 10.0      ## m/s: the speed of the traffic car
const CAR_S := 50.0          ## m: the place of the traffic car on its lane
const REACT_DISTANCE := 25.0 ## m: how far behind the car the player comes up
const REACT_SPEED := 30.0    ## m/s: the speed of the player that catches the car
const REACT_STEPS := 200     ## the number of ticks of the lane change
const LANE := 0              ## the lane of the traffic car of the near miss and the horn
const REACT_LANE := 1        ## the lane of the traffic car of the startled driver

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()
## The distance between the player and the car of the last setup (m), for the messages.
var _distance: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 4242
	_test_near_miss_same_level()
	_test_near_miss_on_a_deck()
	_test_horn_same_level()
	_test_horn_on_a_deck()
	_test_reaction_same_level()
	_test_reaction_on_a_deck()
	print("TRAFFIC LAYER TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The near miss on the same level: the player squeezes by the car and is rewarded for it.
func _test_near_miss_same_level() -> void:
	var car := _make_car(LANE, CAR_S)
	var player := _make_player()
	_place_player(car, player, NEAR_GAP, 0.0)
	var events := TrafficPlayerEvents.new()
	events.update(DT, player, _cars(car))
	_check(events.near_misses == 1, "the near miss on the same level is counted (%d, distance %.1f m)"
		% [events.near_misses, _distance])


## The same pass, but the player is on the deck 10.6 m above the street: no near miss, no horn.
func _test_near_miss_on_a_deck() -> void:
	var car := _make_car(LANE, CAR_S)
	var player := _make_player()
	_place_player(car, player, NEAR_GAP, DECK)
	var events := TrafficPlayerEvents.new()
	events.update(DT, player, _cars(car))
	_check(events.near_misses == 0, "no near miss for a player on the deck (%d, distance %.1f m)"
		% [events.near_misses, _distance])
	_check(events.horns == 0, "no horn for a player on the deck (%d)" % events.horns)


## The horn on the same level: the player squeezes by the car with less than 1.5 m of gap.
func _test_horn_same_level() -> void:
	var car := _make_car(LANE, CAR_S)
	var player := _make_player()
	_place_player(car, player, HORN_GAP, 0.0)
	var events := TrafficPlayerEvents.new()
	events.update(DT, player, _cars(car))
	_check(events.horns == 1, "the horn on the same level is sounded (%d, distance %.1f m)"
		% [events.horns, _distance])


## The same squeeze on the deck: the car below does not hear anything.
func _test_horn_on_a_deck() -> void:
	var car := _make_car(LANE, CAR_S)
	var player := _make_player()
	_place_player(car, player, HORN_GAP, DECK)
	var events := TrafficPlayerEvents.new()
	events.update(DT, player, _cars(car))
	_check(events.horns == 0, "no horn for a player on the deck (%d, distance %.1f m)"
		% [events.horns, _distance])


## The startled driver on the same level: a player that comes up fast from behind makes the car
## move out of the way or brake.
func _test_reaction_same_level() -> void:
	var car := _make_car(REACT_LANE, CAR_S)
	car.speed = 5.0
	var player := _make_player()
	_place_player_behind(car, player, 0.0)
	_run_lane_change(car, player)
	_check(car.lane_change._reacting, "the car on the same level is startled by the player behind it")


## The same approach on the deck: the car on the street does not even notice the player.
func _test_reaction_on_a_deck() -> void:
	var car := _make_car(REACT_LANE, CAR_S)
	car.speed = 5.0
	var player := _make_player()
	_place_player_behind(car, player, DECK)
	_run_lane_change(car, player)
	_check(not car.lane_change._reacting, "the car does not react to a player on the deck")
	_check(car.lane_change.reaction_brake == 0.0, "the car does not brake for a player on the deck (%.2f)"
		% car.lane_change.reaction_brake)


## Ticks the lane change of the car with the player in reach.
func _run_lane_change(car: TrafficCar, player: VehicleBase) -> void:
	_ctx.player = player
	for i in REACT_STEPS:
		_ctx.rng.seed = 1000 + i
		car.lane_change.update(DT, _ctx, car.follower, car.speed, car.desired_speed,
				car.car_length, car.global_position)


## Puts the player next to the car: `gap` metres of side gap, `dy` metres above the road.
func _place_player(car: TrafficCar, player: VehicleBase, gap: float, dy: float) -> void:
	var side := car.car_width * 0.5 + TrafficPlayerEvents.PLAYER_HALF_WIDTH + gap
	var forward := -car.global_transform.basis.z
	player.global_position = car.global_transform * Vector3(side, dy, 0.0)
	player.linear_velocity = forward * PLAYER_SPEED
	car.linear_velocity = forward * CAR_SPEED
	_distance = car.global_position.distance_to(player.global_position)


## Puts the player behind the car, on the same level or `dy` metres above it.
func _place_player_behind(car: TrafficCar, player: VehicleBase, dy: float) -> void:
	var forward := -car.global_transform.basis.z
	player.global_position = car.global_position - forward * REACT_DISTANCE + Vector3(0.0, dy, 0.0)
	player.linear_velocity = forward * REACT_SPEED
	car.linear_velocity = forward * CAR_SPEED
	_distance = car.global_position.distance_to(player.global_position)


## A traffic car on the test road (the same as ai/traffic/tests/test_wreck.gd).
func _make_car(lane: int, s: float) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	car.place(lane, s)
	car.player_distance = 0.0
	return car


## The player: the stub car of the core (a VehicleBase that can be put anywhere).
func _make_player() -> VehicleBase:
	var player := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	add_child(player)
	player.gravity_scale = 0.0
	player.collision_layer = 0
	player.collision_mask = 0
	return player


## The list of cars the player events look at.
func _cars(car: TrafficCar) -> Array[TrafficCar]:
	var cars: Array[TrafficCar] = []
	cars.append(car)
	return cars

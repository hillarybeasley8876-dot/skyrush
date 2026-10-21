class_name RaceStart
extends RefCounted
## The start of a race: the cars on the grid and the checkpoint every racer starts behind.
##
## The rivals take the grid slots of the route (the one of the player is left for him) and the
## player is put on its own slot and held there through the countdown.

## The racers of the race (the player first, then the rivals).
var racers: Array[RaceRacer] = []
## The grid slot of the player.
var player_slot: Transform3D = Transform3D.IDENTITY


## Puts the field on the grid.
static func place(route: RaceRoute, difficulty: StringName, player: VehicleBase,
		director: Node, options: Dictionary) -> RaceStart:
	var out := RaceStart.new()
	var count := RivalGrid.SLOT_COUNT
	var player_slot := clampi(int(options.get("player_slot", count - 1)), 0, count - 1)
	# The rivals go first: they build the racing line the grid stands on.
	if director != null and director.has_method("start_race"):
		director.call("start_race", route, difficulty, player_slot)
	if player != null:
		var slots := _grid_slots(route, director)
		if player_slot < slots.size():
			out.player_slot = RivalGrid.ground_spot(slots[player_slot])
			player.reset_to(out.player_slot)
			player.freeze = true
		out.racers.append(RaceRacer.new(player, _player_name(player), true))
	for car in _rival_cars(director):
		out.racers.append(RaceRacer.new(car, String(car.display_name), false))
	_set_start_checkpoints(out, route, director)
	return out


## Every racer starts behind the checkpoint it meets first: the lap ends when it comes back to
## it. A grid that stands in the middle of the route would otherwise break the lap count.
static func _set_start_checkpoints(start: RaceStart, route: RaceRoute, director: Node) -> void:
	for racer in start.racers:
		var index := 0
		if director != null and director.has_method("first_checkpoint_ahead"):
			index = int(director.call("first_checkpoint_ahead", route,
				racer.vehicle.global_position))
		racer.start_cp = index
		racer.next_cp = index


## The name of the player in the results (the car is the Roadster).
static func _player_name(car: VehicleBase) -> String:
	if not car.display_name.is_empty():
		return car.display_name
	return "Roadster"


## The rivals of the current race (empty when the rivals unit is not loaded).
static func _rival_cars(director: Node) -> Array[RivalCar]:
	var out: Array[RivalCar] = []
	if director == null or not director.has_method("get_cars"):
		return out
	for car in director.call("get_cars") as Array:
		var rival := car as RivalCar
		if rival != null:
			out.append(rival)
	return out


## The grid slots: two columns behind the start line of the racing line.
static func _grid_slots(route: RaceRoute, director: Node) -> Array[Transform3D]:
	if director == null or not director.has_method("grid_slots"):
		return RivalGrid.slots_of(route, null)
	return director.call("grid_slots") as Array[Transform3D]

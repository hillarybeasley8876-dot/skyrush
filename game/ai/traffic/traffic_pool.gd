class_name TrafficPool
extends RefCounted
## The cars that wait for their next turn.
##
## Building a traffic car means instantiating a glb, and that took half a second the first time
## and a few milliseconds later. The pool keeps the cars that are not on the road: a spawn takes
## one out and puts it on the road, a despawn puts it back. A spawn is then a placement, not a
## build, and it costs a fraction of a millisecond.

const CAR_SCENE := preload("res://ai/traffic/traffic_car.tscn")

var ctx: DriveContext = null
## The node the cars are children of (the director).
var parent: Node3D = null
## The cars that wait, per model.
var _pool: Dictionary = {}


## Takes a car of `model_id` out of the pool, or builds a new one.
func acquire(model_id: StringName) -> TrafficCar:
	var pool: Array = _pool.get(model_id, [])
	if not pool.is_empty():
		var pooled := pool.pop_back() as TrafficCar
		_pool[model_id] = pool
		return pooled
	var car := CAR_SCENE.instantiate() as TrafficCar
	parent.add_child(car)
	car.add_to_group("traffic")
	car.add_to_group("vehicles")
	car.build(ctx, model_id, Color.WHITE, ctx.rng.randi())
	# The car waits in the parking place until it is given a lane: a car that waits in the
	# middle of the city stands where the player drives.
	car.set_active(false)
	return car


## Builds the whole pool while the world is still building.
##
## The first car of a model takes 28 ms (the glb is instantiated and the lamp materials are
## built), the next one 0.4 ms. Paying that in the middle of the game would cost a frame, so
## the pool is filled in the mix of the fleet while the world loads.
func prefill(total: int) -> void:
	var counts := TrafficFleet.fleet_counts(total)
	for model: StringName in counts:
		for i in int(counts[model]):
			var car := CAR_SCENE.instantiate() as TrafficCar
			parent.add_child(car)
			car.add_to_group("traffic")
			car.add_to_group("vehicles")
			car.build(ctx, model, Color.WHITE, ctx.rng.randi())
			car.set_active(false)
			var pool: Array = _pool.get(model, [])
			pool.append(car)
			_pool[model] = pool


## A model that is in the pool: a spawn of it does not have to build a car.
func pooled_model(rng: RandomNumberGenerator) -> StringName:
	var models: Array = _pool.keys()
	if models.is_empty():
		return &""
	return models[rng.randi() % models.size()]


## Puts a car back into the pool, so the next spawn does not have to build one.
func release(car: TrafficCar) -> void:
	car.set_active(false)
	var pool: Array = _pool.get(car.model_id, [])
	pool.append(car)
	_pool[car.model_id] = pool


## Puts a car on a lane: it comes out of the pool, takes its colour and its place.
func spawn_at(lane: int, s: float, model_id: StringName, colour: Color) -> TrafficCar:
	var car := acquire(model_id)
	car.set_colour(colour)
	car.place(lane, s)
	return car

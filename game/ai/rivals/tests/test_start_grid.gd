extends Node
## The rivals leave the start grid by themselves.
##
## The back rows of the grid stand BEHIND the start of the racing line (the offsets on the
## line are negative there). The rivals on those rows must drive away on their own: they may
## not be picked up by the marshal, and they may not drive backwards to get away from the car
## in front of them.
##
## The test watches the first seconds of a race on the sandbox loop and checks every rival:
## its progress grows, its speed is forward, its distance (the travel the watchdog measures)
## grows and the marshal did not have to rescue it.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const WATCH := 8.0       ## s: the time the start of the race is watched
const SAMPLE := 0.5      ## s: the interval of the samples
const MIN_TRAVEL := 20.0 ## m: the distance a rival has to cover in the watched time
const MIN_SPEED := 1.0   ## m/s: the forward speed of a rival that drives away

var _rivals: Node = null
var _failures: int = 0
var _start: Dictionary = {}   ## the id of the car -> its travelled at the start


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	# The player stands well behind the grid: it must not be in the way of the field.
	car.reset_to(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(380.0, 0.04, 196.0)))
	_rivals = (load(RIVAL_DIRECTOR) as PackedScene).instantiate()
	add_child(_rivals)
	var route := Game.world.get_route(&"sandbox_loop")
	if route == null:
		print("FAIL no sandbox route")
		get_tree().quit(1)
		return
	_rivals.call("start_race", route, &"normal", -1)
	# The green light: the grid is released.
	_rivals.set("on_grid", false)
	for car_node in _rivals.call("get_cars") as Array:
		_start[car_node.get_instance_id()] = (car_node as RivalCar).brain.travelled
	_run()


## Watches the start of the race and checks every rival.
func _run() -> void:
	var waited := 0.0
	while waited < WATCH:
		await get_tree().create_timer(SAMPLE).timeout
		waited += SAMPLE
	for car_node in _rivals.call("get_cars") as Array:
		_check(car_node as RivalCar)
	print("START GRID TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Checks one rival: it drives away on its own.
func _check(car: RivalCar) -> void:
	if car == null or car.brain == null:
		return
	var brain := car.brain
	var start := float(_start.get(car.get_instance_id(), brain.travelled))
	var travel := brain.travelled - start
	_expect(brain.rescues == 0, "%s was not rescued (%d)" % [car.rival_name, brain.rescues])
	_expect(brain.speed >= MIN_SPEED, "%s drives forward (%.1f m/s)" % [car.rival_name, brain.speed])
	_expect(travel >= MIN_TRAVEL, "%s left the grid (%.1f m)" % [car.rival_name, travel])
	# The travel the watchdog measures: a rival that drives away has a growing distance.
	_expect(brain.distance >= MIN_TRAVEL, "%s has a growing distance (%.1f m)" % [
		car.rival_name, brain.distance])


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

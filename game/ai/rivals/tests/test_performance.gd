extends Node
## The cost of the rivals: the milliseconds per physics tick with and without the field.
##
## The dossier (7.7) allows 1.5 ms per frame for the car controllers of 18 cars.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const FRAMES := 240        ## the frames of one measurement
const BUDGET := 0.35       ## ms: the budget for the rivals alone

var _failures: int = 0
var _modes: ModeDirector = null
var _rivals: Node = null


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	_rivals = (load(RIVAL_DIRECTOR) as PackedScene).instantiate()
	add_child(_rivals)
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	# Warm up: the first frames build the physics world.
	await _measure(FRAMES / 2)
	var without := await _measure(FRAMES)
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1, "difficulty": "normal"})
	await get_tree().create_timer(4.0).timeout
	var with_rivals := await _measure(FRAMES)
	var cost := with_rivals - without
	# The AI cost on its own: the sum of the brain ticks of the five rivals.
	var brain_usec := 0
	for c in _rivals.call("get_cars") as Array:
		brain_usec += (c as RivalCar).brain_usec
	var brain_ms := float(brain_usec) / 1000.0
	print("PERF without the rivals %.3f ms per tick, with 5 rivals %.3f ms, the rivals cost %.3f ms" % [
		without, with_rivals, cost])
	print("PERF the AI of the five rivals costs %.3f ms per tick (the rest is the physics of the cars)" % brain_ms)
	_expect(brain_ms < BUDGET, "the AI of the rivals costs less than %.2f ms per tick (%.3f ms)" % [BUDGET, brain_ms])
	print("RIVAL PERF TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The milliseconds per physics tick over a number of frames.
func _measure(frames: int) -> float:
	var start := Time.get_ticks_usec()
	for i in frames:
		await get_tree().physics_frame
	return float(Time.get_ticks_usec() - start) / float(frames) / 1000.0


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

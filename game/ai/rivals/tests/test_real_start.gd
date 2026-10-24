extends Node
## The real start: on the city the rivals have to drive away from the grid of a real route
## by themselves, and no rival may need the marshal in the first seconds of the race.
##
## The grid of a city route stands on the road of the city: a route that starts on a
## roundabout has a grid that follows the roundabout, and a grid that stands in the
## footway is a grid whose cars cannot move at all.
##
## Run it with the stubs of the other units, so the city does not drown the test:
##   python tools/gd.py test res://ai/rivals/tests/test_real_start.gd -- --timeout=300 \
##       --stub=traffic,police,audio,fx,damage,hud,menu

const WORLD := "res://world/world.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const GO_SPEED := 8.0        ## m/s: the speed every rival has to reach after the go
const GO_CHECK := 4.0        ## s after the start
const RESCUE_WINDOW := 20.0  ## s: the time in which no rival may be rescued
const ROUTES: Array[String] = ["lujiazui_ring", "bund_sprint"]

var _failures: int = 0
var _modes: ModeDirector = null


func _ready() -> void:
	var world := (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	# The city builds over several seconds: a mode that is started before it is built waits
	# for it and has no session yet.
	await Game.world_ready()
	for route in ROUTES:
		await _check_route(route)
	print("REAL START TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The start of one route: the rivals drive away and nobody needs the marshal.
func _check_route(route: String) -> void:
	var started := _modes.start_mode(&"race", {"route": route, "laps": 1,
		"difficulty": "normal"})
	_expect(started, "the race on %s starts" % route)
	var session := _modes.session as RaceSession
	if session == null:
		_expect(false, "the race session of %s exists" % route)
		return
	await _wait_for_go()
	await get_tree().create_timer(GO_CHECK).timeout
	var slow: Array[String] = []
	for racer in session.racers:
		if racer.is_player:
			continue
		var speed := racer.vehicle.linear_velocity.length()
		if speed < GO_SPEED:
			slow.append("%s %.1f m/s" % [racer.name, speed])
	_expect(slow.is_empty(), "every rival is rolling at GO+%.0f s on %s (%s)" % [
		GO_CHECK, route, str(slow)])
	await get_tree().create_timer(RESCUE_WINDOW - GO_CHECK).timeout
	var rescued: Array[String] = []
	for racer in session.racers:
		if racer.is_player:
			continue
		var rival := racer.vehicle as RivalCar
		if rival != null and rival.brain != null and rival.brain.rescues > 0:
			rescued.append("%s (%d)" % [racer.name, rival.brain.rescues])
	_expect(rescued.is_empty(), "no rival needed the marshal in the first %.0f s on %s (%s)" % [
		RESCUE_WINDOW, route, str(rescued)])


## Waits for the green light.
func _wait_for_go() -> void:
	while _modes.session != null:
		var session := _modes.session as RaceSession
		if session != null and session.state == RaceSession.State.RUNNING:
			return
		await get_tree().create_timer(0.2).timeout


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

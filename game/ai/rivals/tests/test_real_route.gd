extends Node
## The real route: the grid must not gridlock, the rivals must drive away from the line and
## pass the gates.
##
## Run it with the stubs of the other units, so the city does not drown the test:
##   tools/godot.sh test res://ai/rivals/tests/test_real_route.gd -- --timeout=300 \
##       --stub=traffic,police,audio,fx,damage,hud,menu --route=bund_sprint --limit=120

const WORLD := "res://world/world.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const CONTACT_LIMIT := 800.0   ## N*s: a hit over this counts as a crash
const MIN_SPEED := 15.0        ## m/s: the speed the rivals must have at GO+3 s
const GO_CHECK := 3.0          ## s after the start
const CONTACT_WINDOW := 10.0   ## s: the window the contacts are counted in

var _failures: int = 0
var _contacts: int = 0
var _modes: ModeDirector = null


func _ready() -> void:
	Events.vehicle_collided.connect(_on_collision)
	var world := (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	var route_id := _option("route", "bund_sprint")
	var limit := float(_option("limit", "120"))
	# The city builds over several seconds: a mode that is started before it is built waits for it
	# and has no session yet.
	await Game.world_ready()
	var started := _modes.start_mode(&"race", {"route": route_id, "laps": 1,
		"difficulty": "normal"})
	_expect(started, "the race on %s starts" % route_id)
	var session := _modes.session as RaceSession
	_expect(session != null, "the race session exists")
	_expect(session.racers.size() == 6, "the race has 6 racers (%d)" % session.racers.size())
	await _wait_for_go()
	await _check_start(session)
	await _check_gates(session, limit)
	print("REAL ROUTE TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Waits for the green light.
func _wait_for_go() -> void:
	while _modes.session != null:
		var session := _modes.session as RaceSession
		if session != null and session.state == RaceSession.State.RUNNING:
			return
		await get_tree().create_timer(0.2).timeout


## The rivals must be rolling three seconds after the start, and they must not hit each other.
func _check_start(session: RaceSession) -> void:
	await get_tree().create_timer(GO_CHECK).timeout
	var slow: Array[String] = []
	for racer in session.racers:
		if racer.is_player:
			continue
		var speed := racer.vehicle.linear_velocity.length()
		if speed < MIN_SPEED:
			slow.append("%s %.1f m/s" % [racer.name, speed])
	_expect(slow.is_empty(), "every rival is rolling at GO+%.0f s (%s)" % [GO_CHECK, str(slow)])
	await get_tree().create_timer(CONTACT_WINDOW - GO_CHECK).timeout
	_expect(_contacts == 0, "no rival hit a rival over %.0f N*s (%d)" % [CONTACT_LIMIT, _contacts])


## Every rival must pass the gates of the route.
func _check_gates(session: RaceSession, limit: float) -> void:
	var waited := 0.0
	while waited < limit:
		await get_tree().create_timer(2.0).timeout
		waited += 2.0
		var done := true
		for racer in session.racers:
			if racer.is_player:
				continue
			if racer.cp_count < 3:
				done = false
		if done:
			break
	var counts: Array[String] = []
	var passed := true
	for racer in session.racers:
		if racer.is_player:
			continue
		counts.append("%s %d" % [racer.name, racer.cp_count])
		if racer.cp_count < 3:
			passed = false
	_expect(passed, "every rival passed cp1 and cp2 (%s)" % str(counts))


## A hit between two rivals over the limit.
func _on_collision(_vehicle: VehicleBase, other: Node3D, impulse: float, _point: Vector3,
		_normal: Vector3) -> void:
	if impulse < CONTACT_LIMIT:
		return
	if other is VehicleBase and (other as VehicleBase).team == VehicleBase.Team.RIVAL:
		_contacts += 1
		if _contacts < 8:
			print("CONTACT %s x %s impulse %.0f at %s" % [_vehicle.display_name,
				(other as VehicleBase).display_name, impulse, str(_point.snapped(Vector3(1,1,1)))])


## The value of a command line option of the test.
func _option(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

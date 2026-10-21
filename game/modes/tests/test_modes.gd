extends Node
## The modes: the switch between free roam, race and pursuit, the free-roam score, the records
## and the robustness of `start_mode`.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const TEST_RECORDS := "user://test_records.cfg"

var _failures: int = 0
var _modes: ModeDirector = null


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	await _test_free()
	await _test_race()
	await _test_pursuit()
	await _test_records()
	await _test_robustness()
	print("MODE TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Free roam: the score comes from the stunts, the near misses and the takedowns.
func _test_free() -> void:
	_expect(_modes.start_mode(&"free", {}), "free roam starts")
	_expect(Game.mode == &"free", "the game mode is free")
	var session := _modes.session as FreeSession
	_expect(session != null, "the free session exists")
	Events.stunt.emit(&"fly_over_gas", 800, "飞跃加油站!")
	Events.near_miss.emit(Game.player, Game.player)
	Events.takedown.emit(Game.player, &"police")
	await get_tree().process_frame
	_expect(session.score == 855, "the score counts the stunt, the pass and the takedown (%d)" % session.score)
	_expect(session.stunts == 1 and session.near_misses == 1 and session.takedowns == 1,
		"the free session counts the events")
	_expect(session.streak == 1, "the takedown starts a streak (%d)" % session.streak)


## A race: the gates, the grid and the countdown.
func _test_race() -> void:
	_expect(_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 2}), "the race starts")
	_expect(Game.mode == &"race", "the game mode is race")
	var session := _modes.session as RaceSession
	_expect(session != null, "the race session exists")
	_expect(session.gates.size() == 8, "the route has 8 checkpoint gates (%d)" % session.gates.size())
	_expect(session.racers.size() == 6, "the race has 6 racers (%d)" % session.racers.size())
	_expect(session.state == RaceSession.State.COUNTDOWN, "the race waits for the countdown")
	_expect(Game.player.freeze, "the player waits on the grid")
	var standings := _modes.standings()
	_expect(standings.size() == 6, "the standings hold every racer (%d)" % standings.size())


## A pursuit: the session of the police chase.
func _test_pursuit() -> void:
	_expect(_modes.start_mode(&"pursuit", {}), "the pursuit starts")
	_expect(_modes.session is PursuitSession, "the pursuit session exists")


## The records: the best time, the best lap and the high score (in the test file).
func _test_records() -> void:
	var records := GameRecords.new(TEST_RECORDS)
	records.load_from_disk()
	_expect(records.record_time("test_route", 120.0), "a time is a new record")
	_expect(not records.record_time("test_route", 130.0), "a slower time is no record")
	_expect(records.record_time("test_route", 110.0), "a faster time is a new record")
	_expect(absf(records.best_time("test_route") - 110.0) < 0.001, "the best time is kept")
	_expect(records.record_lap("test_route", 30.0), "a lap is a new record")
	_expect(absf(records.best_lap("test_route") - 30.0) < 0.001, "the best lap is kept")
	_expect(records.record_score(500.0), "a score is a new record")
	_expect(not records.record_score(400.0), "a lower score is no record")
	_expect(records.best_score() == 500.0, "the high score is kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_RECORDS))


## `start_mode` must not break the game when it is given something it cannot run.
func _test_robustness() -> void:
	_modes.start_mode(&"free", {})
	var session := _modes.session
	_expect(not _modes.start_mode(&"nonsense", {}), "an unknown mode is refused")
	_expect(Game.mode == &"free", "an unknown mode leaves the game mode alone")
	_expect(_modes.session == session, "an unknown mode leaves the session alone")
	_expect(_modes.start_mode(&"race", {"route": "no_such_route_at_all"}),
		"a race with an unknown route falls back to the first route")
	_expect(_modes.session != null, "the race with a fallback route still starts")


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

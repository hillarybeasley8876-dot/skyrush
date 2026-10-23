extends Node
## The hygiene of the modes: the new record of a race, the police that stop when a pursuit is
## won and the police that go away when a mode is left.
##
## The test drives the modes the way the game does: the sandbox world, the player, the rival
## director, the police dispatcher and the director of the modes.
##
## Run: python tools/gd.py test res://modes/tests/test_hygiene.gd

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const POLICE_DIRECTOR := "res://ai/police/police_director.tscn"
const RESULTS_SCREEN := preload("res://ui/menu/screens/results_screen.gd")
## The records of the test (the player's own file is never touched).
const TEST_RECORDS := "user://test_records_hygiene.cfg"
## The route of the sandbox.
const ROUTE_ID := "sandbox_loop"

var _failures: int = 0
var _modes: ModeDirector = null
var _police: Node = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_records()
	_build_world()
	await get_tree().process_frame
	await _test_new_record()
	await _test_results_screen()
	await _test_pursuit_won()
	await _test_leaving_pursuit()
	_remove_test_records()
	if _failures == 0:
		print("MODE HYGIENE TESTS OK (%d failures)" % _failures)
	else:
		print("MODE HYGIENE TESTS FAILED (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The sandbox, the player, the rivals, the police and the director of the modes.
func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_police = (load(POLICE_DIRECTOR) as PackedScene).instantiate()
	add_child(_police)
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)


## The record of a race: the time of the player is a record when it beats the stored one.
func _test_new_record() -> void:
	var records := GameRecords.new(TEST_RECORDS)
	records.load_from_disk()
	records.record_time(ROUTE_ID, 100.0)
	# A race that is slower than the record.
	var slow := _start_race(records)
	_finish_player(slow, 120.0)
	_expect(not _is_new_record(slow), "a time that does not beat the record is no record")
	# A race that beats the record.
	var fast := _start_race(records)
	_finish_player(fast, 90.0)
	_expect(_is_new_record(fast), "a time that beats the record is a new record")
	_expect(_player_row_is_record(_results_of(fast)),
			"the row of the player in the results carries the new record")


## The results screen: the new record of the payload is shown.
func _test_results_screen() -> void:
	var screen := RESULTS_SCREEN.new()
	add_child(screen)
	screen.payload = _race_payload(true)
	screen.on_enter()
	_expect(screen.record_label.text.contains("NEW RECORD"),
			"the results screen shows NEW RECORD (%s)" % screen.record_label.text)
	screen.payload = _race_payload(false)
	screen.on_enter()
	_expect(not screen.record_label.text.contains("NEW RECORD"),
			"the results screen does not show NEW RECORD without a record (%s)"
			% screen.record_label.text)
	screen.queue_free()


## A pursuit that is won stops the police.
func _test_pursuit_won() -> void:
	_modes.start_mode(&"pursuit", {"goal": "takedowns", "count": 1, "time": 60.0})
	await get_tree().process_frame
	var session := _modes.session
	_expect(session != null, "the pursuit session exists")
	_expect(_pursuit_heat() > 0, "the chase is running (%d)" % _pursuit_heat())
	# The player drives on: a car that stands still is busted by the police before the test is
	# over, and then the pursuit ends by itself.
	Game.player.linear_velocity = Vector3(0.0, 0.0, -10.0)
	var has_unit := await _wait_for_unit(3.0)
	_expect(has_unit, "a police unit is on the road")
	var units_before := _unit_count()
	Events.takedown.emit(Game.player, &"police")
	# The units are counted right away: the police put their patrols on the road again in the
	# next tick, and that is the free roam, not the chase.
	var units_after := _unit_count()
	var heat_after := _pursuit_heat()
	var over_after := _pursuit_is_over()
	await get_tree().process_frame
	var result: Variant = session.get("result") if session != null else -1
	_expect(result == PursuitSession.Result.SUCCESS,
			"the pursuit is won (result %s)" % str(result))
	_expect(heat_after == 0, "the heat is gone after the win (%d)" % heat_after)
	_expect(over_after, "the pursuit is over after the win")
	_expect(units_after == 0, "no police unit is left after the win (%d of %d)"
			% [units_after, units_before])
	# The chase does not go on in the background.
	await get_tree().create_timer(0.5).timeout
	_expect(_pursuit_heat() == 0, "the heat stays gone after the win (%d)" % _pursuit_heat())
	_expect(_pursuit_is_over(), "the pursuit stays over after the win")


## Leaving the pursuit leaves no chase behind.
func _test_leaving_pursuit() -> void:
	_modes.start_mode(&"pursuit", {"goal": "escape", "time": 60.0})
	await get_tree().process_frame
	_expect(_pursuit_heat() > 0, "the chase is running again (%d)" % _pursuit_heat())
	_modes.start_mode(&"free", {})
	# The units are counted right away: the police put their patrols on the road again in the
	# next tick, and that is the free roam, not the chase.
	var units_after := _unit_count()
	var heat_after := _pursuit_heat()
	var over_after := _pursuit_is_over()
	await get_tree().process_frame
	_expect(heat_after == 0, "the heat is gone after leaving the mode (%d)" % heat_after)
	_expect(over_after, "the pursuit is over after leaving the mode")
	_expect(units_after == 0, "no police unit is left after leaving the mode (%d)"
			% units_after)
	_expect(bool(_police.get("spawn_enabled")), "the police can spawn again")


## --- helpers --------------------------------------------------------------------------------------

## Starts a race and gives the session the records of the test.
func _start_race(records: GameRecords) -> Node:
	_modes.start_mode(&"race", {"route": ROUTE_ID, "laps": 2})
	var session := _modes.session
	if session != null:
		session.set("records", records)
	return session


## The player comes home with the given time.
func _finish_player(session: Node, time: float) -> void:
	if session == null:
		return
	session.set("elapsed", time)
	var racers: Array = session.get("racers")
	for racer: RaceRacer in racers:
		if racer.is_player:
			session.call("_finish_racer", racer)
			return


## True when the session reports a new record (the old session has no such report).
func _is_new_record(session: Node) -> bool:
	if session == null or not session.has_method("is_new_record"):
		return false
	return bool(session.call("is_new_record"))


## The results of a race.
func _results_of(session: Node) -> Array:
	if session == null:
		return []
	var results: Variant = session.call("build_results")
	return results if results is Array else []


## True when the row of the player in the results carries the new record.
func _player_row_is_record(rows: Array) -> bool:
	for entry: Dictionary in rows:
		if bool(entry.get("is_player", false)):
			return bool(entry.get("new_record", false))
	return false


## A race payload for the results screen (the best time is the time of the player).
func _race_payload(new_record: bool) -> Dictionary:
	return {
		"kind": "race",
		"results": [{"name": "Roadster", "time": 90.0, "position": 1, "is_player": true,
			"finished": true, "new_record": new_record}],
		"route": ROUTE_ID,
		"route_title": "测试环线",
		"best_time": 90.0,
		"best_lap": 30.0,
		"new_record": new_record,
	}


## The pursuit of the police dispatcher.
func _pursuit() -> RefCounted:
	if _police == null:
		return null
	return _police.get("pursuit") as RefCounted


## The heat of the pursuit (-1 when there is no pursuit).
func _pursuit_heat() -> int:
	var pursuit := _pursuit()
	if pursuit == null:
		return -1
	return int(pursuit.get("heat"))


## True when the pursuit is over.
func _pursuit_is_over() -> bool:
	var pursuit := _pursuit()
	if pursuit == null or not pursuit.has_method("is_over"):
		return false
	return bool(pursuit.call("is_over"))


## The police units on the road (-1 when there is no dispatcher).
func _unit_count() -> int:
	if _police == null:
		return -1
	var units: Variant = _police.get("units")
	if not (units is Array):
		return -1
	return (units as Array).size()


## Waits until a police unit is on the road (false when the time is up).
func _wait_for_unit(seconds: float) -> bool:
	var frames := int(seconds * 60.0)
	for i in frames:
		if _unit_count() > 0:
			return true
		await get_tree().physics_frame
	return false


## The records file of the test is gone.
func _remove_test_records() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_RECORDS))


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

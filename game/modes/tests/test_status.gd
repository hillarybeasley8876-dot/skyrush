extends Node
## The status of the running mode for the HUD (the contract of `Events.mode_status`).
##
## The test drives the modes the way the game does: the sandbox world, the player, the rival
## director and the director of the modes. Every status of the bus is collected and looked at.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"

var _failures: int = 0
var _modes: ModeDirector = null
## Every status of the bus: [kind, data].
var _records: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_world()
	Events.mode_status.connect(_on_mode_status)
	await _test_free()
	await _test_race()
	await _test_pursuit()
	await _test_none()
	if _failures == 0:
		print("MODE STATUS TESTS OK (0 failures)")
	else:
		print("MODE STATUS TESTS FAILED (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The sandbox, the player, the rivals and the director of the modes.
func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)


## Free roam: the score of the run reaches the HUD.
func _test_free() -> void:
	_records.clear()
	_modes.start_mode(&"free", {})
	await get_tree().create_timer(0.2).timeout
	_expect(_has(&"free", "score", 0), "the free roam reports a score of 0")
	Events.stunt.emit(&"test", 500, "t")
	await get_tree().create_timer(0.2).timeout
	_expect(_has(&"free", "score", 500), "the free roam reports the score of a stunt")
	var before := _count(&"free")
	await get_tree().create_timer(1.3).timeout
	_expect(_count(&"free") - before >= 2,
		"the free roam reports itself every half second (%d in 1.3 s)" % (_count(&"free") - before))
	_expect(_count(&"free") >= 3, "the free roam keeps reporting itself (%d records)" % _count(&"free"))


## A race: the lap of the player, the laps of this race, the place of the player and the field.
func _test_race() -> void:
	_records.clear()
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 3})
	await get_tree().create_timer(1.0).timeout
	var data := _last_of(&"race")
	_expect(int(data.get("laps", 0)) == 3, "the race reports the 3 laps of this race (%s)" % str(data))
	_expect(int(data.get("lap", 0)) == 1, "the player is on the first lap (%s)" % str(data))
	_expect(int(data.get("racers", 0)) == 6, "the race reports the 6 racers (%s)" % str(data))
	var position := int(data.get("position", 0))
	_expect(position >= 1 and position <= 6,
		"the place of the player is between 1 and 6 (%d)" % position)


## A pursuit: the takedowns, the goal and the clock.
func _test_pursuit() -> void:
	_records.clear()
	_modes.start_mode(&"pursuit", {"goal": "takedowns", "count": 3, "time": 60})
	await get_tree().create_timer(0.2).timeout
	var data := _last_of(&"pursuit")
	_expect(int(data.get("target", -1)) == 3, "the pursuit reports the goal of 3 takedowns (%s)" % str(data))
	_expect(int(data.get("takedowns", -1)) == 0, "the pursuit starts without a takedown (%s)" % str(data))
	var left := float(data.get("time_left", 0.0))
	_expect(left >= 55.0 and left <= 60.0, "the pursuit has about a minute left (%.1f)" % left)
	await get_tree().create_timer(1.2).timeout
	var later := float(_last_of(&"pursuit").get("time_left", 0.0))
	_expect(later < left, "the clock of the pursuit runs down (%.1f -> %.1f)" % [left, later])
	Events.takedown.emit(Game.player, &"police")
	await get_tree().create_timer(0.2).timeout
	_expect(_has(&"pursuit", "takedowns", 1), "the pursuit reports the takedown")
	# A pursuit without a time has no clock.
	_records.clear()
	_modes.start_mode(&"pursuit", {"goal": "takedowns", "count": 3})
	await get_tree().create_timer(0.2).timeout
	var endless := float(_last_of(&"pursuit").get("time_left", 0.0))
	_expect(endless == -1.0, "a pursuit without a time has no clock (%.1f)" % endless)


## The end of a mode: the HUD is told that there is nothing to show.
func _test_none() -> void:
	_records.clear()
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1})
	await get_tree().create_timer(0.3).timeout
	_modes.start_mode(&"free", {})
	await get_tree().create_timer(0.3).timeout
	_expect(_count(&"none") >= 1, "the end of a mode is reported")
	var none_at := _last_index_of(&"none")
	var after := 0
	for i in range(none_at + 1, _records.size()):
		if _records[i][0] == &"race":
			after += 1
	_expect(after == 0, "the old mode reports nothing after the end (%d records)" % after)


## The bus: every status is collected.
func _on_mode_status(kind: StringName, data: Dictionary) -> void:
	_records.append([kind, data])


## The data of the last status of a kind (empty when there is none).
func _last_of(kind: StringName) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		if _records[i][0] == kind:
			return _records[i][1] as Dictionary
	return {}


## True when a status of the kind carries the key with the value.
func _has(kind: StringName, key: String, value: Variant) -> bool:
	for record in _records:
		if record[0] != kind:
			continue
		var data: Dictionary = record[1]
		if data.has(key) and data[key] == value:
			return true
	return false


## The number of the statuses of a kind.
func _count(kind: StringName) -> int:
	var total := 0
	for record in _records:
		if record[0] == kind:
			total += 1
	return total


## The place of the last status of a kind (-1 when there is none).
func _last_index_of(kind: StringName) -> int:
	for i in range(_records.size() - 1, -1, -1):
		if _records[i][0] == kind:
			return i
	return -1


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

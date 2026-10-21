class_name GameRecords
extends RefCounted
## The records of the game: the best race time and the best lap per route, and the free-roam
## high score. They live in `user://records.cfg`.
##
## The menu keeps its own file (`user://skyrush_menu.cfg`) for the front-end preferences; the
## records of the modes unit are the ones the gameplay writes. The menu can read them through
## `ModeDirector.records`.

const PATH := "user://records.cfg"
const SECTION_TIMES := "times"
const SECTION_LAPS := "laps"
const SECTION_SCORES := "scores"

## The file the records live in (the tests use their own file).
var path: String = PATH

## The best total race time per route id (seconds).
var times: Dictionary = {}
## The best single lap per route id (seconds).
var laps: Dictionary = {}
## The free-roam high score.
var score: float = 0.0


## The records of a file (the tests use their own file, so the player's is untouched).
func _init(file_path: String = PATH) -> void:
	path = file_path


## Reads the file (a missing file is not an error).
func load_from_disk() -> void:
	times.clear()
	laps.clear()
	score = 0.0
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if cfg.has_section(SECTION_TIMES):
		for key: String in cfg.get_section_keys(SECTION_TIMES):
			times[key] = float(cfg.get_value(SECTION_TIMES, key, 0.0))
	if cfg.has_section(SECTION_LAPS):
		for key: String in cfg.get_section_keys(SECTION_LAPS):
			laps[key] = float(cfg.get_value(SECTION_LAPS, key, 0.0))
	if cfg.has_section(SECTION_SCORES):
		score = float(cfg.get_value(SECTION_SCORES, "best_score", 0.0))


## Writes the file.
func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for key: String in times:
		cfg.set_value(SECTION_TIMES, key, float(times[key]))
	for key: String in laps:
		cfg.set_value(SECTION_LAPS, key, float(laps[key]))
	cfg.set_value(SECTION_SCORES, "best_score", score)
	var err := cfg.save(path)
	if err != OK:
		push_warning("[modes] could not save %s (error %d)" % [path, err])


## The best race time of a route in seconds, or -1.0 when the route was never finished.
func best_time(route_id: String) -> float:
	return float(times.get(route_id, -1.0))


## The best lap of a route in seconds, or -1.0.
func best_lap(route_id: String) -> float:
	return float(laps.get(route_id, -1.0))


## The free-roam high score.
func best_score() -> float:
	return score


## Stores a race time when it beats the record. Returns true on a new record.
func record_time(route_id: String, seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	var previous := best_time(route_id)
	if previous >= 0.0 and previous <= seconds:
		return false
	times[route_id] = seconds
	save_to_disk()
	return true


## Stores a lap time when it beats the record. Returns true on a new record.
func record_lap(route_id: String, seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	var previous := best_lap(route_id)
	if previous >= 0.0 and previous <= seconds:
		return false
	laps[route_id] = seconds
	save_to_disk()
	return true


## Stores the free-roam score when it beats the record. Returns true on a new record.
func record_score(value: float) -> bool:
	if value <= score:
		return false
	score = value
	save_to_disk()
	return true

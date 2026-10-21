extends RefCounted
## The front-end preferences of the menu: the last race setup, the rain and the motion blur.
##
## The records of the game (the best times, the high score) belong to the modes unit
## (`GameRecords` in `user://records.cfg`); the menu only reads them through the results router,
## so there is one owner for the scores.

const PATH := "user://skyrush_menu.cfg"

## The file the preferences are read from and written to.
var path: String = PATH

## The id of the route of the last race.
var last_route: String = ""
## The difficulty of the last race: "easy" | "normal" | "hard".
var difficulty: String = "normal"
## The laps of the last race.
var laps: int = 2
## The rain toggle of the last session.
var rain: bool = true
## The motion blur toggle of the last session.
var motion_blur: bool = true
## The goal of the last pursuit: "escape" | "takedowns".
var pursuit_goal: String = "escape"
## The number of police cars to take down in the last pursuit.
var pursuit_count: int = 3
## The heat the last pursuit started at.
var pursuit_heat: int = 3


## The preferences of a file (the tests use their own file, so the player's is never touched).
func _init(file_path: String = "") -> void:
	path = file_path if not file_path.is_empty() else PATH


func load_from_disk() -> void:
	if _read_only():
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	last_route = String(cfg.get_value("race", "route", ""))
	difficulty = String(cfg.get_value("race", "difficulty", "normal"))
	laps = int(cfg.get_value("race", "laps", 2))
	rain = bool(cfg.get_value("video", "rain", true))
	motion_blur = bool(cfg.get_value("video", "motion_blur", true))
	pursuit_goal = String(cfg.get_value("pursuit", "goal", "escape"))
	pursuit_count = int(cfg.get_value("pursuit", "count", 3))
	pursuit_heat = int(cfg.get_value("pursuit", "heat", 3))


func save_to_disk() -> void:
	if _read_only():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("race", "route", last_route)
	cfg.set_value("race", "difficulty", difficulty)
	cfg.set_value("race", "laps", laps)
	cfg.set_value("video", "rain", rain)
	cfg.set_value("video", "motion_blur", motion_blur)
	cfg.set_value("pursuit", "goal", pursuit_goal)
	cfg.set_value("pursuit", "count", pursuit_count)
	cfg.set_value("pursuit", "heat", pursuit_heat)
	var err := cfg.save(path)
	if err != OK:
		push_warning("menu: could not save %s (error %d)" % [path, err])


## A run with --quality=... (every tools/godot.sh run) neither reads nor writes the player's
## file, so a dev run and a test never touch the saved state of the player.
func _read_only() -> bool:
	return Game.has_option("quality")


## "1:23.45" for a duration in seconds; "--:--.--" when there is no time.
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.--"
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes * 60)
	return "%d:%05.2f" % [minutes, rest]

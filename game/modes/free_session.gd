class_name FreeSession
extends Node
## Free roam (the default mode): the city, the traffic, the police and the score.
##
## The score comes from the stunts (Events.stunt), the near misses (Events.near_miss) and the
## takedowns (Events.takedown) of the player. The high score goes into the records.

const NEAR_MISS_POINTS := 5
const TAKEDOWN_POINTS := 50
const STREAK_BONUS := 25
const STREAK_WINDOW := 10.0
const WRECK_PENALTY := 25

## The mode is over (the player asked for the results).
signal finished(results: Dictionary)

## The score of the run.
var score: int = 0
## The number of stunts the player pulled off.
var stunts: int = 0
## The number of near misses.
var near_misses: int = 0
## The number of cars the player wrecked.
var wrecks: int = 0
## The number of cars the player took down.
var takedowns: int = 0
## The number of takedowns in a row (the streak of dossier 3.5).
var streak: int = 0
## The time the run lasted (s).
var elapsed: float = 0.0

var records: GameRecords = null
var _player: VehicleBase = null
var _streak_timer: float = 0.0


## Starts the mode.
func setup(new_records: GameRecords) -> void:
	records = new_records
	score = 0
	streak = 0
	stunts = 0
	near_misses = 0
	wrecks = 0
	takedowns = 0
	elapsed = 0.0
	_player = Game.player
	Events.stunt.connect(_on_stunt)
	Events.near_miss.connect(_on_near_miss)
	Events.takedown.connect(_on_takedown)
	Events.vehicle_wrecked.connect(_on_wrecked)
	Events.toast.emit("自由漫游 FREE ROAM", &"info")


## A stunt: the points come with the event.
func _on_stunt(_kind: StringName, points: int, _label: String) -> void:
	if _player == null:
		return
	stunts += 1
	_add_score(points)


## A near miss: five points.
func _on_near_miss(vehicle: VehicleBase, _other: VehicleBase) -> void:
	if vehicle != _player:
		return
	near_misses += 1
	_add_score(NEAR_MISS_POINTS)


## A takedown: fifty points and a streak (dossier 3.5: the streak window is 10 s).
func _on_takedown(_victim: VehicleBase, kind: StringName) -> void:
	if kind != &"police" and kind != &"rival" and kind != &"traffic":
		return
	takedowns += 1
	_add_score(TAKEDOWN_POINTS + STREAK_BONUS * streak)
	streak += 1
	_streak_timer = STREAK_WINDOW


## The streak ends when the window is over.
func _process(delta: float) -> void:
	elapsed += delta
	if _streak_timer > 0.0:
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			streak = 0


## Adds points and stores the high score as soon as it is beaten.
func _add_score(points: int) -> void:
	score += points
	if records != null and float(score) > records.best_score():
		records.record_score(float(score))


## A wrecked car: the player loses points.
func _on_wrecked(vehicle: VehicleBase, _source: Node3D) -> void:
	if vehicle != _player:
		return
	wrecks += 1
	score = maxi(0, score - WRECK_PENALTY)


## The result of the run (the menu shows it on the results screen).
func build_results() -> Dictionary:
	return {
		"kind": "free",
		"score": score,
		"stunts": stunts,
		"near_misses": near_misses,
		"wrecks": wrecks,
		"takedowns": takedowns,
		"time": elapsed,
		"best_score": records.best_score() if records != null else 0.0,
	}

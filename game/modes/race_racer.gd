class_name RaceRacer
extends RefCounted
## One entry of the race: the player or a rival. The session keeps the progress of every
## racer, so the order, the laps and the results come from one place.

## The car.
var vehicle: VehicleBase = null
## The display name (the player's name or the handle of the rival).
var name: String = ""
## True for the player.
var is_player: bool = false
## The laps the racer has completed.
var lap: int = 0
## The checkpoint the racer has to pass next.
var next_cp: int = 0
## The checkpoint the racer started behind: the lap ends when it comes back to it.
var start_cp: int = 0
## True once the racer has passed its start checkpoint.
var passed_start: bool = false
## The checkpoints the racer has passed in this race.
var cp_count: int = 0
## When the current lap started (the race clock).
var lap_start: float = 0.0
## The best lap of the race (-1 when there is none yet).
var best_lap: float = -1.0
## When the racer crossed the line (-1 when it has not).
var finish_time: float = -1.0
## The position in the race (1 = the leader).
var position: int = 0
## The distance along the racing line (m).
var progress: float = 0.0
## The (time, progress) samples of the last SPEED_WINDOW seconds.
var samples: Array[Vector2] = []


func _init(car: VehicleBase, display_name: String, player: bool) -> void:
	vehicle = car
	name = display_name
	is_player = player


## True when the racer has crossed the line.
func is_finished() -> bool:
	return finish_time >= 0.0


## Stores a sample of the progress (the average speed is worked out from the last samples).
func push_sample(time: float, progress: float) -> void:
	samples.append(Vector2(time, progress))
	while samples.size() > 2 and samples[0].x < time - RaceResults.SPEED_WINDOW:
		samples.remove_at(0)


## The average speed of the racer over the last SPEED_WINDOW seconds (m/s).
func average_speed() -> float:
	if samples.size() < 2:
		return 0.0
	var first := samples[0]
	var last := samples[samples.size() - 1]
	var span := last.x - first.x
	if span <= 0.01:
		return 0.0
	return maxf(0.0, (last.y - first.y) / span)

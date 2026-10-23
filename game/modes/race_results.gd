class_name RaceResults
extends RefCounted
## The order of a race and the results it hands to the bus (the contract of `Events.race_finished`).
##
## The results of a racer that did not come home are estimated: the distance it still has to
## drive (to the last gate on a sprint, the laps it has left plus the rest of the lap on a
## circuit) divided by the average speed it held over the last ten seconds.

const SPEED_WINDOW := 10.0       ## s: the window the average speed of a racer is worked out over
const MIN_AVERAGE_SPEED := 5.0   ## m/s: the floor of the average speed in an estimate
const LINE_EPS := 1.0            ## m: a line shorter than this has no length to divide by

## The racers of the race.
var racers: Array[RaceRacer] = []
## The race clock.
var elapsed: float = 0.0
## The number of laps of the race.
var laps: int = 1
## True when the route is a sprint (one lap, the race ends at the last gate).
var sprint: bool = false
## The length of the racing line (m).
var line_length: float = 0.0
## The offset of every gate of the route on the racing line (m).
var gate_offsets: PackedFloat32Array = PackedFloat32Array()
## True when the time of the player is a new record.
var new_record: bool = false


## The racers, the finished ones first and then by the distance covered.
func order() -> Array[RaceRacer]:
	var out: Array[RaceRacer] = []
	out.append_array(racers)
	out.sort_custom(_compare)
	return out


## Writes the position of every racer.
func assign_positions() -> void:
	var sorted := order()
	for i in sorted.size():
		sorted[i].position = i + 1


## The sort: the finish time, then the checkpoints, then the distance on the racing line.
func _compare(a: RaceRacer, b: RaceRacer) -> bool:
	if a.is_finished() != b.is_finished():
		return a.is_finished()
	if a.is_finished() and b.is_finished():
		return a.finish_time < b.finish_time
	if a.cp_count != b.cp_count:
		return a.cp_count > b.cp_count
	return a.progress > b.progress


## The results of the race: one row per racer, in the order of the finish.
func build() -> Array:
	var out: Array = []
	var leader := _leader_time()
	for racer in order():
		var finished := racer.is_finished()
		var estimate := estimated_gap(racer)
		var time := racer.finish_time if finished else elapsed + estimate
		var row := {
			"name": racer.name,
			"time": time,
			"position": racer.position,
			"is_player": racer.is_player,
			"finished": finished,
			"best_lap": racer.best_lap,
			"gap": maxf(0.0, time - leader),
		}
		if racer.is_player:
			# Only the row of the player carries the flag: the record is his time.
			row["new_record"] = new_record
		out.append(row)
	return out


## The time of the leader of the race (the race clock when nobody has come home yet).
func _leader_time() -> float:
	for racer in racers:
		if racer.is_finished():
			return racer.finish_time
	return elapsed


## The time gap of a racer to the leader (the live order of the race).
func gap_to_leader(racer: RaceRacer) -> float:
	if racer == null:
		return 0.0
	var leader := _leader_progress()
	var behind := leader - racer.progress
	if behind <= 0.0:
		return 0.0
	return behind / maxf(racer.average_speed(), MIN_AVERAGE_SPEED)


## The distance the leader has covered (the biggest progress of the field).
func _leader_progress() -> float:
	var best := 0.0
	for racer in racers:
		best = maxf(best, racer.progress)
	return best


## The time a racer that is still on the road would need to come home.
func estimated_gap(racer: RaceRacer) -> float:
	var remaining := remaining_distance(racer)
	if remaining <= 0.0:
		return 0.0
	return remaining / maxf(racer.average_speed(), MIN_AVERAGE_SPEED)


## The distance a racer still has to drive to come home (m).
##
## A sprint ends at the last gate of the route; a circuit ends after the laps that are left plus
## the rest of the lap the racer is on.
func remaining_distance(racer: RaceRacer) -> float:
	if sprint:
		return _remaining_to_last_gate(racer)
	if line_length <= LINE_EPS:
		return 0.0
	var laps_left := maxi(0, laps - racer.lap)
	var rest_of_lap := line_length - fposmod(racer.progress, line_length)
	return float(laps_left) * line_length + rest_of_lap


## The distance to the last gate of a sprint (m).
func _remaining_to_last_gate(racer: RaceRacer) -> float:
	if gate_offsets.is_empty():
		return 0.0
	var last := gate_offsets[gate_offsets.size() - 1]
	var remaining := last - racer.progress
	if remaining < 0.0:
		remaining += line_length
	return maxf(0.0, remaining)

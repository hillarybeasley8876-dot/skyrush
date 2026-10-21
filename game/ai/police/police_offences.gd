class_name PoliceOffences
extends RefCounted
## The offences that start a pursuit (ref/gameplay/DOSSIER.md §3.4).
##
## Exactly four offences count:
##   &"toll_evaded" - the player flies through a toll plaza without paying (the world unit sees it)
##   &"speeding"    - the player is caught above 160 km/h while a patrol has line of sight
##   &"hit_police"  - the player hits a police car
##   &"hit_traffic" - the player hits a traffic car while a patrol sees it
##
## Every offence is edge triggered: it is reported once, not once per frame. Nothing counts
## within the grace after the player appears (spawn, respawn or a new car).

## The speed above which the player is speeding (km/h).
const SPEEDING_KMH := 160.0
## The seconds after the player appears in which no offence counts.
const SPAWN_GRACE := 10.0
## The pause between two offences of the same kind (s).
const OFFENCE_COOLDOWN := 1.0

## The number of offences the police reported (the tests and the HUD read it).
var reported: int = 0
## The number of offences of every kind.
var reported_kinds: Dictionary = {}
## The seconds left of the grace.
var grace: float = SPAWN_GRACE
## The time of the last report of every kind.
var _last: Dictionary = {}
## The tick clock of the offences (the wall clock would change the cooldown in slow motion).
var _clock: float = 0.0


## The player appeared (spawn, respawn or a new car): the grace starts again.
func on_player_appeared() -> void:
	grace = SPAWN_GRACE
	_last.clear()


## The tick of the grace. Returns true when an offence may count.
func tick(delta: float) -> bool:
	_clock += delta
	grace = maxf(grace - delta, 0.0)
	return grace <= 0.0


## True when the grace is over.
func can_count() -> bool:
	return grace <= 0.0


## Reports an offence once: the second report of the same kind inside the cooldown is ignored.
func report(kind: StringName) -> bool:
	if _clock - float(_last.get(kind, -99.0)) < OFFENCE_COOLDOWN:
		return false
	_last[kind] = _clock
	reported += 1
	reported_kinds[kind] = int(reported_kinds.get(kind, 0)) + 1
	return true

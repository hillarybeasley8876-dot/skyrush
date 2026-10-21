class_name PoliceHeat
extends RefCounted
## The heat table of the police pursuit and the rules that move the heat up
## (ref/gameplay/DOSSIER.md §3.1 and §3.4).
##
## Heat 0 means "no pursuit". The heat only rises while a pursuit runs and never falls inside a
## pursuit: it is reset when the player escapes or is busted.

## The number of police units that may be engaged at heat 0..5.
const UNITS_MAX: Array[int] = [0, 3, 5, 7, 9, 12]
## Seconds until a replacement unit arrives when every unit is gone.
const BACKUP: Array[float] = [0.0, 60.0, 50.0, 45.0, 40.0, 35.0]
## Seconds the evade bar needs to fill at heat 0..5.
const COOLDOWN: Array[float] = [0.0, 20.0, 35.0, 50.0, 70.0, 90.0]
## The pursuit seconds that raise the heat to 1..5. Heat 1 is never reached by the clock: it is
## the first offence that starts the pursuit.
const TIME_STEPS: Array[float] = [0.0, INF, 60.0, 120.0, 200.0, 300.0]
## The number of disabled police cars that raises the heat to 1..5.
const DISABLED_STEPS: Array[int] = [0, 999999, 2, 5, 9, 14]
## The offence kinds that start a pursuit at heat 1 (§3.4).
const OFFENCES: Array[StringName] = [
	&"toll_evaded", &"speeding", &"hit_police", &"hit_traffic",
]
## The first heat level.
const MIN_HEAT := 1
## The highest heat level.
const MAX_HEAT := 5


## The number of units that may be engaged at `heat`.
static func units_max(heat: int) -> int:
	return UNITS_MAX[clampi(heat, 0, MAX_HEAT)]


## The seconds until a backup unit arrives at `heat`.
static func backup_time(heat: int) -> float:
	return BACKUP[clampi(heat, 0, MAX_HEAT)]


## The seconds the evade bar needs at `heat`.
static func cooldown_time(heat: int) -> float:
	return COOLDOWN[clampi(heat, 0, MAX_HEAT)]


## The heat the pursuit time alone asks for.
static func heat_for_time(seconds: float) -> int:
	var heat := 0
	for level in range(MIN_HEAT, MAX_HEAT + 1):
		if seconds >= TIME_STEPS[level]:
			heat = level
	return heat


## The heat the number of disabled police cars asks for.
static func heat_for_disabled(count: int) -> int:
	var heat := 0
	for level in range(MIN_HEAT, MAX_HEAT + 1):
		if count >= DISABLED_STEPS[level]:
			heat = level
	return heat


## The heat that the time and the disabled cars ask for together.
static func heat_for(pursuit_seconds: float, disabled: int) -> int:
	return maxi(heat_for_time(pursuit_seconds), heat_for_disabled(disabled))


## True when the offence kind starts or raises a pursuit.
static func is_offence(kind: StringName) -> bool:
	return OFFENCES.has(kind)


## Clamps a heat level to the legal range.
static func clamp_heat(heat: int) -> int:
	return clampi(heat, 0, MAX_HEAT)

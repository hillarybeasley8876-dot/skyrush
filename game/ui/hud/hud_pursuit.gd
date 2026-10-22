extends RefCounted
## The pursuit state (the evade / busted bar) and the race standings of the HUD. Kept apart from
## `hud.gd` so both stay small.
##
## The numbers are the dossier's (§3.2 / §3.4): a unit within BUSTED_RANGE fills the busted meter
## at a third per second below BUSTED_SPEED, and the evade bar shows the progress through the
## heat's cooldown.

## Police units on you per heat level (dossier §3.4).
const HEAT_UNITS: Array[int] = [3, 5, 7, 9, 12]
## The cooldown of each heat level, in seconds.
const HEAT_COOLDOWN: Array[float] = [20.0, 35.0, 50.0, 70.0, 90.0]
## A police unit this close fills the busted meter (dossier §3.2).
const BUSTED_RANGE := 12.0
## Two things are on the same level when their heights differ by at most this: a unit under a
## deck cannot bust the player on the deck above it (the same rule as the police module).
const BUSTED_LEVEL: float = PolicePursuit.LEVEL
## Below this speed the busted meter fills (dossier §3.2).
const BUSTED_SPEED := 15.0
## The busted meter fills at a third per second (dossier §3.2).
const BUSTED_RATE := 1.0 / 3.0
## The sort key of a car that was not in the previous standings.
const NO_PREVIOUS_ORDER := 9999

## The progress of the busted meter (0..1).
var busted: float = 0.0
## The progress through the cooldown (the evade bar, 0..1).
var evade: float = 0.0
## The number of police units on the player.
var units: int = 0
## The number of units the current heat allows.
var units_max: int = HEAT_UNITS[0]
## The standings of the race, sorted by progress.
var standings: Array[Dictionary] = []

var _busted: float = 0.0
var _cooldown: float = 0.0
## The previous position of every vehicle, so a tie keeps the order the cars already had.
var _previous_order: Dictionary[int, int] = {}


## Update the pursuit bar. t: the car's telemetry; heat: the current heat level; state: the
## pursuit state; police: the police positions on the map; player_pos: the player's position.
func update(t: CarTelemetry, heat: int, state: StringName, police: PackedVector3Array,
		player_pos: Vector3, delta: float) -> void:
	var heat_index := clampi(heat - 1, 0, HEAT_UNITS.size() - 1)
	units_max = HEAT_UNITS[heat_index]
	units = police.size()
	var close := 0
	for p in police:
		if absf(p.y - player_pos.y) > BUSTED_LEVEL:
			# The unit is on another level: no warning for a cop under a deck.
			continue
		if player_pos.distance_to(p) <= BUSTED_RANGE:
			close += 1
	if t.airborne or t.flying:
		_busted = maxf(_busted - delta, 0.0)
	elif t.speed_kmh < BUSTED_SPEED and close >= 1:
		_busted = minf(_busted + delta * BUSTED_RATE, 1.0)
	else:
		_busted = maxf(_busted - delta, 0.0)
	busted = _busted
	if state == &"search" or state == &"cooldown":
		_cooldown += delta
		evade = clampf(_cooldown / HEAT_COOLDOWN[heat_index], 0.0, 1.0)
	else:
		_cooldown = 0.0
		evade = 0.0


## Rebuild the standings of the race. progress: the checkpoint progress per vehicle;
## player: the player's vehicle; rivals: the rival vehicles.
func rebuild_standings(progress: Dictionary[int, int], player: VehicleBase,
		rivals: Array[VehicleBase]) -> void:
	standings.clear()
	if player != null:
		standings.append(_entry_for(player, progress))
	for v in rivals:
		standings.append(_entry_for(v, progress))
	standings.sort_custom(_sort_by_progress)
	# Remember the new order: a tie keeps the order the cars already had.
	_previous_order.clear()
	for i in standings.size():
		_previous_order[int(standings[i].get("id", 0))] = i


func _entry_for(vehicle: VehicleBase, progress: Dictionary[int, int]) -> Dictionary:
	var id := vehicle.get_instance_id()
	var name_text := vehicle.display_name
	if name_text.is_empty():
		name_text = "选手"
	return {
		"id": id,
		"name": name_text,
		"is_player": vehicle == Game.player,
		"progress": progress.get(id, 0),
		"prev": _previous_order.get(id, NO_PREVIOUS_ORDER),
	}


## Best progress first; on a tie the previous order decides (the player is not favoured).
func _sort_by_progress(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("progress", 0))
	var pb := int(b.get("progress", 0))
	if pa != pb:
		return pa > pb
	return int(a.get("prev", 0)) < int(b.get("prev", 0))

class_name PolicePursuit
extends RefCounted
## The state of the pursuit: the heat, the line of sight, the evade bar and the busted meter
## (ref/gameplay/DOSSIER.md §3.2, §3.4 and §3.5).
##
## The module owns the rules; the dispatcher owns the units and tells it what it sees.

const EVADE_DELAY := 4.0     ## s: the time without sight before the evade bar starts
const SEARCH_TIME := 2.0      ## s: the time the police search before the bar fills
const ENGAGE_MEMORY := 12.0   ## s: how long a unit keeps chasing after it lost the player
const BUST_SPEED := 15.0      ## km/h: below this the busted meter fills
const BUST_RANGE := 12.0      ## m: a unit this close counts
const BUST_FILL := 1.0 / 3.0  ## 1/s: the fill rate of the busted meter
const BUST_DRAIN := 1.0       ## 1/s: the drain rate
## The box: a player that is boxed and slower than this is busted twice as fast.
const BUST_BOX_SPEED := 40.0  ## km/h
const BUST_BOX_TIME := 2.0     ## s: the box has to hold for this long
const HIDE_RADIUS := 25.0      ## m: the radius of a hiding spot
## Two things are on the same level when their heights differ by at most this (the layers of
## the map: a street at y = 0 runs under the deck at y = 10). A cop under a deck cannot bust
## the player above it, and a hiding spot under a deck does not hide the player on the deck.
const LEVEL := 4.0             ## m: the height difference of one level
## The bounty of an escaped pursuit (dossier §3.5).
const BOUNTY_HEAT := 500.0     ## points per heat level
const BOUNTY_SECOND := 10.0    ## points per second of the pursuit
const BOUNTY_DISABLED := 250.0 ## points per disabled police car

## The heat of the pursuit (0 = free roam).
var heat: int = 0
## The state of the pursuit: &"none", &"chase", &"search", &"cooldown", &"escaped", &"busted".
var state: StringName = &"none"
## The evade bar (0..1).
var evade: float = 0.0
## The busted meter (0..1).
var busted: float = 0.0
## The seconds the pursuit has been running.
var pursuit_time: float = 0.0
## The number of police cars that were disabled in this pursuit.
var disabled: int = 0
## The seconds since a unit last saw the player.
var no_sight: float = 0.0
## True while a unit sees the player.
var seen_now: bool = false
## The seconds the police cannot see the player (the flash charge).
var sight_block: float = 0.0
## True while the player flies in a sky lane.
var player_flying: bool = false
## True while the player is in a hiding spot.
var in_hiding_spot: bool = false
## The hiding spots of the world.
var hiding_spots: Array[Vector3] = []
## The seconds the player has been boxed and slow (the ×2 rule of the box).
var box_time: float = 0.0


## Caches the hiding spots of the world.
func cache_hiding_spots(world: WorldBase) -> void:
	hiding_spots.clear()
	if world == null:
		return
	for poi in world.get_points_of_interest():
		if StringName(poi.get("kind", &"")) != &"hiding_spot":
			continue
		hiding_spots.append(poi.get("position", Vector3.ZERO))


## The heat only rises while a pursuit runs.
func update_heat(delta: float) -> void:
	if is_over():
		return
	pursuit_time += delta
	var wanted := PoliceHeat.heat_for(pursuit_time, disabled)
	if wanted > heat:
		set_heat(wanted)


## Sets the heat and tells the bus (and the radio) about it.
func set_heat(level: int) -> void:
	heat = PoliceHeat.clamp_heat(level)
	Events.heat_changed.emit(heat)
	match heat:
		2:
			PoliceRadio.say(&"backup")
		4:
			PoliceRadio.say(&"all_units")
		5:
			PoliceRadio.say(&"heavy")


## True when there is no pursuit running (free roam, escaped or busted).
func is_over() -> bool:
	return state == &"none" or state == &"escaped" or state == &"busted"


## True while a pursuit is running (the patrols react to the player then).
func is_active() -> bool:
	return not is_over()


## The line of sight: every 0.2 s a ray from the roof of every unit to the roof of the player.
func update_sight(space: PhysicsDirectSpaceState3D, player: VehicleBase,
		units: Array[PoliceCar], drones: Array[PoliceDrone]) -> void:
	sight_block = maxf(sight_block - PoliceSight.INTERVAL, 0.0)
	var roof := PoliceSight.roof_of(player.global_position)
	var blocked := sight_block > 0.0
	var seen := false
	for unit in units:
		if unit.is_wrecked or unit.parked:
			unit.seen = false
			continue
		var ok := not blocked and not player_flying
		if ok:
			ok = PoliceSight.can_see(space, PoliceSight.eye_of(unit.global_position), roof,
					PoliceSight.GROUND_RANGE)
		unit.seen = ok
		if ok:
			seen = true
			unit.engaged = ENGAGE_MEMORY
	for drone in drones:
		var ok := not blocked
		if ok:
			ok = PoliceSight.can_see(space, drone.global_position, roof, PoliceSight.DRONE_RANGE)
		drone.seen = ok
		if ok:
			seen = true
	seen_now = seen
	if seen:
		no_sight = 0.0
	else:
		no_sight += PoliceSight.INTERVAL


## The state of the pursuit: the player is seen, the police search, the evade bar fills.
func update_state(delta: float, player: VehicleBase) -> bool:
	if is_over():
		return false
	_update_hiding_spot(player)
	if seen_now:
		# The player is seen again: the pursuit continues at the same heat.
		if state != &"chase":
			set_state(&"chase")
			PoliceRadio.say(&"found")
		evade = 0.0
		return false
	if no_sight < EVADE_DELAY:
		# The pursuit is on: the units are closing in or just lost the player.
		if state != &"chase":
			set_state(&"chase")
		return false
	# Four seconds without sight: the police search, then the evade bar fills.
	if state == &"chase":
		PoliceRadio.say(&"lost")
	set_state(&"search" if no_sight < EVADE_DELAY + SEARCH_TIME else &"cooldown")
	# The bar fills twice as fast under a deck, in a tunnel or in a parking garage.
	var rate := 2.0 if in_hiding_spot else 1.0
	evade = minf(evade + delta * rate / maxf(PoliceHeat.cooldown_time(heat), 1.0), 1.0)
	return evade >= 1.0


## True when the player is in a hiding spot of the world.
##
## A spot only hides the player when she is on its level: a spot under a deck does not hide the
## player who drives on the deck above it.
func _update_hiding_spot(player: VehicleBase) -> void:
	in_hiding_spot = false
	var height := player.global_position.y
	for pos in hiding_spots:
		if absf(height - pos.y) > LEVEL:
			continue
		if player.global_position.distance_to(pos) < HIDE_RADIUS:
			in_hiding_spot = true
			return


## The busted meter: it fills while the player is slow and a unit is close.
func update_busted(delta: float, player: VehicleBase, units: Array[PoliceCar]) -> bool:
	if is_over():
		busted = maxf(busted - delta * BUST_DRAIN, 0.0)
		return false
	if player_flying or player.is_airborne():
		# Never busts while airborne or in a sky lane (dossier 3.4).
		busted = maxf(busted - delta * BUST_DRAIN, 0.0)
		return false
	var close := 0
	var boxing := false
	for unit in units:
		if unit.is_wrecked:
			continue
		if unit.global_position.distance_to(player.global_position) > BUST_RANGE:
			continue
		if absf(unit.global_position.y - player.global_position.y) > LEVEL:
			# The unit is on another level: a cop under a deck cannot bust the player above.
			continue
		close += 1
		if unit.state == PoliceCar.State.BOX:
			boxing = true
	# The box: a player that is boxed and slower than 40 km/h is busted twice as fast.
	if boxing and player.get_speed_kmh() < BUST_BOX_SPEED:
		box_time += delta
	else:
		# The box breaks up for a moment (the units change their place): the time it held
		# does not disappear, it only fades.
		box_time = maxf(box_time - delta * BUST_DRAIN, 0.0)
	var rate := 0.0
	if player.get_speed_kmh() < BUST_SPEED:
		rate = BUST_FILL
	elif boxing and player.get_speed_kmh() < BUST_BOX_SPEED \
			and box_time >= BUST_BOX_TIME:
		# The box holds a slow player: the meter fills twice as fast. A player who is faster
		# than 40 km/h is not in the box, whatever the box held a moment ago.
		rate = BUST_FILL * 2.0
	if close < 1 or rate <= 0.0:
		busted = maxf(busted - delta * BUST_DRAIN, 0.0)
		return false
	busted = minf(busted + delta * rate, 1.0)
	return busted >= 1.0


## Sets the state of the pursuit and tells the bus about it.
func set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	Events.pursuit_state_changed.emit(new_state)


## Starts the pursuit: the heat goes to 1 and the first unit comes.
##
## `level` is the heat the pursuit starts at (1 for an offence, 2 or 3 for the mode "pursuit").
func start(level: int = 1) -> void:
	if not is_over():
		return
	set_state(&"chase")
	set_heat(PoliceHeat.clamp_heat(level))
	pursuit_time = 0.0
	disabled = 0
	evade = 0.0
	PoliceRadio.say(&"stop")


## Starts a pursuit at a given heat.
##
## The alias of start() for the modes unit (game/modes/police_link.gd calls `start_at`).
func start_at(level: int) -> void:
	start(level)


## The bounty of the pursuit: the heat, the time and the disabled cars (dossier §3.5).
func bounty() -> int:
	return int(BOUNTY_HEAT * float(heat) + BOUNTY_SECOND * pursuit_time
			+ BOUNTY_DISABLED * float(disabled))


## The pursuit is over: the heat goes back to zero and the player is paid.
func end(new_state: StringName) -> void:
	var reward := bounty()
	set_state(new_state)
	heat = 0
	Events.heat_changed.emit(0)
	pursuit_time = 0.0
	disabled = 0
	evade = 0.0
	busted = 0.0
	box_time = 0.0
	_reset_sight()
	if new_state == &"escaped":
		Events.stunt.emit(&"escape", reward, "甩掉警察！ +%d" % reward)
		Events.toast.emit("甩掉警察！ ESCAPED +%d" % reward, &"good")
	else:
		Events.toast.emit("被捕了！ BUSTED −%d" % reward, &"danger")


## The pursuit is over without a reward (the test hook).
func reset() -> void:
	set_state(&"none")
	heat = 0
	pursuit_time = 0.0
	disabled = 0
	evade = 0.0
	busted = 0.0
	box_time = 0.0
	_reset_sight()


## The police see nothing: the next tick must not report an offence of a player they cannot see.
func _reset_sight() -> void:
	seen_now = false
	no_sight = 0.0
	sight_block = 0.0

class_name PoliceSquad
extends RefCounted
## The police units on the road: their tick, their removal, the disabled count, the hold-back
## and the light bars.
##
## The module owns the list of the units, so the dispatcher, the pursuit and the spawner all
## talk about the same cars.

const LIGHTS_NEAR := 3           ## the omni lights of the three nearest units
const DESPAWN_DISTANCE := 420.0   ## m: a unit further away is removed (when it is out of sight)
const OFFSCREEN_TIME := 2.0       ## s: a unit has to be out of sight this long before it goes
const HOLD_BACK_COUNT := 3        ## only the three nearest units come close to the player
## The radius a unit that holds back stays outside of (m).
const HOLD_BACK_RADIUS := 31.0
## The speed a unit that holds back gives up on the player (m/s).
const HOLD_BACK_BRAKE := 6.0
## The extra brake per metre inside the radius (m/s per m).
const HOLD_BACK_BRAKE_RATE := 1.0
## The distance between two units that hold back (m): they queue up behind the player.
const HOLD_BACK_SPACING := 6.0
## The catch-up of a unit that holds back and is too far away (m/s per m).
const HOLD_BACK_CATCH_UP := 0.3
const HOLD_BACK_CATCH_UP_MAX := 8.0
## The number of units that drive with the full car physics; the others drive as a ghost.
const FULL_PHYSICS_COUNT := 3
## The seconds a unit keeps its mode (a body that enters or leaves the simulation costs a
## physics step, so the modes do not change every frame).
const MODE_HOLD := 1.5
## A unit that lies on its roof or that stands still counts as disabled (dossier §6.3).
const FLIP_TIME := 1.5
const STUCK_TIME := 4.0

## The units on the road.
var units: Array[PoliceCar] = []
## The number of units that became disabled in the last tick.
var newly_disabled: int = 0
## The pool the units come from: a unit that leaves the road goes back into it.
var pool: PolicePool = null
var _flip_time: Dictionary = {}
var _stuck_time: Dictionary = {}
## The units of the last tick, the nearest one first. It is the ONE ranking of the tick: the
## hold-back, the physics and the lights all read it.
var _ranked: Array[PoliceCar] = []
## The units that drive with the full car physics, by instance id (the modes are held for a
## while, and the units change their place in the ranking).
var _modes: Dictionary = {}
## The time until the modes may change again.
var _mode_timer: float = 0.0
## The units that leave the road in this tick.
var _dead: Array[PoliceCar] = []


## The tick of the units: they drive, the disabled ones leave the budget and the far ones go.
##
## The ranking of the units (the hold-back, the physics and the lights) happens in one pass, so
## the dispatcher does not sort the same list three times a frame.
func update(delta: float, player: VehicleBase, camera: Camera3D, hold_point: Vector3,
		extra: Array[PoliceCar]) -> void:
	newly_disabled = 0
	_dead.clear()
	_rank(player, camera)
	for i in range(units.size() - 1, -1, -1):
		var unit := units[i]
		if unit.state == PoliceCar.State.WRECK:
			_tick_wreck(unit, delta)
		else:
			unit.tick(delta)
		if unit.despawn:
			_dead.append(unit)
			continue
		if not unit.disabled and _check_disabled(unit, delta):
			newly_disabled += 1
		if unit.disabled:
			continue
		var distance := unit.global_position.distance_to(player.global_position)
		if distance <= DESPAWN_DISTANCE:
			continue
		if _in_view(camera, unit.global_position):
			unit.off_screen_time = 0.0
			continue
		unit.off_screen_time += delta
		if unit.off_screen_time > OFFSCREEN_TIME:
			_dead.append(unit)
	for unit in _dead:
		remove_unit(unit)
	_hold_back(player, hold_point)
	_update_lights(player, extra)


## The wreck: the unit stops driving and lies still.
func _tick_wreck(unit: PoliceCar, delta: float) -> void:
	unit.wreck_time += delta
	unit.set_controls(0.0, 1.0, 0.0, true)
	if unit.wreck_time > PoliceCar.WRECK_LIFETIME:
		unit.despawn = true


## A unit that lies on its roof for a while or that stands still while it is engaged counts as
## disabled (dossier §6.3: "Units disabled = HP 0, flipped, or stuck > 4 s").
func _check_disabled(unit: PoliceCar, delta: float) -> bool:
	if unit.is_wrecked:
		unit.disabled = true
		return true
	var id := unit.get_instance_id()
	var flipped := unit.is_flipped()
	var stuck := unit.is_stuck()
	_flip_time[id] = float(_flip_time.get(id, 0.0)) + delta if flipped else 0.0
	_stuck_time[id] = float(_stuck_time.get(id, 0.0)) + delta if stuck else 0.0
	if float(_flip_time[id]) < FLIP_TIME and float(_stuck_time[id]) < STUCK_TIME:
		return false
	unit.disabled = true
	return true


## Adds a unit to the squad.
func add(unit: PoliceCar) -> void:
	units.append(unit)


## Removes a unit from the squad.
func remove(index: int) -> void:
	if index < 0 or index >= units.size():
		return
	var unit := units[index]
	units.remove_at(index)
	_flip_time.erase(unit.get_instance_id())
	_stuck_time.erase(unit.get_instance_id())
	if pool != null:
		pool.release_unit(unit)
	else:
		unit.queue_free()


## Removes a unit by its instance (the director uses it when a test despawns a unit).
func remove_unit(unit: PoliceCar) -> bool:
	for i in units.size():
		if units[i] == unit:
			remove(i)
			return true
	return false


## Removes every unit.
func clear() -> void:
	for unit in units:
		if pool != null:
			pool.release_unit(unit)
		else:
			unit.queue_free()
	units.clear()
	_flip_time.clear()
	_stuck_time.clear()


## The units that are still driving.
func live() -> Array[PoliceCar]:
	var out: Array[PoliceCar] = []
	for unit in units:
		if not unit.is_wrecked and not unit.parked:
			out.append(unit)
	return out


## The number of units that are on the player (the HUD shows it).
func engaged_count() -> int:
	return live().size()


## The hold-back of §6.3: never more than three units within thirty metres of the player.
##
## The three nearest units keep their roles; the others drive to a point behind the player and
## brake, so the road in front of the player stays free (and the meter of the bust still fills
## when he stops, because the three nearest units come in).
func _hold_back(player: VehicleBase, hold_point: Vector3) -> void:
	var player_speed := player.get_speed_kmh() / 3.6
	for i in _ranked.size():
		var unit := _ranked[i]
		var distance := unit.global_position.distance_to(player.global_position)
		# Every unit behind the three nearest holds back: a unit that is still far away is
		# held back as well, or it would drive up to the player before it is stopped.
		var held := i >= HOLD_BACK_COUNT
		unit.hold_back = held
		if not held:
			continue
		# The units that hold back queue up behind the player, so they do not pile up.
		unit.hold_back_point = _hold_back_point(unit, player, hold_point, i)
		unit.hold_back_speed = _hold_back_speed(player_speed, distance)


## The point a unit that holds back drives to.
##
## A unit that is closer than the hold distance drives at the player: it slows down, it does
## not turn around (a unit that drives backwards is a unit that crashes into the traffic).
func _hold_back_point(unit: PoliceCar, player: VehicleBase, hold_point: Vector3,
		index: int) -> Vector3:
	var distance := unit.global_position.distance_to(player.global_position)
	if distance < PoliceCar.HOLD_BACK_DISTANCE:
		return player.global_position
	return hold_point - player.get_forward() \
			* float(index - HOLD_BACK_COUNT) * HOLD_BACK_SPACING


## The speed of a unit that holds back: the speed of the player, less the brake it needs to
## stay behind him.
func _hold_back_speed(player_speed: float, distance: float) -> float:
	var catch_up := clampf(maxf(distance - PoliceCar.HOLD_BACK_DISTANCE, 0.0)
			* HOLD_BACK_CATCH_UP, 0.0, HOLD_BACK_CATCH_UP_MAX)
	var brake := 0.0
	var over := PoliceCar.HOLD_BACK_DISTANCE - distance
	if over > 0.0:
		brake = minf(HOLD_BACK_BRAKE_RATE * over, HOLD_BACK_BRAKE)
	return maxf(player_speed + catch_up - brake, 0.0)


## The units that drive with the full car physics: the nearest ones and the ones the player can
## see. The others drive as a ghost, so a dozen police cars do not cost a frame.
func _rank(player: VehicleBase, camera: Camera3D) -> void:
	_ranked.clear()
	for unit in units:
		if unit.is_wrecked or unit.parked:
			continue
		_ranked.append(unit)
	_sort_by_distance(_ranked, player)
	if _mode_timer > 0.0 and _modes.size() == _ranked.size():
		for unit in _ranked:
			unit.full_physics = bool(_modes.get(unit.get_instance_id(), true))
		return
	_mode_timer = MODE_HOLD
	_modes.clear()
	for i in _ranked.size():
		var unit := _ranked[i]
		var visible := _in_view(camera, unit.global_position)
		unit.full_physics = visible or i < FULL_PHYSICS_COUNT
		_modes[unit.get_instance_id()] = unit.full_physics


## Sorts the units by their distance to the player, the nearest one first.
##
## The sort is an insertion sort on the squared distance: the list is short and a lambda in a
## sort_custom costs more than the sort itself.
func _sort_by_distance(list: Array[PoliceCar], player: VehicleBase) -> void:
	var keys: Array[float] = []
	for unit in list:
		keys.append(unit.global_position.distance_squared_to(player.global_position))
	for i in range(1, list.size()):
		var unit := list[i]
		var key := keys[i]
		var j := i - 1
		while j >= 0 and keys[j] > key:
			list[j + 1] = list[j]
			keys[j + 1] = keys[j]
			j -= 1
		list[j + 1] = unit
		keys[j + 1] = key


## The omni lights of the light bars go to the three nearest units.
func _update_lights(player: VehicleBase, extra: Array[PoliceCar]) -> void:
	var all: Array[PoliceCar] = []
	all.append_array(_ranked)
	all.append_array(extra)
	var chosen: Array[PoliceCar] = []
	for i in LIGHTS_NEAR:
		var best: PoliceCar = null
		var best_distance := INF
		for unit in all:
			if chosen.has(unit):
				continue
			var distance := unit.global_position.distance_squared_to(player.global_position)
			if distance < best_distance:
				best_distance = distance
				best = unit
		if best == null:
			break
		chosen.append(best)
	for unit in all:
		unit.set_lights_enabled(chosen.has(unit))


## True when the player can see the point (the spawn and the mode of a unit).
func _in_view(camera: Camera3D, pos: Vector3) -> bool:
	return PoliceSight.visible_to_player(camera, pos)

class_name PoliceEvents
extends RefCounted
## The events the dispatcher listens to (ref/gameplay/DOSSIER.md §3.4).
##
## The offences of the player, the collisions with the police cars, the sky lane, the flash
## charge and the appearance of the player. The module owns the rules of the events; the
## dispatcher owns the units and the world.

## The speed the player has to close on a police car for the hit to be his offence (m/s).
const STRIKER_SPEED := 3.0
## The seconds the police lose sight of the player after a flash charge (dossier §3.4).
const FLASH_BLIND := 1.0

## The offence rules (the four kinds of §3.4 and the grace).
var offences: PoliceOffences = PoliceOffences.new()
## The rules of the pursuit (the heat, the states, the busted meter).
var pursuit: PolicePursuit = PolicePursuit.new()
## The player of the moment.
var player: VehicleBase = null
## The velocity cache of the contacts: who hit whom and how hard.
var contact: PoliceContact = PoliceContact.new()
## The number of PIT taps the police gave.
var pit_assists: int = 0


## An offence was reported on the bus: the police only count what they saw themselves.
func on_infraction(vehicle: VehicleBase, kind: StringName) -> void:
	if vehicle != player or not PoliceHeat.is_offence(kind):
		return
	if not offences.can_count():
		return
	if kind == &"speeding" or kind == &"hit_traffic":
		# An offence the police did not see does not count.
		if not pursuit.seen_now:
			return
	if not offences.report(kind):
		return
	if pursuit.is_over():
		pursuit.start()


## A collision: the contacts of the police cars, the PIT tap and the offences.
func on_collision(vehicle: VehicleBase, other: Node3D, point: Vector3, _impulse: float) -> void:
	if vehicle is PoliceCar and other == player:
		_on_cop_hit(vehicle as PoliceCar, point)
		return
	if other is PoliceCar and vehicle == player:
		_on_cop_hit(other as PoliceCar, point)
		return
	if vehicle == player and other is Node3D and other.is_in_group(&"traffic"):
		if pursuit.seen_now:
			_offence(&"hit_traffic")


## The player hit a police car: the unit knows the contact, the PIT may help and the hit is
## an offence (dossier §3.4).
func _on_cop_hit(unit: PoliceCar, point: Vector3) -> void:
	unit.notify_contact()
	if _player_is_striker(unit, point):
		_offence(&"hit_police")
	_pit_tap(unit, point)


## True when the PLAYER rammed the unit.
##
## The police that hit the player do not commit an offence: the player has to drive into the
## police, fast enough and in the front half of his car.
func _player_is_striker(unit: PoliceCar, point: Vector3) -> bool:
	if player == null:
		return false
	if contact.approach_speed(player, unit) < STRIKER_SPEED:
		return false
	return (point - player.global_position).dot(player.get_forward()) > 0.0


## The tap of the PIT: only the unit that is really striking may give it.
func _pit_tap(unit: PoliceCar, point: Vector3) -> void:
	if player == null:
		return
	# The closing speed of the hit: the two cars move apart or together at that speed.
	var closing := contact.relative_speed(unit, player)
	if PolicePit.assist(player, unit, point, closing) > 0.0:
		unit.mark_pit_assisted()
		pit_assists += 1


## An offence the police spotted itself (the speeding offence of the director).
func report_offence(kind: StringName) -> void:
	_offence(kind)


## An offence the police spotted itself.
func _offence(kind: StringName) -> void:
	if not offences.can_count() or not offences.report(kind):
		return
	Events.infraction.emit(player, kind)
	if pursuit.is_over():
		pursuit.start()


## The player enters a sky lane: the ground units lose sight of it.
func on_flight_changed(vehicle: VehicleBase, active: bool) -> void:
	if vehicle != player:
		return
	pursuit.player_flying = active
	if active:
		PoliceRadio.say(&"flee")


## The player flash-charges: the police lose sight for a second (dossier §3.4).
func on_charge_finished(vehicle: VehicleBase) -> void:
	if vehicle != player:
		return
	pursuit.sight_block = FLASH_BLIND


## A new player car: the grace starts again and the debuffs of the old car are dropped.
func on_player_changed(new_player: VehicleBase) -> void:
	player = new_player
	offences.on_player_appeared()

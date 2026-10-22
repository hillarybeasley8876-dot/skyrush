extends Node
## The rules of the box (ref/gameplay/DOSSIER.md §6.3).
##
##   python tools/gd.py test res://ai/police/tests/test_box_rules.gd
##
## A player who is boxed and slower than 40 km/h is busted twice as fast; a player who is
## faster is not. A box that breaks up fades: the time it held does not disappear, it only
## fades, and the box that forms again starts from the time that is left.

const T := preload("res://ai/police/tests/police_test.gd")
## The speed of the chase before the player slows down (km/h).
const CRUISE_KMH := 70.0
## The speed of a slow player: below the 40 km/h of the box rule.
const SLOW_KMH := 30.0
## The speed of a player who is too fast for the box rule.
const FAST_KMH := 60.0
## The time the units of the box need to take their place (s).
const FORM_TIME := 14.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	# The traffic is not part of this test: a car that the player rear-ends pushes him.
	t.clear_traffic()
	t.director.remove_all_units()
	t.start_pursuit(2)
	t.director.force_roles([PoliceFleet.Role.BOX_FRONT, PoliceFleet.Role.BOX_SIDE,
			PoliceFleet.Role.BOX_SIDE])
	# The three units of the box, behind the player: the box has to form on its own.
	var front: PoliceCar = t.director.spawn_unit_at(
			t.straight_start(-535.0), PoliceFleet.Role.BOX_FRONT)
	var left: PoliceCar = t.director.spawn_unit_at(
			t.straight_start(-540.0), PoliceFleet.Role.BOX_SIDE)
	var right: PoliceCar = t.director.spawn_unit_at(
			t.straight_start(-545.0), PoliceFleet.Role.BOX_SIDE)
	t.check(front != null and left != null and right != null, "the three units of the box are on the road")
	if front == null or left == null or right == null:
		t.finish()
		return
	# The box takes its place while the player drives fast.
	await _drive(t, FORM_TIME, CRUISE_KMH)
	await _check_slow_player(t)
	await _check_fade(t, left, right, front)
	await _check_fast_player(t)
	t.expect(6)
	t.finish()


## A boxed player who is faster than 40 km/h is not busted at all.
##
## The box held the player for a while, so the time of the box is there: a player who speeds
## up is not in the box any more and the meter must not fill.
func _check_fast_player(t: T) -> void:
	t.director.pursuit.busted = 0.0
	_set_speed(t, FAST_KMH)
	await t.drive(1.0, 0.0, FAST_KMH)
	t.check(t.director.busted < 0.05, "a boxed player at %d km/h is not busted (%.2f)"
			% [int(FAST_KMH), t.director.busted])


## A boxed player below 40 km/h is busted twice as fast.
func _check_slow_player(t: T) -> void:
	# The player brakes hard: the box has to hold him, or the meter never fills.
	await _drive(t, 5.0, SLOW_KMH)
	t.director.pursuit.busted = 0.0
	await t.drive(1.0, 0.0, SLOW_KMH)
	t.check(t.director.busted > 0.5, "the busted meter fills twice as fast (%.2f in 1 s)"
			% t.director.busted)


## A box that breaks up fades: the time it held does not disappear.
func _check_fade(t: T, left: PoliceCar, right: PoliceCar, front: PoliceCar) -> void:
	# The box holds while the player is slow.
	await _drive(t, 3.0, SLOW_KMH)
	var held := t.director.pursuit.box_time
	t.check(held > PolicePursuit.BUST_BOX_TIME, "the box holds while the player is slow (%.2f s)"
			% held)
	# The box breaks up: the units leave the box.
	for unit in [left, right, front]:
		unit.state = PoliceCar.State.PURSUE
		unit.set_role(PoliceFleet.Role.PURSUE)
	await _drive(t, 0.5, SLOW_KMH)
	var faded := t.director.pursuit.box_time
	t.check(faded > 0.0 and faded < held, "the time of the box fades, it does not reset (%.2f of %.2f s)"
			% [faded, held])
	# The box forms again: the time it held is still there.
	left.set_role(PoliceFleet.Role.BOX_SIDE)
	right.set_role(PoliceFleet.Role.BOX_SIDE)
	front.set_role(PoliceFleet.Role.BOX_FRONT)
	await _drive(t, 1.0, SLOW_KMH)
	var again := t.director.pursuit.box_time
	t.check(again > faded, "the box that forms again starts from the time that is left (%.2f s)"
			% again)


## Drives the player and keeps the busted meter low: a full meter ends the pursuit.
func _drive(t: T, seconds: float, kmh: float) -> void:
	var steps := int(seconds * 120.0)
	for i in steps:
		await t.drive_frame(0.0, kmh)
		if i % 60 == 0:
			t.director.pursuit.busted = 0.0


## Sets the speed of the player (km/h) on his line.
func _set_speed(t: T, kmh: float) -> void:
	t.player.linear_velocity = t.player.get_forward() * kmh / 3.6
	t.player.angular_velocity = Vector3.ZERO

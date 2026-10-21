extends Node
## The rolling box (ref/gameplay/DOSSIER.md §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_box.gd
##
## The front unit overtakes the player in the next lane and holds nine metres in front of him,
## the two side units squeeze him from both sides. A boxed player below 40 km/h is busted twice
## as fast. The units are NOT pinned: the box has to form on its own.

const T := preload("res://ai/police/tests/police_test.gd")
const PLAYER_KMH := 70.0
## The time the units have to take their place (s).
const FORM_TIME := 14.0
## The time the box has to hold to count (s).
const FORM_HOLD := 3.0
## The front unit: ahead of the player and on his line.
const FRONT_AHEAD := -5.0
const FRONT_LINE := 1.6
## The side units: beside the player.
const SIDE_MIN := 1.8
const SIDE_MAX := 3.6
const SIDE_BACK := -1.5
const SIDE_FRONT := 3.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	# The patrols of the road would take the roles of the test.
	t.director.remove_all_units()
	t.start_pursuit(2)
	t.director.force_roles([PoliceFleet.Role.BOX_FRONT, PoliceFleet.Role.BOX_SIDE,
			PoliceFleet.Role.BOX_SIDE])
	var front: PoliceCar = t.director.spawn_unit_at(t.straight_start(-535.0),
			PoliceFleet.Role.BOX_FRONT)
	var left: PoliceCar = t.director.spawn_unit_at(t.straight_start(-540.0),
			PoliceFleet.Role.BOX_SIDE)
	var right: PoliceCar = t.director.spawn_unit_at(t.straight_start(-545.0),
			PoliceFleet.Role.BOX_SIDE)
	t.check(front != null and left != null and right != null, "the three units are on the road")
	if front == null or left == null or right == null:
		t.finish()
		return
	# The units are already at the speed of the player: the box has to form, not the catch-up.
	for unit: PoliceCar in [front, left, right]:
		unit.linear_velocity = Vector3(PLAYER_KMH / 3.6, 0.0, 0.0)
	await _check_formation(t, front, left, right)
	await _check_busted(t, front, left, right)
	t.expect(7)
	t.finish()


## The formation: the front unit ends up in front of the player, the side units on both sides.
func _check_formation(t: T, front: PoliceCar, left: PoliceCar, right: PoliceCar) -> void:
	var formed := 0.0
	var runs := 0
	var was_formed := false
	for i in int(FORM_TIME * 120.0):
		await t.drive_frame(0.0, PLAYER_KMH)
		var ok := _formed(t, front, left, right)
		if ok:
			formed += 1.0 / 120.0
			if not was_formed:
				runs += 1
		was_formed = ok
	t.check(formed >= FORM_HOLD, "the box forms for %.1f s of %.1f s" % [formed, FORM_TIME])
	t.check(runs == 1, "the box forms once (%d runs)" % runs)
	var front_rel := _relative(t, front)
	t.check(front_rel.z < FRONT_AHEAD and absf(front_rel.x) < FRONT_LINE,
			"the front unit is in front of the player (%.1f, %.1f)" % [front_rel.z, front_rel.x])
	var left_rel := _relative(t, left)
	var right_rel := _relative(t, right)
	t.check(left_rel.x * right_rel.x < 0.0, "the side units are on opposite sides (%.1f / %.1f)"
			% [left_rel.x, right_rel.x])
	t.check(_side_ok(left_rel) and _side_ok(right_rel),
			"the side units squeeze from both sides (%.1f/%.1f and %.1f/%.1f)"
			% [left_rel.x, left_rel.z, right_rel.x, right_rel.z])


## A boxed player below 40 km/h is busted twice as fast.
func _check_busted(t: T, front: PoliceCar, left: PoliceCar, right: PoliceCar) -> void:
	# The box has to hold for two seconds, then the meter fills at 2/3 per second.
	for i in int(4.0 * 120.0):
		await t.drive_frame(0.0, 30.0)
	t.director.pursuit.busted = 0.0
	await t.drive(1.0, 0.0, 30.0)
	var rate := t.director.busted
	t.check(rate > 0.5, "the busted meter fills twice as fast when the player is boxed (%.2f in 1 s)"
			% rate)


## True when the three units form the box around the player.
func _formed(t: T, front: PoliceCar, left: PoliceCar, right: PoliceCar) -> bool:
	var front_rel := _relative(t, front)
	if front_rel.z >= FRONT_AHEAD or absf(front_rel.x) >= FRONT_LINE:
		return false
	var left_rel := _relative(t, left)
	var right_rel := _relative(t, right)
	if not _side_ok(left_rel) or not _side_ok(right_rel):
		return false
	return left_rel.x * right_rel.x < 0.0


## True when a side unit is beside the player.
func _side_ok(rel: Vector3) -> bool:
	var lateral := absf(rel.x)
	return lateral > SIDE_MIN and lateral < SIDE_MAX and rel.z > SIDE_BACK and rel.z < SIDE_FRONT


## The position of a unit in the frame of the player (x = right, z = behind).
func _relative(t: T, unit: PoliceCar) -> Vector3:
	var basis := t.player.global_transform.basis
	return basis.inverse() * (unit.global_position - t.player.global_position)

extends Node
## The heat of the pursuit (ref/gameplay/DOSSIER.md §3.4 and §3.5).
##
##   tools/godot.sh test res://ai/police/tests/test_heat.gd
##
## Checks the heat table, that the heat rises with the time and the disabled cars, that the
## player can escape by breaking the line of sight and that the escape is paid.

const T := preload("res://ai/police/tests/police_test.gd")


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	_check_table(t)
	await _check_pursuit(t)
	await _check_escape(t)
	await _check_disabled(t)
	await _check_disabled_by_state(t)
	t.expect(19)
	t.finish()


## The table of §3.4.
func _check_table(t: T) -> void:
	t.check(PoliceHeat.units_max(1) == 3 and PoliceHeat.units_max(3) == 7
			and PoliceHeat.units_max(5) == 12, "the unit budget of the heat table")
	t.check(is_equal_approx(PoliceHeat.backup_time(1), 60.0)
			and is_equal_approx(PoliceHeat.backup_time(5), 35.0), "the backup timers")
	t.check(is_equal_approx(PoliceHeat.cooldown_time(1), 20.0)
			and is_equal_approx(PoliceHeat.cooldown_time(3), 50.0)
			and is_equal_approx(PoliceHeat.cooldown_time(5), 90.0), "the cooldown times")
	t.check(PoliceHeat.heat_for_time(59.0) == 0 and PoliceHeat.heat_for_time(60.0) == 2
			and PoliceHeat.heat_for_time(120.0) == 3 and PoliceHeat.heat_for_time(200.0) == 4
			and PoliceHeat.heat_for_time(300.0) == 5, "the pursuit time raises the heat")
	t.check(PoliceHeat.heat_for_disabled(2) == 2 and PoliceHeat.heat_for_disabled(5) == 3
			and PoliceHeat.heat_for_disabled(9) == 4 and PoliceHeat.heat_for_disabled(14) == 5,
			"the disabled police cars raise the heat")
	t.check(PoliceHeat.is_offence(&"speeding") and PoliceHeat.is_offence(&"hit_police")
			and PoliceHeat.is_offence(&"hit_traffic") and PoliceHeat.is_offence(&"toll_evaded")
			and not PoliceHeat.is_offence(&"reckless"), "the offence kinds")


## The pursuit starts at heat 1 and the units come.
func _check_pursuit(t: T) -> void:
	t.director.spawn_enabled = false
	t.start_pursuit(1)
	await t.idle(0.4)
	t.check(t.director.heat == 1, "the pursuit runs at heat 1 (%d)" % t.director.heat)
	t.check(t.director.pursuit_state == &"chase", "the pursuit state is chase (%s)"
			% t.director.pursuit_state)


## The player escapes by breaking the line of sight, and the escape is paid.
func _check_escape(t: T) -> void:
	t.director.remove_all_units()
	await t.idle(4.6)
	t.check(t.director.pursuit_state == &"search",
			"the police search after four seconds without sight (%s)"
			% t.director.pursuit_state)
	await t.idle(2.0)
	t.check(t.director.pursuit_state == &"cooldown", "the evade bar fills (%s)"
			% t.director.pursuit_state)
	await t.idle(21.0)
	t.check(t.director.pursuit_state == &"escaped", "the player escapes (%s)"
			% t.director.pursuit_state)
	t.check(t.director.heat == 0, "the heat goes back to zero after the escape")
	var paid := false
	for stunt in t.stunts:
		if StringName(stunt["kind"]) == &"escape" and int(stunt["points"]) > 0:
			paid = true
	t.check(paid, "the escape is paid (%d stunts)" % t.stunts.size())


## Two wrecked police cars raise the heat to 2.
func _check_disabled(t: T) -> void:
	t.start_pursuit(1)
	await t.idle(0.4)
	t.check(t.director.heat == 1, "a new pursuit starts at heat 1")
	var spot: Transform3D = t.straight_start(-400.0)
	for i in 2:
		var cop: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
		if cop == null:
			t.check(false, "the unit %d could not be spawned" % i)
			return
		cop.apply_damage(999.0, cop.global_position, t.player)
	await t.idle(0.5)
	t.check(t.director.heat == 2, "two disabled police cars raise the heat to 2 (%d)"
			% t.director.heat)


## A unit that lies on its roof and a unit that stands still count as disabled (dossier §6.3).
func _check_disabled_by_state(t: T) -> void:
	t.director.remove_all_units()
	t.start_pursuit(1)
	await t.idle(0.4)
	t.director.pursuit.disabled = 0
	# A unit on its roof.
	var flipped: PoliceCar = t.director.spawn_unit_at(t.straight_start(-430.0),
			PoliceFleet.Role.PURSUE)
	t.check(flipped != null, "the unit is on the road")
	if flipped != null:
		var basis := Basis(Vector3.RIGHT, PI) * flipped.global_transform.basis
		flipped.global_transform = Transform3D(basis, flipped.global_position)
		await t.idle(2.5)
	t.check(t.director.pursuit.disabled >= 1, "a unit on its roof counts as disabled (%d)"
			% t.director.pursuit.disabled)
	# A unit that stands still while it is engaged.
	t.director.remove_all_units()
	t.director.pursuit.disabled = 0
	var stuck: PoliceCar = t.director.spawn_unit_at(t.straight_start(-430.0),
			PoliceFleet.Role.PURSUE)
	t.check(stuck != null, "the second unit is on the road")
	if stuck != null:
		stuck.freeze = true
		stuck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		await t.idle(5.0)
	t.check(t.director.pursuit.disabled >= 1, "a unit that stands still counts as disabled (%d)"
			% t.director.pursuit.disabled)

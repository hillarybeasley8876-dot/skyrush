extends Node
## The contacts of the police cars (ref/gameplay/DOSSIER.md §3.4, lead note P-INT1).
##
##   tools/godot.sh test res://ai/police/tests/test_offences_contact.gd
##
## A police car that drives into the player is not an offence of the player: the player has to
## drive into the police, fast enough and in the front half of his car. A patrol that stops
## behind the parked player does not touch him at all.

const T := preload("res://ai/police/tests/police_test.gd")


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	await _check_patrol_contact(t)
	await _check_pursue_contact(t)
	await _check_player_contact(t)
	t.expect(12)
	t.finish()


## A patrol that drives up to the parked player does not start a pursuit (lead note P-INT1).
##
## The patrol follows the car in front (the IDM of the traffic unit), so it stops behind the
## player and there is no contact at all.
func _check_patrol_contact(t: T) -> void:
	t.director.spawn_enabled = false
	t.director.clear_pursuit()
	t.director.remove_all_units()
	t.pin_xform = t.straight_start(-500.0)
	t.pinned = true
	t.player.reset_to(t.pin_xform)
	await t.wait_grace()
	var cop: PoliceCar = t.director.spawn_unit_at(t.straight_start(-590.0),
			PoliceFleet.Role.PATROL)
	t.check(cop != null, "the patrol is on the road")
	if cop == null:
		return
	var hits := t.police_hits
	await t.idle(25.0)
	t.check(t.police_hits == hits, "the patrol never touches the player (%d contacts)"
			% (t.police_hits - hits))
	t.check(t.director.pursuit_state == &"none",
			"the patrol does not start a pursuit (%s)" % t.director.pursuit_state)
	t.check(t.director.heat == 0, "the heat stays at zero (%d)" % t.director.heat)
	t.pinned = false


## A police unit that drives into the parked player is not an offence of the player.
func _check_pursue_contact(t: T) -> void:
	t.director.spawn_enabled = false
	t.director.clear_pursuit()
	t.director.remove_all_units()
	t.director.force_role(PoliceFleet.Role.PURSUE)
	# The player is pinned: he stands still and cannot be pushed off the road.
	t.pin_xform = t.straight_start(-500.0)
	t.pinned = true
	t.player.reset_to(t.pin_xform)
	await t.wait_grace()
	var cop: PoliceCar = t.director.spawn_unit_at(t.straight_start(-510.0),
			PoliceFleet.Role.PURSUE)
	t.check(cop != null, "the pursuing unit is on the road")
	if cop == null:
		return
	await t.idle(20.0)
	var distance := cop.global_position.distance_to(t.player.global_position)
	t.check(distance < 8.0, "the unit drives into the player (%.1f m)" % distance)
	t.check(t.director.pursuit_state == &"none",
			"a police contact is not an offence of the player (%s)" % t.director.pursuit_state)
	t.check(t.director.heat == 0, "the heat stays at zero (%d)" % t.director.heat)
	t.pinned = false


## The player drives into a parked police car: that IS the offence "hit_police".
func _check_player_contact(t: T) -> void:
	t.director.spawn_enabled = false
	t.director.clear_pursuit()
	t.director.remove_all_units()
	t.director.force_role(-1)
	await t.wait_grace()
	var cop: PoliceCar = t.director.spawn_unit_at(t.straight_start(-440.0),
			PoliceFleet.Role.PATROL)
	t.check(cop != null, "the parked police car is on the road")
	if cop == null:
		return
	cop.freeze = true
	cop.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	t.player.reset_to(t.straight_start(-460.0))
	await t.drive(4.0, 0.0, 40.0)
	t.check(t.police_hits > 0, "the player hits the police car (%d contacts)" % t.police_hits)
	t.check(t.director.pursuit_state == &"chase",
			"the player who hits the police starts the pursuit (%s)" % t.director.pursuit_state)
	t.check(t.director.heat == 1, "the pursuit runs at heat 1 (%d)" % t.director.heat)

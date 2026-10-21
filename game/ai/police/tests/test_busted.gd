extends Node
## The busted meter (ref/gameplay/DOSSIER.md §3.2 and §3.4).
##
##   tools/godot.sh test res://ai/police/tests/test_busted.gd
##
## The meter fills at a third per second while the player is slow and a unit is within twelve
## metres, and it never fills while the player is airborne or in a sky lane.

const T := preload("res://ai/police/tests/police_test.gd")


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	t.director.spawn_enabled = false
	await _check_busted(t)
	await _check_airborne(t)
	t.expect(8)
	t.finish()


## The meter fills and the pursuit ends in a bust.
func _check_busted(t: T) -> void:
	t.start_pursuit(1)
	await t.idle(0.4)
	t.check(t.director.pursuit_state == &"chase", "the pursuit runs")
	var spot: Transform3D = t.straight_start(-400.0).translated(Vector3(-9.0, 0.0, 0.0))
	var cop: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
	t.check(cop != null, "a unit is next to the player")
	# The player stands still: the police may lean on it, but they cannot push it away.
	t.pinned = true
	t.pin_xform = t.straight_start(-400.0)
	await t.idle(1.5)
	t.check(t.director.busted > 0.2, "the busted meter fills (%.2f)" % t.director.busted)
	await t.idle(2.5)
	t.check(t.peak_busted >= 0.99, "the busted meter is full (%.2f)" % t.peak_busted)
	t.check(t.director.pursuit_state == &"busted", "the player is busted (%s)"
			% t.director.pursuit_state)
	t.check(t.director.heat == 0, "the heat goes back to zero after the bust")


## The meter never fills while the player is in the air.
func _check_airborne(t: T) -> void:
	t.pinned = false
	t.start_pursuit(1)
	await t.idle(0.4)
	var spot: Transform3D = t.straight_start(-400.0).translated(Vector3(-9.0, 0.0, 0.0))
	t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
	# The player is lifted over the traffic: it must not be busted in the air.
	t.hold_in_air(6.0)
	await t.idle(2.0)
	t.check(t.director.busted < 0.2, "the meter does not fill in the air (%.2f)"
			% t.director.busted)
	t.check(t.director.pursuit_state != &"busted", "the player is not busted in the air")

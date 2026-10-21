extends Node
## The PIT manoeuvre (ref/gameplay/DOSSIER.md §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_pit.gd
##
## The PIT is a collision: the unit lines up beside the player and steers into his rear quarter.
## Only inside that contact the police add their tap, and the tap is sized as a yaw rate target
## (1.6 rad/s), so the player really spins. A unit that rams the player gives no tap at all.

const T := preload("res://ai/police/tests/police_test.gd")
const BUDGET := 30.0
## The heading change that counts as a turn (degrees).
const SPIN_DEGREES := 60.0
## The time the player has to turn in (s).
const SPIN_TIME := 2.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	# The patrols of the road would take the roles of the test.
	t.director.remove_all_units()
	t.start_pursuit(3)
	t.director.force_role(PoliceFleet.Role.PIT)
	# The unit starts 30 m behind the player, on the same straight.
	var spot: Transform3D = t.straight_start(-530.0)
	var cop: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PIT)
	t.check(cop != null, "the PIT unit is on the road")
	if cop == null:
		t.finish()
		return
	# The unit is a little faster than the player: the manoeuvre has to happen, not the catch-up.
	cop.linear_velocity = Vector3(29.0, 0.0, 0.0)
	var hits := t.hits_of(cop)
	var heading := t.player_heading()
	var touched := false
	for i in int(BUDGET * 120.0):
		await t.drive_frame(0.0, 90.0)
		if t.hits_of(cop) <= hits:
			continue
		# A real contact: the player has to be turned now.
		touched = true
		break
	t.check(touched, "the PIT unit touches the player (a real collision)")
	# The player lets go of the wheel: the tap alone has to spin him.
	t.release_all()
	var turned := 0.0
	for j in int(SPIN_TIME * 120.0):
		await t.tree.physics_frame
		turned = rad_to_deg(absf(angle_difference(t.player_heading(), heading)))
		if turned >= SPIN_DEGREES:
			break
	t.check(turned >= SPIN_DEGREES, "the player is turned by the PIT (%.1f degrees)"
			% turned)
	t.check(t.director.pit_assists == 1, "the police gave one tap (%d)"
			% t.director.pit_assists)
	await _check_ram(t)
	t.expect(6)
	t.finish()


## A unit that rams the rear quarter of the player gives no tap.
func _check_ram(t: T) -> void:
	var assists := t.director.pit_assists
	t.director.clear_pursuit()
	t.director.force_role(PoliceFleet.Role.RAM)
	t.player.reset_to(t.straight_start(-500.0))
	await t.idle(0.3)
	var cop: PoliceCar = t.director.spawn_unit_at(t.straight_start(-520.0),
			PoliceFleet.Role.RAM)
	if cop == null:
		t.check(false, "the ramming unit is on the road")
		return
	cop.linear_velocity = Vector3(32.0, 0.0, 0.0)
	for i in int(20.0 * 120.0):
		await t.drive_frame(0.0, 90.0)
		if t.hits_of(cop) > 0:
			break
	t.check(t.hits_of(cop) > 0, "the ramming unit touches the player (%d contacts)"
			% t.hits_of(cop))
	t.check(t.director.pit_assists == assists, "a ram gives no tap (%d)"
			% t.director.pit_assists)

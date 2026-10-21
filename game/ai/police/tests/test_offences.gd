extends Node
## The offences of the dossier §3.4 (the lead note P-INT1).
##
##   tools/godot.sh test res://ai/police/tests/test_offences.gd
##
## Exactly four offences start a pursuit: toll_evaded, speeding, hit_police and hit_traffic. A
## patrol that stands on the road does not chase an innocent player, nothing counts during the
## grace after the player appears and every offence is reported once.

const T := preload("res://ai/police/tests/police_test.gd")
const SPEEDING_KMH := 185.0
const PARKED_TIME := 25.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	await _check_patrol(t)
	await _check_speeding(t)
	await _check_no_sight(t)
	await _check_reckless(t)
	await _check_respawn_grace(t)
	await _check_traffic_out_of_sight(t)
	await _check_edge_trigger(t)
	t.expect(16)
	t.finish()


## A parked player is not chased: the patrols stay on their round.
func _check_patrol(t: T) -> void:
	await t.idle(PARKED_TIME)
	t.check(t.director.pursuit_state == &"none",
			"a parked player is not chased (%s)" % t.director.pursuit_state)
	t.check(t.director.heat == 0, "the heat stays at zero (%d)" % t.director.heat)
	var patrolling := 0
	for unit in t.director.units:
		if unit.state == PoliceCar.State.PATROL:
			patrolling += 1
	t.check(patrolling == t.director.units.size(),
			"every patrol stays in PATROL (%d of %d)" % [patrolling, t.director.units.size()])
	var closest := 9999.0
	for unit in t.director.units:
		closest = minf(closest, unit.global_position.distance_to(t.player.global_position))
	t.check(closest > 3.0, "the patrols keep their distance (%.0f m)" % closest)


## Speeding in front of a patrol starts the pursuit.
func _check_speeding(t: T) -> void:
	await t.wait_grace()
	# A patrol next to the road, in the sight of the player (in the next lane, so the player
	# passes it without touching it).
	# The patrol stands fifty metres in front of the player, in the next lane: the player is
	# over the speed limit while the patrol still sees him.
	var spot: Transform3D = t.straight_start(-450.0).translated(Vector3(0.0, 0.0, 4.0))
	var cop: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PATROL)
	t.check(cop != null, "the patrol is on the road")
	var before := int(t.director.offences.reported_kinds.get(&"speeding", 0))
	# The player drives eight seconds: he is over the speed limit for a few seconds, so the
	# patrol has the time to see it.
	await t.drive(8.0, 0.0, SPEEDING_KMH)
	t.check(t.director.pursuit_state == &"chase",
			"speeding in front of a patrol starts the pursuit (%s)" % t.director.pursuit_state)
	t.check(t.director.heat == 1, "the pursuit runs at heat 1 (%d)" % t.director.heat)
	var speeding := int(t.director.offences.reported_kinds.get(&"speeding", 0))
	t.check(speeding - before <= 1, "the offence is reported once (%d reports)"
			% (speeding - before))


## Speeding without a patrol in sight starts nothing.
func _check_no_sight(t: T) -> void:
	t.director.spawn_enabled = false
	t.director.clear_pursuit()
	var before := t.director.offences.reported
	await t.drive(3.0, 0.0, SPEEDING_KMH)
	t.check(t.director.pursuit_state == &"none",
			"speeding out of sight starts nothing (%s)" % t.director.pursuit_state)
	t.check(t.director.offences.reported == before, "no offence is reported (%d)"
			% (t.director.offences.reported - before))


## An unknown offence kind is ignored.
func _check_reckless(t: T) -> void:
	t.director.spawn_enabled = false
	Events.infraction.emit(t.player, &"reckless")
	await t.idle(0.5)
	t.check(t.director.pursuit_state == &"none",
			"an unknown offence starts nothing (%s)" % t.director.pursuit_state)


## Nothing counts during the grace after the player respawns.
func _check_respawn_grace(t: T) -> void:
	t.director.spawn_enabled = false
	var before := t.director.offences.reported
	Events.player_respawned.emit()
	await t.idle(3.0)
	t.check(t.director.pursuit_state == &"none",
			"nothing counts during the grace after a respawn (%s)" % t.director.pursuit_state)
	t.check(t.director.offences.reported == before, "no offence is reported in the grace")


## The offence of the traffic hit only counts when a patrol sees the player.
func _check_traffic_out_of_sight(t: T) -> void:
	t.director.spawn_enabled = false
	var before := t.director.offences.reported
	Events.infraction.emit(t.player, &"hit_traffic")
	await t.idle(0.5)
	t.check(t.director.offences.reported == before,
			"a traffic hit out of sight is ignored (%d reports)" % t.director.offences.reported)
	t.check(t.director.pursuit_state == &"none", "a traffic hit out of sight starts nothing")


## Every offence is reported once, not once per frame.
func _check_edge_trigger(t: T) -> void:
	t.director.spawn_enabled = false
	t.director.clear_pursuit()
	var before := t.director.offences.reported
	for i in 10:
		Events.infraction.emit(t.player, &"toll_evaded")
	await t.idle(0.05)
	var delta := t.director.offences.reported - before
	t.check(delta <= 1, "the offence is edge triggered (%d reports in 0.5 s)" % delta)

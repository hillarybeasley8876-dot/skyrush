extends Node
## The crowd of police units (the push train of the review round 3).
##
##   tools/godot.sh test res://ai/police/tests/test_bust_crowd.gd
##
## A crowd of pursuing units must not shove a braking player down the road: the units keep
## the gap to the car in front, so the player can stop and be busted.
##
##   K4: three pursuing units, the player at 30 km/h for ten seconds and then the brake.
##   B3: eight pursuing units, the same stop.
##
## The player is NOT pinned: a pinned player cannot show a push train.

const T := preload("res://ai/police/tests/police_test.gd")
## The speed of the player before the brake (km/h).
const CRUISE_KMH := 30.0
## The seconds the player cruises before the brake.
const CRUISE_TIME := 10.0
## The speed under which the player counts as stopped (km/h).
const STOPPED_KMH := 5.0
## The seconds the player has to stop after the brake.
const STOP_TIME := 3.0
## The seconds the busted meter has to be full after the stop.
const BUST_TIME := 8.0
## The number of units of the two runs.
const SMALL_CROWD := 3
const BIG_CROWD := 8


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	t.director.remove_all_units()
	t.director.force_role(PoliceFleet.Role.PURSUE)
	# The traffic would push the player: the test measures the police.
	t.clear_traffic()
	await t.idle(3.0)
	await _check_crowd(t, SMALL_CROWD)
	await _check_crowd(t, BIG_CROWD)
	t.expect(6)
	t.finish()


## A crowd of units, a player that brakes: he has to stop and be busted.
func _check_crowd(t: T, count: int) -> void:
	t.director.clear_pursuit()
	t.director.remove_all_units()
	t.director.force_role(PoliceFleet.Role.PURSUE)
	t.player.reset_to(t.straight_start(-500.0))
	t.start_pursuit(3)
	await t.idle(0.3)
	# The units are lined up behind the player, with a gap between them.
	for i in count:
		var spot: Transform3D = t.straight_start(-500.0 - 12.0 * float(i + 1))
		var unit: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
		if unit != null:
			unit.linear_velocity = Vector3(CRUISE_KMH / 3.6, 0.0, 0.0)
	var collisions := t.police_collisions
	# The player cruises: the units catch up.
	await t.drive(CRUISE_TIME, 0.0, CRUISE_KMH)
	# The brake: the player has to come to a stop on his own.
	var stopped := await t.brake_until_stopped(STOP_TIME, 0.0, STOPPED_KMH)
	t.check(stopped >= 0.0 and stopped <= STOP_TIME,
			"the player stops within %.0f s of the brake (%d units, %.1f s)"
			% [STOP_TIME, count, stopped])
	var busted_at := -1.0
	for i in int(BUST_TIME * Engine.physics_ticks_per_second):
		await t.drive_frame(0.0, 0.0)
		if t.director.pursuit_state == &"busted":
			busted_at = float(i) / Engine.physics_ticks_per_second
			break
	t.check(busted_at >= 0.0, "the player is busted after the stop (%d units, %.1f s)"
			% [count, busted_at])
	t.check(t.police_collisions == collisions,
			"no police car pushes another one (%d units, %d contacts)"
			% [count, t.police_collisions - collisions])

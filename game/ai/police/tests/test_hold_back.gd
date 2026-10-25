extends Node
## The hold-back of §6.3: never more than three units within thirty metres of the player.
##
##   tools/godot.sh test res://ai/police/tests/test_hold_back.gd
##
## Eight units chase a player at 30 km/h. The three nearest keep their roles; the others keep
## their distance, so the road in front of the player stays free. When the player stops, the
## meter of the bust fills.

const T := preload("res://ai/police/tests/police_test.gd")
## The number of units of the chase.
const UNITS := 8
## The heat of the chase (the budget of the heat table).
const HEAT := 4
## The speed of the player (km/h).
const CRUISE_KMH := 30.0
## The seconds the chase runs before the player stops.
const CHASE_TIME := 20.0
## The seconds the check of the hold-back starts after the first unit is on the road.
const CHECK_AFTER := 3.0
## The radius the rule is about (m).
const RULE_RADIUS := 30.0
## The number of units that may be inside it.
const RULE_COUNT := 3
## The seconds the busted meter has to be full after the stop.
const BUST_TIME := 8.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	t.director.remove_all_units()
	t.director.force_role(PoliceFleet.Role.PURSUE)
	t.clear_traffic()
	await t.idle(3.0)
	t.start_pursuit(HEAT)
	await t.idle(0.3)
	# The units are spread on the road behind the player.
	for i in UNITS:
		var spot: Transform3D = t.straight_start(-500.0 - 40.0 - 10.0 * float(i))
		var unit: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
		if unit != null:
			unit.linear_velocity = Vector3(CRUISE_KMH / 3.6, 0.0, 0.0)
	var worst := 0
	var frames_over := 0
	var frames := 0
	for i in int(CHASE_TIME * Engine.physics_ticks_per_second):
		await t.drive_frame(0.0, CRUISE_KMH)
		if float(i) / Engine.physics_ticks_per_second < CHECK_AFTER:
			continue
		frames += 1
		var close := _close_units(t)
		worst = maxi(worst, close)
		if close > RULE_COUNT:
			frames_over += 1
	t.check(frames_over == 0, "never more than %d units within %d m (%d of %d frames, worst %d)"
			% [RULE_COUNT, int(RULE_RADIUS), frames_over, frames, worst])
	# The player stops: the units come in and the meter fills.
	var stopped := await t.brake_until_stopped(3.0, 0.0, 5.0)
	t.check(stopped >= 0.0, "the player stops (%.1f s)" % stopped)
	var busted_at := -1.0
	for i in int(BUST_TIME * Engine.physics_ticks_per_second):
		await t.drive_frame(0.0, 0.0)
		if t.director.pursuit_state == &"busted":
			busted_at = float(i) / Engine.physics_ticks_per_second
			break
	t.check(busted_at >= 0.0, "the player is busted after the stop (%.1f s)" % busted_at)
	t.expect(3)
	t.finish()


## The number of units within the rule radius of the player.
func _close_units(t: T) -> int:
	var count := 0
	for unit in t.director.units:
		if unit.is_wrecked:
			continue
		if unit.global_position.distance_to(t.player.global_position) <= RULE_RADIUS:
			count += 1
	return count

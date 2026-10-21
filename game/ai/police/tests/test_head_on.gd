extends Node
## The head-on unit (ref/gameplay/DOSSIER.md §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_head_on.gd
##
## The SUV comes from an oncoming lane, 350-450 m ahead of the player, and drives into his lane
## at 25 m/s. A unit that is placed far away stays where it was put.

const T := preload("res://ai/police/tests/police_test.gd")
const PLAYER_KMH := 80.0
## The time the head-on unit has to reach the player (s).
const CHARGE_TIME := 20.0
## The distance in which the head-on unit counts as a pass (m).
const PASS_DISTANCE := 3.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	# The test measures the charge, so the dispatcher does not put a roadblock in front of it.
	t.director.blockade.auto_spawn = false
	# The unit of the test keeps the role of the head-on (the heat table would give it the
	# role of an ordinary chase).
	t.director.force_role(PoliceFleet.Role.HEAD_ON)
	t.director.start_pursuit(4)
	await _check_spot(t)
	await _check_charge(t)
	await _check_placement(t)
	t.expect(8)
	t.finish()


## The head-on spot is an oncoming lane ahead of the player, on his route.
func _check_spot(t: T) -> void:
	var spot: Dictionary = t.director.spawner.spots.head_on_spot(t.player, t.director.lane,
			t.director.lane_offset)
	t.check(not spot.is_empty(), "the spawner finds an oncoming lane")
	if spot.is_empty():
		return
	var position: Vector3 = spot["position"]
	var forward := t.player.get_forward()
	# The spot is AHEAD of the player: the unit comes towards him.
	t.check((position - t.player.global_position).dot(forward) > 0.0,
			"the spot is ahead of the player")
	var distance := position.distance_to(t.player.global_position)
	t.check(distance >= 340.0 and distance <= 460.0, "the spot is 350-450 m ahead (%.0f m)"
			% distance)
	# The unit of the spot comes at the player.
	var spot_forward: Vector3 = -spot["transform"].basis.z
	t.check(spot_forward.dot(forward) < -0.5, "the unit of the spot comes at the player (%.2f)"
			% spot_forward.dot(forward))


## The unit charges the player.
func _check_charge(t: T) -> void:
	var spot: Dictionary = t.director.spawner.spots.head_on_spot(t.player, t.director.lane,
			t.director.lane_offset)
	if spot.is_empty():
		t.check(false, "the head-on unit can be placed")
		return
	var cop: PoliceCar = t.director.spawn_unit_at(spot["transform"],
			PoliceFleet.Role.HEAD_ON)
	t.check(cop != null, "the head-on unit is on the road")
	if cop == null:
		return
	var closest := 9999.0
	for i in int(CHARGE_TIME * 120.0):
		await t.drive_frame(0.0, PLAYER_KMH)
		closest = minf(closest, cop.global_position.distance_to(t.player.global_position))
		if t.hits_of(cop) > 0:
			break
	t.check(t.hits_of(cop) > 0 or closest < PASS_DISTANCE,
			"the head-on unit reaches the player (%.1f m, %d contacts of the SUV)"
			% [closest, t.hits_of(cop)])


## A unit that is placed far away stays where it was put.
func _check_placement(t: T) -> void:
	var spot: Transform3D = t.straight_start(-800.0)
	var cop: PoliceCar = t.director.spawn_unit_at(spot, PoliceFleet.Role.PURSUE)
	t.check(cop != null, "the unit is placed 300 m away")
	if cop == null:
		return
	await t.idle(1.0)
	var distance := cop.global_position.distance_to(t.player.global_position)
	t.check(distance > 200.0, "the unit stays where it was put (%.0f m)" % distance)

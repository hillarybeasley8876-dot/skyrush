extends Node
## The police drone (ref/gameplay/DOSSIER.md §3.4 and §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_drone.gd
##
## From heat 4 on a drone follows the player 30-40 m above the road, keeps the line of sight and
## drops a spike strip on the road ahead of the player.

const T := preload("res://ai/police/tests/police_test.gd")
## The seconds the police lose sight after a flash charge (the test holds the blindness).
const BLIND := 5.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	t.director.spawn_enabled = false
	await _check_drone(t)
	await _check_sight(t)
	t.expect(13)
	t.finish()


## The drone appears at heat 4, hovers over the player and drops a spike strip.
func _check_drone(t: T) -> void:
	t.start_pursuit(1)
	await t.idle(0.4)
	t.check(t.director.drones.is_empty(), "there is no drone at heat 1")
	t.director.force_heat(4)
	await t.idle(0.5)
	t.check(t.director.drones.size() == 1, "there is one drone at heat 4 (%d)"
			% t.director.drones.size())
	var drone := t.director.drones[0]
	await t.idle(3.0)
	var height := drone.global_position.y - t.player.global_position.y
	t.check(height > 25.0 and height < 45.0, "the drone hovers 30-40 m above (%.1f m)" % height)
	var behind := drone.global_position.distance_to(t.player.global_position)
	t.check(behind > 5.0, "the drone keeps its distance (%.1f m)" % behind)
	t.check(drone.seen, "the drone keeps the line of sight")
	# The spike strip: the drone drops it 120 m ahead of the player.
	t.director.strips.clear()
	drone.force_spike_drop()
	await t.idle(0.5)
	t.check(t.director.strips.size() == 1, "the drone drops a spike strip (%d)"
			% t.director.strips.size())
	if not t.director.strips.is_empty():
		var strip := t.director.strips[0]
		var distance := strip.global_position.distance_to(t.player.global_position)
		t.check(distance > 100.0 and distance < 140.0,
				"the strip lands ahead of the player (%.0f m)" % distance)
	# Two drones at heat 5.
	t.director.force_heat(5)
	await t.idle(0.5)
	t.check(t.director.drones.size() == 2, "there are two drones at heat 5 (%d)"
			% t.director.drones.size())


## The line of sight of the drone: in the open the pursuit goes on, and when the police lose the
## sight the pursuit searches and then cools down.
func _check_sight(t: T) -> void:
	t.director.force_heat(4)
	await t.idle(0.5)
	t.check(t.director.pursuit.seen_now, "the drone sees the player in the open")
	t.check(t.director.pursuit_state == &"chase", "the pursuit goes on in the open (%s)"
			% t.director.pursuit_state)
	# The police lose the sight: the flash charge blinds the drone too.
	await t.idle(5.0, true)
	t.check(t.director.pursuit.state == &"search", "the police search after four seconds (%s)"
			% t.director.pursuit.state)
	await t.idle(3.0, true)
	t.check(t.director.pursuit.state == &"cooldown", "the pursuit cools down (%s)"
			% t.director.pursuit.state)
	t.check(t.director.pursuit.evade > 0.0, "the evade bar fills (%.2f)"
			% t.director.pursuit.evade)

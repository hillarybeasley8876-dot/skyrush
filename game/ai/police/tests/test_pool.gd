extends Node
## The pool of the police objects (the groups of the cars).
##
##   tools/godot.sh test res://ai/police/tests/test_pool.gd
##
## A car that waits in the pool is no police car on the road: it must not be in the group
## "police" (the audio unit would give it a siren) and not in the group "vehicles". The cars of
## a roadblock that stand on the road ARE police cars.

const T := preload("res://ai/police/tests/police_test.gd")


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	t.director.remove_all_units()
	var group := t.tree.root.get_tree().get_nodes_in_group("police")
	t.check(group.is_empty(), "the pool is not on the road (%d police cars)" % group.size())
	# A block with its cars on the road.
	t.director.blockade.clear_blocks()
	t.director.blockade.auto_spawn = false
	t.director.force_heat(3)
	t.director.spawn_roadblock_now()
	await t.idle(0.3)
	if t.director.blockade.blocks.is_empty():
		t.check(false, "the block of the test is on the road")
		t.expect(2)
		t.finish()
		return
	var block: PoliceRoadblock = t.director.blockade.blocks[0]
	var cars := block.active_cars()
	t.check(not cars.is_empty(), "the block has cars on the road (%d)" % cars.size())
	var group2 := t.tree.root.get_tree().get_nodes_in_group("police")
	t.check(group2.size() == cars.size(),
			"only the cars of the block are police cars (%d of %d)"
			% [group2.size(), cars.size()])
	t.expect(3)
	t.finish()

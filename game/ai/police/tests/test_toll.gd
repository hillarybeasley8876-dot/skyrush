extends Node
## The closed toll plazas (ref/gameplay/DOSSIER.md §3.4).
##
##   tools/godot.sh test res://ai/police/tests/test_toll.gd
##
## From heat 5 the police close the toll plazas of the route: the cars of a block stand across
## every lane of the plaza, and the block faces the player.

const T := preload("res://ai/police/tests/police_test.gd")
## The distance of the plaza ahead of the player (m).
const PLAZA_AHEAD := 450.0
## The distance the block may be from the plaza (m).
const CLOSE_RANGE := 30.0


## A world with a toll plaza on it (the sandbox has none).
class FakeTollWorld extends WorldBase:
	var pois: Array[Dictionary] = []
	var road: Transform3D = Transform3D.IDENTITY

	func get_points_of_interest() -> Array[Dictionary]:
		return pois

	func nearest_road_transform(_pos: Vector3) -> Transform3D:
		return road


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	t.director.remove_all_units()
	t.director.force_heat(5)
	var fake := FakeTollWorld.new()
	t.tree.root.add_child(fake)
	# The plaza is on the route of the player, 450 m ahead of him.
	var graph := t.director.spawner.ctx.graph
	var lane := t.director.lane
	var s := t.director.lane_offset + PLAZA_AHEAD
	if s > graph.lane_length(lane):
		lane = 0
		s = 0.0
	var plaza := graph.position_at(lane, s)
	fake.road = graph.transform_at(lane, s, 0.0)
	fake.pois = [{"kind": &"toll", "position": plaza, "label": "test"}]
	t.director.blockade.toll.set_world(fake)
	t.director.blockade.clear_blocks()
	# Only the toll closure: the dispatcher must not put a roadblock on the road as well.
	t.director.blockade.auto_spawn = false
	for i in 8:
		t.director.blockade.update(1.0, 5, t.player, t.director.lane, t.director.lane_offset)
		await t.idle(0.1)
	var blocks := t.director.blockade.blocks
	t.check(blocks.size() == 1, "the plaza is closed (%d blocks)" % blocks.size())
	if blocks.is_empty():
		t.expect(3)
		t.finish()
		return
	var block: PoliceRoadblock = blocks[0]
	t.check(block.global_position.distance_to(plaza) <= CLOSE_RANGE,
			"the block stands at the plaza (%.0f m)" % block.global_position.distance_to(plaza))
	var cars := block.active_cars()
	t.check(not cars.is_empty() and t.director.blockade.block_cars.size() == cars.size(),
			"the cars of the block are on the road (%d cars, %d in the list)"
			% [cars.size(), t.director.blockade.block_cars.size()])
	# A plaza behind the player is not closed.
	fake.pois = [{"kind": &"toll", "position": t.player.global_position
			- t.player.get_forward() * 200.0, "label": "behind"}]
	t.director.blockade.toll.set_world(fake)
	for i in 8:
		t.director.blockade.update(1.0, 5, t.player, t.director.lane, t.director.lane_offset)
		await t.idle(0.1)
	t.check(t.director.blockade.blocks.size() == 1,
			"a plaza behind the player is not closed (%d blocks)" % t.director.blockade.blocks.size())
	t.expect(4)
	t.finish()

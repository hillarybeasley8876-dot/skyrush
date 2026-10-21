extends Node
## Probe: why do a few props still stand on the carriageway? The probe re-runs the filter on the
## places of the offenders and prints what it says.
## Run: tools/godot.sh test res://world/tests/test_prop_diagnose.gd

const CityData := preload("res://world/loader/city_data.gd")
const LaneIndex := preload("res://world/api/lane_index.gd")
const FurnitureFilter := preload("res://world/build/furniture_filter.gd")

const LANE_CLEARANCE := 2.2


func _ready() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	CityData.forced_city_path = repo.path_join("data/city/city.json")
	var packed := load("res://world/world.tscn") as PackedScene
	var world := packed.instantiate() as WorldBase
	get_tree().root.add_child(world)
	for i in 600:
		await get_tree().process_frame
		if world.is_ready():
			break
	var lanes := world.get_lane_paths()
	var index := LaneIndex.new()
	index.build(lanes)
	var positions: Array[Vector3] = world.get_furniture_positions()
	var kinds: Array[String] = world.get("_builder").furniture_kinds
	var filter := FurnitureFilter.new()
	filter.setup(lanes, [], [], [], world.get("_builder").lane_grid)
	var shown := 0
	for i in positions.size():
		if not _on_carriageway(index, lanes, positions[i]):
			continue
		print("[probe] offender %s at %s" % [kinds[i], str(positions[i])])
		print("[probe]   the filter says it is on the road: %s" % filter.on_carriageway(positions[i]))
		var grid: Object = world.get("_builder").lane_grid
		var near: Dictionary = grid.query_near(positions[i], 20.0)
		print("[probe]   the grid sees %d lanes" % (near["lanes"] as PackedInt32Array).size())
		var ids: PackedInt32Array = near["lanes"]
		var dists: PackedFloat32Array = near["distances"]
		var heights: PackedFloat32Array = near["heights"]
		for k in ids.size():
			print("[probe]     lane %d dist %.2f height %.2f" % [ids[k], dists[k], heights[k]])
		var moved: Variant = filter.place(positions[i], 0.0, kinds[i], "", "")
		print("[probe]   the filter would move it to %s" % str(moved))
		for candidate in index.candidates(positions[i], 24.0):
			var lane := lanes[candidate]
			var offset := lane.curve.get_closest_offset(positions[i])
			var closest := lane.curve.sample_baked(offset, true)
			print("[probe]   lane %s at %.2f m (width %.2f, y %.2f)" % [lane.road_id,
				Vector2(closest.x - positions[i].x, closest.z - positions[i].z).length(),
				lane.lane_width, closest.y])
		shown += 1
		if shown >= 3:
			break
	get_tree().quit(0)


func _on_carriageway(index: LaneIndex, lanes: Array[LanePath], position: Vector3) -> bool:
	for i in index.candidates(position, 24.0):
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(position)
		var closest := lane.curve.sample_baked(offset, true)
		if absf(closest.y - position.y) > 2.5:
			continue
		if Vector2(closest.x - position.x, closest.z - position.z).length() < LANE_CLEARANCE:
			return true
	return false

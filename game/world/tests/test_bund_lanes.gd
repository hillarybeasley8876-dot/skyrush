extends Node
## No lane of the city runs through a building of the Bund.
##
## The Bund buildings stand 16 m from the centre line of the dossier, the cars drive on the road of the city, and that road starts at
## (0, 0) where the dossier line starts at (4.2, -10.2) and bulges up to 7 m west of it: the facades stood in the west lanes of the
## Bund (blender/bund/data.py follows the road of the city now), and the cross streets (Guangdong, Hankou, Jiujiang, Beijing East ...)
## run to the centre line of the Bund through the row (blender/city/roads/buildingcut.py ends them at the buildings). A car on a lane
## that goes through a collider box stops dead against a facade: the traffic and the rivals did.
## Run: python tools/gd.py test res://world/tests/test_bund_lanes.gd -- --timeout=290

const MAIN := "res://main.tscn"
const STEP := 4.0
## The window of the Bund (x, z).
const WINDOW := Rect2(-340.0, -1000.0, 340.0, 1000.0)
## A thin box (the roads unit cuts the lanes that come within 0.3 m of a box, so a box of half a metre only touches what is inside).
const PROBE := Vector3(0.5, 0.74, 1.0)
const PROBE_LIFT := 0.71
const MAX_HITS := 0
## The part of the lanes that has to be left (a pass that deletes the lanes passes this test too).
const MIN_SAMPLES := 3000
## The lanes of the city (a build that loses lanes fails here): 11,359 with the duplicate connectors of the offset crossings,
## 10,790 since roads-lane-dupes removed the 665 duplicates (and the junction jobs added the movements of 130 approaches).
const MIN_STREET_LANES := 10500

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _owner_name(body: Object) -> String:
	var node := body as Node
	var chain := ""
	var depth := 0
	while node != null and depth < 3:
		chain += "/" + String(node.name)
		node = node.get_parent()
		depth += 1
	return chain


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var space := get_tree().root.world_3d.direct_space_state
	var shape := BoxShape3D.new()
	shape.size = PROBE
	var samples := 0
	var hits: Array[String] = []
	var lanes := Game.world.get_lane_paths()
	for lane: LanePath in lanes:
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var offset := 1.0
		while offset < length - 1.0:
			var p := lane.curve.sample_baked(offset, true)
			var q := lane.curve.sample_baked(minf(offset + 3.0, length), true)
			offset += STEP
			if p.y > 6.0 or not WINDOW.has_point(Vector2(p.x, p.z)):
				continue
			var dir := Vector3(q.x - p.x, 0.0, q.z - p.z)
			if dir.length() < 0.1:
				continue
			samples += 1
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.collision_mask = 1
			query.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), Vector3(p.x, p.y + PROBE_LIFT, p.z))
			for entry in space.intersect_shape(query, 8):
				var name := _owner_name(entry["collider"])
				if name.contains("Bund_") and not name.contains("Promenade"):
					hits.append("%s (%s at %.0f %.0f)" % [name.get_file(), String(lane.road_id), p.x, p.z])
	_check(lanes.size() >= MIN_STREET_LANES, "the city keeps its lanes", "(%d)" % lanes.size())
	_check(samples >= MIN_SAMPLES, "the window of the Bund holds lane samples", "(%d)" % samples)
	_check(hits.size() <= MAX_HITS, "no lane runs through a building of the Bund (%.1f m wide probe)" % PROBE.x,
		"(%d of %d samples: %s)" % [hits.size(), samples, ", ".join(hits.slice(0, 4))])
	get_tree().quit(1 if _failures > 0 else 0)

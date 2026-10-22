extends Node
## Probe: which colliders stand in the way of a car on the follow paths of a directory?
##
##   SKYRUSH_PATHS=F:/dev/_scratch/chain_paths_v2 python tools/gd.py test res://world/tests/probe_path_blockers.gd
##
## The world is built from the real city (the roads, the buildings, the furniture), then a car-sized box (the body of the
## player's car, 0.30 m above the path so the road surface itself is not hit) is moved along every path of the directory,
## a point per metre, and tested against the colliders of the world and of the props. Every point that touches a collider is
## printed with the collider's path, and the run ends with "PATH_BLOCKERS n blocked points in m paths".
## The exit code is 1 when a point is blocked, 0 otherwise. It is a probe, not a test of the game: the file name has no test_
## prefix, so run_tests.py does not pick it up.

const CityData := preload("res://world/loader/city_data.gd")

const BOX := Vector3(1.9, 1.0, 4.2)   ## width, height, length of the body of the car
const LIFT := 0.30                    ## m: the underside of the box above the path (the wheels and the ground clearance)
const STEP := 1.0                     ## m between two probe points
const MASK := 0b101                   ## the world (1) and the props (3)

var _blocked := 0
var _paths := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var dir_path := OS.get_environment("SKYRUSH_PATHS")
	if dir_path == "":
		print("SKYRUSH_PATHS is not set")
		get_tree().quit(2)
		return
	var repo := CityData.repo_root()
	CityData.forced_city_path = repo.path_join("data/city/city.json")
	var world := (load("res://world/world.tscn") as PackedScene).instantiate() as WorldBase
	get_tree().root.add_child(world)
	for i in 600:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			break
	for i in 5:
		await get_tree().physics_frame
	var space := get_tree().root.world_3d.direct_space_state
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("cannot open %s" % dir_path)
		get_tree().quit(2)
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".json"):
			_probe_file(space, dir_path.path_join(file))
	print("PATH_BLOCKERS %d blocked points in %d paths" % [_blocked, _paths])
	get_tree().quit(1 if _blocked > 0 else 0)


func _probe_file(space: PhysicsDirectSpaceState3D, path: String) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary or not (doc as Dictionary).has("points"):
		return
	_paths += 1
	var raw: Array = (doc as Dictionary)["points"]
	var points: Array[Vector3] = []
	for p in raw:
		points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var shape := BoxShape3D.new()
	shape.size = BOX
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = MASK
	var name := str((doc as Dictionary).get("id", path.get_file()))
	var distance := 0.0
	var next_probe := 0.0
	var blocked_here := 0
	var first := ""
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var forward := (b - a) / length
		var flat := Vector3(forward.x, 0.0, forward.z)
		var basis := Basis.looking_at(flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		while next_probe <= distance + length:
			var p := a + forward * (next_probe - distance)
			query.transform = Transform3D(basis, p + Vector3(0.0, LIFT + BOX.y * 0.5, 0.0))
			var hits := space.intersect_shape(query, 4)
			if not hits.is_empty():
				blocked_here += 1
				_blocked += 1
				var what := _describe(hits[0]["collider"])
				if blocked_here <= 3:
					print("BLOCK %s at %.0f m (%.1f, %.1f, %.1f): %s" % [name, next_probe, p.x, p.y, p.z, what])
				if first == "":
					first = what
			next_probe += STEP
		distance += length
	print("%s %s: %d blocked points%s" % ["ok  " if blocked_here == 0 else "BAD ", name, blocked_here,
			"" if first == "" else " (first: %s)" % first])


func _describe(collider: Object) -> String:
	var node := collider as Node
	if node == null:
		return str(collider)
	var parent := node.get_parent()
	return "%s (%s) under %s" % [node.name, node.get_class(), parent.name if parent != null else "-"]

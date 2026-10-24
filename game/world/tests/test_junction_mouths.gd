extends Node
## No tree, lamp or shelter stands in the box of a junction.
##
## The junction filter of the furniture kept props 8 m away from the centre of a junction, but the box of a junction is bigger: the
## lanes of the street that leaves the Bund begin 13 m after the kerb of the Bund, and the first tree and the first lamp of that street
## stood in the mouth, 3.5 m from the nearest lane (a turning movement). The props are solid now and the first rival that took the turn
## at 20 m/s hit the tree, stopped dead and the other four drove into it. The filter reaches along every road of a junction as far
## as the box (the half width of the roads that cross it plus the kerb returns).
## Run: python tools/gd.py test res://world/tests/test_junction_mouths.gd -- --timeout=290

const MAIN := "res://main.tscn"
const FurnitureFilter := preload("res://world/build/furniture_filter.gd")
## The props the filter judges (the dressed props of the street dresser keep their place in a junction on purpose).
const JUDGED: Array[String] = ["tree", "lamp", "lamp_heritage", "lamp_magnolia", "lamp_deck_double", "bus_stop", "noise_wall",
	"billboard"]
## The mouth of the Bund and Fuzhou Rd, where the tree stood (the regression).
const FUZHOU_MOUTH := Vector3(-119.6, 0.0, -231.1)
const REGRESSION_RADIUS := 3.0

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	var builder: Object = Game.world.get("_builder")
	var data: Object = builder.get("data")
	var filter := FurnitureFilter.new()
	filter.setup(Game.world.get_lane_paths(), data.call("junctions"), data.call("pois"), data.call("roads"),
		builder.get("lane_grid"))
	var entries: Array = builder.get("_furniture_entries")
	var judged := 0
	var inside: Array[String] = []
	var near_regression: Array[String] = []
	for entry: Dictionary in entries:
		var type := String(entry.get("type", ""))
		if not JUDGED.has(type):
			continue
		judged += 1
		var origin: Vector3 = (entry["transform"] as Transform3D).origin
		if filter.in_junction_box(origin):
			inside.append("%s at (%.0f %.0f)" % [type, origin.x, origin.z])
		if Vector2(origin.x - FUZHOU_MOUTH.x, origin.z - FUZHOU_MOUTH.z).length() < REGRESSION_RADIUS:
			near_regression.append("%s at (%.1f %.1f)" % [type, origin.x, origin.z])
	_check(judged > 10000, "the city keeps its trees and lamps", "(%d judged)" % judged)
	_check(inside.is_empty(), "no tree, lamp or shelter stands in the box of a junction",
		"(%d: %s)" % [inside.size(), ", ".join(inside.slice(0, 4))])
	_check(near_regression.is_empty(), "the mouth of Fuzhou Rd on the Bund is free of trees and lamps",
		"(%s)" % ", ".join(near_regression))
	get_tree().quit(1 if _failures > 0 else 0)

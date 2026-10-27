extends Node
## The street furniture the world places (after the furniture filter moved and dropped what it had to), written to a JSON file:
## [[type, x, y, z, road], ...]. tools/city/check_furniture_ground.py reads it with the road tiles and tells what each prop
## stands on (the asphalt, a sidewalk, a planter).
##
##   python tools/gd.py test res://tools/furniture_dump.gd -- --dump=ABS.json --stub=audio,menu,hud,traffic,police,rivals

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dump := Game.option("dump", "")
	if dump == "":
		print("FURNITURE DUMP FAILED: no --dump=<path>")
		get_tree().quit(1)
		return
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(1.0).timeout
	var entries: Array = Game.world.get("_builder").get("_furniture_entries")
	var rows: Array = []
	for entry: Dictionary in entries:
		var origin: Vector3 = (entry.get("transform", Transform3D.IDENTITY) as Transform3D).origin
		rows.append([String(entry.get("type", "?")), snappedf(origin.x, 0.01), snappedf(origin.y, 0.01),
			snappedf(origin.z, 0.01), String(entry.get("road", ""))])
	var file := FileAccess.open(dump, FileAccess.WRITE)
	if file == null:
		print("FURNITURE DUMP FAILED: cannot write %s" % dump)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(rows))
	file.close()
	print("FURNITURE DUMP OK: %d entries to %s" % [rows.size(), dump])
	get_tree().quit(0)

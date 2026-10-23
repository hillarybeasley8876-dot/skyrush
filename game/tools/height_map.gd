extends Node
## The height map of a place: vertical rays over a grid, the height of the first hit (cm) and the collider of it.
## For the questions "what is the bump at (138, 137)?": the numbers are the road under the car, the letters are the
## colliders (the legend follows). A diagnostic tool, not a test.
##
##   python tools/gd.py test res://tools/height_map.gd -- --timeout=300 --stub=audio,menu,hud,traffic,police,rivals --at=138,137 --radius=8 --step=1
##
## Options: at=x,z (the centre)   radius=m (6)   step=m (1)   from=m (the height the rays start at, 40)
##          dir=deg (rotate the grid, so a road that runs diagonally reads along the rows; 0)

const MAIN := "res://main.tscn"
const MASK := 1 | 4


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var at := String(Game.option("at", "0,0")).split(",")
	var radius := float(Game.option("radius", "6"))
	var step := float(Game.option("step", "1"))
	var top := float(Game.option("from", "40"))
	var turn := deg_to_rad(float(Game.option("dir", "0")))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(2.0).timeout
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var centre := Vector3(float(at[0]), 0.0, float(at[1]))
	var names: Dictionary = {}
	var legend := "abcdefghijklmnopqrstuvwxyz"
	var n := int(floor(radius / step))
	print("HEIGHTS centre (%.1f %.1f), radius %.1f, step %.1f, rotated %.0f deg; rows run along +z of the rotated grid" % [
		centre.x, centre.z, radius, step, rad_to_deg(turn)])
	for row in range(-n, n + 1):
		var line := ""
		for col in range(-n, n + 1):
			var offset := Vector3(float(col) * step, 0.0, float(row) * step).rotated(Vector3.UP, turn)
			var from := centre + offset + Vector3.UP * top
			var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (top + 80.0), MASK)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				line += "    .  "
				continue
			var body := hit["collider"] as Node
			var tag := String(body.name) if body != null else "?"
			if not names.has(tag):
				names[tag] = legend[names.size() % legend.length()]
			line += "%5d%s  " % [int(round(((hit["position"] as Vector3).y) * 100.0)), names[tag]]
		print("HEIGHTS ", line)
	for tag in names:
		print("HEIGHTS legend %s = %s" % [names[tag], tag])
	get_tree().quit(0)

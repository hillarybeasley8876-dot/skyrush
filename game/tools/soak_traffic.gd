extends Node
## The traffic soak: the player stands still at several places of the city while the traffic runs for a few minutes of game
## time, and every traffic car is watched. A diagnostic tool, not a test (the traffic tests run seconds, the jams take minutes).
##
##   python tools/gd.py test res://tools/soak_traffic.gd -- --timeout=3000 --stub=audio,menu,hud,police,rivals --sites=6 --seconds=150 --seed=1
##
## Options: sites (6), seconds (150, per site), seed (1), region x0,x1,z0,z1 (the whole city), kmh (a player that drives past
## at this speed along the lane instead of standing still, 0).
##
## What is reported per site (the car is the name of the node, the lane its follower lane):
##   STUCK    a near car that stood still for 30 s, had no car within 12 m in front of it and was not held by a red or an
##            amber light (the head of a jam that no light and no car explains: a deadlock)
##   OVERLAP  two near cars whose centres were closer than 2.4 m for 3 s (they drive through each other)
##   OFFLANE  a near car more than 3.5 m from the centre of its lane for 3 s
##   FAST     a car that moved more than 70 m/s (not a teleport: less than 15 m in one sample)
##   LOW      a car under the ground (3 m under its nearest road: not a car in the tunnel) or over a 60 m of height
##   (only=N runs the site N alone: the random numbers of the others are still drawn, so it is the same place)

const MAIN := "res://main.tscn"
const SAMPLE := 0.5
const STILL_SPEED := 0.3
const STUCK_AFTER := 30.0
const GAP_FREE := 12.0
const OVERLAP_DIST := 2.4
const OVERLAP_AFTER := 3.0
const OFFLANE_DIST := 3.5
const OFFLANE_AFTER := 3.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_run.call_deferred()


func _near_cars() -> Array[TrafficCar]:
	var out: Array[TrafficCar] = []
	for node in get_tree().get_nodes_in_group(&"traffic"):
		var car := node as TrafficCar
		if car != null and car.visible and car.mode == TrafficCarPhysics.Mode.NEAR and car.follower != null:
			out.append(car)
	return out


func _lane_points(region: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var box: PackedStringArray = region.split(",") if region != "" else PackedStringArray()
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null or lane.elevated:
			continue
		var pts: PackedVector3Array = lane.curve.get_baked_points()
		for i in range(0, pts.size() - 1, 40):
			var p := pts[i]
			if p.y > 1.5 or p.y < -0.5:
				continue
			if box.size() == 4 and (p.x < float(box[0]) or p.x > float(box[1]) or p.z < float(box[2]) or p.z > float(box[3])):
				continue
			out.append({"p": p, "d": (pts[i + 1] - p).normalized()})
	return out


## Is the car held by a red or an amber light (it is at the end of its lane and the light of the junction says stop)?
func _held_by_light(car: TrafficCar) -> bool:
	var ctx := car.ctx
	var lane := car.follower.lane
	if ctx == null or ctx.graph == null:
		return false
	var to_end := ctx.graph.lane_length(lane) - car.follower.s
	if to_end > 40.0:
		return false
	var junction := ctx.junction_of(lane)
	var lane_path := ctx.graph.lanes[lane]
	return ctx.signal_state(junction, lane_path.road_id) != 2


## What the box of a car overlaps where it stands: the body, and the size and the place of the shape of that body.
func _overlaps(car: TrafficCar) -> String:
	var shape_node := car.get_node_or_null(^"Collision") as CollisionShape3D
	if shape_node == null:
		return " no shape"
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = 0b10101
	query.exclude = [car.get_rid()]
	query.margin = 0.3
	var out := ""
	for hit in get_viewport().world_3d.direct_space_state.intersect_shape(query, 8):
		var body := hit["collider"] as CollisionObject3D
		var index := int(hit["shape"])
		var rid: RID = PhysicsServer3D.body_get_shape(body.get_rid(), index)
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(body.get_rid(), index)
		var data: Variant = PhysicsServer3D.shape_get_data(rid)
		var at := body.global_transform * xf
		if data is Dictionary and (data as Dictionary).has("faces"):
			# a mesh: the part of it that touches the box of the car (the triangles that overlap its bounding box)
			var faces: PackedVector3Array = (data as Dictionary)["faces"]
			var reach := AABB(query.transform.origin - Vector3(3.0, 3.0, 3.0), Vector3(6.0, 6.0, 6.0))
			var box := AABB()
			var first := true
			var count := 0
			for f in range(0, faces.size() - 2, 3):
				var a := at * faces[f]
				var b := at * faces[f + 1]
				var c := at * faces[f + 2]
				var tri := AABB(a, Vector3.ZERO).expand(b).expand(c)
				if reach.intersects(tri):
					box = tri if first else box.merge(tri)
					first = false
					count += 1
			out += " [%s mesh: %d triangles within 3 m, together x %.1f..%.1f y %.2f..%.2f z %.1f..%.1f]" % [body.name, count,
				box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z]
			continue
		out += " [%s shape %d %s at (%.1f %.1f %.1f) yaw %.0f]" % [body.name, index,
			("box " + str((data as Vector3) * 2.0)) if data is Vector3 else ("cyl " + str(data) if data is Dictionary else str(data).left(30)),
			at.origin.x, at.origin.y, at.origin.z, rad_to_deg(atan2(-at.basis.x.z, at.basis.x.x))]
	return out if out != "" else " none"


func _run() -> void:
	var sites := int(Game.option("sites", "6"))
	var seconds := float(Game.option("seconds", "150"))
	var kmh := float(Game.option("kmh", "0"))
	var only := int(Game.option("only", "-1"))
	_rng.seed = int(Game.option("seed", "1"))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(3.0).timeout
	var player := Game.player as ArcadeCar
	var points := _lane_points(String(Game.option("region", "")))
	print("SOAK %d lane points, %d sites, %.0f s each" % [points.size(), sites, seconds])
	var problems := 0
	for site in sites:
		var pick: Dictionary = points[_rng.randi_range(0, points.size() - 1)]
		var p: Vector3 = pick["p"]
		# the player stands 7 m beside the lane, frozen: a car that stands on a lane is a car the traffic runs into
		if only >= 0 and site != only:
			continue
		var side := (pick["d"] as Vector3).cross(Vector3.UP).normalized() * (7.0 if kmh <= 0.0 else 0.0)
		player.reset_to(Transform3D(Basis(), p + side + Vector3.UP * 0.6))
		if kmh <= 0.0:
			player.freeze = true
		else:
			player.freeze = false
		await get_tree().physics_frame
		# let the ring of traffic fill up around the player
		await get_tree().create_timer(6.0).timeout
		var still: Dictionary = {}     # car id -> seconds standing still
		var close: Dictionary = {}     # "a_b" -> seconds closer than OVERLAP_DIST
		var off: Dictionary = {}       # car id -> seconds off the lane
		var last: Dictionary = {}      # car id -> last position
		var told: Dictionary = {}
		var t := 0.0
		var cars_seen := 0
		while t < seconds:
			for k in int(SAMPLE * Engine.physics_ticks_per_second):
				await get_tree().physics_frame
			t += SAMPLE
			var cars := _near_cars()
			cars_seen = maxi(cars_seen, cars.size())
			for car in cars:
				var id := car.get_instance_id()
				var here := car.global_position
				var moved := here.distance_to(last[id]) if last.has(id) else 0.0
				last[id] = here
				var speed := moved / SAMPLE
				# stuck
				if speed < STILL_SPEED and not car.stopped:
					still[id] = float(still.get(id, 0.0)) + SAMPLE
				else:
					still[id] = 0.0
				if float(still[id]) >= STUCK_AFTER and not told.has("s%d" % id):
					var gap: float = car.get("_driving").leader_gap
					if gap > GAP_FREE and not _held_by_light(car):
						told["s%d" % id] = true
						problems += 1
						var touching := ""
						for body in car.get_colliding_bodies():
							touching += " " + String(body.name)
						var near_props := ""
						var kinds: Array[String] = Game.world.get("_builder").furniture_kinds
						var positions: Array[Vector3] = Game.world.get_furniture_positions()
						for k in positions.size():
							if positions[k].distance_to(here) < 6.0:
								near_props += " %s@%.1fm" % [kinds[k], positions[k].distance_to(here)]
						touching += " | props within 6 m:" + (near_props if near_props != "" else " none")
						touching += " | overlapping shapes:" + _overlaps(car)
						var director: Node = main.get_node_or_null(^"TrafficDirector")
						var listed: bool = director != null and (director.get("cars") as Array).has(car)
						touching += " | frozen %s, in director list %s, stopped %s, despawn %s, mode %d, lane xform dist %.1f m" % [
							str(car.freeze), str(listed), str(car.stopped), str(car.despawn), car.mode,
							car.follower.transform().origin.distance_to(here)]
						print("SOAK STUCK   site %d at (%.0f %.1f %.0f): %s lane %d s %.0f/%.0f, gap ahead %s, standing %.0f s; lane speed %.1f (wants %.1f), body %.1f m off the lane, touching:%s" % [
							site, here.x, here.y, here.z, car.name, car.follower.lane, car.follower.s,
							car.ctx.graph.lane_length(car.follower.lane), "none" if gap == INF else "%.0f m" % gap, float(still[id]),
							car.speed, car.desired_speed, car.lane_error(), touching if touching != "" else " nothing"])
				# fast / low
				if speed > 70.0 and moved < 15.0 and not told.has("f%d" % id):
					told["f%d" % id] = true
					problems += 1
					print("SOAK FAST    site %d at (%.0f %.1f %.0f): %s moved %.0f m/s" % [site, here.x, here.y, here.z, car.name, speed])
				# under the ground is under its road: the Yan'an tunnel runs 28 m down, a car in it is where it should be
				var low := here.y < -2.0 and here.y < Game.world.nearest_road_transform(here).origin.y - 3.0
				if (low or here.y > 60.0 or is_nan(here.y)) and not told.has("l%d" % id):
					told["l%d" % id] = true
					problems += 1
					print("SOAK LOW     site %d at (%.0f %.1f %.0f): %s" % [site, here.x, here.y, here.z, car.name])
				# off the lane: the body against the centre of its lane
				var lane_path := car.ctx.graph.lanes[car.follower.lane]
				if lane_path != null and lane_path.curve != null and car.follower.connector == null:
					var closest: Vector3 = lane_path.curve.get_closest_point(here)
					var away: float = closest.distance_to(here)
					if away > OFFLANE_DIST:
						off[id] = float(off.get(id, 0.0)) + SAMPLE
					else:
						off[id] = 0.0
					if float(off[id]) >= OFFLANE_AFTER and not told.has("o%d" % id):
						told["o%d" % id] = true
						problems += 1
						print("SOAK OFFLANE site %d at (%.0f %.1f %.0f): %s %.1f m from lane %d" % [site, here.x, here.y, here.z, car.name, away, car.follower.lane])
			# overlaps
			for i in cars.size():
				for j in range(i + 1, cars.size()):
					var a := cars[i]
					var b := cars[j]
					if a.global_position.distance_squared_to(b.global_position) > 36.0:
						continue
					var key := "%d_%d" % [a.get_instance_id(), b.get_instance_id()]
					if a.global_position.distance_to(b.global_position) < OVERLAP_DIST:
						close[key] = float(close.get(key, 0.0)) + SAMPLE
					else:
						close[key] = 0.0
					if float(close[key]) >= OVERLAP_AFTER and not told.has(key):
						told[key] = true
						problems += 1
						print("SOAK OVERLAP site %d at (%.0f %.1f %.0f): %s and %s, %.1f m apart (lanes %d and %d)" % [
							site, a.global_position.x, a.global_position.y, a.global_position.z, a.name, b.name,
							a.global_position.distance_to(b.global_position), a.follower.lane, b.follower.lane])
		print("SOAK site %d at (%.0f %.0f): %d near cars at most, done" % [site, p.x, p.z, cars_seen])
	print("SOAK DONE: %d problems in %d sites" % [problems, sites])
	get_tree().quit(0)

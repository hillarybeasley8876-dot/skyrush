extends Node
## The parapets of the elevated roads hold a car that drives into them: the car is put on an elevated lane beside the
## parapet, turned into it at an angle, sent at a speed with the throttle held (as a player who keeps pushing does), and
## watched for a few seconds. A car that ends up on the far side of the parapet, or falls off the deck, went over. A
## diagnostic tool, not a test: it prints the runs that went over and a summary line.
##
##   python tools/gd.py test res://tools/parapet_probe.gd -- --timeout=900 --stub=audio,menu,hud,traffic,police,rivals
##   [--places=10] [--seed=1] [--seconds=4] [--angles=15,30,45,60] [--speeds=10,25,50] [--push=1] [--trail=1] [--hz=60|120]
##   [--median=1: the median barrier of the deck instead (to the left of the inner lane): a car that ends up in the other
##   carriageway went over]
##
## The fuzz drive found cars that climbed a parapet under full throttle and fell off the deck. With --median=1 the probe found
## that every car crossed the median barrier of the elevated roads (84 of 90 runs; its collider stood 0.23 m over the road).

const MAIN := "res://main.tscn"
## m: the parapet is looked for this far to the right of the lane, at this height over the lane.
const WALL_SEARCH := 10.0
const WALL_RAY_HEIGHT := 0.6
## m: the car starts with its centre this far from the face of the parapet.
const START_GAP := 3.2
## m: a car whose centre is this far past the face of the parapet went over (half the car and a little: the centre of a car
## that leans on the parapet is about 1 m from its face, on the deck side).
const OVER_MARGIN := 1.2
## The wall has to be found at these offsets along the lane (m), all within WALL_EVEN of the same distance: a lamp post, a sign
## post or the gap where a ramp leaves is no parapet.
const WALL_OFFSETS: Array[float] = [-6.0, -3.0, 0.0, 3.0, 6.0]
const WALL_EVEN := 0.3
## s: a car that has no wheel on the ground this long and is under the deck fell off it (a car that drives down a ramp does not).
const FALL_AIR := 0.4
## m: the run ends after this much scrape along the parapet.
const RUN_ALONG := 40.0
## m: the bottom of a car this high over the road has its wheel mounts (0.69 m up) over the top of a 1.0 m parapet, and
## at LIFT_BOX the floor of its box (0.34 m up) is at the top.
const LIFT_REACH := 0.31
const LIFT_BOX := 0.66
## m: a car whose centre is this far past the face of the median stands in the other carriageway.
const MEDIAN_OVER := 2.0
## m: a car this far under the deck fell off it.
const FALL_DEPTH := 3.0
## The collision mask of the world (the roads and the parapets).
const WORLD_MASK := 1

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	_rng.seed = int(Game.option("seed", "1"))
	var car := Game.player as ArcadeCar
	car.freeze = false
	var places := _median_places(int(Game.option("places", "10"))) if Game.option("median", "0") == "1" 			else _places(int(Game.option("places", "10")))
	var angles := _floats(String(Game.option("angles", "15,30,45,60")))
	var speeds := _floats(String(Game.option("speeds", "10,25,50")))
	var seconds := float(Game.option("seconds", "4"))
	var runs := 0
	var over := 0
	var worst_climb := 0.0
	var rises: Array[float] = []
	for place: Dictionary in places:
		for angle in angles:
			for kmh in speeds:
				runs += 1
				var r := await _drive(car, place, angle, kmh, seconds)
				worst_climb = maxf(worst_climb, float(r["climb"]))
				rises.append(float(r["rise"]))
				if bool(r["over"]):
					over += 1
					print("PARAPET over: %s at (%.0f, %.1f, %.0f), %.0f deg at %.0f km/h: %s" % [place["road"], place["p"].x,
						place["p"].y, place["p"].z, angle, kmh, r["why"]])
	for place: Dictionary in places:
		print("PARAPET place %s (%.1f, %.1f, %.1f)" % [place["road"], place["p"].x, place["p"].y, place["p"].z])
	print("PARAPET %d of %d runs went over (%d places, %d Hz), the highest climb over the deck %.2f m" % [over, runs,
		places.size(), Engine.physics_ticks_per_second, worst_climb])
	rises.sort()
	var lifted := 0
	var high := 0
	for v in rises:
		if v > LIFT_REACH:
			lifted += 1
		if v > LIFT_BOX:
			high += 1
	print("PARAPET the bottom of the car rose over the road: median %.2f m, p90 %.2f m, max %.2f m; %d runs over %.2f m (a wheel probe reaches over a parapet), %d over %.2f m (the box reaches its top)" % [
		rises[rises.size() / 2], rises[rises.size() * 9 / 10], rises[-1], lifted, LIFT_REACH, high, LIFT_BOX])
	Input.action_release(&"accelerate")
	get_tree().quit(0)


## One run: the car beside the parapet of `place`, turned into it by `angle`, at `kmh`, the throttle held (and with
## --push=1 the wheel held towards the parapet, as a player who steers into it). The car is judged against the parapet where
## it is (a parapet is not parallel to the lane over the whole scrape): a ray from the deck side finds the face of the
## parapet beside the car every tick. It went over when its centre is OVER_MARGIN past that face, or when it falls off the
## deck (no wheel on the ground for FALL_AIR and FALL_DEPTH under the deck). The run ends after RUN_ALONG metres of scrape.
func _drive(car: ArcadeCar, place: Dictionary, angle: float, kmh: float, seconds: float) -> Dictionary:
	var t: Vector3 = place["t"]
	var r: Vector3 = place["r"]
	var wall: Vector3 = place["wall"]
	var deck_y: float = float(place["p"].y)
	var heading := t.rotated(Vector3.UP, -deg_to_rad(angle))     # towards the right, where the parapet is
	if bool(place.get("median", false)):
		return await _drive_median(car, place, angle, kmh, seconds)
	var start := wall - r * START_GAP
	start.y = deck_y + 0.25
	car.reset_to(Transform3D(Basis.looking_at(heading, Vector3.UP), start))
	await get_tree().physics_frame
	car.linear_velocity = heading * (kmh / 3.6)
	Input.action_press(&"accelerate")
	if Game.option("push", "0") == "1":
		Input.action_press(&"steer_right")
	var space := get_viewport().get_world_3d().direct_space_state
	var climb := 0.0
	var rise := 0.0       ## the most the bottom of the car rose over the road beside it (m)
	var air := 0.0
	var why := ""
	var trail: Array[String] = []      ## the last 5 s of the run, printed when the car went over (--trail=1)
	for i in int(seconds * Engine.physics_ticks_per_second):
		car.health = car.max_health
		car.power.battery = 1.0
		await get_tree().physics_frame
		var pos := car.global_position
		var along := (pos - wall).dot(t)
		if along > RUN_ALONG:
			break
		air = air + 1.0 / Engine.physics_ticks_per_second if car.thruster.airborne else 0.0
		var at := float(i) / Engine.physics_ticks_per_second
		# the parapet beside the car: from the point of the lane beside it (the lane follows the road, and so does the parapet),
		# at the height of a bumper, along the right of the lane there
		var curve: Curve3D = (place["lane"] as LanePath).curve
		var s := curve.get_closest_offset(pos)
		var lp := curve.sample_baked(s, true)
		var la := curve.sample_baked(maxf(s - 2.0, 0.0), true)
		var lb := curve.sample_baked(s + 2.0, true)
		var lt := Vector3(lb.x - la.x, 0.0, lb.z - la.z).normalized()
		var lr := lt.cross(Vector3.UP).normalized()
		rise = maxf(rise, pos.y - lp.y)
		var from := lp + Vector3.UP * WALL_RAY_HEIGHT
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + lr * WALL_SEARCH, WORLD_MASK))
		var wheels := ""
		for w in car.dynamics.wheels:
			if w.contact:
				var col := w.probe.get_collider(0) as Node
				wheels += " [%s n%.2f %+.2f F%.0f]" % [String(col.name).get_slice("_", 3) if col != null else "?", w.contact_normal.y,
					w.contact_point.y - pos.y, w.load]
			else:
				wheels += " [-]"
		var touches := ""
		var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
		if state != null:
			for c in state.get_contact_count():
				var n := state.get_contact_local_normal(c)
				var cp := state.get_contact_local_position(c)
				touches += " {%s n(%.2f %.2f %.2f) h%+.2f}" % [String((state.get_contact_collider_object(c) as Node).name).get_slice("_", 3),
					n.x, n.y, n.z, cp.y - pos.y]
		trail.append("   t=%.3f y%+.2f vy %+.2f v %.0f pitch %+.0f roll %+.0f off %+.1f |%s |%s" % [at, pos.y - deck_y, car.linear_velocity.y,
			car.linear_velocity.length() * 3.6, rad_to_deg(asin(clampf(-car.global_transform.basis.z.y, -1.0, 1.0))),
			rad_to_deg(asin(clampf(car.global_transform.basis.x.y, -1.0, 1.0))), (pos - lp).dot(lr), wheels, touches])
		if trail.size() > int(5.0 * Engine.physics_ticks_per_second):
			trail.pop_front()
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.3:
			var face: Vector3 = hit["position"]
			var out := -Vector3((hit["normal"] as Vector3).x, 0.0, (hit["normal"] as Vector3).z).normalized()
			var past := (pos - face).dot(out)
			climb = maxf(climb, pos.y - (from.y - WALL_RAY_HEIGHT))
			if past > OVER_MARGIN:
				why = "%.1f m past the face of the parapet at %.2f s, %.1f m over the deck" % [past, at, pos.y - from.y + WALL_RAY_HEIGHT]
				break
		if pos.y < deck_y - FALL_DEPTH and air > FALL_AIR:
			why = "fell off the deck at %.2f s, %.0f m along" % [at, along]
			break
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_right")
	car.linear_velocity = Vector3.ZERO
	if why != "" and Game.option("trail", "0") == "1":
		for i in trail.size():
			print("PARAPET trail" + trail[i])
	return {"over": why != "", "why": why, "climb": climb, "rise": rise}


## A run into the median barrier: `place` has the inner lane, the left of it (`r` points to the median), the face of the
## median. Like the parapet runs, the face is found every tick from the point of the lane beside the car (a spiral turns
## away from a straight line). The car went over when its centre is MEDIAN_OVER past that face (half the barrier and half
## the car: it stands in the other carriageway).
func _drive_median(car: ArcadeCar, place: Dictionary, angle: float, kmh: float, seconds: float) -> Dictionary:
	var t: Vector3 = place["t"]
	var r: Vector3 = place["r"]
	var wall: Vector3 = place["wall"]
	var deck_y: float = float(place["p"].y)
	var curve: Curve3D = (place["lane"] as LanePath).curve
	var heading := t.rotated(Vector3.UP, deg_to_rad(angle))      # towards the left, where the median is
	var start := wall - r * START_GAP
	start.y = deck_y + 0.25
	car.reset_to(Transform3D(Basis.looking_at(heading, Vector3.UP), start))
	await get_tree().physics_frame
	car.linear_velocity = heading * (kmh / 3.6)
	Input.action_press(&"accelerate")
	var space := get_viewport().get_world_3d().direct_space_state
	var why := ""
	var rise := 0.0
	for i in int(seconds * Engine.physics_ticks_per_second):
		car.health = car.max_health
		car.power.battery = 1.0
		await get_tree().physics_frame
		var pos := car.global_position
		if (pos - wall).dot(t) > RUN_ALONG:
			break
		var s := curve.get_closest_offset(pos)
		var lp := curve.sample_baked(s, true)
		var la := curve.sample_baked(maxf(s - 2.0, 0.0), true)
		var lb := curve.sample_baked(s + 2.0, true)
		var lt := Vector3(lb.x - la.x, 0.0, lb.z - la.z).normalized()
		var left := -lt.cross(Vector3.UP).normalized()
		rise = maxf(rise, pos.y - lp.y)
		var from := lp + Vector3.UP * 0.1
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + left * 6.0, WORLD_MASK))
		if hit.is_empty() or not String((hit["collider"] as Node).name).contains("concrete"):
			continue
		var past := (pos - (hit["position"] as Vector3)).dot(left)
		if past > MEDIAN_OVER:
			why = "crossed the median: %.1f m past its face at %.2f s, %.1f m over the road" % [past,
				float(i) / Engine.physics_ticks_per_second, pos.y - lp.y]
			break
	Input.action_release(&"accelerate")
	car.linear_velocity = Vector3.ZERO
	return {"over": why != "", "why": why, "climb": rise, "rise": rise}


## Places beside the median barrier of an elevated road: a straight piece of an inner lane with the barrier to its left,
## found at every offset of WALL_OFFSETS at the same distance, and the road of the other carriageway beyond it.
func _median_places(count: int) -> Array[Dictionary]:
	var lanes: Array = Game.world.get_lane_paths()
	var inner: Array[LanePath] = []
	for lane: LanePath in lanes:
		if lane.elevated and lane.curve != null and lane.curve.get_baked_length() > 80.0 				and not bool(lane.get_meta(&"connector", false)):
			inner.append(lane)
	var space := get_viewport().get_world_3d().direct_space_state
	var out: Array[Dictionary] = []
	var tries := 0
	while out.size() < count and tries < count * 120 and not inner.is_empty():
		tries += 1
		var lane := inner[_rng.randi() % inner.size()]
		var length := lane.curve.get_baked_length()
		var s := _rng.randf_range(30.0, length - 30.0)
		var p := lane.curve.sample_baked(s, true)
		var a := lane.curve.sample_baked(s - 15.0, true)
		var b := lane.curve.sample_baked(s + 15.0, true)
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		if Vector3(p.x - a.x, 0.0, p.z - a.z).normalized().dot(t) < 0.995:
			continue
		var left := -t.cross(Vector3.UP).normalized()
		var gaps: Array[float] = []
		var wall := Vector3.ZERO
		var ok := true
		for offset in WALL_OFFSETS:
			var from := p + t * offset + Vector3.UP * 0.1
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + left * 4.0, WORLD_MASK))
			# the face may lean (the collider of the median was its sloped profile once): any concrete that is not a floor
			if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.75 					or not String((hit["collider"] as Node).name).contains("concrete"):
				ok = false
				break
			gaps.append(((hit["position"] as Vector3) - from).dot(left))
			if offset == 0.0:
				wall = hit["position"]
			var beyond := (hit["position"] as Vector3) + left * 2.5 + Vector3.UP * 2.0
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(beyond, beyond - Vector3.UP * 3.0, WORLD_MASK))
			if floor_hit.is_empty() or absf(float((floor_hit["position"] as Vector3).y) - p.y) > 0.5:
				ok = false
				break
		if not ok or gaps.max() - gaps.min() > WALL_EVEN:
			continue
		out.append({"p": p, "t": t, "r": left, "wall": Vector3(wall.x, p.y, wall.z), "road": String(lane.road_id), "lane": lane,
			"median": true})
	return out


## Places beside an edge parapet of an elevated road: a straight piece of an elevated lane with a wall to its right and a
## drop behind the wall. {p (the lane point), t (the lane direction), r (its right), wall (the face of the parapet), road}
func _places(count: int) -> Array[Dictionary]:
	var lanes: Array = Game.world.get_lane_paths()
	var elevated: Array[LanePath] = []
	for lane: LanePath in lanes:
		if lane.elevated and lane.curve != null and lane.curve.get_baked_length() > 80.0 \
				and not bool(lane.get_meta(&"connector", false)):
			elevated.append(lane)
	var space := get_viewport().get_world_3d().direct_space_state
	var out: Array[Dictionary] = []
	var tries := 0
	while out.size() < count and tries < count * 60 and not elevated.is_empty():
		tries += 1
		var lane := elevated[_rng.randi() % elevated.size()]
		var length := lane.curve.get_baked_length()
		var s := _rng.randf_range(30.0, length - 30.0)
		var p := lane.curve.sample_baked(s, true)
		var a := lane.curve.sample_baked(s - 15.0, true)
		var b := lane.curve.sample_baked(s + 15.0, true)
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var t0 := Vector3(p.x - a.x, 0.0, p.z - a.z).normalized()
		if t0.dot(t) < 0.995:
			continue     # a curve: the wall is not where a straight line would meet it
		var r := t.cross(Vector3.UP).normalized()
		var gaps: Array[float] = []
		var wall := Vector3.ZERO
		var ok := true
		for offset in WALL_OFFSETS:
			var from := p + t * offset + Vector3.UP * WALL_RAY_HEIGHT
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + r * WALL_SEARCH, WORLD_MASK))
			if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.3 					or not String((hit["collider"] as Node).name).contains("concrete"):
				ok = false
				break
			var at: Vector3 = hit["position"]
			gaps.append((at - from).dot(r))
			if offset == 0.0:
				wall = at
			# a drop behind the wall: no road within FALL_DEPTH under the deck there
			var behind := at + r * 1.2 + Vector3.UP * 2.0
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(behind, behind - Vector3.UP * (2.0 + FALL_DEPTH),
					WORLD_MASK)).is_empty():
				ok = false
				break
		if not ok or gaps.max() - gaps.min() > WALL_EVEN or gaps[2] < START_GAP + 0.5:
			continue
		out.append({"p": p, "t": t, "r": r, "wall": Vector3(wall.x, p.y, wall.z), "road": String(lane.road_id), "lane": lane})
	return out


func _floats(text: String) -> Array[float]:
	var out: Array[float] = []
	for part in text.split(","):
		out.append(float(part))
	return out

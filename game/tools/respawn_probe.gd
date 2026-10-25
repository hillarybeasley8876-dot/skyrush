extends Node
## The respawn probe: the whole game, the player wrecked at random places of the city and put back by the wreck flow of the game
## (damage/wreck_flow.gd `_respawn`: the nearest lane 30 m behind the wreck, 70 % of the speed, at least 60 km/h, a 2 s ghost).
## Every respawn is followed for a few seconds with the throttle held (what a player does), and everything that looks wrong is
## written down: a spawn inside a building or a prop, a hit in the first seconds, a second wreck, a car that tilts, climbs, sticks
## in the air or stands still, a ghost that leaves the car transparent. A diagnostic tool, not a test.
##
##   python tools/gd.py test res://tools/respawn_probe.gd -- --timeout=3000 --stub=audio,menu,hud,rivals --trials=80 --seed=1
##
## Options (all --name=value):
##   trials   number of respawns (80)        seed     the random seed (1)        seconds   how long a respawn is followed (4)
##   side     the largest distance of the wreck from its lane, in metres (10): a wreck is often off the road
##   only     run only this trial (the random numbers of the others are still drawn)
##   verbose  print the flight recorder of this trial, whether it was odd or not

const MAIN := "res://main.tscn"
## the physics ticks a second (the tool counts its frames in ticks)
var FPS: float = float(Engine.physics_ticks_per_second)
## A hit on the world harder than this (N*s) in the first seconds after a respawn is written down.
const HIT_IMPULSE := 3000.0
## The tilt (degrees) that counts as a car on its side or on a wall, and for how long.
const TILT_DEG := 50.0
const TILT_TIME := 0.5
## A car without a wheel on the ground that does not fall (vertical speed under this, m/s) for this long sticks in the air.
const STICK_VY := 1.5
const STICK_TIME := 0.5
## A car that climbs this far above its spawn (m) was thrown.
const CLIMB := 2.0
## The car stands still: under this speed (m/s) for this long, with the throttle held.
const STILL_SPEED := 2.0
const STILL_TIME := 1.5

var _rng := RandomNumberGenerator.new()
var _hits: Array[Dictionary] = []
var _clock := 0.0


func _ready() -> void:
	_run.call_deferred()


func _on_hit(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3, normal: Vector3) -> void:
	if vehicle != Game.player:
		return
	_hits.append({"t": _clock, "other": _name_of(other), "impulse": impulse, "point": point, "normal": normal,
		"car": other is VehicleBase})


func _name_of(body: Node) -> String:
	if body == null:
		return "?"
	var chain := String(body.name)
	var parent := body.get_parent()
	var depth := 0
	while parent != null and depth < 2 and parent != get_tree().root:
		chain = String(parent.name) + "/" + chain
		parent = parent.get_parent()
		depth += 1
	return chain


func _tilt(car: ArcadeCar) -> float:
	return rad_to_deg(acos(clampf(car.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))


func _grounded(car: ArcadeCar) -> int:
	var count := 0
	for w in car.wheels:
		if w.contact:
			count += 1
	return count


func _transparency(car: VehicleBase) -> float:
	var visual := car.get_visual_root()
	if visual == null:
		return 0.0
	var value := 0.0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		value = maxf(value, (child as GeometryInstance3D).transparency)
	return value


## The world and prop bodies that the collision box of the car overlaps at its transform.
func _overlaps(car: ArcadeCar) -> Array[String]:
	var out: Array[String] = []
	var shape_node := car.get_node_or_null(^"Collision") as CollisionShape3D
	if shape_node == null:
		shape_node = car.get_node_or_null(^"Body") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return out
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = 1 | 4
	query.exclude = [car.get_rid()]
	for hit in car.get_world_3d().direct_space_state.intersect_shape(query, 8):
		out.append(_name_of(hit["collider"] as Node))
	return out


## The height of the road under a point (a ray down from 3 m above), or NAN.
func _ground_y(point: Vector3) -> float:
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point - Vector3.UP * 30.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _frame(car: ArcadeCar) -> String:
	var p := car.global_position
	var v := car.linear_velocity
	var normals := ""
	for w in car.wheels:
		normals += ("%.2f " % w.contact_normal.y) if w.contact else "-- "
	return "t=%.2f p=(%.1f,%.2f,%.1f) v=(%.1f,%.1f,%.1f) tilt=%.0f wheels=[%s] contacts=%d hp=%.0f ghost=%.2f" % [
		_clock, p.x, p.y, p.z, v.x, v.y, v.z, _tilt(car), normals.strip_edges(),
		car.get_contact_count() if car.has_method("get_contact_count") else -1, car.health, _transparency(car)]


func _run() -> void:
	var trials := int(Game.option("trials", "80"))
	var seconds := float(Game.option("seconds", "4"))
	var side := float(Game.option("side", "10"))
	var only := int(Game.option("only", "-1"))
	var verbose := int(Game.option("verbose", "-1"))
	_rng.seed = int(Game.option("seed", "1"))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(3.0).timeout
	var car := Game.player as ArcadeCar
	var flow := get_tree().root.find_child("WreckFlow", true, false)
	if car == null or flow == null:
		print("PROBE no player car or no wreck flow")
		get_tree().quit(1)
		return
	car.contact_monitor = true
	car.max_contacts_reported = maxi(car.max_contacts_reported, 8)
	Events.vehicle_collided.connect(_on_hit)
	var lanes: Array = Game.world.get_lane_paths()
	print("PROBE %d lanes, %d trials, seed %s" % [lanes.size(), trials, Game.option("seed", "1")])
	var counts := {}
	var odd_lines: Array[String] = []
	for n in trials:
		# the wreck: a point near a lane, the heading of the lane give or take 40 degrees, a speed of 15-50 m/s
		var lane := lanes[_rng.randi_range(0, lanes.size() - 1)] as LanePath
		var length := lane.curve.get_baked_length() if lane.curve != null else 0.0
		var offset := _rng.randf_range(0.0, maxf(length, 0.1))
		var lateral := _rng.randf_range(-side, side)
		var turn := deg_to_rad(_rng.randf_range(-40.0, 40.0))
		var speed := _rng.randf_range(15.0, 50.0)
		if only >= 0 and n != only:
			continue
		if lane.curve == null or length < 10.0:
			continue
		var point := lane.curve.sample_baked(offset, true)
		var ahead := lane.curve.sample_baked(minf(offset + 2.0, length), true)
		var tangent := Vector3(ahead.x - point.x, 0.0, ahead.z - point.z)
		if tangent.length() < 0.01:
			continue
		tangent = tangent.normalized()
		var heading := tangent.rotated(Vector3.UP, turn)
		var crash := point + tangent.cross(Vector3.UP) * lateral
		var ground := _ground_y(crash)
		crash.y = (ground if not is_nan(ground) else point.y) + 0.6
		car.reset_to(Transform3D(Basis.looking_at(heading, Vector3.UP), crash))
		car.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
		car.power.battery = 1.0
		# the respawn of the game
		_hits.clear()
		_clock = 0.0
		flow.call("_respawn", car, speed, heading)
		var spawn := car.global_position
		var spawn_ground := _ground_y(spawn)
		var overlap := _overlaps(car)
		Input.action_press(&"accelerate")
		var frames: Array[String] = []
		var tilted := 0.0
		var stuck := 0.0
		var still := 0.0
		var peak_tilt := 0.0
		var peak_stuck := 0.0
		var peak_still := 0.0
		var max_y := spawn.y
		var hp_start := car.health
		var wrecked := false
		var flags: Array[String] = []
		var total := int(seconds * FPS)
		for frame in total:
			await get_tree().physics_frame
			_clock = float(frame + 1) / FPS
			if frame % (Engine.physics_ticks_per_second / 10) == 0:
				frames.append(_frame(car))
			var tilt := _tilt(car)
			peak_tilt = maxf(peak_tilt, tilt)
			tilted = tilted + 1.0 / FPS if tilt > TILT_DEG else 0.0
			if tilted >= TILT_TIME and not flags.has("TILT"):
				flags.append("TILT")
			var vy := car.linear_velocity.y
			if _grounded(car) == 0 and absf(vy) < STICK_VY and not car.telemetry.flying:
				stuck += 1.0 / FPS
			else:
				stuck = 0.0
			peak_stuck = maxf(peak_stuck, stuck)
			if stuck >= STICK_TIME and not flags.has("STICK"):
				flags.append("STICK")
			max_y = maxf(max_y, car.global_position.y)
			if car.linear_velocity.length() < STILL_SPEED and _clock > 0.5:
				still += 1.0 / FPS
			else:
				still = 0.0
			peak_still = maxf(peak_still, still)
			if car.is_wrecked:
				wrecked = true
				break
		Input.action_release(&"accelerate")
		if max_y - spawn.y > CLIMB:
			flags.append("CLIMB")
		if peak_still >= STILL_TIME:
			flags.append("STILL")
		if wrecked:
			flags.append("WRECKED")
		if not overlap.is_empty():
			flags.append("SPAWN_IN")
		if not is_nan(spawn_ground) and spawn.y - spawn_ground > 1.5:
			flags.append("SPAWN_HIGH")
		var world_hits := _hits.filter(func(h: Dictionary) -> bool: return not h["car"] and h["impulse"] > HIT_IMPULSE)
		if not world_hits.is_empty():
			flags.append("HIT")
		for flag in flags:
			counts[flag] = int(counts.get(flag, 0)) + 1
		var line := "TRIAL %d crash=(%.0f,%.1f,%.0f) spawn=(%.1f,%.2f,%.1f) ground=%.2f hp %.0f->%.0f tilt %.0f stick %.2fs %s" % [
			n, crash.x, crash.y, crash.z, spawn.x, spawn.y, spawn.z, spawn_ground, hp_start, car.health, peak_tilt,
			peak_stuck, ",".join(flags) if not flags.is_empty() else "ok"]
		print(line)
		if not overlap.is_empty():
			print("   spawn overlaps: %s" % ", ".join(overlap))
		for h in world_hits.slice(0, 3):
			print("   hit t=%.2f %s impulse %.0f normal (%.2f,%.2f,%.2f)" % [h["t"], h["other"], h["impulse"],
				(h["normal"] as Vector3).x, (h["normal"] as Vector3).y, (h["normal"] as Vector3).z])
		if (not flags.is_empty() and flags != ["HIT"]) or n == verbose:
			odd_lines.append(line)
			if n == verbose or flags.has("STICK") or flags.has("TILT") or flags.has("CLIMB"):
				for f in frames:
					print("      ", f)
		# the ghost must be over and the car opaque again before the next wreck
		var settle := 0
		while settle < int(3.0 * FPS):
			# the car is held still: a car that coasts on with nobody at the wheel crashes, and the wreck flow of the game
			# puts it back in the middle of the next trial
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			await get_tree().physics_frame
			settle += 1
		if _transparency(car) > 0.01:
			counts["STILL_GHOST"] = int(counts.get("STILL_GHOST", 0)) + 1
			var ghosts: Dictionary = flow.get("_ghosts")
			var elapsed := []
			for g in ghosts.values():
				elapsed.append(snappedf(float(g.get("elapsed")), 0.01))
			print("   the car is still transparent (%.2f) 3 s after the ghost: time scale %.2f, ghosts %s, mask %d" % [
				_transparency(car), Engine.time_scale, str(elapsed), car.collision_mask])
		if car.is_wrecked:
			# a second wreck: wait for the wreck flow of the game to put it back
			await get_tree().create_timer(5.0, true, false, true).timeout
	print("PROBE SUMMARY %s" % str(counts))
	get_tree().quit(0)

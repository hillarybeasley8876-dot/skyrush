extends Node
## The fuzz drive: the whole game (traffic, police, damage, fx on) with the player thrown at random places, headings
## and speeds, held on the throttle, and everything that looks wrong written down. A diagnostic tool, not a test:
## it finds the bugs a scripted test never meets (the kerb that launched the Roadster 30 m, found with it).
##
##   python tools/gd.py test res://tools/fuzz_drive.gd -- --timeout=3000 --stub=audio,menu,hud --trials=60 --seed=1
##
## Options (all --name=value):
##   trials        number of drives (60)           seed          the random seed (1)
##   seconds       length of a drive (8)            region        x0,x1,z0,z1 of the start points (all the city)
##   speed         min,max start speed in km/h (100,175)    angle   the largest heading offset from the lane in degrees (45)
##   steer         1 = random steering pulses while driving (a human)   elevated  1 = start on the elevated roads only,
##   only          run only this drive (the random numbers of the others are still drawn, so the start is the same;
##                 the traffic is not, so a drive that hit a car does not repeat: stub traffic,police,rivals to cross
##                 the same place alone)
##   verbose       print the flight recorder of this drive, whether it was odd or not
##   jumps         1 = every tick, a traffic or police car in sight of the game (visible, before and after) that moves
##                 more than JUMP_M in one tick, and more than twice its own speed, is printed once with its state before
##                 and after (a car put somewhere by hand where the player can see it)
##   lift          the height above the road a drive starts at (0.2); the spawns of the game are 0.6 m over the road, but a car
##                 that is thrown at 170 km/h from that height lands, rebounds and flies over a parapet that stops it when it
##                 lands calmly (the first viaduct runs counted 26 falls in 40 drives; most of the 13 that were left were this)
##   at            x,z,heading_deg,kmh: every drive starts there (heading 0 = north = -Z, 90 = east), so a place that
##                 launched the car once is crossed again and again; jitter=m moves each start up to m metres sideways
##                 (the statistics of a place: a launch that happens in 3 of 40 passes is a bug, not bad luck)
##
## A drive is "odd" when the player tilts more than 50 degrees for a second, climbs more than 3 m (not in a sky lane), is in
## the air more than 2.5 s (not in a lane), exceeds 330 km/h, stands still for 3 s under full throttle, falls under the city,
## or when a traffic or police car does something that no car should do (over 350 km/h, 8 m above the road, under the city).
## Every drive is recorded frame by frame; an odd drive prints the frames around its first event (a tilt over 25 degrees,
## a climb over 1.5 m, a fall over 3 m), so what happened is in the log without a second run (the second run is another
## drive: the traffic is random).

const MAIN := "res://main.tscn"
const SAMPLE := 0.1
## The physics rate of the game (frames per second).
## the physics ticks a second (the tool counts its frames in ticks)
var FPS: float = float(Engine.physics_ticks_per_second)
## A car that moves faster than this between two samples is odd (km/h); one that moves more than TELEPORT_M was put there.
const FAST_KMH := 350.0
const TELEPORT_M := 30.0
## The first event of a drive: the tilt (degrees), the climb and the fall (m) that start the recording window.
const EVENT_TILT := 25.0
const EVENT_CLIMB := 1.5
const EVENT_FALL := 3.0
## The ground of the city (x, z, width, depth): a fall within EDGE_REACH metres of its border is the end of the world, not a bug.
const WINDOW := Rect2(-2200.0, -1200.0, 4000.0, 3000.0)
const EDGE_REACH := 150.0
## The distance (m) to every other vehicle that a start has to have.
const START_CLEAR := 12.0
## The seconds the fuzz waits after a wreck before the next drive (the wreck flow of the game takes about 4.3 s).
const SETTLE := 5.0
## The frames printed before and after the first event, and the step between the printed frames.
const WINDOW_BEFORE := 100
const WINDOW_AFTER := 160
const WINDOW_STEP := 2

var _rng := RandomNumberGenerator.new()
## m: a move in one tick that is more than this (and more than twice the speed of the car) is a jump (jumps=1).
const JUMP_M := 3.0
var _jump_last: Dictionary = {}      ## instance id -> [position, mode, frozen, visible]
var _jumps_seen: Dictionary = {}
var _hits: Array[String] = []
var _clock: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _roll_pitch(car: ArcadeCar) -> Vector2:
	var b := car.global_transform.basis
	return Vector2(rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0))), rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0))))


func _name_of(body: Node) -> String:
	var chain := String(body.name)
	var parent := body.get_parent()
	var depth := 0
	while parent != null and depth < 2 and parent != get_tree().root:
		chain = String(parent.name) + "/" + chain
		parent = parent.get_parent()
		depth += 1
	return chain


func _on_hit(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3, normal: Vector3) -> void:
	if vehicle != Game.player:
		return
	var what := _name_of(other) if other != null else "?"
	if what.contains("PropCollision"):
		what += "[%s]" % _prop_near(point)
	_hits.append("t=%.2f %s impulse %.0f at (%.1f %.1f %.1f) normal (%.2f %.2f %.2f)" % [_clock,
		what, impulse, point.x, point.y, point.z, normal.x, normal.y, normal.z])


## The kind of the street prop nearest to a point (the contact point of a hit on a prop body).
func _prop_near(point: Vector3) -> String:
	var positions: Array[Vector3] = Game.world.get_furniture_positions()
	var kinds: Array[String] = Game.world.get("_builder").furniture_kinds
	var best := 4.0
	var kind := "?"
	for i in positions.size():
		var d := positions[i].distance_to(point)
		if d < best:
			best = d
			kind = kinds[i]
	return kind


## The start points: lane points of the city, filtered by the options.
func _points(region: String, elevated: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var box: PackedStringArray = region.split(",") if region != "" else PackedStringArray()
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null or lane.elevated != elevated:
			continue
		var pts: PackedVector3Array = lane.curve.get_baked_points()
		for i in range(2, pts.size() - 2, 6):
			var p := pts[i]
			if not elevated and (p.y > 1.5 or p.y < -0.5):
				continue
			if box.size() == 4 and (p.x < float(box[0]) or p.x > float(box[1]) or p.z < float(box[2]) or p.z > float(box[3])):
				continue
			out.append({"p": p, "d": (pts[i + 1] - p).normalized()})
	return out


## What the other cars do. The speed is measured from the displacement over one sample: the velocity of a traffic car
## that is far away is not a speed (it is frozen and moved by its transform), and a car that was put somewhere else
## (the pool recycles cars) moved more than any car can in 0.1 s.
func _scan_others(seen: Dictionary, last: Dictionary, stale: Dictionary) -> void:
	for group in [&"traffic", &"police"]:
		for node in get_tree().get_nodes_in_group(group):
			var car := node as VehicleBase
			if car == null or not car.visible or car == Game.player:
				continue
			var id := car.get_instance_id()
			var here := car.global_position
			var moved := here.distance_to(last[id]) if last.has(id) else 0.0
			last[id] = here
			var kmh := moved / SAMPLE * 3.6
			var key := "%s %s" % [group, car.name]
			var why := ""
			if kmh > FAST_KMH and moved < TELEPORT_M and not bool(car.freeze):
				why = "moved %.0f km/h" % kmh
			elif (here.y < -10.0 and not _near_edge(here)) or here.y > 60.0:
				why = "at height %.0f m" % here.y
			elif is_nan(here.x) or is_nan(here.y):
				why = "NaN"
			if why != "" and not seen.has(key):
				seen[key] = "%s: %s at (%.0f %.0f %.0f), mode %s, frozen %s, velocity %.0f km/h" % [key, why, here.x, here.y,
					here.z, str(car.get("mode")), str(car.freeze), car.linear_velocity.length() * 3.6]
			if car.linear_velocity.length() * 3.6 > FAST_KMH and kmh < FAST_KMH:
				stale[key] = true


## jumps=1: the traffic and police cars that moved more than JUMP_M (and more than twice their speed) in the last tick.
func _scan_jumps(player: Node3D) -> void:
	var dt := 1.0 / FPS
	# Only the cars of this tick are kept: a police car that went back into its pool (out of the groups) and came out
	# somewhere else is a new car, not a jump.
	var seen: Dictionary = {}
	for group in [&"traffic", &"police"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as VehicleBase
			if other == null:
				continue
			var id := other.get_instance_id()
			var here := other.global_position
			var state := [here, other.get("mode"), other.freeze, other.visible]
			if _jump_last.has(id):
				var before: Array = _jump_last[id]
				var moved := here.distance_to(before[0])
				var allowed := maxf(JUMP_M, 2.0 * other.linear_velocity.length() * dt)
				if moved > allowed and other.visible and bool(before[3]) and not _jumps_seen.has(id):
					_jumps_seen[id] = true
					print("FUZZ JUMP %s %s at %.2f s: %.1f m in a tick from (%.0f %.0f %.0f) to (%.0f %.0f %.0f), %.0f m from the player; mode %s -> %s, frozen %s -> %s, velocity %.0f km/h" % [
						group, other.name, _clock, moved, before[0].x, before[0].y, before[0].z, here.x, here.y, here.z,
						here.distance_to(player.global_position), str(before[1]), str(state[1]), str(before[2]), str(state[2]),
						other.linear_velocity.length() * 3.6])
			seen[id] = state
	_jump_last = seen


## True when a point is within EDGE_REACH of the border of the ground of the city, or outside it.
func _near_edge(p: Vector3) -> bool:
	return not WINDOW.grow(-EDGE_REACH).has_point(Vector2(p.x, p.z))


## True when another vehicle (traffic, police, rival) is within `reach` of the point.
func _vehicle_near(point: Vector3, reach: float) -> bool:
	for group in [&"traffic", &"police", &"rivals"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Node3D
			if other != null and other.visible and other != Game.player and other.global_position.distance_to(point) < reach:
				return true
	return false


## One line of the flight recorder: where the car is, how it moves and what it touches.
func _frame_line(car: ArcadeCar, rp: Vector2, speed: float) -> String:
	var touching := ""
	var bodies := car.get_colliding_bodies()
	for i in mini(bodies.size(), 2):
		touching += " " + _name_of(bodies[i])
	var wheels := ""
	for w in car.dynamics.wheels:
		wheels += "%d" % (1 if w.contact else 0)
	return "t=%.2f pos=(%.1f %.2f %.1f) v=%.0f vy=%.1f roll=%.0f pitch=%.0f spin=%.1f wheels=%s%s air=%s hp=%.0f guard(contacts %d away %.1f hold %s spikes %d)%s" % [
		_clock, car.global_position.x, car.global_position.y, car.global_position.z, speed, car.linear_velocity.y, rp.x, rp.y,
		car.angular_velocity.length(), wheels, "g" if car.dynamics.ground_normal() != Vector3.ZERO else "-",
		str(car.thruster.airborne), car.health, car.impact.seen_contacts, car.impact.seen_away, str(car.impact.seen_holding),
		car.impact.spikes, touching]


func _run() -> void:
	var trials := int(Game.option("trials", "60"))
	var seconds := float(Game.option("seconds", "8"))
	var only := int(Game.option("only", "-1"))
	var verbose := int(Game.option("verbose", "-1"))
	var angle_max := float(Game.option("angle", "45"))
	var steer := Game.option("steer", "0") == "1"
	var jumps := Game.option("jumps", "0") == "1"
	var speed_range := String(Game.option("speed", "100,175")).split(",")
	var elevated := Game.option("elevated", "0") == "1"
	var at := String(Game.option("at", "")).split(",") if String(Game.option("at", "")) != "" else PackedStringArray()
	var jitter := float(Game.option("jitter", "0"))
	var lift := float(Game.option("lift", "0.2"))
	_rng.seed = int(Game.option("seed", "1"))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(3.0).timeout
	var car := Game.player as ArcadeCar
	Events.vehicle_collided.connect(_on_hit)
	var points := _points(String(Game.option("region", "")), elevated)
	print("FUZZ %d start points, %d trials, seed %s, %.0f s each" % [points.size(), trials, Game.option("seed", "1"), seconds])
	if points.is_empty():
		get_tree().quit(1)
		return
	var odd := 0
	var summary: Array[String] = []
	var others: Dictionary = {}
	var last_positions: Dictionary = {}
	var stale: Dictionary = {}
	var wrecked_before := false
	for n in trials:
		# The speed of the other cars is the move between two samples of THIS drive: the last sample of the drive
		# before lies the settle time (SETTLE s) back, and a car that drove 20 m in it "moved 700 km/h".
		last_positions.clear()
		_jump_last.clear()
		var pick_index := _rng.randi_range(0, points.size() - 1)
		var pick: Dictionary = points[pick_index]
		# a drive that starts inside another car (a traffic car of the deck, a police car) is thrown by the solver: the next point
		for step in 12:
			if not _vehicle_near(pick["p"], START_CLEAR):
				break
			pick_index = (pick_index + 1) % points.size()
			pick = points[pick_index]
		var p: Vector3 = pick["p"]
		var d := Vector3(pick["d"].x, 0.0, pick["d"].z).normalized()
		var angle := deg_to_rad(_rng.randf_range(-angle_max, angle_max))
		var heading := d.rotated(Vector3.UP, angle)
		var kmh := _rng.randf_range(float(speed_range[0]), float(speed_range[1]))
		var pulses: Array[float] = []
		for k in 12:
			pulses.append(_rng.randf_range(0.0, seconds))
		var pulse_dir: Array[float] = []
		for k in 12:
			pulse_dir.append(1.0 if _rng.randf() < 0.5 else -1.0)
		if only >= 0 and n != only:
			continue
		if at.size() >= 4:
			var compass := deg_to_rad(float(at[2]))
			heading = Vector3(sin(compass), 0.0, -cos(compass))
			p = Vector3(float(at[0]), 0.0, float(at[1])) + heading.cross(Vector3.UP) * _rng.randf_range(-jitter, jitter)
			kmh = float(at[3])
			angle = 0.0
		if wrecked_before:
			# the wreck flow of the game (crash cam, slow motion, respawn 30 m behind, a ghost of 2 s) must be over, or it
			# takes the car in the middle of this drive
			for k in int(SETTLE * FPS):
				await get_tree().physics_frame
			wrecked_before = false
		car.reset_to(Transform3D(Basis.looking_at(heading, Vector3.UP), p + Vector3.UP * lift))
		await get_tree().physics_frame
		car.health = car.max_health
		car.power.battery = 1.0
		car.linear_velocity = heading * (kmh / 3.6)
		Input.action_press(&"accelerate")
		_hits.clear()
		_clock = 0.0
		var start_y := p.y
		var peak_roll := 0.0
		var peak_pitch := 0.0
		var max_y := -1000.0
		var min_y := 1000.0
		var tilted_run := 0.0
		var longest_tilted := 0.0
		var air := 0.0
		var vmax := 0.0
		var still := 0.0
		var longest_still := 0.0
		var lane_flight := false
		var frames: Array[String] = []
		var event_at := -1
		var wrecked_at := -1.0
		var fall_at := Vector3.ZERO
		var fell := false
		var total := int(seconds * FPS)
		var dt := 1.0 / FPS
		var ticks_before := Engine.get_physics_frames()
		for frame in total:
			await get_tree().physics_frame
			_clock = float(frame + 1) * dt
			if jumps:
				_scan_jumps(car)
			if steer and frame % (Engine.physics_ticks_per_second / 10) == 0:
				Input.action_release(&"steer_left")
				Input.action_release(&"steer_right")
				for k in pulses.size():
					if absf(_clock - pulses[k]) < 0.25:
						Input.action_press(&"steer_right" if pulse_dir[k] > 0.0 else &"steer_left")
			var rp := _roll_pitch(car)
			var y := car.global_position.y
			var speed := car.linear_velocity.length() * 3.6
			peak_roll = maxf(peak_roll, absf(rp.x))
			peak_pitch = maxf(peak_pitch, absf(rp.y))
			max_y = maxf(max_y, y)
			min_y = minf(min_y, y)
			vmax = maxf(vmax, speed)
			if car.telemetry.flying:
				lane_flight = true
			if absf(rp.x) > 50.0 or absf(rp.y) > 50.0 or car.global_transform.basis.y.y < 0.3:
				tilted_run += dt
				longest_tilted = maxf(longest_tilted, tilted_run)
			else:
				tilted_run = 0.0
			if car.thruster.airborne and not car.telemetry.flying:
				air += dt
			if speed < 2.0 and _clock > 1.0:
				still += dt
				longest_still = maxf(longest_still, still)
			else:
				still = 0.0
			frames.append(_frame_line(car, rp, speed))
			if not fell and y < start_y - EVENT_FALL and car.thruster.airborne:
				fell = true
				fall_at = car.global_position
			if car.health <= 0.0:
				wrecked_at = _clock
				wrecked_before = true
				if event_at < 0:
					event_at = frame
				break
			if event_at < 0 and not car.telemetry.flying and (absf(rp.x) > EVENT_TILT or absf(rp.y) > EVENT_TILT
					or y - start_y > EVENT_CLIMB or y < start_y - EVENT_FALL):
				event_at = frame
			if frame % int(SAMPLE * FPS) == 0:
				_scan_others(others, last_positions, stale)
		Input.action_release(&"accelerate")
		Input.action_release(&"steer_left")
		Input.action_release(&"steer_right")
		if n == verbose:
			print("   TICKS %d physics ticks for %d recorded frames (%d ticks per second set)" % [
				Engine.get_physics_frames() - ticks_before, total, Engine.physics_ticks_per_second])
		# bugs (odd) and the plain consequences of driving blind at full throttle (notes)
		var reasons: Array[String] = []
		var notes: Array[String] = []
		if longest_tilted >= 1.0:
			reasons.append("tilted %.1f s" % longest_tilted)
		if not lane_flight and max_y - start_y > 3.0 and not elevated:
			reasons.append("climbed %.1f m" % (max_y - start_y))
		if vmax > 330.0 and not _hits.is_empty():
			reasons.append("%.0f km/h" % vmax)
		if fell and (min_y < start_y - 8.0 or elevated):
			if _near_edge(fall_at):
				notes.append("fell off the edge of the city at (%.0f %.0f), to y %.0f" % [fall_at.x, fall_at.z, min_y])
			else:
				reasons.append("fell %s from y %.1f at (%.0f %.0f) to y %.0f" % [
					"off the deck" if elevated else "", start_y, fall_at.x, fall_at.z, min_y])
		elif not lane_flight and air > 2.5:
			reasons.append("airborne %.1f s" % air)
		if longest_still >= 3.0:
			var by := _hits[_hits.size() - 1].split(" ")[1] if not _hits.is_empty() else ""
			if by == "":
				reasons.append("stood still %.1f s, touching nothing" % longest_still)
			else:
				notes.append("stopped by %s" % by)
		if wrecked_at >= 0.0:
			var killer := _hits[_hits.size() - 1] if not _hits.is_empty() else "no hit recorded"
			notes.append("wrecked at %.2f s by %s" % [wrecked_at, killer.substr(0, 90)])
		var line := "FUZZ %3d at (%.0f %.1f %.0f) %3.0f km/h %+3.0f deg: roll %5.1f pitch %5.1f y %.1f..%.1f air %.1fs vmax %3.0f hp %3.0f hits %d%s" % [
			n, p.x, p.y, p.z, kmh, rad_to_deg(angle), peak_roll, peak_pitch, min_y, max_y, air, vmax, car.health, _hits.size(),
			("   <<< ODD: " + ", ".join(reasons) if not reasons.is_empty() else "") + (
			"   (" + "; ".join(notes) + ")" if not notes.is_empty() else "")]
		print(line)
		if n == verbose or not reasons.is_empty():
			if event_at < 0:
				event_at = maxi(0, frames.size() - WINDOW_AFTER)
			var first := maxi(0, event_at - WINDOW_BEFORE)
			var last := mini(frames.size(), event_at + WINDOW_AFTER)
			print("   RECORDER %d: frames %d..%d of %d, the first event at frame %d" % [n, first, last, frames.size(), event_at])
			for i in range(first, last, WINDOW_STEP):
				print("   R ", frames[i])
			for h in _hits:
				print("   HIT ", h)
		if not reasons.is_empty():
			odd += 1
			summary.append(line)
			for h in _hits.slice(0, 3):
				summary.append("      first hits: " + h)
	for key in others:
		print("FUZZ OTHER ", others[key])
	print("FUZZ (%d cars carry a velocity that is not their speed: harmless unless something reads it)" % stale.size())
	print("FUZZ DONE: %d of %d drives odd, %d other cars misbehaved" % [odd, trials if only < 0 else 1, others.size()])
	for line in summary:
		print("FUZZ ODD ", line)
	get_tree().quit(0)

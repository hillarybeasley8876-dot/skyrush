extends Node
## The collision of the street furniture turns with the prop. The bus shelters (8 m), the noise walls (30 m), the planters and
## the arms of the traffic light masts are boxes: they were put in the physics server without the heading of the prop, so
## 88 % of the 556 bus stops and 85 % of the 33 noise walls of the city had an invisible box that ran along the X axis of the
## world while the shelter or the wall that was drawn ran along the road: a car drove through the drawn wall and hit the air
## next to it. The arm of a mast was also on the wrong side of the pole (the glb has it on -Z, the box was on +Z).
## The test builds the shapes of props at several headings and shoots rays at them along and across the prop: the first
## hit must be at the half length (or the half width) of the box, whatever the heading.
## Run: python tools/gd.py test res://world/tests/test_prop_collision_orientation.gd

const PropCollision := preload("res://world/build/prop_collision.gd")
const Heading := preload("res://world/api/heading.gd")
const Layers := preload("res://world/api/layers.gd")

## The headings of the props (compass degrees, 0 = north): the axes and the diagonals of the city.
const HEADINGS: Array[float] = [0.0, 30.0, 91.8, 135.0, 200.0, 316.5]
## How close the hit has to be to the face of the box (m).
const TOLERANCE := 0.15

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", name, "  ", detail)


## The distance from `from` to the first hit of a ray along `direction` (INF when nothing is hit).
func _shoot(from: Vector3, direction: Vector3, length: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * length, Layers.WORLD | Layers.PROP)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return INF
	return from.distance_to(hit["position"])


func _run() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var entries: Array[Dictionary] = []
	var places: Array[Vector3] = []
	# one prop per heading and kind, 100 m apart so the rays of one never meet another
	var index := 0
	for kind in ["bus_stop", "noise_wall"]:
		for heading in HEADINGS:
			var at := Vector3(float(index % 8) * 100.0, 0.0, float(index / 8) * 100.0)
			index += 1
			places.append(at)
			entries.append({"type": kind, "transform": Transform3D(Heading.basis_from_heading(heading), at), "height_m": 0.0})
	var count := PropCollision.new().build(holder, entries)
	_check("every prop got its shape", count == entries.size(), "(%d shapes for %d props)" % [count, entries.size()])
	for i in 4:
		await get_tree().physics_frame
	var half := {"bus_stop": Vector2(4.0, 0.9), "noise_wall": Vector2(15.0, 0.175)}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var xform: Transform3D = entry["transform"]
		var kind := String(entry["type"])
		var centre := places[i] + Vector3.UP * 1.0
		var along := xform.basis.x   # the long axis of the shelter and of the wall is the X of the prop
		var across := xform.basis.z
		var halves: Vector2 = half[kind]
		var worst := 0.0
		var detail := ""
		for pair in [[along, halves.x], [-along, halves.x], [across, halves.y], [-across, halves.y]]:
			var dir: Vector3 = pair[0]
			var expect: float = pair[1]
			# from outside the box, towards the centre: the hit is at (distance - half size)
			var start := centre + dir * (expect + 6.0)
			var got := _shoot(start, -dir, 20.0)
			var error := absf(got - 6.0) if got != INF else INF
			worst = maxf(worst, error)
			if error > TOLERANCE:
				detail += " [%s: expected a hit at 6.00 m, got %s]" % [str(dir.snapped(Vector3.ONE * 0.01)), "none" if got == INF else "%.2f m" % got]
		_check("a %s at heading %.1f has its box along its own axes" % [kind, Heading.yaw_from_heading(0.0) + float(HEADINGS[i % HEADINGS.size()])],
			worst <= TOLERANCE, detail if detail != "" else "(worst %.2f m)" % worst)
	# the arm of a traffic light mast is on -Z of the pole (the side of the glb) and turns with it
	var masts: Array[Dictionary] = []
	var mast_places: Array[Vector3] = []
	for k in HEADINGS.size():
		var at := Vector3(float(k) * 100.0, 0.0, 400.0)
		mast_places.append(at)
		masts.append({"type": "traffic_light", "transform": Transform3D(Heading.basis_from_heading(HEADINGS[k]), at), "height_m": 6.4})
	PropCollision.new().build(holder, masts)
	for i in 4:
		await get_tree().physics_frame
	for k in masts.size():
		var xform: Transform3D = masts[k]["transform"]
		var forward := -xform.basis.z   # the arm of the mast reaches this way
		var arm_at := mast_places[k] + Vector3.UP * 6.15
		var out_hit := _shoot(arm_at + forward * 12.0, -forward, 20.0)
		var back_hit := _shoot(arm_at - forward * 12.0, forward, 20.0)
		# the arm reaches at least 5 m out along -Z, and nothing hangs on the other side of the pole except the pole itself
		_check("the arm of a mast at heading %.1f reaches along -Z" % HEADINGS[k], out_hit < 12.0 - 4.5 + TOLERANCE,
			"(first hit %.2f m from 12 m out)" % out_hit)
		_check("and the pole has no arm behind it at heading %.1f" % HEADINGS[k], back_hit > 12.0 - 0.6,
			"(first hit %.2f m from 12 m behind)" % back_hit)
	print("[probe] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

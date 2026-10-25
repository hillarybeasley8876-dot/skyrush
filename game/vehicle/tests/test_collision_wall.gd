extends Node
## REGRESSION TEST (job collision-explosion): the arcade wall response must survive the hit.
##
## The impact module finds a hit from the change of the speed of the car and then applies the
## arcade rule of a wall (dossier 7.2). The change it applies is a change of the speed too: the
## next tick read that change as a new hit, applied the rule of a graze (95 % of the tangential
## speed) and gave the speed of the crash back. The car drove away from the wall faster than it
## had hit it, and the crash was worth nothing.
##
## The test: the Roadster at 20 m/s into a wall at 25 degrees. After the hit the car must be
## slower than the rule of a hit says, and it must not speed up again in the ticks after it.
## Run: python tools/gd.py test res://vehicle/tests/test_collision_wall.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

## s: the physics step of the engine (the tests wait its ticks)
var DT: float = 1.0 / Engine.physics_ticks_per_second
const SPEED_KMH := 72.0    ## 20 m/s
const WALL_ANGLE := 25.0   ## deg: the angle of the wall to the path of the car
const DROP := 0.75         ## the speed after the hit must be at most this part of the speed
const RISE := 0.5          ## m/s: the speed may not grow by more than this after the hit

var _speeds: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The wall: a box across the path of the car, at 25 degrees.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 12.0)
	shape.shape = box
	wall.add_child(shape)
	# The wall is smooth: the car slides along it, so the arcade rule (and not the friction of
	# the wall) decides how much speed the crash takes.
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	wall.physics_material_override = material
	wall.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(WALL_ANGLE)),
			Vector3(30.0, 1.5, 0.0))
	get_tree().root.add_child(wall)
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), -PI / 2.0)
	await t.run(0.5)
	t.set_speed(car, SPEED_KMH)
	_speeds.clear()
	for i in int(2.5 / DT):
		await get_tree().physics_frame
		_speeds.append(car.linear_velocity.length())
	var hit := _find_hit()
	t.check("the car hit the wall", hit >= 0, "= tick %d" % hit)
	if hit < 0:
		t.finish()
		return
	var before: float = _speeds[hit - 1]
	# The speed right after the crash is the answer of the arcade rule; the speed may not grow
	# after it (the rule of a graze must not be applied to the crash).
	var after: float = _speeds[hit]
	var last: int = mini(hit + Engine.physics_ticks_per_second, _speeds.size())
	var later := 0.0
	for i in range(hit + 1, last):
		later = maxf(later, _speeds[i])
	t.check("the crash slows the car down: <= %.0f %% of the speed before it" % (DROP * 100.0),
			after <= before * DROP, "= %.1f of %.1f m/s" % [after, before])
	t.check("the crash is not given back: the speed does not grow by more than %.1f m/s" % RISE,
			later <= after + RISE, "= %.1f m/s after %.1f m/s" % [later, after])
	t.finish()


## The tick of the first sample after the crash (the speed of the tick before it is the speed
## the car had before the wall), or -1.
func _find_hit() -> int:
	for i in range(1, _speeds.size()):
		if _speeds[i] < _speeds[i - 1] * DROP:
			return i
	return -1

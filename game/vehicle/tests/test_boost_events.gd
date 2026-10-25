extends Node
## The boost events: every boost raises Events.boost_started exactly once and Events.boost_ended
## once when it runs out (dossier: the contract of the Events bus).
## Run: tools/godot.sh test res://vehicle/tests/test_boost_events.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")

var _started: Array[StringName] = []
var _ended: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.boost_started.connect(func(_v: VehicleBase, k: StringName) -> void: _started.append(k))
	events.boost_ended.connect(func(_v: VehicleBase) -> void: _ended += 1)
	# The nitro into a wall 40 m ahead at 100 km/h.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 3.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(120.0, 1.5, -40.0)
	get_tree().root.add_child(wall)
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(120.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	car.boost.n2 = BoostTuning.N2_MAX
	t.set_speed(car, 100.0)
	car.set_controls(1.0, 0.0, 0.0, false)
	await t.run(1.0)
	t.check("the nitro fires", car.use_nitro())
	t.check("one boost_started", _started.size() == 1 and _started[0] == &"nitro",
			"= %s" % str(_started))
	# The nitro burns for 3 s, then it ends.
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
	t.check("the boost ended", _ended == 1, "= %d" % _ended)
	t.check("the kind is empty", car.boost.kind == &"", "= %s" % car.boost.kind)
	t.check("the cap is back to the base", absf(car.boost.speed_cap - DriveTuning.V_TOP) < 0.01,
			"= %.1f km/h" % (car.boost.speed_cap * 3.6))
	# A boost that is blocked by a wall still ends exactly once.
	_started.clear()
	var ended_before: int = _ended
	car.boost.n2 = BoostTuning.N2_MAX
	car.use_nitro()
	for i in Engine.physics_ticks_per_second * 5:
		await t.step()
	t.check("the blocked nitro ends once", _ended - ended_before == 1,
			"= %d" % (_ended - ended_before))
	t.finish()

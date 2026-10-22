extends Node
## A race gate that stands under a deck must not count a car that drives on the deck above it.
##
##   python tools/gd.py test res://modes/tests/test_gate_layers.gd
##
## The trigger box of a gate is 14 m high (so a car can fly through it on a sky lane). The map has gates on the
## street under the elevated roads (the tunnel gates, the gates under the Yan'an elevated road): a car that drives
## on the deck 10 m above such a gate is inside the box, but it is on another level and must not count.
## A car that drives on the gate's own level counts, and so does a car that is in the air (a sky lane).

const STUB_CAR := "res://core/stubs/stub_car.tscn"
const GATE_AT := Vector3(100.0, 0.0, 0.0)

var _failures := 0
var _checks := 0
var _counted: Array[VehicleBase] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var gate := RaceGate.new()
	add_child(gate)
	gate.build(2, Transform3D(Basis.IDENTITY, GATE_AT), 24.0, Color.CYAN, 7)
	gate.passed.connect(func(vehicle: VehicleBase, _index: int) -> void: _counted.append(vehicle))
	await _frames(3)

	var street := await _drive_through(gate, Vector3(0.0, 0.7, 0.0), false)
	_check(_counted.has(street), "a car on the gate's own level is counted")

	var deck := await _drive_through(gate, Vector3(0.0, 10.7, 0.0), false)
	_check(not _counted.has(deck), "a car that drives on a deck 10 m above the gate is NOT counted")

	var high_deck := await _drive_through(gate, Vector3(0.0, 31.0, 0.0), false)
	_check(not _counted.has(high_deck), "a car that drives 31 m above the gate (the Nanpu bridge) is NOT counted")

	var flying := await _drive_through(gate, Vector3(0.0, 9.0, 0.0), true)
	_check(_counted.has(flying), "a car that flies through the gate (airborne, 9 m up) is counted")

	var below := await _drive_through(gate, Vector3(0.0, -9.0, 0.0), false)
	_check(not _counted.has(below), "a car that drives 9 m below the gate (the tunnel) is NOT counted")

	print("GATE LAYER TESTS %s (%d failures of %d checks)" % ["OK" if _failures == 0 else "FAILED", _failures, _checks])
	get_tree().quit(0 if _failures == 0 else 1)


## A car comes from 40 m away and enters the trigger box at `offset` (relative to the gate), without gravity.
func _drive_through(gate: RaceGate, offset: Vector3, airborne: bool) -> VehicleBase:
	var car := (load(STUB_CAR) as PackedScene).instantiate() as VehicleBase
	add_child(car)
	car.gravity_scale = 0.0
	car.global_position = GATE_AT + Vector3(0.0, offset.y, 40.0)
	car.linear_velocity = Vector3.ZERO
	car.telemetry.airborne = airborne
	await _frames(3)
	car.global_position = GATE_AT + offset
	await _frames(4)
	car.telemetry.airborne = airborne
	return car


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)

extends Node
## The lamps of the AI traffic: the real lenses of the model, the brake state and the housings.
##
##   tools/godot.sh test res://ai/traffic/tests/test_lamps.gd
##
## Every model of the fleet has to carry a tail lens, a brake lens and a head lens. The brake
## state is a per-surface material swap: the brake lens has to be at least four times brighter
## while the car brakes, and the black housing of the lamp must not be painted red.

const MODELS: Array[StringName] = [&"sedan_ev", &"hatch_ev", &"suv_ev", &"taxi_ev", &"robotaxi",
	&"van_ev", &"bus_city", &"truck_box"]
const BRAKE_RATIO := 4.0  ## how much brighter the brake lens has to be

var _failures: int = 0
var _ctx: DriveContext = DriveContext.new()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_ctx = DriveContext.new()
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 4242
	for model in MODELS:
		_test_model(model)
	print("LAMP TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The lenses of one model: there has to be a tail, a brake and a head lens, and the brake has
## to light up when the car brakes.
func _test_model(model: StringName) -> void:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, model, Color.WHITE, 7)
	car.place(1, 40.0)
	var lamps := car.lamps
	_check(not lamps.tail_lenses.is_empty(), "%s has a tail lens (%d)"
			% [model, lamps.tail_lenses.size()])
	_check(not lamps.head_lenses.is_empty(), "%s has a head lens (%d)"
			% [model, lamps.head_lenses.size()])
	if not lamps.reverse_lenses.is_empty():
		var reverse := _energy(lamps.reverse_lenses[0])
		_check(reverse <= 0.2, "%s: the reversing lens is dim (%.2f)" % [model, reverse])
	# The braking: the brake lens (or the tail lens of a bus) has to get much brighter.
	var lens := _brake_lens(lamps)
	_check(lens != null, "%s has a brake lens" % model)
	if lens == null:
		return
	var off := _energy(lens)
	car.lamps.update(0.1, -3.0, 0, 0.0, true, 0.0, true)
	var on := _energy(lens)
	_check(on >= off * BRAKE_RATIO, "%s: the brake lens is %.1fx brighter (%.2f -> %.2f)"
			% [model, on / maxf(off, 0.001), off, on])
	car.lamps.update(0.5, 0.0, 0, 0.0, true, 0.0, true)
	_check(absf(_energy(lens) - off) < 0.01, "%s: the brake lens goes off again" % model)
	_test_housing(lamps)


## The lens that carries the brake: the brake lens of the model, or the tail lens of a model
## that has none (a bus has no brake lens of its own).
func _brake_lens(lamps: TrafficLamps) -> TrafficLamps.Lens:
	if not lamps.brake_lenses.is_empty():
		return lamps.brake_lenses[0]
	if not lamps.tail_lenses.is_empty():
		return lamps.tail_lenses[0]
	return null


## The energy of the material the lens shows right now.
func _energy(lens: TrafficLamps.Lens) -> float:
	var mat := lens.mesh.get_surface_override_material(lens.index)
	if mat is ShaderMaterial:
		return float((mat as ShaderMaterial).get_shader_parameter(&"energy"))
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).emission_energy_multiplier
	return 0.0


## The black housing of the lamp must keep its own material: a car whose whole lamp glows red
## looks broken.
func _test_housing(lamps: TrafficLamps) -> void:
	var mesh: MeshInstance3D = null
	for lens in lamps.head_lenses:
		mesh = lens.mesh
		break
	if mesh == null:
		return
	for i in mesh.mesh.get_surface_count():
		var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
		if source == null or source.resource_name != "NPC_gloss_black":
			continue
		var active := mesh.get_surface_override_material(i)
		_check(active == null or active == source,
			"the lamp housing keeps its own material")
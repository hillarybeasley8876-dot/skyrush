class_name RaceGates
extends RefCounted
## The checkpoint gates of a race: one hologram gate per checkpoint of the route.
##
## The gates of a sprint are a start, the checkpoints and a finish at the end; the gates of a
## circuit are a start/finish at the first checkpoint and the checkpoints after it.

const GATE_TINT := Color("19e6ff")        ## the checkpoints are cyan
const FIRST_GATE_TINT := Color("ffb000")   ## the start is amber
const FINISH_TINT := Color("ff2d55")       ## the finish is red
const GATE_FADE_TIME := 0.5   ## s: the time a passed gate takes to fade out
const ENERGY_NEXT := 4.5      ## the energy of the next gate of the player
const ENERGY_AFTER := 1.8     ## the energy of the gate after it
const ENERGY_REST := 0.6      ## the energy of the gates further ahead

## The gates of the race.
var gates: Array[RaceGate] = []


## Builds one gate per checkpoint of the route.
##
## `circuit` tells the gates apart: a circuit has a start/finish at the first checkpoint, a
## sprint has a start at the first one and a finish at the last one.
func build(parent: Node, route: RaceRoute, circuit: bool) -> void:
	clear()
	if route == null or parent == null:
		return
	var count := route.checkpoints.size()
	for i in count:
		var gate := RaceGate.new()
		gate.name = "Gate%d" % i
		parent.add_child(gate)
		var kind := _kind_of(i, count, circuit)
		gate.build(i, route.checkpoints[i], route.gate_width, _tint_of(kind), count, kind)
		gates.append(gate)


## The kind of the gate at `index` (&"start", &"checkpoint", &"finish" or &"start_finish").
func _kind_of(index: int, count: int, circuit: bool) -> StringName:
	if circuit:
		return &"start_finish" if index == 0 else &"checkpoint"
	if index == 0:
		return &"start"
	if index == count - 1:
		return &"finish"
	return &"checkpoint"


## The tint of a kind of gate.
func _tint_of(kind: StringName) -> Color:
	match kind:
		&"start":
			return FIRST_GATE_TINT
		&"start_finish":
			return FIRST_GATE_TINT
		&"finish":
			return FINISH_TINT
	return GATE_TINT


## The number of gates.
func size() -> int:
	return gates.size()


## Removes the gates.
func clear() -> void:
	for gate in gates:
		if is_instance_valid(gate):
			gate.queue_free()
	gates.clear()


## The next gate of the player burns bright, the one after it is dim, the rest barely glow.
func set_next_gate(index: int) -> void:
	for i in gates.size():
		var distance := (i - index + gates.size()) % gates.size()
		var energy := ENERGY_REST
		if distance == 0:
			energy = ENERGY_NEXT
		elif distance == 1:
			energy = ENERGY_AFTER
		gates[i].set_energy(energy)


## Fades a gate out (the player has passed it).
func fade(index: int) -> void:
	if index < 0 or index >= gates.size():
		return
	var gate := gates[index]
	var tween := gate.create_tween()
	tween.tween_property(gate, "fade", 0.0, GATE_FADE_TIME)

extends RefCounted
## The registry of the cars the damage unit knows: their state, their dent painter and their
## tier rig. The state is built when a car joins the world (not on its first crash, which
## would cost 8 ms on the frame of the crash) and it is erased when the car leaves.
##
## The rig of a car (the materials, the mask, the lights and the particles) is built when
## the car is hurt for the first time: a car that is never hit owns nothing.

const CarDamage := preload("res://damage/car_damage.gd")
const DentPainter := preload("res://damage/dent_painter.gd")

## The state of every car, by instance id.
var states: Dictionary = {}
## The painters with a mask to upload.
var dirty_painters: Array[DentPainter] = []
## Called when a car leaves the world (its state must not leak).
var on_forget: Callable = Callable()


## The state of a car, built on the first call.
func state_of(car: VehicleBase) -> CarDamage:
	var id := car.get_instance_id()
	if states.has(id):
		return states[id] as CarDamage
	var state := CarDamage.new()
	state.setup(car)
	states[id] = state
	var painter := DentPainter.new()
	if painter.setup(car):
		state.painter = painter
		painter.on_dirty = _on_painter_dirty
	car.tree_exiting.connect(_on_tree_exiting.bind(car))
	return state


## The number of cars the unit knows (for the test).
func count() -> int:
	return states.size()


## Uploads the masks that changed. The list is empty in a quiet frame.
func flush_painters(delta: float) -> void:
	if dirty_painters.is_empty():
		return
	var still_dirty: Array[DentPainter] = []
	for painter in dirty_painters:
		painter.tick(delta)
		if painter.pending():
			still_dirty.append(painter)
	dirty_painters = still_dirty


## The respawn: the car is whole again, with two soft dents and half the scrape left.
func reset_state(car: VehicleBase) -> void:
	var state := state_of(car)
	state.reset()
	if state.painter != null:
		state.painter.soften()
	if state.fx != null:
		state.fx.reset()


## A car that comes out of its pool: it is a whole new car. No dent, no scrape, no smoke
## and the parts that came off are back on it.
func recycle_state(car: VehicleBase) -> void:
	var state := states.get(car.get_instance_id(), null) as CarDamage
	if state == null:
		return
	state.recycle()
	if state.painter != null:
		state.painter.reset()
	if state.fx != null:
		state.fx.reset()


## Forgets a car that left the world (its mask and its meshes would leak).
func forget(car: VehicleBase) -> void:
	var id := car.get_instance_id()
	var state := states.get(id, null) as CarDamage
	if state != null:
		dirty_painters.erase(state.painter)
		if state.painter != null:
			state.painter.dispose()
	states.erase(id)
	if on_forget.is_valid():
		on_forget.call(car)


func _on_painter_dirty(painter: DentPainter) -> void:
	if not dirty_painters.has(painter):
		dirty_painters.append(painter)


func _on_tree_exiting(car: VehicleBase) -> void:
	forget(car)

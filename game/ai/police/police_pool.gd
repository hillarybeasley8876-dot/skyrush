class_name PolicePool
extends RefCounted
## The pool of the police objects (the perf budget of the brief: 1.5 ms per frame with 12
## units).
##
## Everything the police put on the road is built once, when the dispatcher is ready, and then
## reused: a spawn is a placement, not an instantiation. So the dispatcher never hitches when a
## unit comes, a block is set up or a strip is dropped.

const BLOCK_COUNT := 3
const STRIP_COUNT := 4
const DRONE_COUNT := 2
## The collision layer of a unit on the road (the layer of the cars) and the mask it hits
## (the world, the cars and the props): the same as the spec of the vehicle unit.
const UNIT_LAYER := 1 << 1
const UNIT_MASK := 0b111
## The kinds of the pooled units: the head-on unit needs the SUV, the PIT the interceptor.
const UNIT_KINDS: Array[StringName] = [
	&"heavy_suv", &"heavy_suv", &"interceptor", &"interceptor", &"interceptor", &"interceptor",
	&"interceptor", &"interceptor", &"patrol", &"patrol", &"patrol", &"patrol",
]

## The pooled units.
var units: Array[PoliceCar] = []
## The pooled roadblock sets.
var blocks: Array[PoliceRoadblock] = []
## The pooled spike strips.
var strips: Array[PoliceSpikeStrip] = []
## The pooled drones.
var drones: Array[PoliceDrone] = []

var _free_units: Array[PoliceCar] = []
var _free_blocks: Array[PoliceRoadblock] = []
var _free_strips: Array[PoliceSpikeStrip] = []
var _free_drones: Array[PoliceDrone] = []


## Builds the pool: the units, the roadblock sets, the strips and the drones.
func build(host: Node3D, ctx: DriveContext, grid: LaneGrid) -> void:
	for i in UNIT_KINDS.size():
		var kind: StringName = UNIT_KINDS[i]
		var car := PoliceFleet.build_unit(host, kind, PoliceFleet.Role.PATROL, ctx,
				Transform3D.IDENTITY, i, grid)
		if car == null:
			continue
		units.append(car)
		_park(car)
	for i in BLOCK_COUNT:
		var block := PoliceRoadblock.new()
		block.name = "Roadblock%d" % i
		host.add_child(block)
		block.build_pool(ctx, grid)
		blocks.append(block)
		_free_blocks.append(block)
	for i in STRIP_COUNT:
		var strip := PoliceSpikeStrip.new()
		strip.name = "SpikeStrip%d" % i
		host.add_child(strip)
		strip.setup(Vector3.RIGHT)
		strip.set_active(false)
		strips.append(strip)
		_free_strips.append(strip)
	for i in DRONE_COUNT:
		var drone := PoliceDrone.new()
		drone.name = "PoliceDrone%d" % i
		host.add_child(drone)
		drone.setup()
		drone.visible = false
		drones.append(drone)
		_free_drones.append(drone)


## True when the pool holds its objects.
func is_built() -> bool:
	return not units.is_empty()


## Points the pooled cars at a new context (the world changed).
func set_context(ctx: DriveContext) -> void:
	for unit in units:
		unit.ctx = ctx
	for block in blocks:
		for car in block.cars:
			car.ctx = ctx


## Puts a car away: it is hidden, it has no collider and it does not tick.
##
## The car also leaves the groups "police" and "vehicles": a car that waits in the pool is no
## police car on the road, and the audio unit would give it a siren.
func _park(car: PoliceCar) -> void:
	car.visible = false
	car.collision_layer = 0
	car.remove_from_group("police")
	car.remove_from_group("vehicles")
	car.put_to_sleep(true)
	car.process_mode = Node.PROCESS_MODE_DISABLED
	_free_units.append(car)


## Takes a unit out of the pool. Returns null when the pool is empty.
func take_unit(kind: StringName = &"") -> PoliceCar:
	if _free_units.is_empty():
		return null
	var index := 0
	if kind != &"":
		for i in _free_units.size():
			if _free_units[i].kind == kind:
				index = i
				break
	var car := _free_units[index]
	_free_units.remove_at(index)
	car.process_mode = Node.PROCESS_MODE_INHERIT
	car.visible = true
	car.collision_layer = UNIT_LAYER
	# A unit that was wrecked lost its collider (the wreck flow takes it away): the unit
	# that comes out of the pool hits the world and the other cars again.
	car.collision_mask = UNIT_MASK
	car.add_to_group("police")
	car.add_to_group("vehicles")
	car.reset_for_spawn()
	# The unit is back on the road: the unit that keeps the state of the cars (the damage
	# unit) makes it whole again. The signal is the only link between the two units.
	Events.vehicle_recycled.emit(car)
	return car


## Puts a unit back into the pool.
func release_unit(car: PoliceCar) -> void:
	if car == null or not is_instance_valid(car):
		return
	_park(car)


## Takes a roadblock set out of the pool.
func take_block() -> PoliceRoadblock:
	if _free_blocks.is_empty():
		return null
	var block: PoliceRoadblock = _free_blocks.pop_back()
	block.set_active(true)
	return block


## Puts a roadblock set back into the pool.
func release_block(block: PoliceRoadblock) -> void:
	if block == null or not is_instance_valid(block):
		return
	block.set_active(false)
	_free_blocks.append(block)


## Takes a spike strip out of the pool.
func take_strip() -> PoliceSpikeStrip:
	if _free_strips.is_empty():
		return null
	var strip: PoliceSpikeStrip = _free_strips.pop_back()
	strip.set_active(true)
	return strip


## Puts a spike strip back into the pool.
func release_strip(strip: PoliceSpikeStrip) -> void:
	if strip == null or not is_instance_valid(strip):
		return
	strip.set_active(false)
	_free_strips.append(strip)


## Takes a drone out of the pool.
func take_drone() -> PoliceDrone:
	if _free_drones.is_empty():
		return null
	var drone: PoliceDrone = _free_drones.pop_back()
	drone.visible = true
	return drone


## Puts a drone back into the pool.
func release_drone(drone: PoliceDrone) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	drone.visible = false
	_free_drones.append(drone)

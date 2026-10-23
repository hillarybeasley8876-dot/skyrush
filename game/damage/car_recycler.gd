extends RefCounted
## The restore of a car that comes out of its pool: it is a whole new car.
##
## The traffic cars and the police cars live in pools. A car that is wrecked sinks, fades
## out and is hidden, then it goes back into its pool and the next spawn takes it out again.
## The car must be whole then: its health, its paint, its parts, its smoke and its opacity.
##
## The pools know nothing of the damage unit: they only say on the bus that a car is back
## (Events.vehicle_recycled). This file is what that signal does.

const CarDamage := preload("res://damage/car_damage.gd")
const CarStateManager := preload("res://damage/car_state_manager.gd")
const WreckFlow := preload("res://damage/wreck_flow.gd")

## The state of every car the unit knows.
var registry: CarStateManager = null
## The wreck flow: the sink, the fade and the hide of a wrecked car.
var flow: WreckFlow = null


## A pooled car (traffic, police) comes back into play: it is a whole new car.
##
## The wreck of its old life is void (the sink, the fade and the hide), the car has its
## health back and its damage state is fresh. A car that was never hurt is not touched:
## the traffic spawns cars all the time and the handler must cost nothing.
func on_recycled(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if not _needs_restore(vehicle):
		return
	# The old wreck must not touch the new life of the car: the pending sink, the fade and
	# the hide are void before the car is made whole again.
	flow.cancel_sink(vehicle)
	# The car is whole again: it is not a wreck, it has its health and its meshes are opaque.
	vehicle.repair()
	flow.restore_visual(vehicle)
	# The damage state of the car is fresh: no tier, no dent, no scrape, no smoke, and the
	# parts that came off are back on.
	registry.recycle_state(vehicle)


## True when the car carries the damage of an old life and has to be made whole again.
func _needs_restore(vehicle: VehicleBase) -> bool:
	if vehicle.is_wrecked or vehicle.health < vehicle.max_health:
		return true
	var state := registry.states.get(vehicle.get_instance_id(), null) as CarDamage
	if state == null:
		return false
	return state.wrecked or state.tier != CarDamage.Tier.CLEAN

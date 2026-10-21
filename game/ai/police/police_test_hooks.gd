class_name PoliceTestHooks
extends RefCounted
## The test hooks of the dispatcher (the police tests drive the units through them).
##
## The hooks live in their own module, so the dispatcher stays small and the tests have one
## place that changes the rules of the pursuit.

## The dispatcher the hooks belong to.
var director: PoliceDirector = null


## Ends the pursuit without a reward.
func clear_pursuit() -> void:
	if director == null:
		return
	director.pursuit.reset()
	director.remove_all_units()


## Every unit gets this role (-1 = the roles of the heat table).
func force_role(role: int) -> void:
	if director == null:
		return
	director.spawner.forced_role = role


## The units get these roles in order.
func force_roles(roles: Array) -> void:
	if director == null:
		return
	director.spawner.forced_roles = roles


## The heat of the pursuit, without a pursuit.
func force_heat(level: int) -> void:
	if director == null:
		return
	director.pursuit.set_heat(level)


## A unit at a given place, with a given role.
func spawn_unit_at(xform: Transform3D, role: PoliceFleet.Role) -> PoliceCar:
	if director == null:
		return null
	return director.place_unit(xform, role)


## Sets up a roadblock right now.
func spawn_roadblock_now() -> bool:
	if director == null:
		return false
	return director.blockade.spawn(director.pursuit.heat, director.player,
			director.lane, director.lane_offset)

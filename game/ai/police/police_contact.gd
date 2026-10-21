class_name PoliceContact
extends RefCounted
## The velocity cache of the contacts (ref/gameplay/DOSSIER.md §3.4).
##
## The physics solver equalises the velocities of two bodies when the contact is reported, so
## the speed of a hit cannot be read from the bodies any more. The module keeps the velocity of
## every body of the previous physics tick, so the police can tell WHO hit whom and how hard:
## only the player may commit the offence "hit_police" (the player rams the police), never the
## other way round.

## The velocity of a body, by its instance id.
var _cache: Dictionary = {}


## Remembers the velocity of a body for the next contact report.
##
## The director calls this once per physics tick, before the step, so the value is the velocity
## of the previous tick.
func cache(body: RigidBody3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	_cache[body.get_instance_id()] = body.linear_velocity


## The velocity of a body in the previous tick (zero when it is unknown).
func velocity_of(body: Node3D) -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO
	return _cache.get(body.get_instance_id(), Vector3.ZERO) as Vector3


## The forward speed of a body in the previous tick (m/s).
##
## The police use it as the ceiling of the speed of a unit on the bumper of the player: a
## player who brakes must not be shoved down the road by the unit behind him.
func cached_speed(body: Node3D) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	var forward := -body.global_transform.basis.z
	return maxf(velocity_of(body).dot(forward), 0.0)


## The speed at which `a` closes on `b` (m/s): positive when they approach.
func closing_speed(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return 0.0
	var to_b := b.global_position - a.global_position
	var distance := to_b.length()
	if distance < 0.01:
		return 0.0
	var direction := to_b / distance
	return (velocity_of(a) - velocity_of(b)).dot(direction)


## The relative speed of two bodies (m/s): how fast they move apart or together.
func relative_speed(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return 0.0
	return (velocity_of(a) - velocity_of(b)).length()


## The speed at which `a` moves towards `b` on its own (m/s).
##
## This is the speed of the striker: a police car that rams the player moves towards the
## player, not the other way round.
func approach_speed(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return 0.0
	var to_b := b.global_position - a.global_position
	var distance := to_b.length()
	if distance < 0.01:
		return 0.0
	return velocity_of(a).dot(to_b / distance)

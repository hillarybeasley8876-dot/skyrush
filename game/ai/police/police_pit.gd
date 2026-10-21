class_name PolicePit
extends RefCounted
## The tap of the PIT manoeuvre (ref/gameplay/DOSSIER.md §6.3).
##
## The PIT is a real collision: the unit steers into the rear quarter of the player. Only inside
## that contact the police add their tap, and the tap is sized as a yaw rate target: the torque
## impulse is the yaw inertia of the player times the yaw rate the manoeuvre wants to give him
## (1.6 rad/s), so it spins a 1,900 kg car without being an invisible hand.

## The yaw rate the PIT tries to give the player (rad/s).
const TARGET_YAW := 1.6
## The largest torque impulse of the tap (N*m*s).
const MAX_TORQUE := 6000.0
## The largest lateral shove of the tap (N*s).
const MAX_SHOVE := 1200.0
## The shove per m/s of the relative speed of the contact (N*s).
const SHOVE_GAIN := 200.0
## The relative speed a contact needs for the tap (m/s).
const MIN_CLOSING := 3.0
## The yaw inertia of a car without a spec (kg*m^2).
const DEFAULT_INERTIA := 3200.0


## The tap of a PIT contact. Returns the torque impulse that was applied (0 when there was none).
##
## The tap is only allowed when the unit really is in its PIT strike, when the contact closes
## fast enough and when it hits the player behind his centre.
static func assist(player: VehicleBase, unit: PoliceCar, point: Vector3,
		closing: float) -> float:
	if player == null or unit == null:
		return 0.0
	if unit.state != PoliceCar.State.PIT or not unit.is_striking():
		return 0.0
	if unit.pit_assisted():
		# The tap is given once per strike, not once per contact report.
		return 0.0
	if closing < MIN_CLOSING:
		return 0.0
	# The hit has to be behind the centre of the player: a hit in the middle does not spin him.
	if (point - player.global_position).dot(-player.get_forward()) <= 0.0:
		return 0.0
	# The unit hits the rear quarter of the player: the rear is pushed to the other side and the
	# player spins around his own axis.
	var right := player.global_transform.basis.x
	var side := signf((unit.global_position - player.global_position).dot(right))
	if side == 0.0:
		side = 1.0
	var torque := minf(yaw_inertia(player) * maxf(TARGET_YAW - absf(player.angular_velocity.y), 0.0),
			MAX_TORQUE)
	var shove := minf(closing * SHOVE_GAIN, MAX_SHOVE)
	player.apply_central_impulse(-right * side * shove)
	player.apply_torque_impulse(Vector3.UP * (-side * torque))
	return torque


## The yaw inertia of a car (kg*m^2): the spec of the vehicle unit is the source of truth.
static func yaw_inertia(player: VehicleBase) -> float:
	var car := player as ArcadeCar
	if car != null and car.spec != null:
		return maxf(car.spec.inertia.y, 1.0)
	return DEFAULT_INERTIA

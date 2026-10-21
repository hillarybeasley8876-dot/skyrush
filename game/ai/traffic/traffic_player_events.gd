class_name TrafficPlayerEvents
extends RefCounted
## What the traffic does when the player goes past: the near miss (dossier 6.1: a gap under
## 1.2 m at 60 km/h of relative speed) and the horn (a car honks when the player squeezes by
## it with less than 1.5 m of gap).
##
## Only the cars near the player are looked at - the list the modes built - and the cooldowns
## live in the cars themselves: a dictionary lookup per car and per tick costs more than the
## whole check.

const NEAR_MISS_GAP := 1.2       ## m: the gap between the player and a car that counts as a pass
const NEAR_MISS_SPEED := 16.67   ## m/s: 60 km/h of relative speed
const NEAR_MISS_COOLDOWN := 1.5  ## s: how long a car waits before it reports another pass
const HORN_GAP := 1.5            ## m: the side gap at which the traffic honks
const HORN_COOLDOWN := 3.0       ## s: how long a car waits before it honks again
const HORN_MIN_SPEED := 5.0      ## m/s: the horn is for a car that really drives past
const PLAYER_HALF_WIDTH := 0.95  ## m: half the width of the player car
const CHECK_RANGE := 12.0        ## m: only the cars this close to the player are checked

## The number of near misses reported since the traffic started.
var near_misses: int = 0
## The number of horns.
var horns: int = 0


## One tick: the cooldown of every car decays, the cars next to the player are checked.
func update(dt: float, player: VehicleBase, cars: Array[TrafficCar]) -> void:
	# The player and the cars can be gone (the menu takes the player away, a car is removed):
	# the types are checked at runtime, not at the call.
	if player == null or not is_instance_valid(player):
		return
	var player_position: Vector3 = player.global_position
	var player_velocity := player.linear_velocity
	for car in cars:
		if car == null or not is_instance_valid(car):
			continue
		car.near_miss_cooldown = maxf(car.near_miss_cooldown - dt, 0.0)
		car.horn_cooldown = maxf(car.horn_cooldown - dt, 0.0)
		if car.mode == TrafficCar.Mode.WRECK:
			continue
		var distance := car.global_position.distance_to(player_position)
		if distance > CHECK_RANGE:
			continue
		var gap := _side_gap(car, player_position)
		var relative: float = (player_velocity - car.linear_velocity).length()
		if relative >= NEAR_MISS_SPEED and gap > 0.0 and gap <= NEAR_MISS_GAP \
				and car.near_miss_cooldown <= 0.0:
			car.near_miss_cooldown = NEAR_MISS_COOLDOWN
			near_misses += 1
			Events.near_miss.emit(player, car)
		if gap <= HORN_GAP and car.horn_cooldown <= 0.0 and relative >= HORN_MIN_SPEED:
			car.horn_cooldown = HORN_COOLDOWN
			horns += 1
			car.horn()


## The gap between the player and the side of the car (m). A negative value means the player
## overlaps the car.
func _side_gap(car: TrafficCar, player_position: Vector3) -> float:
	var local := car.global_transform.affine_inverse() * player_position
	var half := Vector3(car.car_width * 0.5, 0.75, car.car_length * 0.5)
	if absf(local.z) > half.z + 1.0:
		return INF
	return absf(local.x) - half.x - PLAYER_HALF_WIDTH

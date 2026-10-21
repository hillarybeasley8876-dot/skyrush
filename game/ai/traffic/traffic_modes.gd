class_name TrafficModes
extends RefCounted
## The simulation mode of the traffic cars: FAR (frozen) and NEAR (dynamic).
##
## FAR cars are frozen kinematic bodies that are moved along their lane: cheap, and the player
## never hits an infinite-mass wall, because the car turns dynamic long before the contact. NEAR
## cars are dynamic: the player hits a real 1.5 t mass.
##
## The switch happens at 60 m, far enough from the player for the change to be invisible. A car
## that has drifted away from its lane (a lane change that was given up, a bump) stays dynamic
## until it is back on the lane, so the switch never snaps. Only the four cars nearest to the
## player may light the road: the world already pools 44 lights and the budget of the scene is 48
## (ART.md section 4).

const NEAR_RADIUS := 60.0      ## m: the distance that makes a car dynamic
const HEAD_LIGHT_CARS := 4     ## cars: how many traffic cars may light the road at once


## Switches the cars between the two modes and gives the head lamps to the nearest cars.
##
## The list of the near cars is returned: the events of the player (the near miss, the horn)
## only have to look at the cars that are around the player.
static func update(cars: Array[TrafficCar], player_position: Vector3,
		other_vehicles: Array[Node3D]) -> Array[TrafficCar]:
	var near_cars: Array[TrafficCar] = []
	for car in cars:
		var distance := car.global_position.distance_to(player_position)
		car.player_distance = distance
		if car.mode == TrafficCar.Mode.WRECK:
			car.head_light_allowed = false
			continue
		var near := distance < NEAR_RADIUS
		if not near:
			for other in other_vehicles:
				if not is_instance_valid(other):
					continue
				if car.global_position.distance_to(other.global_position) < NEAR_RADIUS:
					near = true
					break
		if near:
			if car.mode != TrafficCar.Mode.NEAR:
				car.set_mode(TrafficCar.Mode.NEAR)
		elif car.mode == TrafficCar.Mode.NEAR:
			# The car may only be frozen again when its body is on the lane: otherwise the
			# switch would snap it back onto the lane in front of the player. A car that has
			# drifted stays dynamic until the lane has it back.
			if car.can_freeze():
				car.set_mode(TrafficCar.Mode.FAR)
		if car.mode == TrafficCar.Mode.NEAR:
			near_cars.append(car)
	_give_head_lights(near_cars)
	return near_cars


## The head lamps go to the cars nearest to the player: a light per car is expensive, and the
## scene has a budget of 48 lights (ART.md section 4).
static func _give_head_lights(near_cars: Array[TrafficCar]) -> void:
	var sorted := near_cars.duplicate()
	sorted.sort_custom(func(a: TrafficCar, b: TrafficCar) -> bool:
		return a.player_distance < b.player_distance)
	for i in sorted.size():
		(sorted[i] as TrafficCar).head_light_allowed = i < HEAD_LIGHT_CARS

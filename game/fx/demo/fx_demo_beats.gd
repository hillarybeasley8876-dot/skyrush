extends Node3D
## The beats of the fx demo: the near miss, the hit, the scrape, the wreck, the takedown and the
## wreck of the traffic car.
##
## They live in their own file, so fx_demo.gd stays a readable timeline: the demo schedules the
## beats, this node plays them.

const WORLD := preload("res://fx/demo/fx_demo_world.gd")

const BOOST_START := 11.0
const BOOST_END := 12.0

var car: VehicleBase = null
var traffic: VehicleBase = null
var barrier: StaticBody3D = null
## The speed of the traffic car while it passes the player.
var traffic_speed: float = 30.0
## The throttle is released for the rest of the run (the car coasts at a street speed).
var throttle_on: bool = true
## True once the traffic car has passed the player.
var near_miss_done: bool = false
## The traffic car drives on until it leaves the frame: after that it stays where a beat puts
## it (the wreck of the ice car has to stay next to the player).
var traffic_driving: bool = true

var _scrape_timer: float = 0.0
var _nitro_state: int = 0


## Hands the beats the actors of the demo.
func setup(player_car: VehicleBase, traffic_car: VehicleBase, guard_rail: StaticBody3D) -> void:
	car = player_car
	traffic = traffic_car
	barrier = guard_rail


## The beats that need the clock (the traffic car, the scrape and the nitro).
func step(delta: float, t: float) -> void:
	_drive_traffic(delta, t)
	_scrape_step(delta)
	_nitro_input(t)


## A traffic car passes within a metre: a ribbon of displaced air.
func near_miss() -> void:
	if traffic == null or car == null:
		return
	# The traffic car passes on the open side of the road (the guard rail is on the other one
	# and it would hide it): the pass is real, the two cars never touch.
	# The traffic AI drives the car along its lane: its physics is switched off and its body is
	# frozen, or it would drive the car out of the frame.
	traffic_driving = false
	traffic.set_physics_process(false)
	traffic.freeze = true
	traffic.global_position = car.global_position \
			+ car.global_transform.basis * Vector3(2.8, 0.0, 3.0)
	Events.near_miss.emit(car, traffic)


## A hard hit on the side of the car: E5 sparks, glass and plastic. The surface is the flank of
## the car, so the sparks spray forward with the car (the burst is thrown around the reflection
## of the car's velocity on that surface).
func hit() -> void:
	# The traffic car is sent out of the frame: the burst is the subject of the shot, and the
	# sparks have to be seen against the road.
	if traffic != null and car != null:
		traffic.global_position = car.global_position \
				+ car.global_transform.basis * Vector3(-14.0, 0.0, -30.0)
	if car == null:
		return
	# The burst is on the right flank: the chase camera stands on that side, so the burst is
	# not hidden by the body of the car.
	var point := car.global_position + car.global_transform.basis * Vector3(1.2, 0.6, 0.4)
	var normal := car.global_transform.basis * Vector3(1.0, 0.1, 0.0)
	Events.vehicle_collided.emit(car, traffic, 26000.0, point, normal.normalized())


## Grinding along the guard rail: a continuous shower of sparks. The rail is moved next to the
## car, so the sparks always fly along a visible barrier, and it is passed as the other body, so
## the contact is read as a scrape.
func scrape() -> void:
	_scrape_timer = 1.6
	if car != null:
		# The car slows down to a sane speed, so it does not brake off the road.
		car.linear_velocity = Vector3(0.0, 0.0, -16.0)
	if barrier != null and car != null:
		barrier.global_position = car.global_position \
				+ car.global_transform.basis * Vector3(-1.6, 0.55, 0.0)


## The car is wrecked: a smoke column and fire licks. The car really takes the damage, so the
## electrical arcs of the EV show (they need a health below 30 %).
func wreck() -> void:
	if car == null:
		return
	car.apply_damage(car.max_health * 0.85, car.global_position + Vector3.UP, null)
	Events.vehicle_wrecked.emit(car, null)


## A takedown: oversized sparks, glass and body parts.
func takedown() -> void:
	if car == null:
		return
	Events.takedown.emit(car, &"traffic")


## The traffic car has passed the player: it drives on down the road.
func traffic_leaves() -> void:
	traffic_driving = false
	if traffic == null or car == null:
		return
	traffic.global_position = car.global_position \
			+ car.global_transform.basis * Vector3(2.8, 0.0, 60.0)


## The road dries: the weather controller of the environment unit owns the wetness, the fx unit
## only reads it.
func dry_road() -> void:
	var weather := get_tree().get_first_node_in_group(&"weather")
	if weather != null and weather.has_method(&"set_dry"):
		weather.call(&"set_dry")
		if weather.has_method(&"apply_now"):
			weather.call(&"apply_now")


## The driver lifts off: the car coasts at a speed a city street can hold.
func coast() -> void:
	throttle_on = false
	Input.action_release(&"accelerate")


## Before the skid the car is slowed down to a speed a street can hold: the drift then stays
## on the road.
func skid_speed() -> void:
	if car == null:
		return
	# 75 km/h: the drift has to be fast enough for a full plume of tyre smoke.
	car.linear_velocity = Vector3(0.0, 0.0, -21.0)


## After the drift the car is put back on the road and straightened: the showcase continues
## with a straight run.
func straighten() -> void:
	if car == null:
		return
	var speed := car.linear_velocity.length()
	car.global_rotation = Vector3.ZERO
	car.global_position = Vector3(WORLD.ROAD_CENTRE.x, car.global_position.y, car.global_position.z)
	car.angular_velocity = Vector3.ZERO
	car.linear_velocity = Vector3(0.0, 0.0, -maxf(speed, 15.0))


## The car stops: no input at all and it is frozen, so it stands still for the wreck beats
## (holding the brake would drive it backwards).
func stop() -> void:
	if car == null:
		return
	Input.action_release(&"accelerate")
	Input.action_release(&"brake")
	Input.action_release(&"drift")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true


## The traffic car burns: an ice car wrecks with fire, the player is an EV.
func wreck_ice() -> void:
	if traffic == null or car == null:
		return
	traffic.set_physics_process(false)
	traffic.freeze = true
	traffic.global_position = car.global_position + car.global_transform.basis * Vector3(2.5, 0.0, 3.0)
	if traffic.has_method(&"apply_damage"):
		traffic.apply_damage(traffic.max_health * 0.85, traffic.global_position + Vector3.UP, null)
	Events.vehicle_wrecked.emit(traffic, null)


## The traffic car drives past the player on its own lane, so the near miss is a real pass.
func _drive_traffic(delta: float, t: float) -> void:
	if traffic == null or car == null:
		return
	if t < 7.0 or not traffic_driving:
		return
	var forward := car.get_forward()
	traffic.global_position += forward * traffic_speed * delta
	traffic.global_position.y = car.global_position.y


## The scrape: the car grinds along the rail, the rail is the other body of the contact.
func _scrape_step(delta: float) -> void:
	if _scrape_timer <= 0.0 or car == null:
		return
	_scrape_timer -= delta
	var point := car.global_position + car.global_transform.basis * Vector3(-0.9, 0.5, 0.0)
	var normal := car.global_transform.basis * Vector3(-1.0, 0.05, 0.0)
	Events.vehicle_collided.emit(car, barrier, 900.0, point, normal.normalized())


## Taps the nitro: the key is held for a quarter of a second, so the vehicle really starts the
## boost (and the fx unit really gets the ignition event).
func _nitro_input(t: float) -> void:
	if _nitro_state == 0 and t >= BOOST_START and t < BOOST_END:
		Input.action_press(&"nitro")
		_nitro_state = 1
		return
	if _nitro_state == 1 and t >= BOOST_START + 0.25:
		Input.action_release(&"nitro")
		_nitro_state = 2

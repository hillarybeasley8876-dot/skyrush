class_name PoliceAir
extends RefCounted
## The drones of the pursuit (ref/gameplay/DOSSIER.md §3.4 and §6.3).
##
## One drone from heat 4, two from heat 5. The drone hovers 30-40 m over the player, keeps the
## line of sight even in a sky lane, drops a spike strip 120 m ahead every 25 s and fires an EMP
## pulse at heat 5.

## The node the drones are added to.
var host: Node3D = null
## The pool of the police objects.
var pool: PolicePool = null
## The spike strips on the road (the list of the dispatcher).
var strips: Array[PoliceSpikeStrip] = []
## The drones in the air.
var drones: Array[PoliceDrone] = []


## The tick: the drones fly, and the number of them follows the heat.
func update(delta: float, heat: int, player: VehicleBase) -> void:
	for drone in drones:
		drone.tick(delta, player, heat)
	var wanted := 0
	if heat >= 5:
		wanted = 2
	elif heat >= 4:
		wanted = 1
	while drones.size() > wanted:
		_release_drone(drones.pop_back() as PoliceDrone)
	while drones.size() < wanted:
		spawn_drone(player)


## Spawns a drone above the player.
func spawn_drone(player: VehicleBase) -> void:
	if host == null or player == null:
		return
	var drone := _take_drone()
	if drone == null:
		return
	drone.global_position = player.global_position + Vector3.UP * PoliceDrone.HOVER_HEIGHT
	drones.append(drone)
	PoliceRadio.say(&"drone")


## Takes a drone out of the pool.
func _take_drone() -> PoliceDrone:
	if pool != null:
		return pool.take_drone()
	var drone := PoliceDrone.new()
	host.add_child(drone)
	drone.setup()
	return drone


## Puts a drone back into the pool.
func _release_drone(drone: PoliceDrone) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	if pool != null:
		pool.release_drone(drone)
	else:
		drone.queue_free()

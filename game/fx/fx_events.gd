extends Node3D
## The event handlers of the fx director: the collisions, the wrecks, the takedowns, the near
## misses, the 闪充 charge flash and the nitro ignition.
##
## The handlers live in their own file so fx_director.gd stays about the pools, the tiers and the
## weather. The node is a child of the director.

const RigManager := preload("res://fx/fx_rig_manager.gd")
const IgnitionFx := preload("res://fx/fx_ignition.gd")
const ChargeFx := preload("res://fx/fx_charge.gd")
const SparkPool := preload("res://fx/fx_spark_pool.gd")
const DebrisPool := preload("res://fx/fx_debris_pool.gd")
const LightPool := preload("res://fx/fx_light_pool.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const Dev := preload("res://fx/fx_dev.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

## A contact is only used for the takedown burst while it is this fresh (seconds).
const CONTACT_FRESHNESS := 0.5

var manager: RigManager = null
var spark: SparkPool = null
var debris: DebrisPool = null
var lights: LightPool = null
## The quality scale of the particle preset (Settings.feature("particles")).
var quality: float = 1.0
## The dev switches of the director (--fx-no-*): they switch one family of effects off.
var dev: Dev = null


## Hands the handler the pools, the manager of the rigs and the quality scale.
func setup(rig_manager: RigManager, spark_pool: SparkPool, debris_pool: DebrisPool,
		light_pool: LightPool, particle_quality: float) -> void:
	manager = rig_manager
	spark = spark_pool
	debris = debris_pool
	lights = light_pool
	quality = particle_quality


## Connects every event of the fx unit.
func connect_events() -> void:
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.vehicle_wrecked.connect(_on_vehicle_wrecked)
	Events.takedown.connect(_on_takedown)
	Events.near_miss.connect(_on_near_miss)
	Events.charge_started.connect(_on_charge_started)
	Events.charge_finished.connect(_on_charge_finished)
	Events.boost_started.connect(_on_boost_started)


## ---------------------------------------------------------------------------------------------
## Collisions and wrecks
## ---------------------------------------------------------------------------------------------

func _on_vehicle_collided(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3,
		normal: Vector3) -> void:
	if vehicle == null or manager == null:
		return
	manager.set_contact(vehicle, point, normal)
	var rig := manager.rig_of(vehicle)
	if rig != null and is_instance_valid(rig):
		rig.on_collision(impulse, point, normal, other)


func _on_vehicle_wrecked(vehicle: VehicleBase, _source: Node3D) -> void:
	if manager == null:
		return
	var rig := manager.rig_of(vehicle)
	if rig != null and is_instance_valid(rig):
		rig.set_wrecked()


## A takedown is the show piece: oversized sparks, glass and body parts (DOSSIER §3.3).
##
## The burst starts at the last contact point of the victim, but only when that contact is
## fresh (half a second): after that the burst happens on the side of the victim that faces
## the attacker, so it never lands 40 m behind the car.
func _on_takedown(victim: VehicleBase, _kind: StringName) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var contact := manager.contact_of(victim)
	var fresh := float(contact.get("time", -10.0)) > _now() - CONTACT_FRESHNESS
	var point: Vector3
	var normal: Vector3
	if fresh:
		point = contact.get("point", victim.global_position)
		normal = contact.get("normal", Vector3.UP)
	else:
		var attacker := Game.player
		var side := Vector3.FORWARD
		if attacker != null and is_instance_valid(attacker):
			side = (attacker.global_position - victim.global_position)
			if side.length() < 0.01:
				side = victim.get_forward()
			else:
				side = side.normalized()
		point = victim.global_position + side * 0.6 + Vector3.UP * 0.6
		normal = side
	var ground := _ground_under(point)
	spark.burst(point, normal, TUNE.TAKEDOWN_SPARKS, TUNE.TAKEDOWN_SPEED, TUNE.TAKEDOWN_SCALE,
			ground, victim.linear_velocity)
	if not _debris_off():
		debris.burst(point, normal, TUNE.TAKEDOWN_GLASS, TUNE.TAKEDOWN_PLASTIC,
				TUNE.TAKEDOWN_SCALE, ground, victim.linear_velocity)
	lights.flash(point, Color(1.0, 0.85, 0.6), 12.0, 6.0, 0.25)


## True when the dev switches ask for the debris to be off.
func _debris_off() -> bool:
	return dev != null and dev.no_debris


## The height of the road under a point (the events arrive in the physics step, so the raycast
## is safe here).
func _ground_under(point: Vector3) -> float:
	var world := Game.world
	if world != null:
		var y := world.ground_height(point)
		if not is_nan(y):
			return y
	var space := get_world_3d().direct_space_state
	var result := GROUND.probe(space, point)
	return (result["point"] as Vector3).y if result["hit"] else 0.0


## ---------------------------------------------------------------------------------------------
## Near miss, charge and nitro
## ---------------------------------------------------------------------------------------------

func _on_near_miss(vehicle: VehicleBase, other: VehicleBase) -> void:
	if manager == null:
		return
	var rig := manager.rig_of(vehicle)
	if rig != null and is_instance_valid(rig):
		rig.near_miss(other)


func _on_charge_started(vehicle: VehicleBase, _station: Area3D) -> void:
	_spawn_charge(vehicle)


func _on_charge_finished(vehicle: VehicleBase, _station: Area3D, _amount: float) -> void:
	_spawn_charge(vehicle)


## A nitro ignition is cold gas: a white vapour puff and a shock ring, never orange sparks
## (dossier §5.5).
func _on_boost_started(vehicle: VehicleBase, kind: StringName) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or kind != &"nitro":
		return
	if dev != null and dev.no_ignition:
		return
	for child in vehicle.get_children():
		if child.name == "IgnitionFx":
			return
	var ignition := IgnitionFx.new()
	ignition.name = "IgnitionFx"
	vehicle.add_child(ignition)
	ignition.play(vehicle, quality)


## The 闪充 flash: it lives on the car, so it follows it through the charging bay.
func _spawn_charge(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if dev != null and dev.no_charge_flash:
		return
	for child in vehicle.get_children():
		if child.name == "ChargeFlash":
			return
	var charge := ChargeFx.new()
	charge.name = "ChargeFlash"
	charge.dev = dev
	vehicle.add_child(charge)
	charge.play(vehicle)


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

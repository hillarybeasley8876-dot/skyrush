class_name VehicleBase
extends RigidBody3D
## Contract for every car (player, rivals, police, traffic). The vehicle unit implements the physics
## in a subclass (ArcadeCar); AI controllers drive any VehicleBase only through set_controls() and
## the ability methods; damage/FX/audio/HUD read `telemetry` and the signals below.
## Node conventions inside a car scene: a child Node3D named "Visual" holds all meshes (the glTF
## instance); Marker3D nodes named like the glTF empties (Nozzle_R1, Light_Rear, ...) sit under it.

signal damaged(amount: float, point: Vector3, source: Node3D)
signal wrecked(source: Node3D)

enum Team { PLAYER, RIVAL, POLICE, TRAFFIC }

@export var team: Team = Team.TRAFFIC
@export var display_name: String = ""
@export var max_health: float = 100.0

var health: float = 100.0
var is_wrecked: bool = false
var telemetry: CarTelemetry = CarTelemetry.new()


func _ready() -> void:
	health = max_health


## Driving input in [-1, 1] / [0, 1]. Implemented by the vehicle unit.
func set_controls(_throttle: float, _brake: float, _steer: float, _handbrake: bool) -> void:
	pass


## Optional abilities (no-ops for cars that do not have them).
func set_drift(_on: bool) -> void:
	pass


func use_nitro() -> bool:
	return false


func request_hop() -> bool:
	return false


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func get_forward() -> Vector3:
	return -global_transform.basis.z


func is_airborne() -> bool:
	return telemetry.airborne


## The markers that get_marker found, by name.
var _markers: Dictionary = {}


func get_visual_root() -> Node3D:
	return get_node_or_null(^"Visual") as Node3D


## Finds a marker/empty by name anywhere under Visual (e.g. &"Nozzle_R1"), or null.
##
## A marker that was found is kept: the effects ask for the four wheels of every car near the player in every physics tick, and a
## search of the visual for each of them cost 20-30 traffic cars 0.8 ms a tick. A kept marker counts only while it is still under
## the visual (a pooled traffic car changes its model).
func get_marker(marker_name: StringName) -> Node3D:
	var visual := get_visual_root()
	if visual == null:
		return null
	var kept: Variant = _markers.get(marker_name)
	if kept != null and is_instance_valid(kept) and visual.is_ancestor_of(kept as Node):
		return kept as Node3D
	var found := visual.find_child(String(marker_name), true, false) as Node3D
	if found != null:
		_markers[marker_name] = found
	return found


func apply_damage(amount: float, point: Vector3, source: Node3D) -> void:
	if is_wrecked or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	telemetry.health_norm = health / max_health
	damaged.emit(amount, point, source)
	Events.vehicle_damaged.emit(self, amount, source)
	if health <= 0.0:
		wreck(source)


func wreck(source: Node3D) -> void:
	if is_wrecked:
		return
	is_wrecked = true
	wrecked.emit(source)
	Events.vehicle_wrecked.emit(self, source)


func repair() -> void:
	is_wrecked = false
	health = max_health
	telemetry.health_norm = 1.0


## Teleport (respawn/reset): zero velocities, place at xform.
func reset_to(xform: Transform3D) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = xform
	reset_physics_interpolation()

extends RefCounted
## Shared helpers for the camera unit's tests: the camera rig, a car, walls, a victim and a
## sampler that reads the camera after its own _process (so the test sees the drawn frame).

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

var cam_root: Node3D = null
var cam: Camera3D = null
var car: VehicleBase = null


## Samples the camera after its own _process (process_priority), so the test sees the
## position that is actually drawn.
class Sampler extends Node:
	var cam: Camera3D = null
	var worst: float = INF
	var frames: int = 0

	func _ready() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		if cam == null:
			return
		frames += 1
		worst = minf(worst, cam.global_position.z)


## Builds the chase camera and a parked car, and hands the car to the game.
func setup(host: Node) -> void:
	cam_root = (load("res://vehicle/camera/chase_camera.tscn") as PackedScene).instantiate() as Node3D
	host.add_child(cam_root)
	car = new_car(host, Vector3.ZERO, Vector3.ZERO)
	Game.player = car
	cam = cam_root.call("get_camera") as Camera3D


func new_car(host: Node, pos: Vector3, velocity: Vector3) -> VehicleBase:
	var vehicle := VehicleBase.new()
	vehicle.freeze = true
	vehicle.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	vehicle.collision_layer = 2
	host.add_child(vehicle)
	vehicle.global_position = pos
	vehicle.linear_velocity = velocity
	return vehicle


## A static box, used as a wall, a parapet or a tunnel side.
func box(host: Node, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	host.add_child(body)
	body.global_position = pos
	return body


## Runs the physics for `count` ticks.
func tick(host: Node, count: int) -> void:
	for i in count:
		await host.get_tree().physics_frame


## The horizontal distance between two points.
func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True when a ray from `from` to `to` is blocked by the world.
func blocked(host: Node, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	return not host.get_viewport().world_3d.direct_space_state.intersect_ray(query).is_empty()

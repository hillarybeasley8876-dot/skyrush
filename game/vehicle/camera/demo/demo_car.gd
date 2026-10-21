extends VehicleBase
## The capture rig's car: the real Roadster (game/assets/cars/roadster/roadster.glb) on the
## camera unit's own physics, driven by demo_cam.gd. The camera reads it exactly like the
## real car: transform, velocity, telemetry and the `Camera_Hood` marker of the glb.

const ROADSTER := preload("res://assets/cars/roadster/roadster.glb")


func _ready() -> void:
	super._ready()
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 1 << 1
	collision_mask = 0b111
	_build_visual()


func _build_visual() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var model := ROADSTER.instantiate() as Node3D
	model.name = "Model"
	visual.add_child(model)
	MaterialLibrary.apply(model)


## Places the car and sets the velocity the camera reads.
func set_drive(pos: Vector3, heading: Vector3, vel: Vector3) -> void:
	global_position = pos
	var flat := Vector3(heading.x, 0.0, heading.z)
	if flat.length() > 0.01:
		look_at(pos + flat.normalized(), Vector3.UP)
	linear_velocity = vel
	telemetry.speed_kmh = vel.length() * 3.6
	telemetry.forward_speed_kmh = vel.dot(flat.normalized()) * 3.6
	telemetry.throttle = 1.0 if vel.length() > 1.0 else 0.0

extends VehicleBase
## Placeholder driveable car (until the vehicle unit lands): a white box that slides on low-friction
## physics with arcade forces. Reads player input itself when it is Game.player. Not a reference
## implementation — the vehicle unit replaces it entirely.

const ENGINE_FORCE := 16000.0
const MAX_KMH := 230.0
const TURN_RATE := 2.0
const HOP_SPEED := 9.0

var _throttle: float = 0.0
var _brake: float = 0.0
var _steer: float = 0.0


func _ready() -> void:
	super._ready()
	mass = 1800.0
	collision_layer = 1 << 1
	collision_mask = 0b111
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.05
	_build_body()


func _build_body() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.1, 4.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.95)
	mat.roughness = 0.3
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.55
	visual.add_child(mesh)
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	shape.position.y = 0.55
	add_child(shape)


func set_controls(throttle: float, brake: float, steer: float, _handbrake: bool) -> void:
	_throttle = clampf(throttle, 0.0, 1.0)
	_brake = clampf(brake, 0.0, 1.0)
	_steer = clampf(steer, -1.0, 1.0)


func request_hop() -> bool:
	if telemetry.n2 < 25.0:
		return false
	telemetry.n2 -= 25.0
	linear_velocity.y = HOP_SPEED
	Events.hop.emit(self, &"hop")
	return true


func _physics_process(delta: float) -> void:
	if Game.player == self:
		set_controls(Input.get_action_strength(&"accelerate"), Input.get_action_strength(&"brake"),
				Input.get_axis(&"steer_left", &"steer_right"), false)
		if Input.is_action_just_pressed(&"hop"):
			request_hop()
	var fwd := get_forward()
	var speed := linear_velocity.dot(fwd)
	if absf(speed) * 3.6 < MAX_KMH:
		apply_central_force(fwd * ENGINE_FORCE * (_throttle - _brake * 0.9))
	var right := global_transform.basis.x
	apply_central_force(-right * linear_velocity.dot(right) * mass * 3.0)
	var yaw_target := -_steer * TURN_RATE * clampf(speed / 12.0, -1.0, 1.0)
	angular_velocity.y = lerpf(angular_velocity.y, yaw_target, clampf(delta * 8.0, 0.0, 1.0))
	_update_telemetry(speed)


func _update_telemetry(speed: float) -> void:
	telemetry.speed_kmh = linear_velocity.length() * 3.6
	telemetry.forward_speed_kmh = speed * 3.6
	telemetry.throttle = _throttle
	telemetry.brake = _brake
	telemetry.steer = _steer
	telemetry.airborne = global_position.y > 1.5 and absf(linear_velocity.y) > 0.5
	telemetry.altitude_m = maxf(global_position.y - 0.0, 0.0)
	telemetry.n2 = minf(telemetry.n2 + 3.0 / Engine.physics_ticks_per_second, 200.0)

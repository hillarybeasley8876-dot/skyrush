class_name RaycastWheelCar
extends RigidBody3D
## Arcade raycast-suspension car. Verified on Godot 4.7.2 + Jolt Physics, 120 Hz physics,
## 100 m/s over a seamed/bumpy ConcavePolygonShape3D road and a 2 m kicker jump
## (harness: ref/tech/probe/scripts/phys_wheels.gd).
## Scene setup: this RigidBody3D + one CollisionShape3D (BoxShape3D or convex hull of the body,
## NOT the wheels). Wheels are visual only; read wheel_center(i) each frame to place them.

enum Probe { RAY, SPHERE }
@export var probe_mode := Probe.SPHERE        # SPHERE = ShapeCast3D, rides over seams/curbs better
## Local mount points FL, FR, RL, RR (-Z is forward). Mount = top of suspension travel.
@export var wheel_mounts: Array[Vector3] = [
	Vector3(-0.82, -0.05, -1.38), Vector3(0.82, -0.05, -1.38),
	Vector3(-0.82, -0.05, 1.38), Vector3(0.82, -0.05, 1.38)]
@export var rest_length := 0.30      # m, suspension travel
@export var wheel_radius := 0.34     # m
@export var spring_k := 45000.0      # N/m per wheel (1800 kg car -> ~0.10 m static sag)
@export var damper_c := 3200.0       # N*s/m per wheel (~0.35 damping ratio)
@export var grip := 1.6              # lateral friction coefficient (arcade: > 1)
@export var engine_force := 12000.0  # N total at throttle 1 (rear wheels)
@export var max_steer_deg := 28.0
@export var max_load_factor := 6.0     # suspension force cap = 6x static wheel load (landing spikes)
@export var slip_cancel := 0.5         # fraction of side slip removed per step (1.0 = twitchy)
@export var air_level_k := 20000.0     # N*m per rad: rotates the car upright while airborne
@export var air_level_d := 8000.0      # N*m*s per rad: damps spin while airborne

var throttle := 0.0                  # -1..1, written by input / AI code
var steer := 0.0                     # -1..1 (positive = left)
var contact: Array[bool] = [false, false, false, false]
var compression: Array[float] = [0.0, 0.0, 0.0, 0.0]
var probes: Array[Node3D] = []
var _hit_point := Vector3.ZERO
var _susp_len: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	continuous_cd = true            # mandatory at 100 m/s (see GODOT.md tunnelling table)
	can_sleep = false
	for m in wheel_mounts:
		var p: Node3D
		if probe_mode == Probe.RAY:
			var r := RayCast3D.new()
			r.target_position = Vector3(0, -(rest_length + wheel_radius), 0)
			r.add_exception(self)
			p = r
		else:
			var s := ShapeCast3D.new()
			var sph := SphereShape3D.new()
			sph.radius = wheel_radius
			s.shape = sph
			s.target_position = Vector3(0, -rest_length, 0)
			s.max_results = 1
			s.add_exception(self)
			p = s
		p.position = m
		add_child(p)
		probes.append(p)

## Suspension length (m) of wheel i this step, or -1.0 when the wheel is in the air.
func _probe(i: int) -> float:
	var p := probes[i]
	if p is RayCast3D:
		var r := p as RayCast3D
		r.force_raycast_update()
		if not r.is_colliding():
			return -1.0
		_hit_point = r.get_collision_point()
		return r.global_position.distance_to(_hit_point) - wheel_radius
	var s := p as ShapeCast3D
	s.force_shapecast_update()
	if not s.is_colliding():
		return -1.0
	_hit_point = s.get_collision_point(0)
	return rest_length * s.get_closest_collision_safe_fraction()

func _physics_process(delta: float) -> void:
	var up := global_basis.y
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var static_load := mass * g / probes.size()
	for i in probes.size():
		var length := _probe(i)
		contact[i] = length >= 0.0
		_susp_len[i] = length if contact[i] else rest_length
		if not contact[i]:
			compression[i] = 0.0
			continue
		var comp := clampf(rest_length - length, 0.0, rest_length)
		compression[i] = comp
		var offset := probes[i].global_position - global_position   # force at mount: stable, less roll
		var v := linear_velocity + angular_velocity.cross(offset)
		var f_susp := clampf(spring_k * comp - damper_c * v.dot(up), 0.0, max_load_factor * static_load)
		var fwd := -global_basis.z
		var side := global_basis.x
		if i < 2:
			var a := deg_to_rad(max_steer_deg) * steer
			fwd = fwd.rotated(up, a)
			side = side.rotated(up, a)
		# lateral: remove part of this wheel's share of side slip, capped by grip * (load, max 2x static)
		var f_cap := grip * minf(f_susp, 2.0 * static_load)
		var f_lat := clampf(-v.dot(side) * slip_cancel * mass / probes.size() / delta, -f_cap, f_cap)
		var force := up * f_susp + side * f_lat
		if i >= 2:
			force += fwd * engine_force * 0.5 * throttle
		apply_force(force, offset)
	if not is_grounded():   # arcade air control: level the car, kill tumble
		apply_torque(up.cross(Vector3.UP) * air_level_k - angular_velocity * air_level_d)

## World-space wheel centre for visuals (mesh.global_position = car.wheel_center(i)).
func wheel_center(i: int) -> Vector3:
	return probes[i].global_position - global_basis.y * _susp_len[i]

func is_grounded() -> bool:
	return contact.has(true)

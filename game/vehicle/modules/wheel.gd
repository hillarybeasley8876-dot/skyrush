extends RefCounted
## One wheel of the arcade car: a ShapeCast3D sphere probe, the suspension spring/damper and the
## lateral tyre force. Pure physics - it touches the scene only through its probe node.
## Geometry (dossier 4.4, lead decision): a small probe sphere is cast straight down from the
## mount; the tyre centre sits one tyre radius above the contact point.
##
## The suspension numbers come from the CarSpec (per car), so every preset settles on its
## wheels instead of on its bump stops.

const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")
const TyreTuning := preload("res://vehicle/tuning/tyre_tuning.gd")

## What a wheel can stand on: the world, the cars and the props.
const PROBE_MASK := 0b111

## Wheel index: 0 = FL, 1 = FR, 2 = RL, 3 = RR.
var index: int = 0
var radius: float = 0.36
## Mount point in body-local space (top of the suspension travel).
var mount: Vector3 = Vector3.ZERO
var steerable: bool = false
var driven: bool = false

var probe: ShapeCast3D
## True while the tyre touches something.
var contact: bool = false
## Spring compression in metres (0 at full droop).
var compression: float = 0.0
## Anchor -> wheel centre distance in metres.
var susp_length: float = 0.0
## Suspension force of this wheel in newtons.
var load: float = 0.0
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
## World position of the wheel centre (for the visual wheel).
var wheel_center: Vector3 = Vector3.ZERO
## Visual state.
var spin: float = 0.0
var steer_angle: float = 0.0
## Accumulated longitudinal travel, used to spin the visual wheel.
var travel: float = 0.0
## The slip angle of this tyre in degrees (for the squeal and the smoke).
var slip: float = 0.0

var _spring_k: float = 0.0
var _damp_bump: float = 0.0
var _damp_rebound: float = 0.0
var _bumpstop_k: float = 0.0
var _susp_max: float = 0.0
var _rest_len: float = 0.0
var _travel: float = 0.0


## Creates the probe node under `parent` (the car body).
func setup(parent: Node3D, spec: CarSpec, wheel_index: int) -> void:
	index = wheel_index
	radius = spec.wheel_radii[wheel_index]
	mount = spec.wheel_mounts[wheel_index]
	steerable = spec.is_steered(wheel_index)
	driven = spec.is_driven(wheel_index)
	_spring_k = spec.spring_k
	_damp_bump = spec.damp_bump
	_damp_rebound = spec.damp_rebound
	_bumpstop_k = spec.bumpstop_k
	_susp_max = spec.susp_max
	_rest_len = spec.rest_len
	_travel = spec.travel
	probe = ShapeCast3D.new()
	probe.name = "WheelProbe%d" % wheel_index
	var sphere := SphereShape3D.new()
	sphere.radius = SuspensionTuning.PROBE_RADIUS
	probe.shape = sphere
	probe.target_position = Vector3(0.0, -SuspensionTuning.PROBE_CAST, 0.0)
	probe.collision_mask = PROBE_MASK
	probe.exclude_parent = true
	probe.max_results = 1
	probe.position = probe_mount(mount, spec.body_size.x)
	# The car casts the probe itself (update_probe, every physics tick): an enabled ShapeCast3D casts again on its own in the same
	# tick, from the same place, for nothing (four casts of every car near the player, 120 times a second).
	probe.enabled = false
	parent.add_child(probe)
	susp_length = _rest_len


## Where the probe of a wheel at `mount` is cast from: the mount, moved in so the sphere stays inside the side of the
## collision box (`box_width` wide) by SuspensionTuning.PROBE_INSET.
static func probe_mount(at: Vector3, box_width: float) -> Vector3:
	var reach: float = maxf(box_width * 0.5 - SuspensionTuning.PROBE_RADIUS - SuspensionTuning.PROBE_INSET, 0.0)
	return Vector3(clampf(at.x, -reach, reach), at.y, at.z)


## Casts the probe and refreshes contact, compression and the wheel centre.
func update_probe(anchor_world: Vector3, body_up: Vector3) -> void:
	if probe == null:
		return
	# The probe sees what the body hits: a ghost (damage/wreck_flow.gd) drives through the other cars, and its wheels must not
	# stand on them (a player stood half on the police car that had driven into its ghost, and popped up when it drove off).
	var body := probe.get_parent() as CollisionObject3D
	if body != null:
		probe.collision_mask = PROBE_MASK & body.collision_mask
	probe.force_shapecast_update()
	# The probe is cast from inside the box (probe_mount): what it finds is put back under the mount, where the tyre is drawn
	# and the force acts.
	var to_mount: Vector3 = probe.global_basis * (mount - probe.position)
	# A wall, a ceiling or the back of a surface is not ground (SuspensionTuning.MIN_GROUND_NORMAL_Y).
	var standing: bool = probe.is_colliding() \
			and probe.get_collision_normal(0).y >= SuspensionTuning.MIN_GROUND_NORMAL_Y
	if not standing:
		contact = false
		compression = 0.0
		load = 0.0
		susp_length = _rest_len
		wheel_center = anchor_world + to_mount - body_up * _rest_len
		return
	contact = true
	contact_point = probe.get_collision_point(0) + to_mount
	contact_normal = probe.get_collision_normal(0)
	var frac: float = probe.get_closest_collision_safe_fraction()
	# Distance from the mount down to the probe sphere centre at the contact.
	var d_probe: float = frac * SuspensionTuning.PROBE_CAST
	# The tyre centre is one tyre radius above the probe sphere.
	susp_length = d_probe - (radius - SuspensionTuning.PROBE_RADIUS)
	compression = clampf(_rest_len - susp_length, 0.0, _rest_len)
	wheel_center = contact_point + contact_normal * radius


## Spring + damper force in newtons (never negative: the tyre cannot pull the car down).
## v_mount is the velocity of the mount point, up the body up axis.
func suspension_force(v_mount: Vector3, up: Vector3, damp_mult: float) -> float:
	if not contact:
		return 0.0
	var v_vert: float = v_mount.dot(up)
	var c: float = _damp_bump if v_vert < 0.0 else _damp_rebound
	var f: float = _spring_k * compression - c * damp_mult * v_vert
	if compression > _travel:
		# The stop springs and damps: a stop that only springs gives the energy of a hard landing back as a bounce (the
		# floor of the collision box used to take the landing, and it is out of reach of the road now).
		f += _bumpstop_k * (compression - _travel) - _bumpstop_k * SuspensionTuning.BUMPSTOP_DAMP_TIME * v_vert
	return clampf(f, 0.0, _susp_max)


## The most lateral force of the tyre (N): mu x load x the grip curve of its slip (`slip_deg`, measured before the force).
func lateral_cap(slip_deg: float, mu: float) -> float:
	if not contact or load <= 0.0:
		return 0.0
	return mu * load * grip_factor(slip_deg)


## The grip curve: the slip in degrees -> the grip factor (dossier 4.5). The curve is read
## linearly, so the grip fades smoothly instead of in steps.
static func grip_factor(slip_deg: float) -> float:
	var curve: Array[Vector2] = TyreTuning.GRIP_CURVE
	if slip_deg <= curve[0].x:
		return curve[0].y
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		if slip_deg <= b.x:
			var t: float = (slip_deg - a.x) / maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, t)
	return curve[curve.size() - 1].y

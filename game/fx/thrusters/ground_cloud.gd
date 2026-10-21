extends Node3D
## Ground clouds: the vapour where a down-firing jet meets the road (dossier §6.1 / §6.3).
##
## Lift cloud: a low bank of vapour standing on the road where the plume hits. The puffs are
## 2.4-3.6 m across, and 280 of them make one continuous bank 14 m wide and 2.2 m tall a
## second after the impact (23 m and 2.6 m after a second and a half).
## Rear launch cloud: a cone that starts at the nozzle exit and trails backwards, 12-13 m long
## and 4-5 m wide at the far end (photo 29).
##
## The sprites are the lead's shared smoke atlas (core/fx/smoke.gd, SmokeFX).

const SmokeFX := preload("res://core/fx/smoke.gd")
const PlumeAssets := preload("res://fx/thrusters/lib/plume_assets.gd")

## Particles alive per cloud. The lift cloud uses 280: the review's coverage targets (70 %
## within 6 m, 40 % within 10 m) need a dense bank, and the count must never drop below 90.
const CLOUD_AMOUNT := 280
const REAR_AMOUNT := 110
const CLOUD_LIFETIME := 3.5
const REAR_LIFETIME := 1.1
## The ring of vapour under the impact point.
const EMIT_HEIGHT := 0.3
## Radial burst speed, m/s (the dossier's 6-12 m/s, the fast end for the bank to reach 20 m).
const RADIAL_MIN := 8.0
const RADIAL_MAX := 16.0
## The vapour spreads sideways, in a flat fan on the road.
const LIFT_SPREAD := 180.0
## The lift cloud's drag. Measured: a particle at 12 m/s with a damping of 5.5 only travels
## 3.4 m, so the bank was 7 m across instead of 20. With a damping of 1.2 the travel is 10 m
## after a second, and the bank is 20 m wide.
const CLOUD_DAMPING := 0.8
## The rear trail is a narrow cone behind the car (9 degrees half angle, 12-13 m long). The
## damping is low, so the gas keeps moving: v/d * ln(1 + d t) = 13.6 m after 1.1 s.
const REAR_SPEED_MIN := 12.0
const REAR_SPEED_MAX := 16.0
const REAR_SPREAD := 9.0
const REAR_DAMPING := 0.6
## The cloud's puffs: 2.4-3.6 m across. The review's preset size (2.0-3.2 m, grown to
## 4.8-7.7 m) covers the whole screen from the chase camera: 220 of them cost more than the
## whole frame budget on their own (see the request in the status file).
const CLOUD_SIZE := Vector2(2.4, 3.6)
const CLOUD_GROW := 2.4
## The rear trail's sprites: 1.2-1.8 m, so the cone has no gaps and is 4-5 m wide at the far
## end (photo 29).
const REAR_SIZE := Vector2(1.2, 1.8)
const REAR_GROW := 3.0
## The rear trail reaches 13 m, so the emitter's bounding box has to cover it: the box is in the
## emitter's own frame, whose -Z is the jet direction. Without it the trail pops out of view
## when the car drives out of the frame.
const REAR_AABB := AABB(Vector3(-8.0, -5.0, -18.0), Vector3(16.0, 10.0, 22.0))

var _lift: GPUParticles3D
var _rear: GPUParticles3D


func _ready() -> void:
	_lift = _make_cloud(CLOUD_AMOUNT, true)
	_lift.name = "LiftCloud"
	_rear = _make_cloud(REAR_AMOUNT, false)
	_rear.name = "RearCloud"
	add_child(_lift)
	add_child(_rear)


func _make_cloud(amount: int, lift: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var spec: Dictionary = SmokeFX.preset(&"ground_cloud")
	spec["amount"] = amount
	spec["lifetime"] = CLOUD_LIFETIME if lift else REAR_LIFETIME
	spec["damping"] = Vector2(CLOUD_DAMPING, CLOUD_DAMPING) if lift \
			else Vector2(REAR_DAMPING, REAR_DAMPING)
	spec["spread"] = LIFT_SPREAD if lift else REAR_SPREAD
	spec["size"] = CLOUD_SIZE if lift else REAR_SIZE
	spec["grow"] = CLOUD_GROW if lift else REAR_GROW
	spec["color"] = PlumeAssets.CLOUD_BIRTH if lift else PlumeAssets.TRAIL_BIRTH
	# The rear trail is a cone along the jet, not a flat fan on the ground.
	spec["flat"] = 0.0 if not lift else 1.0
	if lift:
		# The dossier's radial burst: 6-12 m/s out of the impact point.
		spec["speed"] = Vector2(RADIAL_MIN, RADIAL_MAX)
	else:
		spec["speed"] = Vector2(REAR_SPEED_MIN, REAR_SPEED_MAX)
	SmokeFX.setup(p, spec)
	PlumeAssets.uncap_growth(p, CLOUD_GROW if lift else REAR_GROW)
	# The big soft sprites use the cheap per-vertex variant of the shared atlas.
	var quad := p.draw_pass_1 as QuadMesh
	quad.material = PlumeAssets.cloud_material()
	if not lift:
		p.visibility_aabb = REAR_AABB
	p.emitting = false
	_tune_cloud(p, lift)
	return p


## The parts the shared preset cannot know: the gas stays where it was emitted, the vapour lands
## on the road, and the rear trail points along the jet.
func _tune_cloud(p: GPUParticles3D, lift: bool) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	# The gas stays where it was emitted (dossier §6.1).
	pm.inherit_velocity_ratio = 0.0
	# The vapour lands on the road instead of sinking through it.
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.0
	pm.collision_friction = 0.3
	pm.collision_use_scale = true
	if lift:
		# The lead's ground_cloud preset is a flat fan of vapour that spreads over the road
		# (core/fx/smoke.gd, look-dev captures/lead_smoke7_*.jpg). Only the burst speed is
		# retuned: the dossier's 6-12 m/s.
		pm.initial_velocity_min = RADIAL_MIN
		pm.initial_velocity_max = RADIAL_MAX
		pm.radial_velocity_min = 0.0
		pm.radial_velocity_max = 0.0
		pm.radial_accel_min = 0.0
		pm.radial_accel_max = 0.0
	else:
		# The rear trail is a cone along the jet axis.
		pm.direction = Vector3(0, 0, -1)
		pm.spread = REAR_SPREAD
		pm.flatness = 0.0
		pm.initial_velocity_min = REAR_SPEED_MIN
		pm.initial_velocity_max = REAR_SPEED_MAX
		pm.radial_velocity_min = 0.0
		pm.radial_velocity_max = 0.0
		pm.radial_accel_min = 0.0
		pm.radial_accel_max = 0.0


## The particles alive for both clouds.
func particle_capacity() -> int:
	return _lift.amount + _rear.amount


## Called every frame by the rig. `lift_hit` is the road under a down-firing jet (or INF), and the
## rear cloud only runs while `rear_enabled` is true, from `rear_exit` along `rear_dir`.
## `lift_ratio` is the throttle of the lift jets: a weak jet throws up less vapour.
func update_clouds(_delta: float, lift_hit: Vector3, lift_ratio: float, rear_enabled: bool,
		rear_exit: Vector3, rear_dir: Vector3, _car_basis: Basis) -> void:
	_lift.amount_ratio = clampf(lift_ratio, 0.0, 1.0)
	_update_one(_lift, lift_hit, Basis.IDENTITY, Vector3(0.0, EMIT_HEIGHT, 0.0))
	if rear_enabled and rear_exit.is_finite():
		# The jet is the emitter's -Z, so the basis looks along the jet.
		var basis := Basis.looking_at(rear_dir, Vector3.UP)
		_update_one(_rear, rear_exit, basis, Vector3.ZERO)
	else:
		_rear.emitting = false


## Stops both clouds. Used when the rig is demoted, so a demoted car does not keep throwing up
## vapour (review SHOULD-FIX 1).
func stop() -> void:
	_lift.emitting = false
	_rear.emitting = false


func _update_one(emitter: GPUParticles3D, point: Vector3, basis: Basis, offset: Vector3) -> void:
	if not point.is_finite():
		emitter.emitting = false
		return
	emitter.global_transform = Transform3D(basis, point + offset)
	emitter.emitting = true

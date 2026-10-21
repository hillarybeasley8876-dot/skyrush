extends Node3D
## Landing puff (gameplay dossier §5.5): a low ring of vapour bursting outwards past the wheels
## plus a faint ring decal on the road.
##
## The sprites are the lead's shared smoke atlas (core/fx/smoke.gd, SmokeFX).

const SmokeFX := preload("res://core/fx/smoke.gd")
const PlumeAssets := preload("res://fx/thrusters/lib/plume_assets.gd")

const PUFF_AMOUNT := 64
const PUFF_LIFETIME := 0.9
## Radius of the ring under the car.
const RING_RADIUS := 1.2
## The ring is stretched to the car's footprint.
const RING_SCALE := Vector3(1.2, 1.0, 2.4)
## The inner radius, as a fraction of the ring radius.
const RING_INNER_FACTOR := 0.72
const RING_HEIGHT := 0.1
## Radial burst speed, m/s.
const RADIAL_MIN := 5.5
const RADIAL_MAX := 6.5
## A little lift on top of the radial burst.
const LIFT_SPEED := 0.8
## The burst lifts the vapour a little less than it spreads it.
const LIFT_SPEED_FACTOR := 0.8
const LIFT_SPREAD := 10.0
const DAMPING := 4.0
const PUFF_SIZE := Vector2(1.4, 2.0)
const PUFF_GROW := 2.5
## The decal under the puff.
const DECAL_SIZE := Vector3(4.0, 2.0, 6.0)
const DECAL_ALPHA := 0.4
const DECAL_LIFETIME := 0.25
## The decal fades out over this distance at its edges.
const DECAL_EDGE_FADE := 0.2
## The decal must not be culled by a layer mask.
const DECAL_CULL_MASK := 1048575
## The puff outlives the decal by this much before it frees itself.
const PUFF_LIFETIME_MARGIN := 0.1
## Height of the ring above the road.
const RING_HEIGHT_ABOVE := 0.18
const DECAL_HEIGHT := 0.03

var _puff: GPUParticles3D
var _decal: Decal
var _age: float = 0.0


func _ready() -> void:
	_puff = _make_puff()
	add_child(_puff)
	_decal = Decal.new()
	_decal.name = "GroundRing"
	_decal.texture_albedo = PlumeAssets.ring_texture()
	_decal.size = DECAL_SIZE
	_decal.albedo_mix = 1.0
	_decal.modulate = Color(PlumeAssets.VAPOUR_BIRTH.r, PlumeAssets.VAPOUR_BIRTH.g,
			PlumeAssets.VAPOUR_BIRTH.b, 0.0)
	_decal.upper_fade = DECAL_EDGE_FADE
	_decal.lower_fade = DECAL_EDGE_FADE
	_decal.cull_mask = DECAL_CULL_MASK
	_decal.visible = false
	add_child(_decal)


func _make_puff() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Puff"
	var spec: Dictionary = SmokeFX.preset(&"ground_cloud")
	spec["amount"] = PUFF_AMOUNT
	spec["lifetime"] = PUFF_LIFETIME
	spec["damping"] = Vector2(DAMPING, DAMPING)
	spec["spread"] = LIFT_SPREAD
	spec["size"] = PUFF_SIZE
	spec["grow"] = PUFF_GROW
	spec["gravity"] = 0.0
	spec["color"] = Color(PlumeAssets.VAPOUR_BIRTH.r, PlumeAssets.VAPOUR_BIRTH.g,
			PlumeAssets.VAPOUR_BIRTH.b, 0.7)
	SmokeFX.setup(p, spec)
	PlumeAssets.uncap_growth(p, PUFF_GROW)
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	_tune_puff(p)
	return p


## The ring lies flat on the road and bursts outwards past the wheels.
func _tune_puff(p: GPUParticles3D) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = RING_RADIUS
	pm.emission_ring_inner_radius = RING_RADIUS * RING_INNER_FACTOR
	pm.emission_ring_height = RING_HEIGHT
	pm.direction = Vector3.UP
	pm.spread = LIFT_SPREAD
	pm.initial_velocity_min = LIFT_SPEED * LIFT_SPEED_FACTOR
	pm.initial_velocity_max = LIFT_SPEED
	# A radial velocity, not a radial acceleration: the ring bursts out and stops.
	pm.radial_velocity_min = RADIAL_MIN
	pm.radial_velocity_max = RADIAL_MAX
	pm.radial_accel_min = 0.0
	pm.radial_accel_max = 0.0
	pm.inherit_velocity_ratio = 0.0
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.0
	pm.collision_friction = 0.3
	pm.collision_use_scale = true


## Fires the puff at a world position, with the car's yaw so the ring follows the car.
func trigger(ground_point: Vector3, car_basis: Basis) -> void:
	var ring_basis: Basis = car_basis.orthonormalized() * Basis.from_scale(RING_SCALE)
	_puff.global_transform = Transform3D(ring_basis, ground_point + Vector3(0.0, RING_HEIGHT_ABOVE, 0.0))
	_puff.emitting = false
	_puff.emitting = true
	# The ground ring follows the car's yaw, so it lies along the car and not across it.
	var yaw: float = atan2(-car_basis.z.x, -car_basis.z.z)
	_decal.global_transform = Transform3D(Basis(Vector3.UP, yaw),
			ground_point + Vector3(0.0, DECAL_HEIGHT, 0.0))
	_decal.visible = true
	_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	var a: float = clampf(1.0 - _age / DECAL_LIFETIME, 0.0, 1.0)
	_decal.modulate = Color(PlumeAssets.VAPOUR_BIRTH.r, PlumeAssets.VAPOUR_BIRTH.g,
			PlumeAssets.VAPOUR_BIRTH.b, a * DECAL_ALPHA)
	if _age > DECAL_LIFETIME:
		_decal.visible = false
	if _age > PUFF_LIFETIME + PUFF_LIFETIME_MARGIN:
		queue_free()

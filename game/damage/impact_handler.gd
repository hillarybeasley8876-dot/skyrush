extends RefCounted
## The damage of one contact: the classification, the HP, the dent, the scrape and the parts
## that come off. The director owns the event bus, this file owns what a hit costs.

const Rules := preload("res://damage/damage_rules.gd")
const Parts := preload("res://damage/part_catalog.gd")
const Contact := preload("res://damage/contact.gd")
const CarDamage := preload("res://damage/car_damage.gd")
const CarStateManager := preload("res://damage/car_state_manager.gd")
const PartManager := preload("res://damage/part_manager.gd")
const SparkBurst := preload("res://damage/spark_burst.gd")

## The body box of a car without a usable collision shape.
const DEFAULT_HALF := Vector3(0.98, 0.40, 2.19)
const DEFAULT_CENTRE := Vector3(0.0, 0.62, 0.0)
## A contact that is further than this from the car is not on the car (the panel of the
## middle of the car is used instead).
const MAX_CONTACT_DISTANCE := 4.0
## How much of the body box a contact may be outside of and still be on the panel.
const PANEL_MARGIN_XZ := 1.2
const PANEL_MARGIN_Y := 1.5

var registry: CarStateManager = null
var parts: PartManager = null
var sparks: SparkBurst = null


## The damage of a hit on one car.
## `own_velocity` is the speed of the car before the hit (the respawn speed of §7.8).
func hit(car: VehicleBase, other: Node3D, n_car: Vector3, point: Vector3, v_n: float,
		impact: float, v_rel: Vector3, elapsed: float, own_velocity: Vector3 = Vector3.ZERO,
		severity: float = -1.0) -> void:
	if car == null or car.is_wrecked:
		return
	var state := registry.state_of(car)
	# The speed of the car itself before the hit: the relative speed of a head-on is twice
	# that, and the respawn must not use it.
	state.pre_crash_speed = own_velocity.length()
	state.pre_crash_velocity = own_velocity
	state.pre_crash_heading = heading_of(car)
	state.wreck_impact = impact
	var other_car := other as VehicleBase
	var k := Rules.k_mass(car.mass, other_car.mass if other_car != null else 0.0,
			other_car != null)
	# The front-ram bonus: the car that hits with its front takes half the damage. In a
	# head-on both cars drive into each other, so nobody rams and nobody gets the bonus.
	var factor := ram_factor(car, n_car, other_car)
	# The severity of the hit: the speed it took from this car. It is the measure of the
	# hit for the HP and for the wreck rule. It is the momentum the hit transferred divided
	# by the mass of the car and not the closing speed of the two cars: a car that meets a
	# slow car head-on does not lose the speed of the other car.
	var force: float = severity if severity >= 0.0 else v_n
	var hp := Rules.damage_hp(force, k) * factor
	var contact := contact_of(car, state, n_car, point, v_n, impact, v_rel.normalized())
	# The point of the hit, so the wheel that comes off is the nearest one.
	state.wreck_point = contact.world_point
	# The side of the hit, so the bumper hangs on the corner away from it.
	state.last_hit_side = signf(contact.local_point.x)
	# A scrape against something static grinds the paint off: 2 HP per second (dossier 7.2).
	if impact < Rules.SCRAPE_LIMIT and other is StaticBody3D:
		hp += Rules.GRIND_HP_PER_S * clampf(elapsed, 0.0, Rules.IMPACT_WINDOW)
	state.add_zone_damage(parts.zone_key(contact.zone), hp)
	if hp > 0.0:
		car.apply_damage(hp, contact.world_point, other)
	# The dents and the scrape of the paint.
	if state.painter != null:
		state.painter.add_dent(contact.world_point, contact.world_normal, v_n, contact.slide,
				impact)
	spark_hit(contact, v_rel)
	parts.check(car, state, contact, v_n, impact, own_velocity)
	# A head-on hit that took 30 m/s of speed from the car wrecks it (dossier 7.2).
	if factor >= 1.0 and impact >= Rules.HIT_LIMIT and force >= Rules.WRECK_HEAD_ON:
		car.wreck(other)


## The vertical takedown: the car below is wrecked, the car above gets the credit.
func vertical_takedown(vehicle: VehicleBase, other_car: VehicleBase, normal: Vector3,
		point: Vector3, v_n: float) -> void:
	var below := other_car if other_car.global_position.y < vehicle.global_position.y else vehicle
	var above := vehicle if below == other_car else other_car
	var contact := contact_of(below, registry.state_of(below), -normal, point, v_n, 1.0)
	below.apply_damage(Rules.VERTICAL_HP, contact.world_point, above)
	if above == Game.player:
		registry.state_of(below).vertical_credit = true


## The contact of a hit, in the world and in the local space of the car that was hit.
func contact_of(car: VehicleBase, state: CarDamage, n_world: Vector3, point: Vector3,
		v_n: float, impact: float, slide: Vector3 = Vector3.ZERO) -> Contact:
	var contact := Contact.new()
	var basis := car.global_transform.basis
	var local_normal := basis.inverse() * n_world
	if local_normal.length() < 0.001:
		local_normal = Vector3.FORWARD
	local_normal = local_normal.normalized()
	body_box(car, state)
	var centre: Vector3 = state.body_centre
	var half: Vector3 = state.body_half
	# The point of the contact: the one the engine reported, or the middle of the panel.
	var world_point := point
	var local_point := car.global_transform.affine_inverse() * world_point
	if local_point.length() > MAX_CONTACT_DISTANCE:
		local_point = centre
		world_point = car.global_transform * local_point
	# The zone of the hit: the direction of the other body (the normal points out of it).
	var zone := Parts.zone_from_direction(-local_normal)
	var on_panel := local_point - centre
	if on_panel.length() < 0.01 or absf(local_point.x) > half.x * PANEL_MARGIN_XZ \
			or absf(local_point.z) > half.z * PANEL_MARGIN_XZ \
			or absf(local_point.y - centre.y) > half.y * PANEL_MARGIN_Y:
		# The hit did not tell where it landed: the middle of the panel that was hit.
		var dir := -local_normal
		var reach := INF
		for axis in 3:
			var d := absf(dir[axis])
			if d > 0.0001:
				reach = minf(reach, half[axis] / d)
		if reach == INF:
			reach = 0.0
		on_panel = dir * reach
		local_point = centre + on_panel
		world_point = car.global_transform * local_point
	contact.world_point = world_point
	contact.local_point = local_point
	contact.local_normal = local_normal
	contact.world_normal = n_world.normalized()
	contact.zone = zone
	contact.closing = v_n
	contact.impact = impact
	contact.slide = slide
	return contact


## The horizontal heading of a car.
func heading_of(car: VehicleBase) -> Vector3:
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return Vector3.FORWARD
	return forward.normalized()


## The damage factor of the car that hits: 0.5 when it rams the other car with its front.
## A head-on (both cars drive into each other) is not a ram, so both take the full damage.
func ram_factor(car: VehicleBase, n_car: Vector3, other_car: VehicleBase) -> float:
	if other_car != null and other_car.get_forward().dot(n_car) > Rules.RAM_DOT:
		return 1.0
	return Rules.ram_factor(car.get_forward(), n_car)


## The sparks of a hard hit: they fly away from the contact, along the surface.
func spark_hit(contact: Contact, v_rel: Vector3) -> void:
	if sparks == null:
		return
	var speed := v_rel.length()
	if speed < SparkBurst.MIN_SPEED:
		return
	# The sparks leave along the surface of the panel, not into it. A head-on hit has no
	# surface direction, so the spray goes up and back, the way a real crash throws it.
	var direction := v_rel.normalized()
	var away := direction - contact.world_normal * direction.dot(contact.world_normal)
	if away.length() < 0.2:
		away = -direction * 0.8 + Vector3.UP * 0.35
	sparks.burst(contact.world_point, away, speed)


## The body box of a car in its local space (the collision shape of the car).
##
## The box of a car does not change, so it is read once per car and kept in its state: a hit
## must not walk the children of the car again.
func body_box(car: VehicleBase, state: CarDamage) -> void:
	if state != null and state.body_known:
		return
	var centre: Vector3 = DEFAULT_CENTRE
	var half: Vector3 = DEFAULT_HALF
	for child in car.get_children():
		var node := child as CollisionShape3D
		if node == null:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		centre = node.position
		half = box.size * 0.5
		break
	if state != null:
		state.body_centre = centre
		state.body_half = half
		state.body_known = true

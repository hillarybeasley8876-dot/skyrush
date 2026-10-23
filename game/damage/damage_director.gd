extends Node3D
## The damage director (brief "damage"): it turns the physics contacts into damage, dents,
## flying parts, wrecks and takedowns (ref/gameplay/DOSSIER.md §7 and §3.5).
##
## The numbers live in damage_rules.gd, the parts in part_catalog.gd. The unit never touches
## the collision response: the vehicle unit owns the physics, this unit only decides what a
## hit costs and what it looks like.

const Rules := preload("res://damage/damage_rules.gd")
const Parts := preload("res://damage/part_catalog.gd")
const CarDamage := preload("res://damage/car_damage.gd")
const CarRecycler := preload("res://damage/car_recycler.gd")
const Contact := preload("res://damage/contact.gd")
const ContactPairs := preload("res://damage/contact_pairs.gd")
const CarStateManager := preload("res://damage/car_state_manager.gd")
const DebrisPool := preload("res://damage/debris_pool.gd")
const DamageFx := preload("res://damage/damage_fx.gd")
const WreckFlow := preload("res://damage/wreck_flow.gd")
const PartManager := preload("res://damage/part_manager.gd")
const TakedownTracker := preload("res://damage/takedown_tracker.gd")
const SparkBurst := preload("res://damage/spark_burst.gd")
const ImpactHandler := preload("res://damage/impact_handler.gd")
const DentMaterials := preload("res://damage/dent_materials.gd")
const FxAssets := preload("res://damage/fx_assets.gd")
const MaskPool := preload("res://damage/mask_pool.gd")
const TierEmitters := preload("res://damage/tier_emitters.gd")

## How often the list of the cars is refreshed.
const TRACK_REFRESH := 0.5


var _registry: CarStateManager = null
## The restore of the cars that come out of their pool.
var _recycler: CarRecycler = null
var _tracked: Array[VehicleBase] = []
var _prev_velocity: Dictionary = {}   # instance id -> the velocity before the last step
var _pairs: ContactPairs = ContactPairs.new()   # the contacts of the pairs of cars
var _debris: DebrisPool = null
var _flow: WreckFlow = null
var _parts: PartManager = null
var _takedowns: TakedownTracker = null
var _sparks: SparkBurst = null
var _impact: ImpactHandler = null
var _refresh_timer: float = 0.0
## The game clock (the scaled physics time), so the windows of the unit are game seconds
## and not wall-clock seconds.
var _clock: float = 0.0
## The cost of the last tick of the unit in microseconds (dossier §7.7: <= 0.3 ms).
var cpu_usec: float = 0.0
## The cost of the last hit in microseconds (for the budget test).
var hit_usec: int = 0
## The cost of building the state of a car when it joins the world (the budget of §7.7).
var join_usec: int = 0
## The worst of the builds of the cars that joined (the budget of §7.7 is per car).
var join_worst_usec: int = 0
## The sum and the number of the builds of the cars that joined.
var join_total_usec: int = 0
var join_count: int = 0
## The cost of every build of a car that joined (the budget test takes the best of them).
var join_costs: Array[int] = []
## The cost of the respawn of the player (the budget of §7.7).
var respawn_usec: int = 0


func _ready() -> void:
	_registry = CarStateManager.new()
	_registry.on_forget = _on_car_gone
	_debris = DebrisPool.new()
	_debris.name = "DebrisPool"
	add_child(_debris)
	_flow = WreckFlow.new()
	_flow.name = "WreckFlow"
	add_child(_flow)
	_recycler = CarRecycler.new()
	_recycler.registry = _registry
	_recycler.flow = _flow
	_parts = PartManager.new()
	_parts.debris = _debris
	_takedowns = TakedownTracker.new()
	_sparks = SparkBurst.new()
	_sparks.name = "Sparks"
	add_child(_sparks)
	_impact = ImpactHandler.new()
	_impact.registry = _registry
	_impact.parts = _parts
	_impact.sparks = _sparks
	_prewarm()
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.vehicle_wrecked.connect(_on_vehicle_wrecked)
	Events.vehicle_damaged.connect(_on_vehicle_damaged)
	Events.player_respawned.connect(_on_player_respawned)
	Events.vehicle_recycled.connect(_on_vehicle_recycled)


## The static textures and the shader uniforms are built here, not on the first crash: the
## smoke texture alone used to cost 13.9 ms on the frame of the first hit.
func _prewarm() -> void:
	FxAssets.smoke_texture()
	FxAssets.spark_texture()
	FxAssets.fireball_texture()
	# The uniform list of a shader is parsed on every call (0.7 ms), so it is read once here.
	DentMaterials.warm_up()
	# The masks are a megabyte each: the pool is filled here, not on the first crash.
	MaskPool.warm_up()
	# The particle shader of the smoke is compiled when the first puff is drawn: 15 ms on the
	# frame of the first crash. It is warmed up here: the warmers keep the shared materials
	# alive (the cars use the same ones), and they stop a moment later.
	for warm in TierEmitters.warm_up(self):
		warm.position = Vector3(0.0, -40.0, 0.0)
		var timer := get_tree().create_timer(2.0, true, false, true)
		timer.timeout.connect(warm.set_emitting.bind(false))
	# The damage materials are built on the meshes of a dummy car, so the rendering server
	# has them before the first crash.
	for warm in DentMaterials.warm_up_meshes():
		warm.position = Vector3(0.0, -40.0, 0.0)
		add_child(warm)
		var timer := get_tree().create_timer(2.0, true, false, true)
		timer.timeout.connect(warm.queue_free)


func _process(_delta: float) -> void:
	# The pool of the masks is filled while the game is idle: a mask costs 1.9 ms to build
	# and that cost must not land on a hit.
	MaskPool.top_up()


## The unit leaves the world: the shared particle materials go back with it.
func _exit_tree() -> void:
	TierEmitters.release_cache()


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = TRACK_REFRESH
		_refresh_tracked()
	_sample_velocities()
	_build_one_state()
	_registry.flush_painters(delta)
	cpu_usec = Time.get_ticks_usec() - t0


## The number of cars the unit keeps the state of (for the test).
func tracked_count() -> int:
	return _registry.count()


## The debris that is in the world (for the test).
func debris_count() -> int:
	return _debris.active_count() if _debris != null else 0


## The state of one car (for the test).
func state_of(car: VehicleBase) -> CarDamage:
	return _registry.state_of(car)


## The streak of takedowns (for the test).
func streak() -> int:
	return _takedowns.streak


## The number of velocities the unit remembers (for the leak test).
func velocity_entries() -> int:
	return _prev_velocity.size()


## The number of contacts the unit remembers (for the leak test).
func pair_entries() -> int:
	return _pairs.count()


## The cost of every build of a car that joined, and the list back to empty (the budget
## test takes the best of the rounds).
func take_join_costs() -> Array[int]:
	var costs := join_costs
	join_costs = []
	return costs


## The cost of the builds of the cars that joined, and the counters back to zero (the
## budget test measures the cars that join the world).
func take_join_stats() -> Dictionary:
	var stats := {
		"worst": join_worst_usec,
		"total": join_total_usec,
		"count": join_count,
	}
	join_worst_usec = 0
	join_total_usec = 0
	join_count = 0
	return stats


# --- the tracking --------------------------------------------------------------------------------
func _refresh_tracked() -> void:
	_tracked.clear()
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var car := node as VehicleBase
		if car != null:
			_track(car)
	_pairs.prune(_now())


## A car left the world: its velocity and its contacts are forgotten.
func _on_car_gone(car: VehicleBase) -> void:
	var id := car.get_instance_id()
	_prev_velocity.erase(id)
	_pairs.forget(id)


func _track(car: VehicleBase) -> void:
	if not _tracked.has(car):
		_tracked.append(car)


## The state of a car is built when it joins the world, one car per frame, so the first
## crash of a car never costs the build (dossier §7.7).
func _build_one_state() -> void:
	for car in _tracked:
		if car == null or not is_instance_valid(car):
			continue
		if _registry.states.has(car.get_instance_id()):
			continue
		var t0 := Time.get_ticks_usec()
		_registry.state_of(car)
		join_usec = Time.get_ticks_usec() - t0
		join_worst_usec = maxi(join_worst_usec, join_usec)
		join_total_usec += join_usec
		join_count += 1
		join_costs.append(join_usec)
		return


## The velocity of every car before the current physics step. The engine resolves a contact
## before the script sees it, so the current velocity is the post-impact one: the damage is
## measured on the velocities of the step before (dossier §7.2).
func _sample_velocities() -> void:
	for car in _tracked:
		if car == null or not is_instance_valid(car):
			continue
		_prev_velocity[car.get_instance_id()] = car.linear_velocity


func _pre_velocity(car: VehicleBase) -> Vector3:
	return _prev_velocity.get(car.get_instance_id(), car.linear_velocity) as Vector3


func _pre_velocity_of(other: Node3D) -> Vector3:
	var body := other as RigidBody3D
	if body == null:
		return Vector3.ZERO
	if body is VehicleBase:
		var known: Variant = _prev_velocity.get(body.get_instance_id())
		if known != null:
			return known as Vector3
	return body.linear_velocity


# --- the collision -------------------------------------------------------------------------------
func _on_vehicle_collided(vehicle: VehicleBase, other: Node3D, impulse: float,
		point: Vector3, normal: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_resolve_collision(vehicle, other, impulse, point, normal)
	hit_usec = Time.get_ticks_usec() - t0


## The collision of two bodies: the classification, the damage and the takedown credit.
##
## The severity of the hit is the momentum the hit took from the car (the impulse of the
## vehicle unit): the speed the car lost in the crash. The closing speed of the two cars
## would count the speed of the other car as if it were the loss of this one: a player that
## meets a slow patrol car head-on at 160 km/h would pay for a 190 km/h crash, although it
## only lost the part of the speed that the patrol did not take.
func _resolve_collision(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3,
		normal: Vector3) -> void:
	if vehicle == null or other == null or normal.length() < 0.01:
		return
	var now := _now()
	# The two cars of a contact report it in the same physics step, so the physics frame
	# is the exact key of a duplicate report.
	var elapsed := _pairs.begin(vehicle, other, Engine.get_physics_frames(), now)
	if elapsed < 0.0:
		return
	_track(vehicle)
	var other_car := other as VehicleBase
	if other_car != null:
		_track(other_car)
	var own_velocity := _pre_velocity(vehicle)
	var v_rel := own_velocity - _pre_velocity_of(other)
	var closing := Rules.closing_speed(v_rel, normal)
	if closing <= 0.0:
		return
	var impact := Rules.impact_ratio(v_rel, normal)
	var self_state := _registry.state_of(vehicle)
	if other_car != null:
		var other_state := _registry.state_of(other_car)
		# A contact counts from 3 m/s of RELATIVE speed (dossier 3.5), not from the
		# closing speed along the normal.
		if vehicle == Game.player and v_rel.length() >= Rules.TAKEDOWN_MIN_SPEED:
			other_state.last_player_contact = now
		elif other_car == Game.player and v_rel.length() >= Rules.TAKEDOWN_MIN_SPEED:
			self_state.last_player_contact = now
	# The vertical takedown: one car lands on the roof of the other. The rule is symmetric:
	# the car below is wrecked whatever its HP is (dossier 7.3: 999 HP).
	if other_car != null and Rules.is_vertical(normal, v_rel):
		_impact.vertical_takedown(vehicle, other_car, normal, point, closing)
		return
	# The traffic glance: the player loses 1 HP and the panel is not dented (dossier 7.2).
	if impact < Rules.GRAZE_IMPACT and other_car != null and vehicle == Game.player \
			and other_car.team == VehicleBase.Team.TRAFFIC:
		vehicle.apply_damage(Rules.GRAZE_HP, point, other)
		return
	# The severity of the hit: the speed it took from each of the two cars. The momentum of
	# the hit is measured by the vehicle unit and sent with the event: the two cars share it
	# (the momentum the one loses is the momentum the other takes), so the same number
	# measures the hit for both of them.
	var severity := _severity(vehicle, impulse, closing)
	_impact.hit(vehicle, other, normal, point, closing, impact, v_rel, elapsed, own_velocity,
			severity)
	if other_car != null:
		var other_severity := _severity(other_car, impulse, closing)
		_impact.hit(other_car, vehicle, -normal, point, closing, impact, -v_rel, elapsed,
				_pre_velocity(other_car), other_severity)


## The severity of a hit for one car: how hard the hit was for it (m/s).
##
## It is the smaller of the two measures of the hit:
##   * the closing speed of the two cars (the dossier §7.2): the cars cannot approach each
##     other faster than that,
##   * the momentum the hit transferred, divided by the mass of the car: the speed the car
##     lost in the crash. The vehicle unit measures that momentum and sends it with the
##     event (the third law: the momentum the one car loses is the momentum the other
##     takes, so the same number measures the hit for both of them).
##
## The closing speed alone is not enough: it counts the speed of the other car as if it
## were the loss of this one. A player that meets a slow patrol car head-on at 160 km/h
## would pay for a 190 km/h crash, although it only lost the part of the speed that the
## patrol did not take.
func _severity(car: VehicleBase, impulse: float, closing: float) -> float:
	if car == null or impulse <= 0.0:
		return closing
	return minf(closing, impulse / maxf(car.mass, 1.0))


# --- the tiers and the wreck ----------------------------------------------------------------------
## The damage of a car changed: its tier (dossier §7.4) may have changed with it.
func _on_vehicle_damaged(vehicle: VehicleBase, _amount: float, _source: Node3D) -> void:
	_update_tier(vehicle)


## The respawn: the car is whole again (the parts are back, the state is clean).
func _on_player_respawned() -> void:
	if Game.player != null:
		var t0 := Time.get_ticks_usec()
		_registry.reset_state(Game.player)
		_update_tier(Game.player)
		respawn_usec = Time.get_ticks_usec() - t0


## A pooled car (traffic, police) comes back into play: it is a whole new car.
##
## The wreck of its old life is void (the sink, the fade and the hide), the car has its
## health back and its damage state is fresh. A car that was never hurt is not touched:
## the traffic spawns cars all the time and the handler must cost nothing.
func _on_vehicle_recycled(vehicle: VehicleBase) -> void:
	_recycler.on_recycled(vehicle)


## Sets the tier of a car and shows it.
func _update_tier(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var state := _registry.state_of(vehicle)
	var tier := CarDamage.tier_of(vehicle.health, state.max_health)
	if tier == state.tier:
		return
	state.tier = tier
	if tier <= CarDamage.Tier.CLEAN:
		if state.fx != null:
			state.fx.apply_tier(tier)
		return
	# The rig of a hurt car (the smoke, the lamp, the arcs) is built on the frame after the
	# hit: a hit must not pay for it (dossier §7.7).
	_build_fx.call_deferred(vehicle, tier, state.last_hit_side)


## Builds the rig of a hurt car and shows the tier.
func _build_fx(vehicle: VehicleBase, tier: int, side: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var state := _registry.state_of(vehicle)
	var fx := state.ensure_fx()
	if fx == null:
		return
	fx.apply_tier(tier)
	if tier >= CarDamage.Tier.HEAVY:
		fx.hang_bumper(side)


## A car is wrecked: the tiers, the wheels, the credit of the player and the wreck flow.
func _on_vehicle_wrecked(vehicle: VehicleBase, source: Node3D) -> void:
	if vehicle == null:
		return
	var state := _registry.state_of(vehicle)
	state.wrecked = true
	var fx := state.ensure_fx()
	if fx != null:
		fx.apply_tier(CarDamage.Tier.WRECKED)
		fx.play_wreck()
	# A violent wreck takes one wheel off (dossier 7.6: the impact must be 0.7 or more).
	_parts.detach_wheel(vehicle, state)
	_takedowns.credit(vehicle, state, _now())
	if vehicle == Game.player:
		_flow.player_wreck(vehicle, state.pre_crash_speed, state.pre_crash_heading)
	else:
		_flow.ai_wreck(vehicle)


## The game clock in seconds.
func _now() -> float:
	return _clock

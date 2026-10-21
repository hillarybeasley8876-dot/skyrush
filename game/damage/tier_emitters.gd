extends RefCounted
## The emitters of the damage tiers (dossier §7.4): the smoke of a hurt car and the sparks
## under it. They are built when the car is hurt, not when it joins the world.
##
## The smoke starts at the engine bay (the hood of the car) and grows; the puffs are
## billboards that keep their scale, so the curve of the size is not thrown away.

const FxAssets := preload("res://damage/fx_assets.gd")

## The smoke of the tiers.
const SMOKE_LIGHT := Color(0.541, 0.561, 0.588, 0.5)   ## #8A8F96
const SMOKE_HEAVY := Color(0.169, 0.176, 0.192, 0.7)   ## #2B2D31
const SMOKE_EV := Color(0.86, 0.91, 1.0, 0.6)           ## the cold smoke of an electric car
## The smoke reads at night with a little emission of its own.
const SMOKE_EMISSION := 0.18
const SPARK_COLOR := Color(1.0, 0.78, 0.35)

const LIGHT_PARTICLES := 24
const HEAVY_PARTICLES := 40
const LIGHT_LIFETIME := 2.2
const HEAVY_LIFETIME := 2.8
const SPARK_INTERVAL := 0.5
## The engine bay of the car: the top of the hood, a little behind the front.
const BAY_HEIGHT := 0.70
const BAY_DEPTH := 0.15

var vehicle: VehicleBase = null
## True for the electric cars (the player Roadster): white smoke.
var electric: bool = false

var _smoke: GPUParticles3D = null
var _sparks: GPUParticles3D = null
var _spark_timer: float = 0.0

## The process materials are shared by every car: the shader of the particles is compiled
## once for the whole game and not once per car (a compile costs 15 ms).
static var _smoke_processes: Dictionary = {}
static var _spark_process: ParticleProcessMaterial = null


## The colour of the smoke of a tier: the light tier smokes grey, the heavy tier smokes
## dark, and an electric car smokes white.
static func smoke_colour(tier: int, is_electric: bool) -> Color:
	if tier == 1:
		return SMOKE_LIGHT
	if is_electric:
		return SMOKE_EV
	return SMOKE_HEAVY


## The process material of the smoke of a tier (shared by every car of that tier).
static func smoke_process(tier: int, is_electric: bool) -> ParticleProcessMaterial:
	var colour := smoke_colour(tier, is_electric)
	var key := colour.to_html(false)
	if _smoke_processes.has(key):
		return _smoke_processes[key] as ParticleProcessMaterial
	var process := _make_process(colour)
	_smoke_processes[key] = process
	return process


## The process material of the sparks (shared by every car).
static func spark_process() -> ParticleProcessMaterial:
	if _spark_process == null:
		_spark_process = _make_spark_process()
	return _spark_process


## The shared process materials go back when the unit leaves the world: the shaders of the
## particles are freed with them (the engine complains about the ones that stay).
static func release_cache() -> void:
	_smoke_processes.clear()
	_spark_process = null


## Builds the rig of the car.
func setup(car: VehicleBase, is_electric: bool) -> void:
	vehicle = car
	electric = is_electric


## The tier of the car: 1 light, 2 heavy. The smoke and the sparks follow it.
func apply_tier(tier: int) -> void:
	if tier <= 0:
		stop()
		return
	_ensure_smoke(tier)
	if tier >= 2:
		_ensure_sparks()
		_sparks.emitting = true
	else:
		_stop_sparks()


## True while the tier smoke is running (for the test).
func smoke_running() -> bool:
	return _smoke != null and _smoke.emitting


## The car is whole again: the smoke and the sparks stop.
func reset() -> void:
	stop()


func stop() -> void:
	if _smoke != null:
		_smoke.emitting = false
		_smoke.visible = false
	_stop_sparks()


## The sparks under the car every half second while it is badly hurt.
func tick(delta: float) -> void:
	if _sparks == null or not _sparks.emitting:
		return
	_spark_timer += delta
	if _spark_timer < SPARK_INTERVAL:
		return
	_spark_timer = 0.0
	_sparks.restart()


## The particle shader of the smoke is compiled when the first puff is drawn: 15 ms on the
## frame of the first crash. The director warms it up when it starts: one emitter for
## every colour of the smoke and one for the sparks.
static func warm_up(parent: Node) -> Array[Node]:
	var out: Array[Node] = []
	for colour: Color in [SMOKE_LIGHT, SMOKE_HEAVY, SMOKE_EV]:
		# The material goes into the cache: the cars of the game use THE SAME one, so the
		# shader of the particles is compiled once and not once per material.
		var process := _make_process(colour)
		_smoke_processes[colour.to_html(false)] = process
		var smoke := GPUParticles3D.new()
		smoke.amount = 1
		smoke.lifetime = 0.1
		smoke.emitting = true
		smoke.local_coords = false
		smoke.position = Vector3(0.0, 0.0, 0.0)
		smoke.process_material = process
		smoke.draw_pass_1 = FxAssets.smoke_quad()
		parent.add_child(smoke)
		out.append(smoke)
	var spark_process := _make_spark_process()
	_spark_process = spark_process
	var sparks := GPUParticles3D.new()
	sparks.amount = 1
	sparks.lifetime = 0.1
	sparks.emitting = true
	sparks.local_coords = false
	sparks.one_shot = true
	sparks.position = Vector3(0.0, 0.0, 0.0)
	sparks.process_material = spark_process
	sparks.draw_pass_1 = FxAssets.spark_quad()
	parent.add_child(sparks)
	out.append(sparks)
	return out


# --- the emitters -------------------------------------------------------------------------------
func _ensure_smoke(tier: int) -> void:
	if _smoke == null:
		_smoke = _make_smoke(tier)
		vehicle.add_child(_smoke)
	var amount := HEAVY_PARTICLES
	var lifetime := HEAVY_LIFETIME
	if tier == 1:
		amount = LIGHT_PARTICLES
		lifetime = LIGHT_LIFETIME
	_smoke.amount = amount
	_smoke.lifetime = lifetime
	_smoke.position = engine_bay()
	_smoke.emitting = true
	_smoke.visible = true


func _stop_sparks() -> void:
	if _sparks != null:
		_sparks.emitting = false


func _ensure_sparks() -> void:
	if _sparks != null:
		return
	_sparks = _make_sparks()
	vehicle.add_child(_sparks)


## The engine bay of the car: the top of the hood, a little behind the front axle.
func engine_bay() -> Vector3:
	for child in vehicle.get_children():
		var node := child as CollisionShape3D
		if node == null:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		var minimum := node.position - box.size * 0.5
		return Vector3(0.0, minimum.y + box.size.y * BAY_HEIGHT,
				minimum.z + box.size.z * BAY_DEPTH)
	return Vector3(0.0, 0.72, -1.35)


func _make_smoke(tier: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = LIGHT_PARTICLES
	particles.lifetime = LIGHT_LIFETIME
	particles.local_coords = false
	particles.emitting = false
	particles.visible = false
	particles.process_material = smoke_process(tier, electric)
	particles.draw_pass_1 = FxAssets.smoke_quad()
	return particles


## The process of the smoke: it is the same for every car, so the particle shader is compiled
## once.
static func _make_process(colour: Color) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.color = colour
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.damping_min = 0.4
	process.damping_max = 0.9
	process.scale_min = 0.5
	process.scale_max = 1.2
	process.turbulence_enabled = true
	process.turbulence_influence = Vector2(1.2, 1.2)
	process.turbulence_noise_strength = 1.0
	process.turbulence_noise_scale = 2.5
	# The smoke turns slowly and drifts with the car.
	process.angle_min = -PI
	process.angle_max = PI
	process.angular_velocity_min = -0.52
	process.angular_velocity_max = 0.52
	process.inherit_velocity_ratio = 0.3
	process.color_ramp = _smoke_ramp()
	process.scale_curve = _smoke_scale_curve()
	return process


## The alpha of the smoke over its life: in, hold, out.
static func _smoke_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.15, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.60, Color(1.0, 1.0, 1.0, 0.30))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## The smoke grows over its life.
static func _smoke_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 2.2))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _make_sparks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 12
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = false
	particles.local_coords = false
	particles.position = Vector3(0.0, 0.25, 0.0)
	particles.process_material = spark_process()
	particles.draw_pass_1 = FxAssets.spark_quad()
	return particles


## The process of the sparks: the same for every car, so the particle shader is compiled once.
static func _make_spark_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.DOWN
	process.spread = 60.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.0
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.scale_min = 0.06
	process.scale_max = 0.14
	process.color = SPARK_COLOR
	return process

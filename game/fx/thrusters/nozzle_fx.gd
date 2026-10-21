extends Node3D
## One nozzle's plume: the jet core cone, the vapour column, the vapour trail and the lit
## throat.
##
## The node is parented to the nozzle marker, so the marker's -Z (the jet direction, CONTRACTS §2)
## is the direction everything points. Intensity is smoothed here: 40 ms attack, 120 ms release.
##
## The vapour sprites come from the lead's shared SmokeFX (core/fx/smoke.gd): one look for
## every unit, soft billows, one random frame per particle.

const SmokeFX := preload("res://core/fx/smoke.gd")
const PlumeAssets := preload("res://fx/thrusters/lib/plume_assets.gd")
const JetMesh := preload("res://fx/thrusters/lib/jet_mesh.gd")
const JetColumnMesh := preload("res://fx/thrusters/lib/jet_column.gd")
const CORE_SHADER := preload("res://fx/thrusters/shaders/jet_core.gdshader")
const COLUMN_SHADER := preload("res://fx/thrusters/shaders/jet_column.gdshader")

const ATTACK := 0.04
const RELEASE := 0.12
## Particles alive per nozzle, by group. The column mesh carries the body of the plume, so the
## particles only break it up further out (review MUST-FIX 5). The sprites are 0.4-0.6 m
## across, so far fewer of them cover the same plume.
const VAPOUR_AMOUNT := {"rear": 130, "lift": 130, "yaw": 40}
const VAPOUR_LIFETIME := 0.9
## Emission-time jitter, so the particles do not arrive in per-frame batches.
const VAPOUR_RANDOMNESS := 0.3
## Below this the plume counts as off.
const LIVE_EPSILON := 0.002
## Emission energy of the lit throat at full throttle. The glow of the four throats blooms
## over the first shock diamond, so it stays low (review MUST-FIX 4).
const THROAT_ENERGY_MAX := 1.2
## The core shrinks with the throttle, but never disappears completely.
const CORE_MIN_SCALE := 0.55
## The core colour (dossier §6.1): #EAF4FF, never orange.
const CORE_COLOUR := Color(0.918, 0.957, 1.0)
const CORE_ENERGY := 1.5
## The four shock diamonds, in metres from the throat, and their relative brightness.
const RING_POS := Vector4(0.06, 0.15, 0.24, 0.33)
const RING_BRIGHT := Vector4(1.0, 0.7, 0.45, 0.25)
## The width of a diamond, in metres.
const RING_WIDTH := 0.025
## The throat disc, in metres.
const THROAT_RADIUS := 0.032
const THROAT_HEIGHT := 0.012
## The throat disc sits this far out of the nozzle.
const THROAT_OFFSET := 0.006
const THROAT_SEGMENTS := 12
## The vapour column: length and tip radius in metres, per group (review MUST-FIX 3).
## The lift column is 7 m long, so it still reaches the road from a 6 m hover with the
## throttle at half: the column is scaled by lerpf(0.8, 1.0, value).
const COLUMN_LENGTH := {"rear": 5.0, "lift": 7.0, "yaw": 1.5}
## The column's tip radius. The review wants the plume 0.4-0.8 m wide three metres below the
## car: a 0.32 m tip radius gives 0.6 m there. A wider tube is a bigger alpha blended surface,
## and the column is the most expensive layer of the plume.
const COLUMN_RADIUS := {"rear": 0.32, "lift": 0.32, "yaw": 0.12}
const COLUMN_ALPHA := 1.0
## A little self-illumination, so the column still reads in an unlit alley.
const COLUMN_EMISSION_GAIN := 0.3
## The column starts this far along the jet, so the bright core cone and its shock diamonds
## are not drowned by the vapour tube.
const COLUMN_START := 0.55
## The column's length only shrinks a little with the throttle; the rest goes into its alpha.
const COLUMN_LENGTH_MIN := 0.8
## The vapour's sprites: 0.4-0.6 m (dossier §6.3: 0.12 -> 1.4 m, but a 1.4 m sprite covers a
## fifth of the screen at the chase camera's distance: 120 of them per nozzle cost 30 ms per
## view, and the perf budget is 1.2 ms. The review's MUST-FIX 5 numbers this trade-off).
const VAPOUR_SIZE := Vector2(0.4, 0.6)
const VAPOUR_GROW := 4.0
## The gas leaves a little slower than the jet speed.
const VAPOUR_SPEED_FACTOR := 0.95
## Fallbacks for a nozzle table entry that is missing a field.
const DEFAULT_LENGTH := 0.9
const DEFAULT_RADIUS := 0.9
const DEFAULT_SPEED := 30.0
const DEFAULT_DAMPING := 100.0
const DEFAULT_SPREAD := 7.0

var nozzle_name: StringName = &""
var _cfg: Dictionary = {}
var _core: MeshInstance3D
var _core_mat: ShaderMaterial
var _column: MeshInstance3D
var _column_mat: ShaderMaterial
var _vapour: GPUParticles3D
var _throat: MeshInstance3D
var _throat_mat: StandardMaterial3D
var _target: float = 0.0
var _value: float = 0.0
var _quality: float = 1.0
## The particle budget of this nozzle, before the quality preset scales it.
var _vapour_amount: int = 0
## Counter used to give every nozzle a different flicker phase, deterministically.
static var _build_index: int = 0


## Builds the plume. `quality` scales the particle counts (Settings.feature("particles")).
func setup(cfg: Dictionary, quality: float) -> void:
	_cfg = cfg
	_quality = clampf(quality, 0.0, 1.0)
	_build_core()
	_build_column()
	_build_throat()
	_build_vapour()


func _build_core() -> void:
	_build_index += 1
	_core = MeshInstance3D.new()
	_core.name = "JetCore"
	_core.mesh = JetMesh.mesh()
	# The mesh runs along +Y; rotate so its tip points along the marker's -Z.
	_core.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.set_shader_parameter(&"core_color", CORE_COLOUR)
	_core_mat.set_shader_parameter(&"energy", CORE_ENERGY)
	_core_mat.set_shader_parameter(&"phase", float(_build_index % 10) * 0.618)
	_core_mat.set_shader_parameter(&"ring_pos", RING_POS)
	_core_mat.set_shader_parameter(&"ring_bright", RING_BRIGHT)
	_core_mat.set_shader_parameter(&"ring_width", RING_WIDTH)
	_core_mat.set_shader_parameter(&"intensity", 0.0)
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.visible = false
	add_child(_core)


## The vapour column: a tapered tube of scrolling noise, one draw call per nozzle. It is what
## makes the plume a continuous rope instead of a string of puffs (review MUST-FIX 5).
func _build_column() -> void:
	_column = MeshInstance3D.new()
	_column.name = "JetColumn"
	_column.mesh = JetColumnMesh.mesh()
	# The tube runs along +Y; rotate so its tip points along the marker's -Z.
	_column.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_column_mat = ShaderMaterial.new()
	_column_mat.shader = COLUMN_SHADER
	_column_mat.set_shader_parameter(&"noise_tex", PlumeAssets.noise_texture())
	_column_mat.set_shader_parameter(&"tint", PlumeAssets.VAPOUR_BIRTH)
	_column_mat.set_shader_parameter(&"intensity", 0.0)
	_column_mat.set_shader_parameter(&"alpha_max", COLUMN_ALPHA)
	_column_mat.set_shader_parameter(&"emission_gain", COLUMN_EMISSION_GAIN)
	_column_mat.set_shader_parameter(&"jet_speed", _jet_speed())
	# The column starts where the bright core cone ends, so the shock diamonds stay readable.
	_column.position = Vector3(0.0, 0.0, -COLUMN_START)
	_column.material_override = _column_mat
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	add_child(_column)


func _build_throat() -> void:
	_throat = MeshInstance3D.new()
	_throat.name = "ThroatGlow"
	var disc := CylinderMesh.new()
	disc.top_radius = THROAT_RADIUS
	disc.bottom_radius = THROAT_RADIUS
	disc.height = THROAT_HEIGHT
	disc.radial_segments = THROAT_SEGMENTS
	_throat.mesh = disc
	# The disc lies across the jet axis.
	_throat.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_throat.position = Vector3(0.0, 0.0, THROAT_OFFSET)
	_throat_mat = PlumeAssets.throat_material()
	_throat.material_override = _throat_mat
	_throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throat.visible = false
	add_child(_throat)


## The vapour trail: the lead's shared jet_vapour preset, retuned for the dossier's numbers
## (damping 100, so the lift jet reaches the road from 5-7 m and the yaw jet is 1 m long).
func _build_vapour() -> void:
	_vapour = GPUParticles3D.new()
	_vapour.name = "JetVapour"
	var spec: Dictionary = SmokeFX.preset(&"jet_vapour")
	_vapour_amount = _group_amount()
	spec["amount"] = _vapour_amount
	spec["lifetime"] = VAPOUR_LIFETIME
	spec["speed"] = Vector2(_jet_speed() * VAPOUR_SPEED_FACTOR, _jet_speed())
	spec["damping"] = Vector2(_damping(), _damping())
	spec["spread"] = _spread()
	spec["size"] = VAPOUR_SIZE
	spec["grow"] = VAPOUR_GROW
	spec["color"] = PlumeAssets.VAPOUR_BIRTH
	SmokeFX.setup(_vapour, spec)
	PlumeAssets.uncap_growth(_vapour, VAPOUR_GROW)
	# The vapour sprites are metres across, so they use the cheap per-vertex variant of the
	# shared atlas: same picture, same frames, a fifth of the fill cost.
	var quad := _vapour.draw_pass_1 as QuadMesh
	quad.material = PlumeAssets.vapour_material()
	# The vapour is the same colour everywhere: sorting it per view is not worth the cost.
	_vapour.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	# A fixed simulation rate, so the plume looks the same at 60 and at 120 fps.
	_vapour.fixed_fps = 60
	_vapour.randomness = VAPOUR_RANDOMNESS
	_vapour.emitting = false
	_tune_vapour()
	add_child(_vapour)


## The bits the shared preset cannot know: the dossier's damping and the gas stays where it
## was emitted (dossier §6.1: the launch trail is as long as the distance driven).
func _tune_vapour() -> void:
	var pm := _vapour.process_material as ParticleProcessMaterial
	# The gas stays where it was emitted: the rear trail is 12-13 m long after one second of
	# boost, because the car drives out of it.
	pm.inherit_velocity_ratio = 0.0
	# The vapour lands on the road instead of sinking through it.
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.0
	pm.collision_friction = 0.3
	pm.collision_use_scale = true


## Changes the particle budget of this nozzle (used when the car's tier changes).
func set_particle_quality(particle_quality: float) -> void:
	_quality = clampf(particle_quality, 0.0, 1.0)
	_vapour.amount = maxi(1, int(round(float(_vapour_amount) * _quality)))
	_vapour.emitting = _value > LIVE_EPSILON and _quality > 0.0


## The particles alive for this nozzle.
func particle_capacity() -> int:
	return _vapour.amount


## The height of the road under this nozzle, so the column can dissolve into it.
func set_ground_height(height: float) -> void:
	_column_mat.set_shader_parameter(&"ground_y", height)


## Target throttle for this nozzle, 0..1.
func set_target(value: float) -> void:
	_target = clampf(value, 0.0, 1.0)


func get_value() -> float:
	return _value


func _process(delta: float) -> void:
	var rate: float = (1.0 / ATTACK) if _target > _value else (1.0 / RELEASE)
	_value = clampf(_value + clampf(_target - _value, -rate * delta, rate * delta), 0.0, 1.0)
	_apply()


func _apply() -> void:
	var live: bool = _value > LIVE_EPSILON
	_core.visible = live
	_column.visible = live
	_throat.visible = live
	_vapour.emitting = live and _quality > 0.0
	if not live:
		return
	var base_length: float = _cfg.get("length", DEFAULT_LENGTH)
	var base_radius: float = _cfg.get("radius", DEFAULT_RADIUS)
	var radial: float = base_radius * lerpf(CORE_MIN_SCALE, 1.0, _value)
	var length: float = base_length * _value
	_core.scale = Vector3(radial, length, radial)
	_core_mat.set_shader_parameter(&"intensity", _value)
	# The shock diamonds sit at fixed distances from the throat, so the shader needs the
	# cone's current length in metres.
	_core_mat.set_shader_parameter(&"cone_length", length)
	_apply_column()
	_throat_mat.emission_energy_multiplier = THROAT_ENERGY_MAX * _value
	_vapour.amount_ratio = clampf(_value, 0.0, 1.0)


## The column grows with the throttle, but only a little: the rest of the throttle goes into
## its alpha, so a choked nozzle keeps its jet and only loses density.
func _apply_column() -> void:
	var group: String = String(_cfg.get("group", "lift"))
	var length: float = float(COLUMN_LENGTH.get(group, 3.0)) * lerpf(COLUMN_LENGTH_MIN, 1.0, _value)
	var radius: float = float(COLUMN_RADIUS.get(group, 0.35))
	_column.scale = Vector3(radius, length, radius)
	_column_mat.set_shader_parameter(&"intensity", _value)
	_column_mat.set_shader_parameter(&"column_length", length)


## The particle budget of this nozzle's group.
func _group_amount() -> int:
	var group: String = String(_cfg.get("group", "lift"))
	return int(VAPOUR_AMOUNT.get(group, VAPOUR_AMOUNT["lift"]))


func _jet_speed() -> float:
	return float(_cfg.get("speed", DEFAULT_SPEED))


func _damping() -> float:
	return float(_cfg.get("damping", DEFAULT_DAMPING))


func _spread() -> float:
	return float(_cfg.get("spread", DEFAULT_SPREAD))

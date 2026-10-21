extends Node3D
## 闪充 charge flash (brief §6): cyan #19E6FF electric arcs around the car for 1.0 s, a ground
## ring, a bloom flash (E4) and "闪充" energy ribbons. The node is added as a child of the car
## so it follows it through the charging bay, and frees itself when the flash is over.
##
## The arcs jump from the bodywork down to the road (they are generated from the surface of the
## car), the ground ring lies on the road under the car and the three energy ribbons spiral
## around the body.
##
## The bloom flash is a small hot core with a soft halo (exp(-8 d^2), no visible rim): a wide
## quad at a high energy whites out the frame from above. The OmniLight does the rest of the
## work: it paints the road and the body in cyan.

const ADD_SHADER := preload("res://fx/fx_add.gdshader")
const RING_SHADER := preload("res://fx/fx_ring.gdshader")
const TEXTURES := preload("res://fx/fx_textures.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")
const ARCS := preload("res://fx/fx_arcs.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const Dev := preload("res://fx/fx_dev.gd")

## The segments of one energy ribbon.
const RIBBON_SEGMENTS := 32
## How often the arcs are regenerated during the flash (seconds).
const ARC_INTERVAL := 0.15
## The ribbons turn once around the car during the flash.
const RIBBON_TURNS := 1.0

var _arcs: Node3D
var _ring: MeshInstance3D
var _ribbons: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _flash: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0
var _running: bool = false
var _arc_timer: float = 0.0
var _radius := Vector2(1.3, 2.6)
## The dev switches of the unit (--fx-no-ribbons).
var dev: Dev = null
## The last ground probe (the physics step owns the raycast).
var _ground_point := Vector3.ZERO
var _ground_normal := Vector3.UP
var _ground_local: float = 0.0
var _ground_hit: bool = false


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	_arcs = ARCS.new()
	_arcs.name = "Arcs"
	add_child(_arcs)

	_ring = MeshInstance3D.new()
	_ring.name = "GroundRing"
	_ring.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = RING_SHADER
	ring_mat.set_shader_parameter(&"tint", PALETTE.CHARGE)
	ring_mat.set_shader_parameter(&"energy", 5.0)
	plane.material = ring_mat
	_ring.mesh = plane
	_ring.material_override = ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# The three energy ribbons: additive strips that spiral around the body.
	_ribbon_mesh = ImmediateMesh.new()
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "EnergyRibbons"
	_ribbons.mesh = _ribbon_mesh
	var ribbon_mat := ShaderMaterial.new()
	ribbon_mat.shader = ADD_SHADER
	ribbon_mat.set_shader_parameter(&"albedo_tex", TEXTURES.energy_ribbon())
	ribbon_mat.set_shader_parameter(&"use_texture", true)
	ribbon_mat.set_shader_parameter(&"tint", PALETTE.CHARGE)
	ribbon_mat.set_shader_parameter(&"energy", 7.0)
	_ribbons.material_override = ribbon_mat
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbons)

	# The bloom flash: a small hot core with a soft halo, that always faces the camera.
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = ADD_SHADER
	flash_mat.set_shader_parameter(&"albedo_tex", TEXTURES.charge_halo())
	flash_mat.set_shader_parameter(&"use_texture", true)
	flash_mat.set_shader_parameter(&"tint", PALETTE.CHARGE)
	flash_mat.set_shader_parameter(&"energy", TUNE.CHARGE_FLASH_ENERGY)
	flash_mat.set_shader_parameter(&"billboard_mode", 1.0)
	# The flash is pushed towards the camera, so the body of the car does not clip it.
	flash_mat.set_shader_parameter(&"push", TUNE.CHARGE_FLASH_PUSH)
	quad.material = flash_mat
	_flash.mesh = quad
	_flash.material_override = flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = Vector3(0.0, 0.9, 0.0)
	add_child(_flash)

	_light = OmniLight3D.new()
	_light.name = "FlashLight"
	_light.light_color = PALETTE.CHARGE
	_light.light_energy = 0.0
	_light.omni_range = TUNE.CHARGE_LIGHT_RANGE
	_light.shadow_enabled = false
	_light.top_level = true
	add_child(_light)


## Starts the flash on `vehicle` (the arcs are matched to its bodywork).
func play(vehicle: VehicleBase = null) -> void:
	_running = true
	_t = 0.0
	_arc_timer = 0.0
	visible = true
	if vehicle != null and is_instance_valid(vehicle):
		var box := _visual_aabb(vehicle.get_visual_root())
		if box.size.length() > 0.0:
			_radius = Vector2(box.size.x * 0.5 + TUNE.CHARGE_RIBBON_MARGIN,
					box.size.z * 0.5 + TUNE.CHARGE_RIBBON_MARGIN)
	_arcs.setup(PALETTE.CHARGE, 6.0, TUNE.CHARGE_ARCS)
	_arcs.set_to_ground(true)
	_arcs.set_surface(vehicle)
	_arcs.set_ground(_ground_height(vehicle))
	_arcs.play()


## The bounding box of the car's bodywork (the visual subtree).
static func _visual_aabb(visual: Node3D) -> AABB:
	var box := AABB()
	var found := false
	if visual == null:
		return box
	for child in visual.find_children("*", "VisualInstance3D", true, false):
		var instance := child as VisualInstance3D
		if instance == null:
			continue
		var aabb := instance.get_aabb()
		box = aabb if not found else box.merge(aabb)
		found = true
	return box


## The height of the road under the car, in the local space of the car.
func _ground_height(vehicle: VehicleBase) -> float:
	var world := Game.world
	var origin := global_position
	if vehicle != null and is_instance_valid(vehicle):
		origin = vehicle.global_position
	if world != null:
		var y := world.ground_height(origin)
		if not is_nan(y):
			return y - origin.y
	var space := get_world_3d().direct_space_state
	var result := GROUND.probe(space, origin)
	return (result["point"] as Vector3).y - origin.y if result["hit"] else -0.6


## The ground is probed in the physics step: a raycast outside of it is not safe.
func _physics_process(_delta: float) -> void:
	if not _running:
		return
	var car := get_parent() as VehicleBase
	var origin := global_position
	if car != null and is_instance_valid(car):
		origin = car.global_position
	var space := get_world_3d().direct_space_state
	var result := GROUND.probe(space, origin)
	_ground_point = result["point"]
	_ground_normal = result["normal"]
	_ground_hit = result["hit"]
	_ground_local = _ground_point.y - origin.y


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	if _t >= TUNE.CHARGE_DURATION:
		_running = false
		visible = false
		queue_free()
		return
	var k := _t / TUNE.CHARGE_DURATION
	_update_ring(k)
	_update_ribbons(k)
	_update_flash()
	_update_arcs(delta)


## The arcs jump over the body for the whole second of the flash.
func _update_arcs(delta: float) -> void:
	_arc_timer -= delta
	if _arc_timer > 0.0:
		return
	_arc_timer = ARC_INTERVAL
	if _arcs.is_running():
		_arcs.regenerate()
	else:
		_arcs.play()


## The ground ring: it lies on the road under the car, along the normal of the surface.
func _update_ring(k: float) -> void:
	_ring.visible = k < 0.85 and _ground_hit
	if not _ring.visible:
		return
	var normal := _ground_normal
	if normal.length() < 0.01:
		normal = Vector3.UP
	_ring.global_position = _ground_point + normal * TUNE.CHARGE_RING_LIFT
	_ring.global_transform = Transform3D(_ring_basis(normal), _ring.global_position)
	_ring.scale = Vector3.ONE * lerpf(TUNE.CHARGE_RING_MIN, TUNE.CHARGE_RING_MAX, sqrt(k))
	_ring.material_override.set_shader_parameter(&"progress", k)


## A basis whose Y axis is the normal of the road (the ring lies flat on a ramp too).
func _ring_basis(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	var forward := up.cross(right).normalized()
	return Basis(right, up, forward)


## The three energy ribbons: additive strips that spiral around the body of the car.
func _update_ribbons(k: float) -> void:
	if dev != null and dev.no_ribbons:
		return
	_ribbon_mesh.clear_surfaces()
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var fade := clampf(1.0 - k, 0.0, 1.0)
	var phase := k * TAU * RIBBON_TURNS
	for i in TUNE.CHARGE_RIBBONS:
		var base: float = TUNE.CHARGE_RIBBON_HEIGHTS[i % TUNE.CHARGE_RIBBON_HEIGHTS.size()]
		# Every ribbon has its own radius and its own start angle, so they read as three
		# spirals and not as three stacked hoops.
		var scale := 0.8 + 0.2 * float(i)
		_emit_ribbon(base, phase + float(i) * TAU / 3.0, scale, fade)
	_ribbon_mesh.surface_end()


## One ribbon: a helix that turns once around the car and rises while it turns.
func _emit_ribbon(base_height: float, phase: float, radius_scale: float, fade: float) -> void:
	var col := Color(1.0, 1.0, 1.0, fade)
	for i in RIBBON_SEGMENTS:
		var f0 := float(i) / float(RIBBON_SEGMENTS)
		var f1 := float(i + 1) / float(RIBBON_SEGMENTS)
		var a0 := phase + TAU * f0
		var a1 := phase + TAU * f1
		var h0 := base_height + f0 * TUNE.CHARGE_RIBBON_RISE
		var h1 := base_height + f1 * TUNE.CHARGE_RIBBON_RISE
		var p0 := Vector3(cos(a0) * _radius.x * radius_scale, h0,
				sin(a0) * _radius.y * radius_scale)
		var p1 := Vector3(cos(a1) * _radius.x * radius_scale, h1,
				sin(a1) * _radius.y * radius_scale)
		var r0 := Vector3(cos(a0), 0.0, sin(a0)).normalized() * TUNE.CHARGE_RIBBON_WIDTH
		var r1 := Vector3(cos(a1), 0.0, sin(a1)).normalized() * TUNE.CHARGE_RIBBON_WIDTH
		# The texture scrolls with the phase: the energy runs around the ring.
		var u0 := f0 + phase / TAU
		var u1 := f1 + phase / TAU
		_ribbon_mesh.surface_set_color(col)
		_ribbon_mesh.surface_set_uv(Vector2(u0, 0.0))
		_ribbon_mesh.surface_add_vertex(p0)
		_ribbon_mesh.surface_set_uv(Vector2(u1, 0.0))
		_ribbon_mesh.surface_add_vertex(p1)
		_ribbon_mesh.surface_set_uv(Vector2(u1, 1.0))
		_ribbon_mesh.surface_add_vertex(p1 + r1)
		_ribbon_mesh.surface_set_uv(Vector2(u0, 0.0))
		_ribbon_mesh.surface_add_vertex(p0)
		_ribbon_mesh.surface_set_uv(Vector2(u1, 1.0))
		_ribbon_mesh.surface_add_vertex(p1 + r1)
		_ribbon_mesh.surface_set_uv(Vector2(u0, 1.0))
		_ribbon_mesh.surface_add_vertex(p0 + r0)


## The bloom flash: a small hot core that peaks after 0.08 s and is gone after 0.25 s. The light
## does the rest: it decays over 0.35 s and paints the road and the bodywork.
func _update_flash() -> void:
	var a := 0.0
	if _t < TUNE.CHARGE_FLASH_PEAK:
		a = _t / TUNE.CHARGE_FLASH_PEAK
	elif _t < TUNE.CHARGE_FLASH_END:
		a = 1.0 - (_t - TUNE.CHARGE_FLASH_PEAK) \
				/ (TUNE.CHARGE_FLASH_END - TUNE.CHARGE_FLASH_PEAK)
	a = clampf(a, 0.0, 1.0)
	_flash.material_override.set_shader_parameter(&"alpha_scale", a)
	# The quad is scaled down when the camera is far away: a wide quad fills the frame from
	# above, even when it is dim.
	var cam := get_viewport().get_camera_3d()
	var distance := 100.0
	if cam != null:
		distance = cam.global_position.distance_to(_flash.global_position)
	var far := minf(1.0, TUNE.CHARGE_FLASH_FAR / maxf(distance, 0.5))
	var grow := lerpf(0.6, 1.0, minf(_t / TUNE.CHARGE_FLASH_PEAK, 1.0))
	_flash.scale = Vector3.ONE * TUNE.CHARGE_FLASH_SIZE * grow * far
	_light.light_energy = TUNE.CHARGE_LIGHT_ENERGY * clampf(1.0 - _t / TUNE.CHARGE_FLASH_END, 0.0, 1.0)
	if _ground_hit:
		_light.global_position = _ground_point + Vector3.UP * TUNE.CHARGE_LIGHT_HEIGHT

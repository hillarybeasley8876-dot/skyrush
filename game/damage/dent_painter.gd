extends RefCounted
## The dent rig of ONE car (dossier §7.5 A).
##
## The dent field lives in the space of the CAR, not in the space of a mesh: every surface
## of the car inside the dent sphere is pushed by the same vector, so the paint never sinks
## behind the black trim that stayed in place. The paint keeps the damage paint (the paint
## scrape mask and the layers of the damaged paint); every other surface gets the generic
## damage shader, which keeps the look of the BaseMaterial3D it replaces.
##
## The rig is built lazily: a car that is never hit owns no material, no mask and no light.

const DentMaterials := preload("res://damage/dent_materials.gd")
const MaskAtlas := preload("res://damage/mask_atlas.gd")
const MaskPool := preload("res://damage/mask_pool.gd")

## The dents of one car (a ring buffer, dossier §7.5 A).
const MAX_DENTS := 8
## The dent of dossier §7.5 A.
const DENT_RADIUS_BASE := 0.25
const DENT_RADIUS_PER_VN := 0.025
const DENT_RADIUS_MAX := 0.9
const DENT_DEPTH_PER_VN := 0.012
const DENT_DEPTH_MIN := 0.03
const DENT_DEPTH_MAX := 0.25
## The deepest a dent may be, as a share of its radius: a dish of 25 % slope. The panels of
## the cars are coarse (0.18 m), so a deeper dent folds them over themselves. The limit is
## the same for every surface of the car, so the paint and the trim move together.
const DENT_SLOPE := 0.25
## The mask is uploaded at most this often (dossier §7.7: <= 10 updates per second).
const MASK_FLUSH_INTERVAL := 0.1
var vehicle: VehicleBase = null
var _panels: Array[CarSurface] = []
## The surfaces that were hit and whose damage material is not built yet.
var _pending: Array[CarSurface] = []
## The dent materials of the car, by the id of the material they replace.
var _materials: Dictionary = {}
## The dent field of the car (in the space of the car), shared by every material.
var _dents: Array[Vector4] = []
var _dirs: Array[Vector4] = []
var _next: int = 0
## The mask of the paint scrape.
var _mask: MaskAtlas = null
## The box of the atlas, in the space of the car.
var _car_min: Vector3 = Vector3(-0.95, 0.0, -2.3)
var _car_size: Vector3 = Vector3(1.9, 1.45, 4.6)
var _flush_timer: float = 0.0
var _prepared: bool = false
## The key of the model of the car: the painted meshes are the same for every car of a
## model, so they are read once for the model and not once for every car.
var _model_key: String = ""
## Called when the mask has to be uploaded.
var on_dirty: Callable = Callable()

## Finds the meshes of the car. This is the cheap part: a car that is never hit owns no
## material, no mask and no light.
func setup(car: VehicleBase) -> bool:
	vehicle = car
	for i in MAX_DENTS:
		_dents.append(Vector4.ZERO)
		_dirs.append(Vector4.ZERO)
	_collect_panels()
	return not _panels.is_empty()


## The number of meshes of the car.
func panel_count() -> int:
	return _panels.size()


## The number of painted meshes of the car.
func painted_count() -> int:
	var count := 0
	for panel in _panels:
		if panel.painted:
			count += 1
	return count


## The number of dents the car carries (for the test).
func dent_count() -> int:
	var count := 0
	for d: Vector4 in _dents:
		if d.w > 0.0:
			count += 1
	return count


## The scrape coverage of the mask, 0..1 (for the test).
func mask_coverage() -> float:
	return _mask.coverage() if _mask != null else 0.0


## The number of times the mask reached the GPU (for the test).
func upload_count() -> int:
	return _mask.upload_count if _mask != null else 0


## True while the mask has to be uploaded or a material has to be built.
func pending() -> bool:
	if not _pending.is_empty():
		return true
	return _mask != null and _mask.dirty


## Adds a dent. `world_point` is the point of the hit, `world_dir` the direction the panel
## is pushed in (the normal of the contact) and `slide` the direction the car slid.
func add_dent(world_point: Vector3, world_dir: Vector3, v_n: float, slide: Vector3,
		impact: float = 1.0) -> void:
	if _panels.is_empty():
		return
	_prepare()
	if _mask == null:
		return
	var radius := clampf(DENT_RADIUS_BASE + v_n * DENT_RADIUS_PER_VN, DENT_RADIUS_BASE,
			DENT_RADIUS_MAX)
	var depth := clampf(v_n * DENT_DEPTH_PER_VN, DENT_DEPTH_MIN, DENT_DEPTH_MAX)
	# A dent deeper than its own radius allows folds the panel over itself.
	depth = minf(depth, radius * DENT_SLOPE)
	var inv := vehicle.global_transform.affine_inverse()
	var car_point: Vector3 = inv * world_point
	var car_dir: Vector3 = (inv.basis * world_dir).normalized()
	# Every surface of the car inside the sphere is pushed by the same field. The damage
	# material of a surface is built on the frame after the hit: a hit must not pay for it
	# (dossier §7.7).
	for panel in _panels:
		var d := car_point - panel.centre
		if absf(d.x) > panel.half.x + radius \
				or absf(d.y) > panel.half.y + radius \
				or absf(d.z) > panel.half.z + radius:
			continue
		if not panel.dented and not _pending.has(panel):
			_pending.append(panel)
	_push_dent(car_point, car_dir, radius, depth)
	_mask.splat(car_point, -car_dir, (inv.basis * slide).normalized(), v_n, radius, impact)
	_notify_dirty()


## Uploads the mask when it is dirty (at most 10 times a second) and builds the damage
## materials of the surfaces that were hit.
func tick(delta: float) -> void:
	_build_pending()
	if _mask == null or not _mask.dirty:
		return
	_flush_timer += delta
	if _flush_timer < MASK_FLUSH_INTERVAL:
		return
	_flush_timer = 0.0
	_mask.upload()


## Puts the damage material on the surfaces that were hit (the frame after the hit).
func _build_pending() -> void:
	while not _pending.is_empty():
		var panel: CarSurface = _pending.pop_front()
		_install(panel)


## Turns the dents and the paint mask off (for the captures and the tests).
func set_damage_enabled(dents: bool, mask: bool) -> void:
	for material: ShaderMaterial in _materials.values():
		DentMaterials.set_uniform(material, "damage_enabled", 1.0 if dents else 0.0)
		DentMaterials.set_uniform(material, "mask_enabled", 1.0 if mask else 0.0)


## The respawn: the car keeps two dents at half depth and half of the scrape.
func soften() -> void:
	var kept := 0
	for i in _dents.size():
		if _dents[i].w <= 0.0:
			continue
		if kept >= 2:
			_dents[i] = Vector4.ZERO
			_dirs[i] = Vector4.ZERO
			continue
		kept += 1
		_dents[i] = Vector4(_dents[i].x, _dents[i].y, _dents[i].z, _dents[i].w * 0.5)
		_dirs[i] = Vector4(_dirs[i].x, _dirs[i].y, _dirs[i].z, _dirs[i].w * 0.5)
	for material: ShaderMaterial in _materials.values():
		DentMaterials.set_uniform(material, "dent_pos", _dents)
		DentMaterials.set_uniform(material, "dent_dir", _dirs)
		# The scrape is halved with a uniform, not with a loop over a million pixels.
		DentMaterials.set_uniform(material, "mask_gain", 0.5)


## A car that comes out of its pool: it has no dent and no scrape at all.
func reset() -> void:
	for i in _dents.size():
		_dents[i] = Vector4.ZERO
		_dirs[i] = Vector4.ZERO
	_next = 0
	for material: ShaderMaterial in _materials.values():
		DentMaterials.set_uniform(material, "dent_pos", _dents)
		DentMaterials.set_uniform(material, "dent_dir", _dirs)
		DentMaterials.set_uniform(material, "mask_gain", 1.0)
	if _mask == null:
		return
	# The scrape is gone: the mask is cleared and the GPU gets it on the next flush.
	_mask.clear()
	_notify_dirty()


## The car leaves the world: its mask goes back to the pool.
func dispose() -> void:
	if _mask != null:
		MaskPool.release(_mask)
		_mask = null
	_pending.clear()
	_materials.clear()
	_panels.clear()


# --- the panels -----------------------------------------------------------------------------------
## The meshes of the car and their box in the space of the car.
func _collect_panels() -> void:
	_panels.clear()
	var visual := vehicle.get_visual_root()
	if visual == null:
		return
	_model_key = visual.scene_file_path
	_panels = CarSurface.collect(vehicle)


## The first hit of the car: the box of the atlas and the mask of the paint scrape.
func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	var box := AABB()
	var first := true
	_scan_painted()
	for panel in _panels:
		if not panel.painted:
			continue
		# The exact box of the painted meshes: it is the box of the atlas.
		panel.car_box = panel.xform * CarSurface.mesh_box(panel.node.mesh)
		if first:
			box = panel.car_box
			first = false
		else:
			box = box.merge(panel.car_box)
	if first:
		return
	_car_min = box.position - Vector3(0.02, 0.02, 0.02)
	_car_size = Vector3(maxf(box.size.x, 0.25), maxf(box.size.y, 0.25), maxf(box.size.z, 0.25)) + Vector3(0.04, 0.04, 0.04)
	_mask = MaskPool.acquire()
	_mask.setup(_car_min, _car_size)


## Marks the painted meshes of the car (the list of the painted meshes is the one of the
## model of the car).
func _scan_painted() -> void:
	CarSurface.mark_painted(_panels, _model_key)


## The damage material of a surface: the damage paint for a painted surface, the generic
## damage shader for a BaseMaterial3D.
func _dent_material(source: Material) -> ShaderMaterial:
	var key := source.get_instance_id()
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var result := DentMaterials.make(source)
	if result != null:
		_materials[key] = result
		if result.shader == DentMaterials.DENT_PAINT:
			DentMaterials.set_substrate(result, _is_hero())
		_set_car_uniforms(result)
	return result


## True for the car of the player (the carbon under its paint, the steel under the others).
func _is_hero() -> bool:
	return vehicle != null and vehicle.team == VehicleBase.Team.PLAYER


## The uniforms of the car: the dent field, the mask and the box of the atlas.
func _set_car_uniforms(material: ShaderMaterial) -> void:
	DentMaterials.set_uniform(material, "dent_pos", _dents)
	DentMaterials.set_uniform(material, "dent_dir", _dirs)
	DentMaterials.set_uniform(material, "damage_enabled", 1.0)
	if _mask == null:
		return
	DentMaterials.set_uniform(material, "damage_mask", _mask.texture)
	DentMaterials.set_uniform(material, "car_min", _car_min)
	DentMaterials.set_uniform(material, "car_size", _car_size)
	DentMaterials.set_uniform(material, "mask_rect", _mask.rects)
	DentMaterials.set_uniform(material, "mask_enabled", 1.0)


## Puts the damage material on a mesh and gives the mesh its place in the car.
func _install(panel: CarSurface) -> void:
	if panel.dented:
		return
	panel.dented = true
	var node := panel.node
	var installed := false
	for i in node.mesh.get_surface_count():
		var source := _source_material(node, i)
		if source == null:
			continue
		var dent_material := _dent_material(source)
		if dent_material == null:
			continue
		node.set_surface_override_material(i, dent_material)
		installed = true
	if not installed:
		return
	# The mesh finds its place in the car with instance uniforms, so every mesh of the car
	# can share one material.
	_set_car_from_obj(node, panel.xform)


## The material of a surface. The material of the mesh is read first (it is a resource call);
## only a shader (or a material the library of the materials may have replaced) has to be asked
## to the mesh, because that one is a rendering call.
func _source_material(node: MeshInstance3D, surface: int) -> Material:
	var source: Material = node.mesh.surface_get_material(surface)
	if source == null:
		source = node.get_material_override()
	if source == null:
		return null
	if source is ShaderMaterial or source.resource_name.get_slice(".", 0).begins_with("SH_"):
		var active := node.get_active_material(surface)
		if active != null:
			source = active
	return source


## Sets the place of a mesh in the car (the four rows of the transform: Godot does not
## allow a matrix as an instance uniform).
func _set_car_from_obj(node: MeshInstance3D, xform: Transform3D) -> void:
	node.set_instance_shader_parameter(&"car_from_obj_x", xform.basis.x)
	node.set_instance_shader_parameter(&"car_from_obj_y", xform.basis.y)
	node.set_instance_shader_parameter(&"car_from_obj_z", xform.basis.z)
	node.set_instance_shader_parameter(&"car_from_obj_o", xform.origin)


## The dent goes into the ring buffer of the car and every material of the car sees it.
func _push_dent(car_point: Vector3, car_dir: Vector3, radius: float, depth: float) -> void:
	_dents[_next] = Vector4(car_point.x, car_point.y, car_point.z, radius)
	_dirs[_next] = Vector4(car_dir.x, car_dir.y, car_dir.z, depth)
	_next = (_next + 1) % MAX_DENTS
	for material: ShaderMaterial in _materials.values():
		DentMaterials.set_uniform(material, "dent_pos", _dents)
		DentMaterials.set_uniform(material, "dent_dir", _dirs)


## The mask has to be uploaded.
func _notify_dirty() -> void:
	if on_dirty.is_valid():
		on_dirty.call(self)


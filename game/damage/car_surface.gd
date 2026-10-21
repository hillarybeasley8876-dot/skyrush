class_name CarSurface
extends RefCounted
## One mesh of a car and its place in the space of the car (dossier §7.5 A).
##
## The panel of a car is read once, when the car joins the world: where it is, how big it
## is and whether it carries the paint. The painted meshes are the same for every car of a
## model, so they are read once for the model and not once for every car.

const DentMaterials := preload("res://damage/dent_materials.gd")

## The mesh of the car.
var node: MeshInstance3D = null
## The id of the mesh resource (the scan of the paint is cached by it).
var mesh_id: int = 0
## The AABB of the mesh in the space of the car (the painted meshes only).
var car_box: AABB = AABB()
## The centre of the mesh in the space of the car.
var centre: Vector3 = Vector3.ZERO
## The half sizes of the box that holds the mesh in the space of the car.
var half: Vector3 = Vector3.ZERO
## The transform of the mesh in the space of the car (it is rigid).
var xform: Transform3D = Transform3D.IDENTITY
## True when the mesh carries a painted surface.
var painted: bool = false
## True when the damage material is already on the mesh.
var dented: bool = false

## The AABB of the meshes, cached by the mesh resource.
static var _mesh_boxes: Dictionary = {}
## True when a mesh carries a painted surface, by the id of the mesh resource.
static var _painted_meshes: Dictionary = {}
## The painted meshes of every model of car, by the path of its scene.
static var _painted_by_model: Dictionary = {}


## The meshes of the car and their place in the space of the car.
static func collect(vehicle: VehicleBase) -> Array[CarSurface]:
	var panels: Array[CarSurface] = []
	var visual := vehicle.get_visual_root()
	if visual == null:
		return panels
	var car_inv := vehicle.global_transform.affine_inverse()
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var panel := CarSurface.new()
		panel.node = mesh_node
		panel.mesh_id = mesh_node.mesh.get_instance_id()
		panel.xform = car_inv * mesh_node.global_transform
		var local := mesh_box(mesh_node.mesh)
		panel.centre = panel.xform * local.get_center()
		panel.half = _half_in_car(panel.xform, local.size * 0.5)
		panels.append(panel)
	return panels


## Marks the painted meshes of the car. The list of the painted meshes is the one of the
## model of the car: it is read once for every model, not once for every car.
static func mark_painted(panels: Array[CarSurface], model_key: String) -> void:
	if model_key.is_empty():
		for panel in panels:
			panel.painted = _has_paint(panel.node, panel.mesh_id)
		return
	var known: Dictionary = _painted_by_model.get(model_key, {}) as Dictionary
	if known.is_empty():
		for panel in panels:
			var painted := _has_paint(panel.node, panel.mesh_id)
			panel.painted = painted
			if painted:
				known[panel.mesh_id] = true
		_painted_by_model[model_key] = known
		return
	for panel in panels:
		panel.painted = known.has(panel.mesh_id)


## True when a point is inside the box that holds a mesh, grown by a margin. The box is
## not built: a hit walks every mesh of the car, and 73 boxes would cost more than the hit.
static func inside(panel: CarSurface, point: Vector3, margin: float) -> bool:
	var d := point - panel.centre
	return absf(d.x) <= panel.half.x + margin \
			and absf(d.y) <= panel.half.y + margin \
			and absf(d.z) <= panel.half.z + margin


## The AABB of a mesh, cached by the mesh resource (the same glb is used by many cars).
static func mesh_box(mesh: Mesh) -> AABB:
	var id := mesh.get_instance_id()
	if _mesh_boxes.has(id):
		return _mesh_boxes[id] as AABB
	var box := mesh.get_aabb()
	_mesh_boxes[id] = box
	return box


## The half sizes of the box that holds a mesh in the space of the car. The box of the
## mesh is not rotated: the box that holds it is a little bigger, but it is cheap (the
## join walks every mesh of the car).
static func _half_in_car(xform: Transform3D, half: Vector3) -> Vector3:
	var basis := xform.basis
	return Vector3(
		absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z,
		absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z,
		absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z)


## True when the mesh carries a painted surface. The answer is cached by the mesh resource.
static func _has_paint(node: MeshInstance3D, mesh_id: int) -> bool:
	if node.mesh == null:
		return false
	if _painted_meshes.has(mesh_id):
		return _painted_meshes[mesh_id] as bool
	var painted := _scan_paint(node)
	_painted_meshes[mesh_id] = painted
	return painted


## The scan itself: the materials of the mesh, not the active ones (`get_active_material`
## is a rendering call). The name of the material is the cheap test, the shader of it the
## sure one.
static func _scan_paint(node: MeshInstance3D) -> bool:
	var override := node.get_material_override()
	for i in node.mesh.get_surface_count():
		var material: Material = override
		if material == null:
			material = node.mesh.surface_get_material(i)
		if material == null:
			continue
		var resource_name := material.resource_name
		# A material without a name (a copy of a .tres) has to be checked with its shader.
		if resource_name.is_empty():
			var active := node.get_active_material(i)
			if active is ShaderMaterial and DentMaterials.is_car_paint(
					(active as ShaderMaterial).shader):
				return true
			continue
		if resource_name.get_slice(".", 0).begins_with("SH_car_paint"):
			return true
	return false

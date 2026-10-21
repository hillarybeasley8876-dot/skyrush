extends RefCounted
## The gas station of a point of interest: the canopy of the props unit (or a procedural one),
## the dispensers, the pylon and the shop. The columns of the canopy are the Support_* nodes
## of the breaker, so the model is returned with the node they hang under.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")

const GAS_GLB := "res://assets/props/sites/gas_station.glb"
## The height of the canopy over the ground.
const GAS_CLEARANCE := 6.0
## The size of a gas station when the city description does not give one.
const DEFAULT_SIZE := Vector2(80.0, 70.0)
## The thickness of the slab of the canopy.
const SLAB_THICKNESS := 0.6
## The height of the fascia band of the canopy.
const FASCIA_HEIGHT := 1.4
## The margin of the fascia band over the slab.
const FASCIA_MARGIN := 0.4


## Builds the station under a node of its own. The result holds the root, the node the
## columns hang under and the size of the canopy. The root is added to the parent before the
## model is built: the size of the canopy is read from the world transform of its meshes.
func build(parent: Node3D, poi: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "GasStation_" + str(poi.get("id", "poi"))
	root.position = _position(poi)
	root.rotation.y = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0)))
	parent.add_child(root)
	var size: Array = poi.get("size", [DEFAULT_SIZE.x, DEFAULT_SIZE.y])
	var width := float(size[0]) if size.size() > 0 else DEFAULT_SIZE.x
	var depth := float(size[1]) if size.size() > 1 else DEFAULT_SIZE.y
	var model := _gas_model()
	if model != null:
		# The whole glb is added once; the Support_* columns hang under its canopy node.
		root.add_child(model)
		var structure := _support_parent(model)
		var box := _model_aabb(structure, "")
		if box.size.length() > 1.0:
			width = box.size.z
			depth = box.size.x
		return {"root": root, "structure": structure, "width": width, "depth": depth}
	var canopy := _procedural_canopy(root, width, depth)
	return {"root": root, "structure": canopy, "width": width, "depth": depth}


## The procedural fallback (the props unit has no glb).
func _procedural_canopy(root: Node3D, width: float, depth: float) -> Node3D:
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	root.add_child(canopy)
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	slab.mesh = ProcMeshes.box(Vector3(depth, SLAB_THICKNESS, width))
	slab.material_override = ProcMeshes.material("metal")
	slab.position = Vector3(0, GAS_CLEARANCE, 0)
	canopy.add_child(slab)
	var fascia := MeshInstance3D.new()
	fascia.name = "Fascia"
	fascia.mesh = ProcMeshes.box(Vector3(depth + FASCIA_MARGIN, FASCIA_HEIGHT, width + FASCIA_MARGIN))
	fascia.material_override = ProcMeshes.glow(Color("e60012"), 0.5)
	fascia.position = Vector3(0, GAS_CLEARANCE + 0.9, 0)
	canopy.add_child(fascia)
	for i in 3:
		for s in 2:
			var column := MeshInstance3D.new()
			column.name = "Support_%d_%d" % [i, s]
			column.mesh = ProcMeshes.box(Vector3(0.7, GAS_CLEARANCE, 0.7))
			column.material_override = ProcMeshes.material("metal")
			column.position = Vector3((float(i) - 1.0) * depth * 0.35, GAS_CLEARANCE * 0.5,
				(float(s) * 2.0 - 1.0) * width * 0.3)
			canopy.add_child(column)
		var dispenser := MeshInstance3D.new()
		dispenser.name = "Dispenser_%d" % i
		dispenser.mesh = ProcMeshes.box(Vector3(2.3, 1.6, 1.0))
		dispenser.material_override = ProcMeshes.glow(Color("f4f4f4"), 0.25)
		dispenser.position = Vector3((float(i) - 1.0) * depth * 0.35, 0.8, 0)
		root.add_child(dispenser)
	var pylon := MeshInstance3D.new()
	pylon.name = "Pylon"
	pylon.mesh = ProcMeshes.box(Vector3(2.2, 9.0, 1.0))
	pylon.material_override = ProcMeshes.glow(Color("e60012"), 0.6)
	pylon.position = Vector3(depth * 0.45, 4.5, width * 0.5 + 3.0)
	root.add_child(pylon)
	var store := MeshInstance3D.new()
	store.name = "Store"
	store.mesh = ProcMeshes.box(Vector3(25.0, 4.5, 12.0))
	store.material_override = ProcMeshes.material("concrete")
	store.position = Vector3(depth * 0.45, 2.25, -width * 0.5 - 9.0)
	root.add_child(store)
	return canopy


## The gas station of the props unit.
func _gas_model() -> Node3D:
	if not ResourceLoader.exists(GAS_GLB):
		return null
	var packed := load(GAS_GLB) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	MaterialLibrary.apply(model)
	return model


## The node the Support_* columns hang under (the canopy of the gas station).
static func _support_parent(model: Node3D) -> Node3D:
	for child in model.find_children("Support_*", "Node3D", true, false):
		var parent := child.get_parent()
		if parent != null:
			return parent as Node3D
	return model


## The bounding box of the meshes whose name contains `filter` (all of them when it is empty).
static func _model_aabb(node: Node3D, filter: String) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if filter != "" and not String(mi.name).contains(filter):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## The place of the station.
static func _position(poi: Dictionary) -> Vector3:
	return Vector3(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)), float(poi.get("z", 0.0)))

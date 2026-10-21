extends RefCounted
## Fallback city massing built from the city.json block lots. Only used while the buildings
## unit has not shipped res://assets/city/blocks/blocks_*.glb. Each lot becomes one prism with
## the shared facade shader (per-lot `building_seed` instance uniform) and a concrete parapet.

const Ribbon := preload("res://world/build/ribbon_builder.gd")
const ProcMeshes := preload("res://world/loader/proc_meshes.gd")

const FACADE_OFFICE := "res://shaders/materials/SH_facade_office.tres"
const FACADE_RESIDENTIAL := "res://shaders/materials/SH_facade_residential.tres"


func build(parent: Node3D, blocks: Array) -> void:
	for block in blocks:
		if block is Dictionary:
			_build_block(parent, block as Dictionary)


func _build_block(parent: Node3D, block: Dictionary) -> void:
	var poly := _polygon(block)
	if poly.size() < 3:
		return
	var style := str(block.get("style", "midrise"))
	var heights: Array = block.get("height_m", [12.0, 24.0])
	var h_min := float(heights[0]) if heights.size() > 0 else 12.0
	var h_max := float(heights[1]) if heights.size() > 1 else h_min
	var seed_value := int(block.get("seed", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var height := rng.randf_range(h_min, h_max)
	var root := Node3D.new()
	root.name = "Block_" + str(block.get("id", "b"))
	parent.add_child(root)

	var mi := MeshInstance3D.new()
	mi.name = "Mass"
	mi.mesh = Ribbon.prism(poly, 0.0, height)
	mi.material_override = _facade_material(style)
	mi.set_instance_shader_parameter(&"building_seed", float(seed_value % 9973) / 9973.0)
	root.add_child(mi)

	var parapet := MeshInstance3D.new()
	parapet.name = "Parapet"
	parapet.mesh = Ribbon.prism(_inset(poly, 0.4), height, height + 0.9)
	parapet.material_override = ProcMeshes.material("concrete")
	root.add_child(parapet)

	if height > 60.0:
		var mast := MeshInstance3D.new()
		mast.name = "Mast"
		mast.mesh = ProcMeshes.cylinder(0.35, 14.0)
		mast.material_override = ProcMeshes.material("metal")
		mast.position = Vector3(poly[0].x, height + 7.0, poly[0].y)
		root.add_child(mast)
		var beacon := MeshInstance3D.new()
		beacon.name = "Beacon"
		beacon.mesh = ProcMeshes.sphere(0.5)
		beacon.material_override = ProcMeshes.glow(Color("ff2a3a"), 4.0)
		beacon.position = Vector3(poly[0].x, height + 14.2, poly[0].y)
		root.add_child(beacon)


func _facade_material(style: String) -> Material:
	match style:
		"office_tower":
			return load(FACADE_OFFICE)
		"residential_slab", "midrise", "neon_street":
			return load(FACADE_RESIDENTIAL)
		"shikumen", "heritage":
			return ProcMeshes.material("concrete")
		_:
			return load(FACADE_RESIDENTIAL)


static func _polygon(block: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var raw: Variant = block.get("polygon", [])
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


## Moves every vertex towards the polygon centre (a cheap setback).
static func _inset(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= maxf(float(poly.size()), 1.0)
	for p in poly:
		var dir := (p - centre)
		if dir.length() > 0.001:
			dir = dir.normalized() * maxf(dir.length() - amount, 0.1)
		out.append(centre + dir)
	return out

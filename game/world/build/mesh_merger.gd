extends RefCounted
## Merges the meshes of an imported scene into a single ArrayMesh so that a whole prop (a
## traffic-light mast, a tree) can be drawn with one MultiMesh instead of one node per part.
## Every surface keeps its own material, so the merged mesh still draws like the original.
##
## The merged mesh gets its LOD levels through an ImporterMesh: a lamp that is drawn 2,000 times
## costs a fraction of the polygons when the far ones fall back to a simpler mesh.

## The angles of the LOD levels, in degrees (the defaults of the glTF importer): two surfaces
## whose normals differ by more than the split angle stay apart, the ones below the merge angle
## are merged into one.
const LOD_MERGE_ANGLE := 60.0
const LOD_SPLIT_ANGLE := 25.0


## The mesh of the given instances, with their transforms baked in.
## `skip` holds the names of the meshes that must not be merged (the lenses, for example).
static func merge(instances: Array[MeshInstance3D], skip: PackedStringArray = PackedStringArray()) -> ArrayMesh:
	return merge_where(instances, skip, func(_material: Material) -> bool: return true)


## The mesh of the surfaces of the given instances whose material passes `keep`.
## The head of a lamp is a surface of its mesh, not a node of its own: the surfaces are split
## here, so the head can be drawn with its own visibility range.
static func merge_where(instances: Array[MeshInstance3D], skip: PackedStringArray,
		keep: Callable) -> ArrayMesh:
	var importer := ImporterMesh.new()
	var materials: Array[Material] = []
	var plain := ArrayMesh.new()
	for instance in instances:
		if instance == null or instance.mesh == null:
			continue
		if skip.has(String(instance.name)):
			continue
		var xform := instance.transform
		for i in instance.mesh.get_surface_count():
			var material := instance.get_active_material(i)
			if not bool(keep.call(material)):
				continue
			var arrays := instance.mesh.surface_get_arrays(i)
			if arrays.is_empty():
				continue
			_transform_arrays(arrays, xform)
			var primitive: Mesh.PrimitiveType = instance.mesh.surface_get_primitive_type(i)
			plain.add_surface_from_arrays(primitive, arrays)
			importer.add_surface(primitive, _with_index(arrays))
			materials.append(material)
	if materials.is_empty():
		return plain
	# The LOD levels of the imported meshes are lost when the surfaces are merged, so they are
	# generated again: a lamp that is drawn two thousand times costs a fraction of the polygons.
	importer.generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
	var merged := importer.get_mesh()
	if merged == null or merged.get_surface_count() != materials.size():
		merged = plain
	for i in materials.size():
		if materials[i] != null and i < merged.get_surface_count():
			merged.surface_set_material(i, materials[i])
	return merged


## The arrays of a surface with an index buffer (the simplifier needs one).
static func _with_index(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_INDEX] != null:
		return arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index := PackedInt32Array()
	index.resize(vertices.size())
	for i in vertices.size():
		index[i] = i
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## The mesh of one instance with its transform baked in (a single surface).
static func bake(mesh: Mesh, xform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	if mesh == null:
		return out
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		_transform_arrays(arrays, xform)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
		var material := mesh.surface_get_material(i)
		if material != null:
			out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## Applies a transform to the vertex, normal and tangent arrays of a surface.
static func _transform_arrays(arrays: Array, xform: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] = xform * vertices[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size():
		normals[i] = (xform.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in tangents.size() / 4:
			var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
			tangent = (xform.basis * tangent).normalized()
			tangents[i * 4] = tangent.x
			tangents[i * 4 + 1] = tangent.y
			tangents[i * 4 + 2] = tangent.z
		arrays[Mesh.ARRAY_TANGENT] = tangents

extends RefCounted
## The traffic-light masts as MultiMeshes: one batch for the mast bodies and one per lens
## (red / amber / green). The lens state travels in the instance custom data, so one material
## is shared by every mast in the city (the old per-mast nodes cost ~2,850 draw calls).
##
## The lenses are found by their exact names (Lens_R / Lens_A / Lens_G); the `*_Visor` meshes
## are the hoods above them and stay unlit.

const MeshMerger := preload("res://world/build/mesh_merger.gd")

const GLB_PATH := "res://assets/props/street/traffic_light_mast.glb"
const LENS_NAMES: Array[String] = ["Lens_R", "Lens_A", "Lens_G"]
const LENS_COLORS: Array[Color] = [Color("ff2a3a"), Color("ffb000"), Color("39ff88")]

const LENS_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec3 lens_color : source_color = vec3(1.0, 0.0, 0.0);
varying float lit;
// INSTANCE_CUSTOM.x is 1 for the lit lens of a mast, 0 for the dark ones.
void vertex() {
	lit = INSTANCE_CUSTOM.x;
}
void fragment() {
	ALBEDO = lens_color * mix(0.16, 0.85, lit);
	EMISSION = lens_color * lit * 3.5;
}
"""

## The size of the tile the masts are batched in.
const TILE := 512.0
## The distance at which the mast bodies disappear.
const BODY_RANGE := 400.0
## The distance at which the lenses disappear.
const LENS_RANGE := 600.0

var body_mesh: ArrayMesh
var lens_meshes: Array[ArrayMesh] = []
## The batches per tile: {"body": mmi, "lenses": [mmi, mmi, mmi], "count": int}.
var _batches: Array[Dictionary] = []
## The batch and the index of every mast.
var _index_of: Array[Vector2i] = []


## Loads the mast of the props unit. Returns false when the glb is not there.
func load_meshes() -> bool:
	if not ResourceLoader.exists(GLB_PATH):
		return false
	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate() as Node3D
	if root == null:
		return false
	MaterialLibrary.apply(root)
	var body_parts: Array[MeshInstance3D] = []
	var lens_parts: Dictionary = {}
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		if LENS_NAMES.has(String(mi.name)):
			lens_parts[String(mi.name)] = mi
		else:
			body_parts.append(mi)
	body_mesh = MeshMerger.merge(body_parts)
	for name in LENS_NAMES:
		var lens: MeshInstance3D = lens_parts.get(name)
		if lens == null:
			root.free()
			return false
		lens_meshes.append(MeshMerger.bake(lens.mesh, lens.transform))
	root.free()
	return not body_parts.is_empty() and lens_meshes.size() == LENS_NAMES.size()


## Creates the batches. `placements` are {"transform": Transform3D}. The masts are batched per
## 512 m tile, so a tile that is out of sight costs nothing.
func build(parent: Node3D, placements: Array[Dictionary]) -> void:
	if body_mesh == null or placements.is_empty():
		return
	_index_of.clear()
	var tiles: Dictionary = {}
	var order: Array[String] = []
	for i in placements.size():
		var xform: Transform3D = placements[i]["transform"]
		var key := "%d_%d" % [int(floor(xform.origin.x / TILE)), int(floor(xform.origin.z / TILE))]
		if not tiles.has(key):
			tiles[key] = []
			order.append(key)
		(tiles[key] as Array).append(i)
	for key in order:
		var indices: Array = tiles[key]
		var batch := _make_batch(parent, String(key), indices.size())
		_batches.append(batch)
		var batch_index := _batches.size() - 1
		for local in indices.size():
			var global := int(indices[local])
			_index_of.append(Vector2i(batch_index, local))
			var xform: Transform3D = placements[global]["transform"]
			(batch["body"] as MultiMeshInstance3D).multimesh.set_instance_transform(local, xform)
			for lens in batch["lenses"] as Array:
				(lens as MultiMeshInstance3D).multimesh.set_instance_transform(local, xform)
			set_state(global, 0)


## Lights the lens of `state` (0 red, 1 amber, 2 green) of the mast `index`.
func set_state(index: int, state: int) -> void:
	if index < 0 or index >= _index_of.size():
		return
	var where := _index_of[index]
	var batch: Dictionary = _batches[where.x]
	for i in (batch["lenses"] as Array).size():
		var on := 1.0 if i == state else 0.0
		((batch["lenses"] as Array)[i] as MultiMeshInstance3D).multimesh \
			.set_instance_custom_data(where.y, Color(on, 0.0, 0.0, 0.0))


## The four batches of one tile: the mast bodies and the three lenses.
func _make_batch(parent: Node3D, tile: String, count: int) -> Dictionary:
	var body := _make_multimesh(parent, "MastBodies_" + tile, body_mesh, count, null, BODY_RANGE)
	var lenses: Array = []
	for i in LENS_NAMES.size():
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = LENS_SHADER
		mat.set_shader_parameter(&"lens_color", LENS_COLORS[i])
		lenses.append(_make_multimesh(parent, "Lenses" + LENS_NAMES[i] + "_" + tile,
			lens_meshes[i], count, mat, LENS_RANGE))
	return {"body": body, "lenses": lenses, "count": count}


func _make_multimesh(parent: Node3D, node_name: String, mesh: ArrayMesh, count: int,
		material: Material, visibility_end: float) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	for i in count:
		multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = multimesh
	if material != null:
		mmi.material_override = material
	mmi.visibility_range_end = visibility_end
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi

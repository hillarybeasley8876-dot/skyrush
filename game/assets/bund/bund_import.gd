@tool
extends EditorScenePostImport
## Post-import hook for the Bund glTF files (bund unit).
##
## glTF cannot carry the two things the Bund needs:
##  * the far-field wash cards have to be unshaded and additive, and they have to fade IN
##    between 45 m and 85 m - the pooled uplights fade out at 60-80 m, so the fake has to
##    take over exactly there (art dossier 3.7);
##  * COLOR_0 carries the facade's AO, its dirt and its cornice shadow lines, so every
##    material whose surface has vertex colours has to multiply its albedo with them.
##
## The flood wall's light curtains get their own additive shader: they are the only
## blue on the row and they have to stay readable from the Pudong bank, through the fog.
##
## The build script points bund_buildings.glb.import and bund_promenade.glb.import at
## this file.

const WASH_SHADER := "res://assets/bund/bund_wash.gdshader"
const FLOOD_SHADER := "res://assets/bund/bund_flood.gdshader"
const WASH_NAMES := ["Bund_Wash", "Bund_Crown_Wash"]
const FLOOD_NAMES := ["Bund_Flood_Wash"]


func _post_import(scene: Node) -> Object:
	_apply_vertex_colors(scene)
	_apply_wash(scene)
	_apply_flood(scene)
	return scene


func _apply_vertex_colors(scene: Node) -> void:
	"""Every surface with COLOR_0 multiplies its albedo with it."""
	for mesh_node in _meshes(scene):
		var mesh: Mesh = mesh_node.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
				continue
			var mat: Material = mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).vertex_color_use_as_albedo = true


func _apply_wash(scene: Node) -> void:
	"""The wash cards get the additive shader with the distance fade."""
	var shader: Shader = load(WASH_SHADER)
	if shader == null:
		return
	for mesh_node in _meshes(scene):
		var mesh: Mesh = mesh_node.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(i)
			if mat == null or not WASH_NAMES.has(mat.resource_name):
				continue
			var src := mat as BaseMaterial3D
			var wash := ShaderMaterial.new()
			wash.resource_name = mat.resource_name + "_Shader"
			wash.shader = shader
			wash.set_shader_parameter("wash_tex", src.emission_texture)
			wash.set_shader_parameter("crown_mix", 0.0 if mat.resource_name == "Bund_Wash" else 1.0)
			mesh.surface_set_material(i, wash)


func _apply_flood(scene: Node) -> void:
	"""The flood wall's curtains get the additive shader (no fog, so they read far off)."""
	var shader: Shader = load(FLOOD_SHADER)
	if shader == null:
		return
	for mesh_node in _meshes(scene):
		var mesh: Mesh = mesh_node.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(i)
			if mat == null or not FLOOD_NAMES.has(mat.resource_name):
				continue
			var src := mat as BaseMaterial3D
			var flood := ShaderMaterial.new()
			flood.resource_name = mat.resource_name + "_Shader"
			flood.shader = shader
			flood.set_shader_parameter("curtain_tex", src.emission_texture)
			mesh.surface_set_material(i, flood)


func _meshes(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out

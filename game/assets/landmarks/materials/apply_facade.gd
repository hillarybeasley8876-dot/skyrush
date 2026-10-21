extends Node3D
## Applies the shared Lujiazui facade shader to the tower meshes of a landmark.
##
## The facade shader (res://shaders/facade_windows.gdshader) works in object
## space, so no UV unwrap is needed; only the per-building `building_seed`
## instance uniform changes the window pattern. One seed per tower so no two
## towers share a window layout.

@export var facade_material: ShaderMaterial
@export var seeds: PackedFloat32Array = PackedFloat32Array()
@export var mesh_prefix: String = ""
@export var mesh_names: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if facade_material == null:
		return
	var index := 0
	for node in _meshes(self):
		if mesh_prefix != "" and not node.name.begins_with(mesh_prefix):
			continue
		if not mesh_names.is_empty() and not mesh_names.has(node.name):
			continue
		node.material_override = facade_material
		var seed_value := float(index) * 7.13
		if index < seeds.size():
			seed_value = seeds[index]
		node.set_instance_shader_parameter("building_seed", seed_value)
		index += 1


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out

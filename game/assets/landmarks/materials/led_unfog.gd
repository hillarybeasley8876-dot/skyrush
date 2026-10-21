extends Node
## Turns the environment fog off for the emissive LED materials of a landmark.
##
## The r3 review: "In every wrapper, set disable_fog = true on all emissive
## LED_* materials. Generalise lupu_fog.gd into one led_unfog.gd." The Lupu
## bridge was the first case (the rainbow at 2.2 km); now every landmark
## wrapper uses this script, so the towers' LED signatures read from the Bund
## and from the air.
##
## The facade windows stay fogged - the env unit owns the fog.

const PREFIX := "LED_"


func _ready() -> void:
	for child in _root().find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and mat.resource_name.begins_with(PREFIX):
				(mat as StandardMaterial3D).disable_fog = true


## The scripts hang off the wrapper's ROOT node, so the meshes live under the
## root's children, not under this node.
func _root() -> Node:
	var parent := get_parent()
	return parent if parent != null else self

extends Node3D
## Preview harness for the NPC fleet: applies the shared material library and
## gives every car a body colour from the ref/art §4.7 traffic mix so the sheet
## shows the fleet as it will appear in game.
##
## The police cars keep their livery (it lives in the second UV set), so only
## the plain traffic paint is tinted here.

const PAINT := {
	"sedan_ev": Color("e8e8e6"),          # white 35 %
	"suv_ev": Color("9da3a8"),            # silver 25 %
	"hatch_ev": Color("1f3a5f"),          # blue 8 %
	"taxi": Color("1e8c8a"),              # fictional teal
	"robotaxi": Color("e8e8e6"),
	"police_patrol": Color("f2f4f5"),
	"police_interceptor": Color("f2f4f5"),
	"police_suv": Color("f2f4f5"),
	"van": Color("e8e8e6"),
	"truck": Color("9da3a8"),
	"bus": Color("e8e8e6"),
	"police_drone": Color("0e0f11"),      # black 20 %
}


func _ready() -> void:
	MaterialLibrary.apply(self)
	for child in get_children():
		if child is Node3D and PAINT.has(String(child.name)):
			_tint(child, PAINT[String(child.name)])


func _tint(node: Node, colour: Color) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null or not src.resource_name.begins_with("SH_car_paint"):
				continue
			var copy := src.duplicate() as Material
			if copy is StandardMaterial3D:
				(copy as StandardMaterial3D).albedo_color = colour
			elif copy is ShaderMaterial:
				(copy as ShaderMaterial).set_shader_parameter("base_color", colour)
			mi.set_surface_override_material(i, copy)

extends Node3D
## Preview harness for the NPC fleet: applies the shared material library and
## gives every car a body colour from the ref/art §4.7 traffic mix so the sheet
## shows the fleet as it will appear in game.
##
## The police cars keep their black and white paint (plain materials), so only the traffic paint is tinted here.

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
	# the paint of the fleet is the shared material SH_car_paint_npc: the colour is an instance uniform (TrafficVisual.apply_colour)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null or not src.resource_name.begins_with("SH_car_paint"):
				continue
			mi.set_instance_shader_parameter(&"base_color_override", Color(colour.r, colour.g, colour.b, 1.0))
			break

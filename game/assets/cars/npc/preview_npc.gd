extends Node3D
## Preview harness for the NPC fleet: applies the shared material library and
## gives every traffic car a body colour from the ref/art §4.7 traffic mix so the sheet
## shows the fleet as it will appear in game.
##
## Like the game (TrafficVisual.apply_colour), only the traffic paint SH_car_paint_npc is tinted: the taxi keeps the teal of
## SH_car_paint_taxi, the police cars the white of SH_car_paint_police with their navy and yellow livery.

const PAINT := {
	"sedan_ev": Color("e8e8e6"),          # white 35 %
	"suv_ev": Color("9da3a8"),            # silver 25 %
	"hatch_ev": Color("1f3a5f"),          # blue 8 %
	"robotaxi": Color("e8e8e6"),
	"van": Color("5a5f63"),               # grey 12 %
	"truck": Color("9da3a8"),
	"bus": Color("1f3a5f"),
	"police_drone": Color("0e0f11"),      # black 20 %
}
const TRAFFIC_PAINT := "SH_car_paint_npc"


func _ready() -> void:
	# The colour first: the material library replaces the imported materials, whose names say which surface is the paint.
	for child in get_children():
		if child is Node3D and PAINT.has(String(child.name)):
			_tint(child, PAINT[String(child.name)])
	MaterialLibrary.apply(self)


func _tint(node: Node, colour: Color) -> void:
	# the paint of the fleet is the shared material SH_car_paint_npc: the colour is an instance uniform (TrafficVisual.apply_colour)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null or src.resource_name != TRAFFIC_PAINT:
				continue
			mi.set_instance_shader_parameter(&"base_color_override", Color(colour.r, colour.g, colour.b, 1.0))
			break

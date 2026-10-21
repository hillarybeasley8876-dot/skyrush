extends RefCounted
## The table of every SH_ material. The factory writes these to .tres and the test checks them,
## so the two can never drift apart.
##
## The recipes live in three files so no file grows past the 400 line limit:
##   recipes_street.gd  - the asphalt, the paint and the concrete family
##   recipes_vehicle.gd - the car paint and the glass
##   recipes_light.gd   - the neon, the hologram, the soffit, the water and the facades

const STREET := preload("res://shaders/recipes_street.gd")
const VEHICLE := preload("res://shaders/recipes_vehicle.gd")
const LIGHT := preload("res://shaders/recipes_light.gd")


## Every material of the library, by its contract name.
static func build_all() -> Dictionary:
	return {
		"SH_wet_asphalt": STREET.wet_asphalt(),
		"SH_road_marking_white": STREET.road_marking(Color("e9e7df"), 0.25),
		"SH_road_marking_yellow": STREET.road_marking(Color("e8b520"), 0.35),
		"SH_concrete_pier": STREET.concrete("concrete", 4.0, 0.18, 0.6, 0.35),
		"SH_concrete_barrier": STREET.concrete("concrete_wall_008", 2.71, 0.22, 0.35, 0.25),
		"SH_granite_bund": STREET.granite(),
		"SH_sidewalk": STREET.sidewalk(),
		"SH_kerb": STREET.kerb(),
		"SH_tactile": STREET.tactile(),
		"SH_car_paint": VEHICLE.car_paint("hero"),
		"SH_car_paint_npc": VEHICLE.car_paint("npc"),
		"SH_car_paint_police": VEHICLE.car_paint("police"),
		"SH_car_paint_taxi": VEHICLE.car_paint("taxi"),
		"SH_glass_gold": VEHICLE.glass_gold(),
		"SH_glass_tinted": VEHICLE.glass_tinted(),
		"SH_neon": LIGHT.neon(),
		"SH_hologram": LIGHT.hologram(),
		"SH_soffit_blue": LIGHT.soffit_blue(),
		"SH_water": LIGHT.water(),
		"SH_facade_office": LIGHT.facade(false),
		"SH_facade_residential": LIGHT.facade(true),
	}

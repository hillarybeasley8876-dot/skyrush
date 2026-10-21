extends Node3D
## Look-dev scene for the SKYRUSH night-Shanghai look (environment unit).
## Wet road with GB paint, a crossing elevated deck with the blue soffit, a lit facade block,
## the Bund stone with gold uplights, neon signs, a hologram, the river edge and the Roadster.
##
##   tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=lookdev \
##       --cams=res://world/env/lookdev_cams.json
##
## The camera presets live in lookdev_cams.json (the tech dossier 3.1 method, nine views).

const STREET := preload("res://world/env/lookdev_street.gd")
const CITY := preload("res://world/env/lookdev_city.gd")
const HERO := preload("res://world/env/lookdev_hero.gd")
const ROADSTER := "res://assets/cars/roadster/roadster.glb"


func _ready() -> void:
	STREET.build_road(self)
	STREET.build_pavement(self)
	STREET.build_overpass(self)
	CITY.build_city(self)
	CITY.build_bund(self)
	CITY.build_shopfronts(self)
	CITY.build_signs(self)
	CITY.build_river(self)
	CITY.build_far_bank(self)
	STREET.build_far_light_pools(self)
	HERO.build_lights(self)
	HERO.build_colour_spill(self)
	HERO.build_hero(self, _load_roadster())
	add_child(CITY.make_street_probe())
	add_child(CITY.make_river_probe())


func _load_roadster() -> Node:
	if not ResourceLoader.exists(ROADSTER):
		return null
	var packed := load(ROADSTER) as PackedScene
	if packed == null:
		return null
	var car := packed.instantiate()
	# The glTF materials named SH_* are replaced by the shared library.
	MaterialLibrary.apply(car)
	return car

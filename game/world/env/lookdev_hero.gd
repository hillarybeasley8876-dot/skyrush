extends RefCounted
## The look-dev hero: the street lamps, the coloured spill, the player's headlights and the cars
## (the real Roadster glb plus two traffic cars that prove SH_car_paint_npc).

const K := preload("res://world/env/lookdev_kit.gd")


## Street lamps (LED 4000 K pole lamps every 30 m) and the player's headlights.
static func build_lights(p: Node) -> void:
	for i in 6:
		var x: float = -5.3 if i % 2 == 0 else 5.3
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("ffcea6")             # 4000 K LED (elevated decks)
		lamp.light_energy = 3.0
		lamp.omni_range = 18.0
		lamp.light_volumetric_fog_energy = 0.04        # the lamps must not fog the street brown
		lamp.position = Vector3(x, 9.0, -10.0 - i * 30.0)
		p.add_child(lamp)
		# The lamp needs a pole: a floating head is not a street lamp (ART 8).
		K.lamp_pole(p, Vector3(x, 0.0, -10.0 - i * 30.0), 9.0, Color("ffcea6"))
	# The player's headlights sit at the FRONT of the car and point forward (-Z): the Roadster's
	# body spans z -2.29 (front) .. +2.09 (rear), so anything behind +2.09 shines into the tail.
	# The shadow is OFF and the fog energy is 0.25: a shadowed spot in the fog costs the most and
	# shows the least (the beams disappear, the cp04/br2049 signature).
	for x: float in [-0.75, 0.75]:
		var hl := SpotLight3D.new()
		hl.light_color = Color("f4f7ff")
		hl.light_energy = 6.0
		hl.spot_range = 48.0
		hl.spot_angle = 26.0
		hl.shadow_enabled = false
		hl.light_volumetric_fog_energy = 0.25
		hl.position = Vector3(x, 0.7, -2.40)
		hl.rotation_degrees = Vector3(-4, 0, 0)
		p.add_child(hl)


## Coloured street light: the neon spill that washes the walls and the wet road (this is where
## most of the saturated-bright budget comes from, exactly as on the real Nanjing Road).
static func build_colour_spill(p: Node) -> void:
	var spills: Array[Dictionary] = [
		{"pos": Vector3(7.2, 3.2, -8.0), "col": Color("ff2a8a")},
		{"pos": Vector3(7.2, 3.2, -18.0), "col": Color("ff3030")},
		{"pos": Vector3(7.2, 3.2, -28.0), "col": Color("ff2a8a")},
		{"pos": Vector3(7.2, 3.2, -38.0), "col": Color("ff3030")},
		{"pos": Vector3(7.2, 3.2, -48.0), "col": Color("ff6a1a")},
		{"pos": Vector3(7.2, 3.2, -58.0), "col": Color("ff2a8a")},
		{"pos": Vector3(-7.2, 3.2, -20.0), "col": Color("2357f3")},
		{"pos": Vector3(-7.2, 3.2, -32.0), "col": Color("2357f3")},
		{"pos": Vector3(-7.2, 3.2, -44.0), "col": Color("ff3030")},
	]
	for sp: Dictionary in spills:
		var light := OmniLight3D.new()
		light.light_color = sp["col"]
		light.light_energy = 1.4
		light.omni_range = 13.0
		light.light_volumetric_fog_energy = 0.0   # 9 spill lights: no fog scattering (the froxel cost)
		light.position = sp["pos"]
		p.add_child(light)


## The hero car (the real Roadster glb) and the traffic fleet (the real NPC glbs), so the look-dev
## judges the shared materials on real meshes, real UVs and real wheel contact.
static func build_hero(p: Node, roadster: Node) -> void:
	if roadster != null:
		roadster.position = Vector3(0, 0, 0)
		p.add_child(roadster)
		_set_panel_offsets(roadster)
	else:
		# A stand-in for the Roadster while the car unit exports the glb: the same SH_ materials
		# on a car-shaped body, so the look-dev still judges the paint and the gold glass.
		K.mesh(p, K.box(Vector3(1.86, 0.62, 4.3)), K.mat("SH_car_paint"), Vector3(0, 0.62, 0))
		K.mesh(p, K.box(Vector3(1.5, 0.55, 1.9)), K.mat("SH_glass_gold"), Vector3(0, 1.16, -0.15))
		K.mesh(p, K.box(Vector3(1.7, 0.22, 1.1)), K.mat("SH_car_paint"), Vector3(0, 0.95, 0.85))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var tyre := K.mesh(p, _torus(0.28, 0.36), _rubber(), Vector3(sx * 0.92, 0.36, sz * 1.42))
				tyre.rotation_degrees = Vector3(0, 90, 0)
		# The red light bar: the brightest saturated accent of the chase frame.
		K.mesh(p, K.box(Vector3(1.3, 0.08, 0.1)), K.emissive(Color("ff1a2e"), 10.0), Vector3(0, 0.95, 2.05))
	_build_fleet(p)


const NPC_DIR := "res://assets/cars/npc/"


## The traffic fleet: the real glbs, each with the shared SH_ materials applied.
static func _build_fleet(p: Node) -> void:
	_fleet_car(p, "sedan_ev", Vector3(4.2, 0, -7.0), Color("1f3a5f"), "SH_car_paint_npc")
	_fleet_car(p, "suv_ev", Vector3(-4.6, 0, -12.0), Color("9da3a8"), "SH_car_paint_npc")
	_fleet_car(p, "taxi", Vector3(7.4, 0, -17.0), Color("1e8c8a"), "SH_car_paint_taxi")
	_fleet_car(p, "police_patrol", Vector3(-7.2, 0, -20.0), Color("f2f4f5"), "SH_car_paint_police")


static func _fleet_car(p: Node, file: String, pos: Vector3, color: Color, material_name: String) -> Node:
	var path := NPC_DIR + file + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("lookdev: missing car " + path)
		_placeholder_car(p, pos, color, material_name)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("lookdev: cannot load car " + path)
		_placeholder_car(p, pos, color, material_name)
		return null
	var car := packed.instantiate()
	car.position = pos
	p.add_child(car)
	MaterialLibrary.apply(car)
	_set_panel_offsets(car)
	# The traffic cars take their colour from the instance override; the taxi and the patrol keep
	# the colour of their own SH_car_paint_taxi / SH_car_paint_police material.
	for mi: Node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			if source != null and source.resource_name.get_slice(".", 0) == "SH_car_paint_npc":
				mesh.set_instance_shader_parameter("base_color_override",
					Color(color.r, color.g, color.b, 1.0))
	return car


## A stand-in for a car whose glb is not exported (or not imported) yet: the same SH_ materials,
## so the look-dev still judges the traffic paint and the library keeps every material in the
## scene (the acceptance item) whatever the car unit is doing.
static func _placeholder_car(p: Node, pos: Vector3, color: Color, material_name: String) -> void:
	var body := K.mesh(p, K.box(Vector3(1.8, 0.9, 4.2)), K.mat(material_name), pos + Vector3(0, 0.6, 0))
	body.set_instance_shader_parameter("base_color_override", Color(color.r, color.g, color.b, 1.0))
	K.mesh(p, K.box(Vector3(1.6, 0.6, 2.0)), K.mat("SH_glass_tinted"), pos + Vector3(0, 1.35, -0.2))


## The grime and the wet film of a panel are based on its height in CAR space, so every panel node
## has to tell the shader where its own origin sits (the Hood, the Door_L and the Bumper_F are
## separate nodes with their own origins).
static func _set_panel_offsets(car: Node) -> void:
	var root_y := (car as Node3D).global_position.y
	for mi: Node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			if source != null and source.resource_name.get_slice(".", 0).begins_with("SH_car_paint"):
				mesh.set_instance_shader_parameter("panel_offset_y", mesh.global_position.y - root_y)


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


static func _rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a2a2a")
	m.roughness = 0.86
	return m
